"""Examination planner engine.

Transforms indexed course ontologies into topologically sequenced oral examination plans
with pre-computed pedagogical questions, hints, and difficulty ratings.
"""

from __future__ import annotations

import logging
import uuid
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from planning.models import (
    ConceptPlanItem,
    ExaminationPlan,
    PlannedQuestion,
    QuestionDifficulty,
)
from rag.graph_store import BaseGraphStore
from rag.models import ConceptNode
from rag.vector_store import BaseVectorStore

logger = logging.getLogger("agent.planning.planner")


class ExaminationPlanner:
    """Generates structured, prerequisite-ordered oral examination plans from course knowledge graphs."""

    def __init__(
        self,
        graph_store: BaseGraphStore,
        vector_store: BaseVectorStore,
    ) -> None:
        self.graph_store = graph_store
        self.vector_store = vector_store

    def _topological_sort_concepts(
        self,
        all_concepts: Sequence[ConceptNode],
        prereqs_map: dict[str, list[str]],
    ) -> list[str]:
        """Topologically order concepts using Kahn's algorithm so prerequisites are examined first."""
        # in-degree represents how many unmet prerequisites a concept has
        concept_ids = [c.id for c in all_concepts]
        in_degree: dict[str, int] = dict.fromkeys(concept_ids, 0)
        dependents_map: dict[str, list[str]] = {cid: [] for cid in concept_ids}

        for cid, p_ids in prereqs_map.items():
            for pid in p_ids:
                if pid in in_degree:
                    in_degree[cid] += 1
                    dependents_map[pid].append(cid)

        # Queue concepts with zero prerequisites first
        queue = [cid for cid, deg in in_degree.items() if deg == 0]
        sorted_order: list[str] = []

        while queue:
            curr = queue.pop(0)
            sorted_order.append(curr)
            for dep in dependents_map.get(curr, []):
                in_degree[dep] -= 1
                if in_degree[dep] == 0:
                    queue.append(dep)

        # Append any remaining concepts (in case of cyclic prerequisites)
        cyclic_ids = [cid for cid in concept_ids if cid not in sorted_order]
        if cyclic_ids:
            logger.warning(
                "Prerequisite cycle detected among concepts %s; keeping them in source order after acyclic concepts",
                cyclic_ids,
            )
            sorted_order.extend(cyclic_ids)

        return sorted_order

    async def generate_plan(
        self,
        document_id: str = "course_doc",
        title: str = "Piano d'Esame Orale Universitario",
    ) -> ExaminationPlan:
        """Constructs an ExaminationPlan from the indexed graph and vector stores."""
        all_concepts = await self.graph_store.get_all_concepts()
        if not all_concepts:
            logger.warning(
                "No concepts found in graph store to generate examination plan."
            )
            return ExaminationPlan(
                plan_id=f"plan_{uuid.uuid4().hex[:8]}",
                document_id=document_id,
                title=title,
            )

        prereqs_map: dict[str, list[str]] = {}
        items: dict[str, ConceptPlanItem] = {}

        for concept in all_concepts:
            prereqs = await self.graph_store.get_prerequisites(concept.id)
            causal = await self.graph_store.get_causal_targets(concept.id)
            contrasts = await self.graph_store.get_contrasting_concepts(concept.id)

            prereqs_map[concept.id] = [p.id for p in prereqs]

            props = concept.properties or {}

            # Determine difficulty
            diff_str = str(props.get("difficulty", "")).upper()
            if diff_str == "EASY":
                difficulty = QuestionDifficulty.EASY
            elif diff_str == "HARD":
                difficulty = QuestionDifficulty.HARD
            elif diff_str == "MEDIUM":
                difficulty = QuestionDifficulty.MEDIUM
            else:
                prereq_count = len(prereqs)
                if prereq_count == 0:
                    difficulty = QuestionDifficulty.EASY
                elif prereq_count == 1:
                    difficulty = QuestionDifficulty.MEDIUM
                else:
                    difficulty = QuestionDifficulty.HARD

            ideal_answer = str(props.get("ideal_answer", "")).strip()

            # Extract key points
            raw_key_points = props.get("expected_key_points")
            if (
                raw_key_points
                and isinstance(raw_key_points, list)
                and len(raw_key_points) >= 2
            ):
                key_points = [
                    str(kp).strip() for kp in raw_key_points if str(kp).strip()
                ]
            else:
                gt_chunks = await self.vector_store.search(
                    query=f"{concept.name} {concept.summary}",
                    limit=3,
                    concept_id_filter=concept.id,
                )
                key_points = self._extract_clean_key_points(concept, gt_chunks)

            clean_name = concept.name.strip().rstrip(".:;,")

            # Main question
            main_q = str(props.get("main_question", "")).strip()
            if not main_q:
                main_q = f"Mi parli dei concetti fondamentali relativi a {clean_name}."

            # Narrowing questions
            raw_narrowing = props.get("narrowing_questions")
            if (
                raw_narrowing
                and isinstance(raw_narrowing, list)
                and len(raw_narrowing) > 0
            ):
                narrowing_q = [
                    str(nq).strip() for nq in raw_narrowing if str(nq).strip()
                ]
            else:
                narrowing_q = []
                if causal:
                    c_target_clean = causal[0].name.strip().rstrip(".:;,")
                    narrowing_q.append(
                        f"Nello specifico, qual è il legame causale tra {clean_name} e {c_target_clean}?"
                    )
                else:
                    narrowing_q.append(
                        f"Quali condizioni operative e caratteristiche regolano il funzionamento di {clean_name}?"
                    )

            # Scaffolds
            raw_scaffolds = props.get("scaffolding_hints")
            if (
                raw_scaffolds
                and isinstance(raw_scaffolds, list)
                and len(raw_scaffolds) > 0
            ):
                scaffolds = [str(sh).strip() for sh in raw_scaffolds if str(sh).strip()]
            else:
                scaffolds = []
                if prereqs:
                    p_clean = prereqs[0].name.strip().rstrip(".:;,")
                    scaffolds.append(
                        f"Pensa alla relazione con {p_clean}: come si collega a {clean_name}?"
                    )
                else:
                    scaffolds.append(
                        f"Prova a partire dalla definizione di base e dai principi di {clean_name}."
                    )

            # Stress tests
            raw_stress = props.get("stress_test_questions")
            if raw_stress and isinstance(raw_stress, list) and len(raw_stress) > 0:
                stress_tests = [str(st).strip() for st in raw_stress if str(st).strip()]
            else:
                stress_tests = [
                    f"Puoi fare un esempio pratico o un caso d'uso reale di {clean_name}?"
                ]

            # Collision checks
            raw_collision = props.get("collision_check_questions")
            if (
                raw_collision
                and isinstance(raw_collision, list)
                and len(raw_collision) > 0
            ):
                collision_checks = [
                    str(cc).strip() for cc in raw_collision if str(cc).strip()
                ]
            else:
                collision_checks = []
                if contrasts:
                    cw_clean = contrasts[0].name.strip().rstrip(".:;,")
                    collision_checks.append(
                        f"Qual è la distinzione fondamentale tra {clean_name} e {cw_clean}?"
                    )

            planned_q = PlannedQuestion(
                question_id=f"q_{concept.id}",
                concept_id=concept.id,
                main_question=main_q,
                ideal_answer=ideal_answer,
                narrowing_questions=narrowing_q,
                scaffolding_hints=scaffolds,
                stress_test_questions=stress_tests,
                collision_check_questions=collision_checks,
                difficulty=difficulty,
                expected_key_points=key_points,
                mastery_threshold=0.75,
                max_attempts=2,
            )

            item = ConceptPlanItem(
                concept_id=concept.id,
                concept_name=concept.name,
                summary=concept.summary,
                prerequisites=[p.id for p in prereqs],
                causal_effects=[c.id for c in causal],
                contrasts_with=[cw.id for cw in contrasts],
                planned_question=planned_q,
            )
            items[concept.id] = item

        ordered_ids = self._topological_sort_concepts(all_concepts, prereqs_map)

        plan = ExaminationPlan(
            plan_id=f"plan_{uuid.uuid4().hex[:8]}",
            document_id=document_id,
            title=title,
            concept_order=ordered_ids,
            items=items,
            current_index=0,
            is_completed=False,
        )

        logger.info(
            "Generated examination plan '%s' with %d planned concepts in pedagogical order: %s",
            plan.plan_id,
            len(ordered_ids),
            ordered_ids,
        )
        return plan

    @staticmethod
    def _extract_clean_key_points(
        concept: ConceptNode, gt_chunks: Sequence[Any]
    ) -> list[str]:
        """Extract clean, complete, pedagogically informative bullet points for expected student answers."""
        import re

        key_points: list[str] = []
        seen = set()

        # 1. Add sentences from the concept summary
        if concept.summary:
            for sentence in re.split(r"(?<=[.!?])\s+", concept.summary):
                s_clean = sentence.strip()
                s_clean = re.sub(r"[:\s.]+$", ".", s_clean)
                if (
                    len(s_clean) > 20
                    and len(s_clean.split()) >= 4
                    and s_clean.lower() not in seen
                ):
                    seen.add(s_clean.lower())
                    key_points.append(s_clean)

        # 2. Extract substantive bullet points from retrieved ground-truth chunks
        for chunk in gt_chunks:
            chunk_text = getattr(chunk, "text", "")
            chunk_title = getattr(chunk, "section_title", "")
            for line in chunk_text.splitlines():
                l_clean = line.strip()
                if not l_clean or l_clean.startswith("##"):
                    continue
                # Remove leading bullet characters
                l_clean = re.sub(r"^-\s*", "", l_clean).strip()
                # Avoid slide titles or short fragments
                if len(l_clean) < 25 or len(l_clean.split()) < 5:
                    continue
                if l_clean.lower() in (concept.name.lower(), chunk_title.lower()):
                    continue
                l_clean = re.sub(r"[:\s.]+$", ".", l_clean)
                if l_clean.lower() not in seen and len(key_points) < 5:
                    seen.add(l_clean.lower())
                    key_points.append(l_clean)

        if not key_points and concept.summary:
            key_points.append(concept.summary)
        elif not key_points:
            key_points.append(
                f"Comprensione e padronanza dei principi fondamentali di {concept.name}."
            )

        return key_points[:5]

    @staticmethod
    def save_plan_to_file(plan: ExaminationPlan, file_path: str | Path) -> None:
        """Persist examination plan to JSON file."""
        path = Path(file_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(plan.to_json(), encoding="utf-8")
        logger.info("Saved ExaminationPlan to %s", path)

    @staticmethod
    def load_plan_from_file(file_path: str | Path) -> ExaminationPlan:
        """Load examination plan from JSON file."""
        path = Path(file_path)
        if not path.exists():
            raise FileNotFoundError(f"Plan file not found at: {path}")
        content = path.read_text(encoding="utf-8")
        return ExaminationPlan.from_json(content)
