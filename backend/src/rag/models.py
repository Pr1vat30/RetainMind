"""Data models and schemas for Knowledge Graph, Hybrid RAG, and Real-time Assessment.

Defines schemas for ontological concepts, graph relationships, semantic document chunks,
ground truth passages, evaluation results, and context payloads for the oral examiner.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


class EvaluationResultType(str, Enum):
    """Categorical outcome of student oral response evaluation."""

    ACCURATE = "ACCURATE"
    PARTIAL = "PARTIAL"
    VAGUE = "VAGUE"
    HESITANT = "HESITANT"
    MISCONCEPTION = "MISCONCEPTION"
    MEMORIZED = "MEMORIZED"


class PedagogicalState(str, Enum):
    """Pedagogical dialogue state guiding the examiner's next action."""

    EXPLORATION = "EXPLORATION"
    CAUSAL_NARROWING = "CAUSAL_NARROWING"
    SCAFFOLDING = "SCAFFOLDING"
    CONCEPTUAL_COLLISION = "CONCEPTUAL_COLLISION"
    MULTI_HOP_SYNTHESIS = "MULTI_HOP_SYNTHESIS"
    STRESS_TEST = "STRESS_TEST"
    PREREQUISITE_FALLBACK = "PREREQUISITE_FALLBACK"


class RelationType(str, Enum):
    """Types of directed relationships in the course knowledge graph."""

    REQUIRES = "REQUIRES"
    CAUSES = "CAUSES"
    CONTRASTS_WITH = "CONTRASTS_WITH"
    DEFINES = "DEFINES"
    CONTAINS = "CONTAINS"
    HAS_CHUNK = "HAS_CHUNK"


class ConceptStatus(str, Enum):
    """Student mastery state for an individual concept."""

    UNTESTED = "UNTESTED"
    MASTERED = "MASTERED"
    IN_PROGRESS = "IN_PROGRESS"
    WEAK = "WEAK"
    BLOCKED_BY_PREREQUISITE = "BLOCKED_BY_PREREQUISITE"


class ConceptNode(BaseModel):
    """A single conceptual entity within the course knowledge graph."""

    id: str
    name: str
    summary: str = ""
    mastery_score: float = 0.50
    hesitation_count: int = 0
    mistake_count: int = 0
    status: ConceptStatus = ConceptStatus.UNTESTED
    last_tested: datetime | str | None = None
    prerequisites: list[str] = Field(default_factory=list)
    contrasts_with: list[str] = Field(default_factory=list)
    topic_id: str | None = None
    properties: dict[str, Any] = Field(default_factory=dict)


class ConceptRelation(BaseModel):
    """Directed edge connecting two concepts in the knowledge graph."""

    source_id: str
    target_id: str
    rel_type: RelationType
    condition: str | None = None
    properties: dict[str, Any] = Field(default_factory=dict)


class CausalChain(BaseModel):
    """Cause-and-effect relationship chain between concepts or phenomena."""

    cause: str
    effect: str
    condition: str | None = None


class DocumentChunk(BaseModel):
    """A semantic chunk of course material stored in the vector database."""

    chunk_id: str
    document_id: str = "default_doc"
    section_title: str = ""
    text: str
    token_count: int = 0
    concept_ids: list[str] = Field(default_factory=list)
    metadata: dict[str, Any] = Field(default_factory=dict)


class GroundTruthPassage(BaseModel):
    """A retrieved reference text passage from course documents with similarity score."""

    chunk_id: str
    text: str
    score: float = 1.0
    section_title: str = ""
    concept_id: str | None = None


class EvaluationDetail(BaseModel):
    """Detailed diagnostic results produced by the response evaluator."""

    evaluation_result: EvaluationResultType
    assessed_concept_id: str
    confidence: float = 1.0
    reasoning: str = ""
    covered_aspects: list[str] = Field(default_factory=list)
    uncovered_aspects: list[str] = Field(default_factory=list)
    missing_concepts: list[str] = Field(default_factory=list)
    missing_relations: list[str] = Field(default_factory=list)
    hesitation_detected: bool = False
    filler_word_count: int = 0
    pause_duration: float = 0.0


class TurnAssessmentState(BaseModel):
    """Summary of turn-level assessment and graph transition for the examiner."""

    assessed_concept_id: str
    evaluation_result: EvaluationResultType
    mastery_delta: float
    next_target_node: str
    graph_relation_followed: str


class ExaminerContext(BaseModel):
    """Enriched prompt payload supplied to the voice examiner model."""

    current_concept: ConceptNode
    pedagogical_state: PedagogicalState
    ground_truth_chunks: list[GroundTruthPassage] = Field(default_factory=list)
    prerequisites: list[ConceptNode] = Field(default_factory=list)
    causal_targets: list[ConceptNode] = Field(default_factory=list)
    contrasting_concepts: list[ConceptNode] = Field(default_factory=list)
    multi_hop_concepts: list[ConceptNode] = Field(default_factory=list)
    evaluation_detail: EvaluationDetail | None = None
    pedagogical_directive: str = ""
    ideal_answer: str = ""
    voice_formatting_instruction: str = ""
