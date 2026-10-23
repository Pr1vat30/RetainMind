"""Course-scoped knowledge stores shared by planning and live assessment."""

from __future__ import annotations

import logging
from typing import Any

from config import config
from rag import create_graph_store, create_vector_store

logger = logging.getLogger("agent.assessment.knowledge")

_COURSE_STORES: dict[str, tuple[Any, Any]] = {}


def register_course_stores(
    course_id: str | None, graph_store: Any, vector_store: Any
) -> None:
    if course_id:
        _COURSE_STORES[course_id] = (graph_store, vector_store)


def get_registered_course_stores(course_id: str | None) -> tuple[Any, Any] | None:
    return _COURSE_STORES.get(course_id) if course_id else None


async def load_course_stores(
    course_id: str | None,
    plan: Any = None,
    material_path: Any = None,
) -> tuple[Any, Any]:
    """Reuse a course's stores or rebuild them from its saved plan and material."""
    cached = get_registered_course_stores(course_id)
    if cached:
        return cached

    graph_store = create_graph_store(
        "neo4j" if config.neo4j_uri != "bolt://localhost:7687" else "memory"
    )
    vector_store = create_vector_store(
        "qdrant" if config.qdrant_url != "http://localhost:6333" else "memory"
    )

    # Persistent backends already contain the indexed course. Memory stores need
    # rebuilding after a backend restart, because they do not survive processes.
    has_memory_store = (
        graph_store.__class__.__name__ == "InMemoryGraphStore"
        or vector_store.__class__.__name__ == "InMemoryVectorStore"
    )
    if plan and material_path and has_memory_store:
        from pathlib import Path

        path = Path(material_path)
        if path.is_file():
            try:
                from rag.ingestion.pipeline import IngestionPipeline

                ontology = {"concepts": [], "relations": []}
                for cid in plan.concept_order:
                    item = plan.items.get(cid)
                    if not item:
                        continue
                    question = item.planned_question
                    ontology["concepts"].append(
                        {
                            "id": cid,
                            "name": item.concept_name,
                            "summary": item.summary,
                            "prerequisites": item.prerequisites,
                            "contrasts_with": item.contrasts_with,
                            "properties": {
                                "ideal_answer": question.ideal_answer,
                                "expected_key_points": question.expected_key_points,
                                "main_question": question.main_question,
                                "narrowing_questions": question.narrowing_questions,
                                "scaffolding_hints": question.scaffolding_hints,
                                "stress_test_questions": question.stress_test_questions,
                                "collision_check_questions": question.collision_check_questions,
                                "difficulty": question.difficulty.value,
                            },
                        }
                    )
                    ontology["relations"].extend(
                        {"source": cid, "target": target, "type": "CAUSES"}
                        for target in item.causal_effects
                    )

                pipeline = IngestionPipeline(vector_store, graph_store)
                await pipeline.ingest_file(
                    str(path),
                    document_id=plan.document_id,
                    structured_ontology=ontology,
                )
            except Exception:
                logger.exception("Could not restore knowledge for course %s", course_id)

    register_course_stores(course_id, graph_store, vector_store)
    return graph_store, vector_store
