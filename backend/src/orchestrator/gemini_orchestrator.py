"""Independent offline orchestrator for knowledge ingestion, planning, and knowledge tracing.

Provides high-level asynchronous APIs to ingest course materials, build topologically
sequenced examination plans, and simulate Bayesian Knowledge Tracing updates outside
the real-time LiveKit audio loop.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from assessment.bkt import BayesianKnowledgeTracing
from assessment.report import SessionReportGenerator
from planning.models import ExaminationPlan, PlanItemStatus
from planning.planner import ExaminationPlanner
from rag.graph_store import BaseGraphStore, create_graph_store
from rag.ingestion.pipeline import IngestionPipeline
from rag.models import EvaluationResultType
from rag.vector_store import BaseVectorStore, create_vector_store

logger = logging.getLogger("orchestrator.gemini")


class GeminiOrchestrator:
    """Independent Knowledge Ingestion, Pedagogical Planning & Bayesian Tracing Engine.

    Operates completely separate from LiveKit's real-time voice loop.
    """

    def __init__(
        self,
        graph_store: BaseGraphStore | None = None,
        vector_store: BaseVectorStore | None = None,
    ) -> None:
        self.graph_store = graph_store or create_graph_store()
        self.vector_store = vector_store or create_vector_store()
        self.pipeline = IngestionPipeline(
            vector_store=self.vector_store,
            graph_store=self.graph_store,
        )
        self.planner = ExaminationPlanner(
            graph_store=self.graph_store,
            vector_store=self.vector_store,
        )
        self.bkt = BayesianKnowledgeTracing(graph_store=self.graph_store)
        self.report_generator = SessionReportGenerator(graph_store=self.graph_store)

    async def ingest_document_and_plan(
        self,
        file_path: str | Path,
        title: str = "Piano d'Esame Orale Universitario",
        plan_output_file: str | Path = "examination_plan.json",
    ) -> ExaminationPlan:
        """Ingests course document, populates ontology in graph & vector stores,

        and generates a topologically sorted examination plan.
        """
        path = Path(file_path)
        logger.info("Gemini Orchestrator: Ingesting %s", path)

        # 1. Ingest file and build knowledge base
        ingest_res = await self.pipeline.ingest_file(
            str(path), llm_model="gemini-3.5-flash-lite"
        )
        logger.info(
            "Gemini Orchestrator: Ingestion done (%d chunks, %d concepts)",
            ingest_res["chunks_count"],
            ingest_res["concepts_count"],
        )

        # 2. Formulate Examination Plan
        plan = await self.planner.generate_plan(
            document_id=ingest_res["document_id"],
            title=title,
        )

        # 3. Persist plan
        out_p = Path(plan_output_file)
        ExaminationPlanner.save_plan_to_file(plan, out_p)
        logger.info("Gemini Orchestrator: Plan saved to %s", out_p)
        return plan

    async def generate_plan_from_topic(
        self,
        topic: str,
        title: str | None = None,
        plan_output_file: str | Path = "examination_plan.json",
    ) -> tuple[ExaminationPlan, str, str]:
        """Generates an academic course syllabus and topologically ordered examination plan directly from a topic.

        Returns (plan, resolved_title, summary_markdown).
        """
        logger.info("Gemini Orchestrator: Generating plan from topic '%s'", topic)
        from assessment.courses import CourseManager
        from rag.ingestion.extractor import KnowledgeExtractor

        extracted = KnowledgeExtractor.extract_from_topic(
            topic=topic,
            model="gemini-3.5-flash-lite",
        )

        resolved_title = title or extracted.get("course_title") or topic
        summary_md = extracted.get(
            "course_summary_markdown", f"# {resolved_title}\n\nSintesi didattica su {topic}."
        )

        doc_id = CourseManager.slugify(resolved_title)

        ingest_res = await self.pipeline.ingest_document(
            content=summary_md,
            document_id=doc_id,
            structured_ontology=extracted,
        )
        logger.info(
            "Gemini Orchestrator: Topic ingestion completed (%d chunks, %d concepts)",
            ingest_res["chunks_count"],
            ingest_res["concepts_count"],
        )

        plan = await self.planner.generate_plan(
            document_id=doc_id,
            title=resolved_title,
        )

        out_p = Path(plan_output_file)
        ExaminationPlanner.save_plan_to_file(plan, out_p)
        logger.info("Gemini Orchestrator: Plan saved to %s", out_p)
        return plan, resolved_title, summary_md

    async def update_knowledge_tracing(
        self,
        concept_id: str,
        evaluation_result: str | EvaluationResultType,
        plan: ExaminationPlan | None = None,
    ) -> dict[str, Any]:
        """Applies Bayesian Knowledge Tracing updates to the knowledge graph

        and advances or adapts the examination plan.
        """
        if isinstance(evaluation_result, str):
            try:
                eval_enum = EvaluationResultType(evaluation_result.upper())
            except ValueError:
                eval_enum = EvaluationResultType.VAGUE
        else:
            eval_enum = evaluation_result

        # Update mastery in Graph
        updated_node, mastery_delta = await self.bkt.update_concept_mastery(
            concept_id=concept_id,
            evaluation=eval_enum,
        )

        next_action = "CONTINUE"
        next_concept = concept_id
        directive = ""

        if plan and concept_id in plan.items:
            item = plan.items[concept_id]
            item.current_attempt += 1

            if eval_enum in (
                EvaluationResultType.ACCURATE,
                EvaluationResultType.MEMORIZED,
            ):
                item.status = PlanItemStatus.MASTERED
                next_item = plan.advance_to_next()
                if next_item:
                    next_concept = next_item.concept_id
                    directive = next_item.planned_question.main_question
                    next_action = "NEXT_CONCEPT"
                else:
                    next_action = "EXAM_COMPLETED"
                    directive = (
                        "L'esame è concluso. Puoi procedere con il riepilogo finale."
                    )
            else:
                if item.current_attempt < item.planned_question.max_attempts:
                    if (
                        eval_enum == EvaluationResultType.VAGUE
                        and item.planned_question.narrowing_questions
                    ):
                        directive = item.planned_question.narrowing_questions[0]
                        next_action = "NARROWING"
                    elif (
                        eval_enum == EvaluationResultType.MISCONCEPTION
                        and item.planned_question.collision_check_questions
                    ):
                        directive = item.planned_question.collision_check_questions[0]
                        next_action = "COLLISION"
                    elif item.planned_question.scaffolding_hints:
                        directive = item.planned_question.scaffolding_hints[0]
                        next_action = "SCAFFOLDING"
                    else:
                        directive = (
                            f"Approfondisci la definizione di {item.concept_name}."
                        )
                else:
                    item.status = (
                        PlanItemStatus.PARTIALLY_MASTERED
                        if eval_enum == EvaluationResultType.PARTIAL
                        else PlanItemStatus.UNMASTERED
                    )
                    next_item = plan.advance_to_next()
                    if next_item:
                        next_concept = next_item.concept_id
                        directive = next_item.planned_question.main_question
                        next_action = "NEXT_CONCEPT_AFTER_FAIL"
                    else:
                        next_action = "EXAM_COMPLETED"
                        directive = "L'esame è concluso."

        return {
            "concept_id": concept_id,
            "evaluation": eval_enum.value,
            "mastery_score": updated_node.mastery_score if updated_node else 0.5,
            "mastery_delta": mastery_delta,
            "next_action": next_action,
            "next_concept": next_concept,
            "spoken_directive": directive,
        }

    async def generate_final_report(
        self, session_history: list[dict[str, Any]]
    ) -> dict[str, Any]:
        """Generates post-examination diagnostic report and Root Cause Analysis."""
        return await self.report_generator.generate_diagnostic_report(session_history)
