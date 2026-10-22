"""Knowledge Graph database interfaces and implementations.

Provides an abstract BaseGraphStore, an InMemoryGraphStore with graph traversal algorithms,
and a production Neo4jGraphStore client using Cypher queries for ontological relations,
BKT degradation propagation, and Root Cause Analysis (RCA).
"""

from __future__ import annotations

import abc
import logging
from collections.abc import Sequence
from datetime import datetime

from config import config
from rag.models import (
    ConceptNode,
    ConceptRelation,
    ConceptStatus,
    RelationType,
)

logger = logging.getLogger("agent.rag.graph_store")


class BaseGraphStore(abc.ABC):
    """Abstract interface for knowledge graph operations."""

    @abc.abstractmethod
    async def upsert_concept(self, concept: ConceptNode) -> None:
        """Create or update a concept node."""
        pass

    @abc.abstractmethod
    async def upsert_concepts(self, concepts: Sequence[ConceptNode]) -> None:
        """Batch upsert concept nodes."""
        pass

    @abc.abstractmethod
    async def add_relation(self, relation: ConceptRelation) -> None:
        """Create a directed relation between concepts."""
        pass

    @abc.abstractmethod
    async def get_concept(self, concept_id: str) -> ConceptNode | None:
        """Retrieve concept by ID."""
        pass

    @abc.abstractmethod
    async def get_all_concepts(self) -> list[ConceptNode]:
        """Retrieve all concept nodes."""
        pass

    @abc.abstractmethod
    async def get_prerequisites(self, concept_id: str) -> list[ConceptNode]:
        """Retrieve direct prerequisites (Concept -[:REQUIRES]-> Prereq)."""
        pass

    @abc.abstractmethod
    async def get_causal_targets(self, concept_id: str) -> list[ConceptNode]:
        """Retrieve causal effects (Concept -[:CAUSES]-> Effect)."""
        pass

    @abc.abstractmethod
    async def get_contrasting_concepts(self, concept_id: str) -> list[ConceptNode]:
        """Retrieve contrasting concepts (Concept -[:CONTRASTS_WITH]-> Other)."""
        pass

    @abc.abstractmethod
    async def get_multi_hop_neighbors(
        self, concept_id: str, max_hops: int = 2
    ) -> list[ConceptNode]:
        """Retrieve 2-hop connected concepts for synthesis."""
        pass

    @abc.abstractmethod
    async def update_mastery(
        self,
        concept_id: str,
        mastery_score: float,
        hesitation_delta: int = 0,
        mistake_delta: int = 0,
        status: ConceptStatus | None = None,
    ) -> ConceptNode | None:
        """Update mastery score and metric counters for a concept."""
        pass

    @abc.abstractmethod
    async def propagate_prerequisite_degradation(
        self, threshold: float = 0.45
    ) -> list[str]:
        """Mark dependent concepts as BLOCKED_BY_PREREQUISITE if a base prerequisite drops below threshold."""
        pass

    @abc.abstractmethod
    async def get_root_cause_analysis(self) -> list[dict[str, str]]:
        """Identify root cause prerequisite gaps for concepts with mistakes/hesitations."""
        pass

    @abc.abstractmethod
    async def clear(self) -> None:
        """Clear the graph database."""
        pass


