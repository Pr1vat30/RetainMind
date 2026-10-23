"""Domain models for structured, adaptive oral examination planning.

Defines schemas for question blueprints, concept-level plan items,
deferred spaced-repetition retry queues, and overall examination plans.
"""

from __future__ import annotations

import json
from datetime import datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


class QuestionDifficulty(str, Enum):
    """Pedagogical difficulty level of an examination question."""

    EASY = "EASY"
    MEDIUM = "MEDIUM"
    HARD = "HARD"


class PlanItemStatus(str, Enum):
    """Progress status of a concept within the examination plan."""

    PENDING = "PENDING"
    IN_PROGRESS = "IN_PROGRESS"
    MASTERED = "MASTERED"
    PARTIALLY_MASTERED = "PARTIALLY_MASTERED"
    DEFERRED = "DEFERRED"
    UNMASTERED = "UNMASTERED"


class PlannedQuestion(BaseModel):
    """Pre-computed question blueprint with targeted pedagogical variants."""

    question_id: str
    concept_id: str
    main_question: str
    ideal_answer: str = ""
    narrowing_questions: list[str] = Field(default_factory=list)
    scaffolding_hints: list[str] = Field(default_factory=list)
    stress_test_questions: list[str] = Field(default_factory=list)
    collision_check_questions: list[str] = Field(default_factory=list)
    difficulty: QuestionDifficulty = QuestionDifficulty.MEDIUM
    expected_key_points: list[str] = Field(default_factory=list)
    mastery_threshold: float = 0.75
    max_attempts: int = 3


class ConceptPlanItem(BaseModel):
    """A scheduled milestone for a specific concept within the examination plan."""

    concept_id: str
    concept_name: str
    summary: str = ""
    prerequisites: list[str] = Field(default_factory=list)
    causal_effects: list[str] = Field(default_factory=list)
    contrasts_with: list[str] = Field(default_factory=list)
    planned_question: PlannedQuestion
    status: PlanItemStatus = PlanItemStatus.PENDING
    current_attempt: int = 0
    attempts_log: list[dict[str, Any]] = Field(default_factory=list)
    stress_test_pending: bool = False


class DeferredRetryItem(BaseModel):
    """Queue entry for a deferred concept scheduled for spaced-repetition re-examination."""

    concept_id: str
    required_correct_answers: int = 2
    correct_count_since_deferred: int = 0
    retry_cycle: int = 1
    max_retry_cycles: int = 1


class ExaminationPlan(BaseModel):
    """Complete, topologically sequenced oral examination plan with dynamic retry queue."""

    plan_id: str
    document_id: str = "default_doc"
    title: str = "Piano d'Esame Orale"
    created_at: str = Field(default_factory=lambda: datetime.now().isoformat())
    concept_order: list[str] = Field(default_factory=list)
    items: dict[str, ConceptPlanItem] = Field(default_factory=dict)
    deferred_queue: list[DeferredRetryItem] = Field(default_factory=list)
    current_index: int = 0
    is_completed: bool = False

    @property
    def current_item(self) -> ConceptPlanItem | None:
        """Retrieves the active ConceptPlanItem according to current_index."""
        if 0 <= self.current_index < len(self.concept_order):
            cid = self.concept_order[self.current_index]
            return self.items.get(cid)
        return None

    @property
    def progress_percentage(self) -> float:
        """Calculates completion percentage of the examination plan."""
        if not self.concept_order:
            return 100.0
        completed = sum(
            1
            for item in self.items.values()
            if item.status
            in (
                PlanItemStatus.MASTERED,
                PlanItemStatus.PARTIALLY_MASTERED,
                PlanItemStatus.UNMASTERED,
            )
        )
        return round((completed / len(self.concept_order)) * 100.0, 1)

    def defer_concept(
        self,
        concept_id: str,
        required_correct_answers: int = 2,
    ) -> None:
        """Defers a failed concept to be retried only after answering other questions correctly."""
        item = self.items.get(concept_id)
        if item:
            item.status = PlanItemStatus.DEFERRED

        # Check if already in queue
        existing = next(
            (d for d in self.deferred_queue if d.concept_id == concept_id), None
        )
        if not existing:
            self.deferred_queue.append(
                DeferredRetryItem(
                    concept_id=concept_id,
                    required_correct_answers=required_correct_answers,
                    correct_count_since_deferred=0,
                    retry_cycle=1,
                    max_retry_cycles=1,
                )
            )

    def on_correct_answer(self) -> str | None:
        """Increments correct answer count for all deferred concepts and returns

        the concept_id of any deferred concept ready to be re-examined.
        """
        ready_concept_id: str | None = None
        remaining_queue: list[DeferredRetryItem] = []

        for d in self.deferred_queue:
            d.correct_count_since_deferred += 1
            if (
                d.correct_count_since_deferred >= d.required_correct_answers
                and ready_concept_id is None
            ):
                ready_concept_id = d.concept_id
                item = self.items.get(d.concept_id)
                if item:
                    item.status = PlanItemStatus.IN_PROGRESS
                    item.current_attempt = 0  # Reset attempts for the retry cycle
            else:
                remaining_queue.append(d)

        self.deferred_queue = remaining_queue
        return ready_concept_id

    def advance_to_next(self) -> ConceptPlanItem | None:
        """Advances the examination plan pointer to the next scheduled concept."""
        self.current_index += 1
        if self.current_index >= len(self.concept_order):
            # Check if any deferred items remain
            if self.deferred_queue:
                # If all regular items are done, pick the deferred one
                deferred = self.deferred_queue.pop(0)
                item = self.items.get(deferred.concept_id)
                if item:
                    item.status = PlanItemStatus.IN_PROGRESS
                    item.current_attempt = 0
                    self.concept_order.append(deferred.concept_id)
                    return item
            self.is_completed = True
            return None

        next_item = self.current_item
        if next_item and next_item.status == PlanItemStatus.PENDING:
            next_item.status = PlanItemStatus.IN_PROGRESS
        return next_item

    def to_json(self, indent: int = 2) -> str:
        """Serializes the examination plan to a JSON string."""
        return self.model_dump_json(indent=indent)

    @classmethod
    def from_json(cls, json_str: str) -> ExaminationPlan:
        """Loads an ExaminationPlan instance from a JSON string."""
        data = json.loads(json_str)
        return cls.model_validate(data)
