"""Hybrid RAG retrieval engine combining graph traversal and dense vector search.

Integrates ontological neighborhood context (prerequisites, causal mechanisms,
contrasting concepts, multi-hop pathways) with semantically matched ground-truth
course text passages from the vector store.
"""

from __future__ import annotations

import asyncio
import logging

from config import config
from rag.graph_store import BaseGraphStore
from rag.models import (
    ConceptNode,
    EvaluationDetail,
    ExaminerContext,
    PedagogicalState,
)
from rag.vector_store import BaseVectorStore

logger = logging.getLogger("agent.rag.hybrid_retriever")


class HybridRAGRetriever:
    """Combines Neo4j ontological traversal and Qdrant semantic vector search."""

    def __init__(
        self,
        graph_store: BaseGraphStore,
        vector_store: BaseVectorStore,
        top_k_chunks: int | None = None,
    ) -> None:
        self.graph_store = graph_store
        self.vector_store = vector_store
        self.top_k_chunks = (
            top_k_chunks if top_k_chunks is not None else config.rag_top_k_chunks
        )

    async def get_root_or_entry_concept(self) -> ConceptNode | None:
        """Find an unmastered or root concept to begin exploration."""
        concepts = await self.graph_store.get_all_concepts()
        if not concepts:
            return None
        # Prioritize UNTESTED or WEAK concepts with lowest mastery
        candidates = sorted(
            concepts, key=lambda c: (c.mastery_score, c.hesitation_count)
        )
        return candidates[0]

    async def retrieve_context_for_concept(
        self,
        concept_id: str,
        pedagogical_state: PedagogicalState,
        evaluation_detail: EvaluationDetail | None = None,
    ) -> ExaminerContext:
        """Assemble hybrid graph + vector context for the examiner."""
        concept = await self.graph_store.get_concept(concept_id)
        if not concept:
            # Fallback placeholder if not found
            concept = ConceptNode(
                id=concept_id,
                name=concept_id.replace("_", " ").title(),
                summary="Target topic under examination.",
            )

        # 1 & 2. Fetch Ontological Neighborhood and Ground Truth Passages concurrently in parallel
        search_query = f"{concept.name} {concept.summary}"
        (
            prereqs,
            causal_targets,
            contrasting,
            multi_hop,
            chunks,
        ) = await asyncio.gather(
            self.graph_store.get_prerequisites(concept_id),
            self.graph_store.get_causal_targets(concept_id),
            self.graph_store.get_contrasting_concepts(concept_id),
            self.graph_store.get_multi_hop_neighbors(concept_id, max_hops=2),
            self.vector_store.search(
                query=search_query,
                limit=self.top_k_chunks,
                concept_id_filter=concept.id,
            ),
        )

        # If filtered search returned nothing, fall back to global vector search
        if not chunks:
            chunks = await self.vector_store.search(
                query=search_query,
                limit=self.top_k_chunks,
            )

        # 3. Build pedagogical directive based on FSM state
        directive, voice_rule = self._generate_pedagogical_directives(
            concept=concept,
            state=pedagogical_state,
            prereqs=prereqs,
            causal_targets=causal_targets,
            contrasting=contrasting,
            multi_hop=multi_hop,
            evaluation=evaluation_detail,
        )

        ideal_ans = (
            str(concept.properties.get("ideal_answer", ""))
            if concept.properties
            else ""
        )

        return ExaminerContext(
            current_concept=concept,
            pedagogical_state=pedagogical_state,
            ground_truth_chunks=chunks,
            prerequisites=prereqs,
            causal_targets=causal_targets,
            contrasting_concepts=contrasting,
            multi_hop_concepts=multi_hop,
            evaluation_detail=evaluation_detail,
            pedagogical_directive=directive,
            ideal_answer=ideal_ans,
            voice_formatting_instruction=voice_rule,
        )

    def _generate_pedagogical_directives(
        self,
        concept: ConceptNode,
        state: PedagogicalState,
        prereqs: list[ConceptNode],
        causal_targets: list[ConceptNode],
        contrasting: list[ConceptNode],
        multi_hop: list[ConceptNode],
        evaluation: EvaluationDetail | None,
    ) -> tuple[str, str]:
        """Derive explicit pedagogical instructions and voice constraints."""
        voice_rule = (
            "Keep the response strictly to 2-3 sentences. "
            "Speak naturally like an oral examiner. Do not list markdown or bullet points."
        )

        if state == PedagogicalState.EXPLORATION:
            directive = (
                f"Start with a broad conceptual question exploring the core principles of '{concept.name}'. "
                f"Ground your question on the provided course material."
            )
        elif state == PedagogicalState.CAUSAL_NARROWING:
            causal_str = (
                f"specifically focus on its causal mechanism with '{causal_targets[0].name}'"
                if causal_targets
                else "demand precise conditions and quantitative or physical mechanisms"
            )
            directive = (
                f"The student gave a vague answer. Narrow down the scope and {causal_str}. "
                f"Require exact reasoning rather than general keywords."
            )
        elif state == PedagogicalState.SCAFFOLDING:
            directive = (
                f"The student was hesitant. Provide a subtle pedagogical scaffolding hint "
                f"for '{concept.name}' without giving away the direct answer. Ask a guiding follow-up."
            )
        elif state == PedagogicalState.CONCEPTUAL_COLLISION:
            contrast_str = (
                f"'{contrasting[0].name}'"
                if contrasting
                else "related contrasting concepts"
            )
            directive = (
                f"The student exhibited a misconception or confused '{concept.name}' with {contrast_str}. "
                f"Directly challenge this misconception and ask them to differentiate the two concepts."
            )
        elif state == PedagogicalState.MULTI_HOP_SYNTHESIS:
            hop_name = (
                multi_hop[0].name
                if multi_hop
                else (prereqs[0].name if prereqs else "adjacent topics")
            )
            directive = (
                f"The student answered accurately. Test higher-order synthesis by connecting '{concept.name}' "
                f"with '{hop_name}'. Ask how these principles interact."
            )
        elif state == PedagogicalState.STRESS_TEST:
            directive = (
                f"The student gave a memorized book definition of '{concept.name}'. "
                f"Stress test their practical understanding by asking for a real-world application, "
                f"an experimental setup, or an edge-case scenario."
            )
        elif state == PedagogicalState.PREREQUISITE_FALLBACK:
            prereq_str = prereqs[0].name if prereqs else "foundational definitions"
            directive = (
                f"The student failed multiple scaffolding attempts on '{concept.name}'. "
                f"Gently step back and test the foundational prerequisite '{prereq_str}' before returning."
            )
        else:
            directive = f"Assess the student's mastery of '{concept.name}'."

        return directive, voice_rule
