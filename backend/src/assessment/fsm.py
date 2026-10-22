"""Pedagogical Finite State Machine (FSM) for dynamic oral examination navigation.

Determines the next pedagogical state and target concept by traversing the knowledge graph
based on student evaluation outcomes (accurate, memorized, vague, hesitant, misconception)
and scaffolding attempt thresholds.
"""

from __future__ import annotations

import logging
from collections.abc import Sequence

from config import config
from rag.models import ConceptNode, EvaluationResultType, PedagogicalState

logger = logging.getLogger("agent.assessment.fsm")


class OralExaminerFSM:
    """Finite State Machine orchestrating pedagogical transitions and graph exploration."""

    def __init__(self, max_scaffolding_attempts: int | None = None) -> None:
        self.max_scaffolding_attempts = (
            max_scaffolding_attempts
            if max_scaffolding_attempts is not None
            else config.max_scaffolding_attempts
        )

    def determine_next_transition(
        self,
        current_concept: ConceptNode,
        evaluation: EvaluationResultType,
        consecutive_failures: int,
        prerequisites: Sequence[ConceptNode],
        causal_targets: Sequence[ConceptNode],
        contrasting_concepts: Sequence[ConceptNode],
        multi_hop_neighbors: Sequence[ConceptNode],
        all_concepts: Sequence[ConceptNode],
    ) -> tuple[PedagogicalState, str, str]:
        """Calculates the next pedagogical transition and target concept.

        Args:
            current_concept: Currently examined ConceptNode.
            evaluation: Evaluation classification of student's response.
            consecutive_failures: Number of consecutive unsuccessful attempts on this concept.
            prerequisites: Direct prerequisites of the current concept in the graph.
            causal_targets: Downstream causal effect concepts in the graph.
            contrasting_concepts: Confusable/contrasting concepts connected via CONTRASTS_WITH.
            multi_hop_neighbors: 2-hop connected concepts for synthesis testing.
            all_concepts: Full list of all indexed concepts in the ontology.

        Returns:
            Tuple of (next_pedagogical_state, next_target_concept_id, graph_relation_followed).
        """
        current_id = current_concept.id

        # 1. ACCURATE response -> Multi-hop synthesis or advance to unmastered topic
        if evaluation == EvaluationResultType.ACCURATE:
            if multi_hop_neighbors:
                target = multi_hop_neighbors[0]
                return (
                    PedagogicalState.MULTI_HOP_SYNTHESIS,
                    target.id,
                    "MULTI_HOP",
                )
            if causal_targets:
                target = causal_targets[0]
                return (
                    PedagogicalState.MULTI_HOP_SYNTHESIS,
                    target.id,
                    "CAUSES",
                )
            # Advance to next untested / unmastered concept
            candidates = [
                c for c in all_concepts if c.id != current_id and c.mastery_score < 0.80
            ]
            if candidates:
                next_c = sorted(candidates, key=lambda x: x.mastery_score)[0]
                return (
                    PedagogicalState.EXPLORATION,
                    next_c.id,
                    "NONE",
                )
            return PedagogicalState.EXPLORATION, current_id, "NONE"

        # 2. MEMORIZED response (Textbook repeat without deep synthesis) -> Stress test
        if evaluation == EvaluationResultType.MEMORIZED:
            return (
                PedagogicalState.STRESS_TEST,
                current_id,
                "NONE",
            )

        # 3. VAGUE response (Keywords present, no mechanisms) -> Causal narrowing
        if evaluation == EvaluationResultType.VAGUE:
            if causal_targets:
                return (
                    PedagogicalState.CAUSAL_NARROWING,
                    current_id,
                    "CAUSES",
                )
            return (
                PedagogicalState.CAUSAL_NARROWING,
                current_id,
                "NONE",
            )

        # 4. HESITANT response -> Scaffolding or Prerequisite Fallback
        if evaluation == EvaluationResultType.HESITANT:
            if consecutive_failures > self.max_scaffolding_attempts and prerequisites:
                # Repeated failure threshold exceeded: Trigger Prerequisite Fallback
                target_prereq = prerequisites[0]
                return (
                    PedagogicalState.PREREQUISITE_FALLBACK,
                    target_prereq.id,
                    "REQUIRES",
                )
            return (
                PedagogicalState.SCAFFOLDING,
                current_id,
                "NONE",
            )

        # 5. MISCONCEPTION / MISTAKE -> Conceptual Collision or Prerequisite Fallback
        if evaluation == EvaluationResultType.MISCONCEPTION:
            if contrasting_concepts:
                return (
                    PedagogicalState.CONCEPTUAL_COLLISION,
                    current_id,
                    "CONTRASTS_WITH",
                )
            if consecutive_failures > self.max_scaffolding_attempts and prerequisites:
                return (
                    PedagogicalState.PREREQUISITE_FALLBACK,
                    prerequisites[0].id,
                    "REQUIRES",
                )
            return (
                PedagogicalState.SCAFFOLDING,
                current_id,
                "NONE",
            )

        # Default fallback
        return PedagogicalState.EXPLORATION, current_id, "NONE"
