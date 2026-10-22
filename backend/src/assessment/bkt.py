r"""Graph-aware Bayesian Knowledge Tracing (BKT) engine.

Models student mastery probability \(P(L_t)\) for each ontological concept in the knowledge graph.
Updates mastery dynamically upon student responses based on accuracy, partial understanding,
hesitation, or misconceptions, and propagates degradation to dependent concepts.
"""

from __future__ import annotations

import logging

from config import config
from rag.graph_store import BaseGraphStore
from rag.models import ConceptNode, EvaluationResultType

logger = logging.getLogger("agent.assessment.bkt")


class BayesianKnowledgeTracing:
    """Graph-aware Bayesian Knowledge Tracing (BKT) and mastery score propagation.

    Attributes:
        graph_store: Backend graph database interface (Neo4j or InMemoryGraphStore).
        accurate_gain: Multiplier for mastery gain on correct answers.
        hesitation_decay: Multiplier decay applied on hesitant or vague answers.
        mistake_decay: Multiplier decay applied on severe misconceptions or errors.
        prerequisite_threshold: Mastery threshold below which dependent concepts are blocked.
    """

    def __init__(
        self,
        graph_store: BaseGraphStore,
        accurate_gain: float | None = None,
        hesitation_decay: float | None = None,
        mistake_decay: float | None = None,
        prerequisite_threshold: float | None = None,
    ) -> None:
        self.graph_store = graph_store
        self.accurate_gain = (
            accurate_gain if accurate_gain is not None else config.bkt_accurate_gain
        )
        self.hesitation_decay = (
            hesitation_decay
            if hesitation_decay is not None
            else config.bkt_hesitation_decay
        )
        self.mistake_decay = (
            mistake_decay if mistake_decay is not None else config.bkt_mistake_decay
        )
        self.prerequisite_threshold = (
            prerequisite_threshold
            if prerequisite_threshold is not None
            else config.bkt_prerequisite_threshold
        )

    def calculate_new_mastery(
        self, current_mastery: float, evaluation: EvaluationResultType
    ) -> tuple[float, int, int]:
        r"""Calculates new mastery score, hesitation delta, and mistake delta.

        Args:
            current_mastery: Previous mastery probability \([0.0, 1.0]\).
            evaluation: The evaluated response classification.

        Returns:
            Tuple of (new_mastery_score, hesitation_delta, mistake_delta).
        """
        m = current_mastery
        hesitation_delta = 0
        mistake_delta = 0

        if evaluation == EvaluationResultType.ACCURATE:
            new_m = m + (1.0 - m) * self.accurate_gain
        elif evaluation == EvaluationResultType.PARTIAL:
            new_m = m + (1.0 - m) * (self.accurate_gain * 0.45)
        elif evaluation == EvaluationResultType.MEMORIZED:
            new_m = m + (1.0 - m) * (self.accurate_gain * 0.5)
        elif evaluation in (EvaluationResultType.HESITANT, EvaluationResultType.VAGUE):
            new_m = m * self.hesitation_decay
            hesitation_delta = 1
        elif evaluation == EvaluationResultType.MISCONCEPTION:
            new_m = m * self.mistake_decay
            mistake_delta = 1
        else:
            new_m = m

        new_m = max(0.0, min(1.0, new_m))
        return new_m, hesitation_delta, mistake_delta

    async def update_concept_mastery(
        self, concept_id: str, evaluation: EvaluationResultType
    ) -> tuple[ConceptNode | None, float]:
        """Updates concept mastery in the graph and propagates prerequisite blockages.

        Args:
            concept_id: Identifier of the evaluated concept node.
            evaluation: The evaluated response classification.

        Returns:
            Tuple of (updated_concept_node, mastery_delta).
        """
        concept = await self.graph_store.get_concept(concept_id)
        if not concept:
            return None, 0.0

        old_score = concept.mastery_score
        new_score, h_delta, m_delta = self.calculate_new_mastery(old_score, evaluation)
        mastery_delta = new_score - old_score

        updated_concept = await self.graph_store.update_mastery(
            concept_id=concept_id,
            mastery_score=new_score,
            hesitation_delta=h_delta,
            mistake_delta=m_delta,
        )

        # Propagate degradation to dependent concepts if score dropped below threshold
        if new_score < self.prerequisite_threshold:
            blocked = await self.graph_store.propagate_prerequisite_degradation(
                threshold=self.prerequisite_threshold
            )
            if blocked:
                logger.info(
                    "Concept %s dropped below prerequisite threshold; blocked dependents: %s",
                    concept_id,
                    blocked,
                )

        return updated_concept, mastery_delta