class InMemoryGraphStore(BaseGraphStore):
    """In-memory knowledge graph implementation for fast unit tests and zero-dependency mode."""

    def __init__(self) -> None:
        self._concepts: dict[str, ConceptNode] = {}
        # source_id -> list[(target_id, rel_type, condition)]
        self._out_edges: dict[str, list[tuple[str, RelationType, str | None]]] = {}
        # target_id -> list[(source_id, rel_type, condition)]
        self._in_edges: dict[str, list[tuple[str, RelationType, str | None]]] = {}

    async def upsert_concept(self, concept: ConceptNode) -> None:
        if concept.id in self._concepts:
            existing = self._concepts[concept.id]
            # merge fields
            concept.mastery_score = (
                existing.mastery_score
                if concept.mastery_score == 0.50
                else concept.mastery_score
            )
            concept.hesitation_count = (
                existing.hesitation_count + concept.hesitation_count
            )
            concept.mistake_count = existing.mistake_count + concept.mistake_count
        self._concepts[concept.id] = concept

        # Handle implicit prerequisites & contrasts in model
        for prereq_id in concept.prerequisites:
            await self.add_relation(
                ConceptRelation(
                    source_id=concept.id,
                    target_id=prereq_id,
                    rel_type=RelationType.REQUIRES,
                )
            )
        for contrast_id in concept.contrasts_with:
            await self.add_relation(
                ConceptRelation(
                    source_id=concept.id,
                    target_id=contrast_id,
                    rel_type=RelationType.CONTRASTS_WITH,
                )
            )

    async def upsert_concepts(self, concepts: Sequence[ConceptNode]) -> None:
        for c in concepts:
            await self.upsert_concept(c)

    async def add_relation(self, relation: ConceptRelation) -> None:
        if relation.source_id not in self._out_edges:
            self._out_edges[relation.source_id] = []
        if relation.target_id not in self._in_edges:
            self._in_edges[relation.target_id] = []

        edge = (relation.target_id, relation.rel_type, relation.condition)
        if edge not in self._out_edges[relation.source_id]:
            self._out_edges[relation.source_id].append(edge)

        rev_edge = (relation.source_id, relation.rel_type, relation.condition)
        if rev_edge not in self._in_edges[relation.target_id]:
            self._in_edges[relation.target_id].append(rev_edge)

        # For CONTRASTS_WITH, make it symmetric
        if relation.rel_type == RelationType.CONTRASTS_WITH:
            sym_edge = (
                relation.source_id,
                RelationType.CONTRASTS_WITH,
                relation.condition,
            )
            if sym_edge not in self._out_edges.get(relation.target_id, []):
                self._out_edges.setdefault(relation.target_id, []).append(sym_edge)

    async def get_concept(self, concept_id: str) -> ConceptNode | None:
        return self._concepts.get(concept_id)

    async def get_all_concepts(self) -> list[ConceptNode]:
        return list(self._concepts.values())

    async def get_prerequisites(self, concept_id: str) -> list[ConceptNode]:
        edges = self._out_edges.get(concept_id, [])
        prereq_ids = [tgt for tgt, rel, _ in edges if rel == RelationType.REQUIRES]
        return [self._concepts[pid] for pid in prereq_ids if pid in self._concepts]

    async def get_causal_targets(self, concept_id: str) -> list[ConceptNode]:
        edges = self._out_edges.get(concept_id, [])
        effect_ids = [tgt for tgt, rel, _ in edges if rel == RelationType.CAUSES]
        return [self._concepts[eid] for eid in effect_ids if eid in self._concepts]

    async def get_contrasting_concepts(self, concept_id: str) -> list[ConceptNode]:
        edges = self._out_edges.get(concept_id, [])
        contrast_ids = [
            tgt for tgt, rel, _ in edges if rel == RelationType.CONTRASTS_WITH
        ]
        return [self._concepts[cid] for cid in contrast_ids if cid in self._concepts]

    async def get_multi_hop_neighbors(
        self, concept_id: str, max_hops: int = 2
    ) -> list[ConceptNode]:
        visited = {concept_id}
        current_layer = {concept_id}
        multi_hop_nodes: list[ConceptNode] = []

        for _ in range(max_hops):
            next_layer = set()
            for node_id in current_layer:
                for tgt, rel, _ in self._out_edges.get(node_id, []):
                    if (
                        rel in (RelationType.REQUIRES, RelationType.CAUSES)
                        and tgt not in visited
                    ):
                        visited.add(tgt)
                        next_layer.add(tgt)
                        if tgt in self._concepts:
                            multi_hop_nodes.append(self._concepts[tgt])
                for src, rel, _ in self._in_edges.get(node_id, []):
                    if (
                        rel in (RelationType.REQUIRES, RelationType.CAUSES)
                        and src not in visited
                    ):
                        visited.add(src)
                        next_layer.add(src)
                        if src in self._concepts:
                            multi_hop_nodes.append(self._concepts[src])
            current_layer = next_layer
            if not current_layer:
                break

        return multi_hop_nodes

    async def update_mastery(
        self,
        concept_id: str,
        mastery_score: float,
        hesitation_delta: int = 0,
        mistake_delta: int = 0,
        status: ConceptStatus | None = None,
    ) -> ConceptNode | None:
        concept = self._concepts.get(concept_id)
        if not concept:
            return None
        concept.mastery_score = max(0.0, min(1.0, mastery_score))
        concept.hesitation_count += max(0, hesitation_delta)
        concept.mistake_count += max(0, mistake_delta)
        concept.last_tested = datetime.now()

        if status:
            concept.status = status
        elif concept.mastery_score >= 0.80:
            concept.status = ConceptStatus.MASTERED
        elif concept.mastery_score < 0.40 or concept.mistake_count >= 2:
            concept.status = ConceptStatus.WEAK
        else:
            concept.status = ConceptStatus.IN_PROGRESS

        return concept

    async def propagate_prerequisite_degradation(
        self, threshold: float = 0.45
    ) -> list[str]:
        blocked: list[str] = []
        for concept_id, concept in self._concepts.items():
            if concept.mastery_score < threshold:
                # Find all nodes that require this concept
                queue = [concept_id]
                visited = {concept_id}
                while queue:
                    curr = queue.pop(0)
                    for src, rel, _ in self._in_edges.get(curr, []):
                        if rel == RelationType.REQUIRES and src not in visited:
                            visited.add(src)
                            queue.append(src)
                            if src in self._concepts:
                                self._concepts[
                                    src
                                ].status = ConceptStatus.BLOCKED_BY_PREREQUISITE
                                blocked.append(src)
        return list(set(blocked))

    async def get_root_cause_analysis(self) -> list[dict[str, str]]:
        results: list[dict[str, str]] = []
        for concept_id, concept in self._concepts.items():
            if concept.mistake_count > 0 or concept.hesitation_count >= 2:
                # Traverse prerequisite chain to find root causes with low mastery
                queue = [concept_id]
                visited = {concept_id}
                while queue:
                    curr = queue.pop(0)
                    for tgt, rel, _ in self._out_edges.get(curr, []):
                        if rel == RelationType.REQUIRES and tgt not in visited:
                            visited.add(tgt)
                            queue.append(tgt)
                            prereq = self._concepts.get(tgt)
                            if prereq and prereq.mastery_score < 0.50:
                                results.append(
                                    {
                                        "failed_concept_id": concept.id,
                                        "failed_concept_name": concept.name,
                                        "root_cause_id": prereq.id,
                                        "root_cause_name": prereq.name,
                                        "root_cause_mastery": f"{prereq.mastery_score:.2f}",
                                    }
                                )
        return results

    async def clear(self) -> None:
        self._concepts.clear()
        self._out_edges.clear()
        self._in_edges.clear()


class Neo4jGraphStore(BaseGraphStore):
    """Production Neo4j Cypher knowledge graph store."""

    def __init__(
        self,
        uri: str | None = None,
        user: str | None = None,
        password: str | None = None,
        database: str | None = None,
    ) -> None:
        try:
            from neo4j import AsyncGraphDatabase
        except ImportError as exc:
            raise ImportError(
                "neo4j package is required. Install with `uv add neo4j`"
            ) from exc

        self.uri = uri or config.neo4j_uri
        self.user = user or config.neo4j_user
        self.password = password or config.neo4j_password
        self.database = database or config.neo4j_database
        self.driver = AsyncGraphDatabase.driver(
            self.uri, auth=(self.user, self.password)
        )

    async def close(self) -> None:
        await self.driver.close()

    async def upsert_concept(self, concept: ConceptNode) -> None:
        query = """
        MERGE (c:Concept {id: $id})
        ON CREATE SET
            c.name = $name,
            c.summary = $summary,
            c.mastery_score = $mastery_score,
            c.hesitation_count = $hesitation_count,
            c.mistake_count = $mistake_count,
            c.status = $status,
            c.last_tested = datetime()
        ON MATCH SET
            c.name = $name,
            c.summary = $summary
        """
        async with self.driver.session(database=self.database) as session:
            await session.run(
                query,
                id=concept.id,
                name=concept.name,
                summary=concept.summary,
                mastery_score=concept.mastery_score,
                hesitation_count=concept.hesitation_count,
                mistake_count=concept.mistake_count,
                status=concept.status.value,
            )

        for p_id in concept.prerequisites:
            await self.add_relation(
                ConceptRelation(
                    source_id=concept.id,
                    target_id=p_id,
                    rel_type=RelationType.REQUIRES,
                )
            )
        for c_id in concept.contrasts_with:
            await self.add_relation(
                ConceptRelation(
                    source_id=concept.id,
                    target_id=c_id,
                    rel_type=RelationType.CONTRASTS_WITH,
                )
            )

    async def upsert_concepts(self, concepts: Sequence[ConceptNode]) -> None:
        for c in concepts:
            await self.upsert_concept(c)

    async def add_relation(self, relation: ConceptRelation) -> None:
        rel_type = relation.rel_type.value
        query = f"""
        MATCH (s:Concept {{id: $source_id}})
        MATCH (t:Concept {{id: $target_id}})
        MERGE (s)-[r:{rel_type}]->(t)
        ON CREATE SET r.condition = $condition
        """
        async with self.driver.session(database=self.database) as session:
            await session.run(
                query,
                source_id=relation.source_id,
                target_id=relation.target_id,
                condition=relation.condition or "",
            )

    async def get_concept(self, concept_id: str) -> ConceptNode | None:
        query = """
        MATCH (c:Concept {id: $id})
        OPTIONAL MATCH (c)-[:REQUIRES]->(p:Concept)
        OPTIONAL MATCH (c)-[:CONTRASTS_WITH]->(cw:Concept)
        RETURN c, collect(DISTINCT p.id) AS prereqs, collect(DISTINCT cw.id) AS contrasts
        """
        async with self.driver.session(database=self.database) as session:
            result = await session.run(query, id=concept_id)
            record = await result.single()
            if not record:
                return None
            c = record["c"]
            return ConceptNode(
                id=c["id"],
                name=c["name"],
                summary=c.get("summary", ""),
                mastery_score=float(c.get("mastery_score", 0.50)),
                hesitation_count=int(c.get("hesitation_count", 0)),
                mistake_count=int(c.get("mistake_count", 0)),
                status=ConceptStatus(c.get("status", "UNTESTED")),
                prerequisites=record["prereqs"],
                contrasts_with=record["contrasts"],
            )

    async def get_all_concepts(self) -> list[ConceptNode]:
        query = """
        MATCH (c:Concept)
        OPTIONAL MATCH (c)-[:REQUIRES]->(p:Concept)
        OPTIONAL MATCH (c)-[:CONTRASTS_WITH]->(cw:Concept)
        RETURN c, collect(DISTINCT p.id) AS prereqs, collect(DISTINCT cw.id) AS contrasts
        """
        async with self.driver.session(database=self.database) as session:
            result = await session.run(query)
            records = await result.data()
            nodes = []
            for r in records:
                c = r["c"]
                nodes.append(
                    ConceptNode(
                        id=c["id"],
                        name=c["name"],
                        summary=c.get("summary", ""),
                        mastery_score=float(c.get("mastery_score", 0.50)),
                        hesitation_count=int(c.get("hesitation_count", 0)),
                        mistake_count=int(c.get("mistake_count", 0)),
                        status=ConceptStatus(c.get("status", "UNTESTED")),
                        prerequisites=r["prereqs"],
                        contrasts_with=r["contrasts"],
                    )
                )
            return nodes

    async def get_prerequisites(self, concept_id: str) -> list[ConceptNode]:
        query = """
        MATCH (c:Concept {id: $id})-[:REQUIRES]->(p:Concept)
        RETURN p
        """
        async with self.driver.session(database=self.database) as session:
            result = await session.run(query, id=concept_id)
            records = await result.data()
            return [
                ConceptNode(
                    id=r["p"]["id"],
                    name=r["p"]["name"],
                    summary=r["p"].get("summary", ""),
                    mastery_score=float(r["p"].get("mastery_score", 0.50)),
                    hesitation_count=int(r["p"].get("hesitation_count", 0)),
                    mistake_count=int(r["p"].get("mistake_count", 0)),
                    status=ConceptStatus(r["p"].get("status", "UNTESTED")),
                )
                for r in records
            ]

    async def get_causal_targets(self, concept_id: str) -> list[ConceptNode]:
        query = """
        MATCH (c:Concept {id: $id})-[:CAUSES]->(e:Concept)
        RETURN e
        """
        async with self.driver.session(database=self.database) as session:
            result = await session.run(query, id=concept_id)
            records = await result.data()
            return [
                ConceptNode(
                    id=r["e"]["id"],
                    name=r["e"]["name"],
                    summary=r["e"].get("summary", ""),
                    mastery_score=float(r["e"].get("mastery_score", 0.50)),
                    hesitation_count=int(r["e"].get("hesitation_count", 0)),
                    mistake_count=int(r["e"].get("mistake_count", 0)),
                    status=ConceptStatus(r["e"].get("status", "UNTESTED")),
                )
                for r in records
            ]

    async def get_contrasting_concepts(self, concept_id: str) -> list[ConceptNode]:
        query = """
        MATCH (c:Concept {id: $id})-[:CONTRASTS_WITH]-(cw:Concept)
        RETURN DISTINCT cw
        """
        async with self.driver.session(database=self.database) as session:
            result = await session.run(query, id=concept_id)
            records = await result.data()
            return [
                ConceptNode(
                    id=r["cw"]["id"],
                    name=r["cw"]["name"],
                    summary=r["cw"].get("summary", ""),
                    mastery_score=float(r["cw"].get("mastery_score", 0.50)),
                    hesitation_count=int(r["cw"].get("hesitation_count", 0)),
                    mistake_count=int(r["cw"].get("mistake_count", 0)),
                    status=ConceptStatus(r["cw"].get("status", "UNTESTED")),
                )
                for r in records
            ]

    async def get_multi_hop_neighbors(
        self, concept_id: str, max_hops: int = 2
    ) -> list[ConceptNode]:
        query = """
        MATCH (c:Concept {id: $id})-[:REQUIRES|CAUSES*2]-(target:Concept)
        WHERE target.id <> $id
        RETURN DISTINCT target LIMIT 5
        """
        async with self.driver.session(database=self.database) as session:
            result = await session.run(query, id=concept_id)
            records = await result.data()
            return [
                ConceptNode(
                    id=r["target"]["id"],
                    name=r["target"]["name"],
                    summary=r["target"].get("summary", ""),
                    mastery_score=float(r["target"].get("mastery_score", 0.50)),
                    hesitation_count=int(r["target"].get("hesitation_count", 0)),
                    mistake_count=int(r["target"].get("mistake_count", 0)),
                    status=ConceptStatus(r["target"].get("status", "UNTESTED")),
                )
                for r in records
            ]

    async def update_mastery(
        self,
        concept_id: str,
        mastery_score: float,
        hesitation_delta: int = 0,
        mistake_delta: int = 0,
        status: ConceptStatus | None = None,
    ) -> ConceptNode | None:
        status_val = status.value if status else "IN_PROGRESS"
        query = """
        MATCH (c:Concept {id: $id})
        SET c.mastery_score = $mastery_score,
            c.hesitation_count = c.hesitation_count + $hesitation_delta,
            c.mistake_count = c.mistake_count + $mistake_delta,
            c.status = $status,
            c.last_tested = datetime()
        RETURN c
        """
        async with self.driver.session(database=self.database) as session:
            result = await session.run(
                query,
                id=concept_id,
                mastery_score=max(0.0, min(1.0, mastery_score)),
                hesitation_delta=max(0, hesitation_delta),
                mistake_delta=max(0, mistake_delta),
                status=status_val,
            )
            record = await result.single()
            if not record:
                return None
            c = record["c"]
            return ConceptNode(
                id=c["id"],
                name=c["name"],
                summary=c.get("summary", ""),
                mastery_score=float(c["mastery_score"]),
                hesitation_count=int(c["hesitation_count"]),
                mistake_count=int(c["mistake_count"]),
                status=ConceptStatus(c["status"]),
            )

    async def propagate_prerequisite_degradation(
        self, threshold: float = 0.45
    ) -> list[str]:
        query = """
        MATCH (base:Concept)-[:REQUIRES*]->(advanced:Concept)
        WHERE base.mastery_score < $threshold
        SET advanced.status = "BLOCKED_BY_PREREQUISITE"
        RETURN DISTINCT advanced.id AS blocked_id
        """
        async with self.driver.session(database=self.database) as session:
            result = await session.run(query, threshold=threshold)
            records = await result.data()
            return [r["blocked_id"] for r in records]

    async def get_root_cause_analysis(self) -> list[dict[str, str]]:
        query = """
        MATCH (c:Concept)
        WHERE c.mistake_count > 0 OR c.hesitation_count >= 2
        MATCH (c)-[:REQUIRES*]->(root_cause:Concept)
        WHERE root_cause.mastery_score < 0.50
        RETURN c.id AS failed_concept_id, c.name AS failed_concept_name,
               root_cause.id AS root_cause_id, root_cause.name AS root_cause_name,
               toString(root_cause.mastery_score) AS root_cause_mastery
        ORDER BY root_cause.mastery_score ASC
        """
        async with self.driver.session(database=self.database) as session:
            result = await session.run(query)
            return await result.data()

    async def clear(self) -> None:
        query = "MATCH (n) DETACH DELETE n"
        async with self.driver.session(database=self.database) as session:
            await session.run(query)


def create_graph_store(store_type: str = "memory") -> BaseGraphStore:
    """Factory to create graph store instance."""
    if store_type.lower() == "neo4j":
        try:
            return Neo4jGraphStore()
        except Exception as err:
            logger.warning(
                "Could not connect to Neo4j (%s), falling back to InMemoryGraphStore",
                err,
            )
            return InMemoryGraphStore()
    return InMemoryGraphStore()
