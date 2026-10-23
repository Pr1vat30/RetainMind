"""Response evaluation engine for real-time oral examination.

Analyzes student spoken transcripts against target concepts, ontological relationships,
and ground-truth course excerpts. Classifies answers into pedagogical outcome types
(ACCURATE, PARTIAL, VAGUE, HESITANT, MISCONCEPTION, MEMORIZED) using acoustic/pause cues,
phonetic STT normalization, verbal filler detection, and semantic keyword matching.
"""

from __future__ import annotations

import logging
import re
from collections.abc import Sequence

from rag.models import (
    ConceptNode,
    EvaluationDetail,
    EvaluationResultType,
    GroundTruthPassage,
)

logger = logging.getLogger("agent.assessment.evaluator")

# -----------------------------------------------------------------------------
# Heuristic Dictionaries & Normalization Patterns
# -----------------------------------------------------------------------------

# Verbal hesitation markers (Italian and English conversational fillers)
HESITATION_WORDS: frozenset[str] = frozenset(
    {
        "ehm",
        "uhm",
        "um",
        "uh",
        "tipo",
        "forse",
        "non so",
        "credo",
        "penso",
        "maybe",
        "probably",
        "like",
    }
)

# Common STT phonetic misrecognitions for technical computer science / physics terms
STT_CORRECTIONS: dict[str, str] = {
    r"\bnão esse que ele\b": "nosql",
    r"\bnao esse que ele\b": "nosql",
    r"\bno esse que ele\b": "nosql",
    r"\bnon esse que ele\b": "nosql",
    r"\bno sql\b": "nosql",
    r"\bnon sql\b": "nosql",
    r"\bno-sql\b": "nosql",
    r"\bscreto\b": "schema",
    r"\br d b m s\b": "rdbms",
    r"\brdb ms\b": "rdbms",
    r"\bc a p\b": "cap",
    r"\bb c n f\b": "bcnf",
    r"\ba c i d\b": "acid",
    r"\bb a s e\b": "base",
    r"\bneo 4 j\b": "neo4j",
    r"\bmongo db\b": "mongodb",
}

# Stop words excluded from semantic overlap calculation
STOP_WORDS: frozenset[str] = frozenset(
    {
        "il",
        "la",
        "lo",
        "i",
        "le",
        "gli",
        "un",
        "una",
        "uno",
        "di",
        "a",
        "da",
        "in",
        "con",
        "su",
        "per",
        "tra",
        "fra",
        "del",
        "della",
        "dello",
        "dei",
        "degli",
        "delle",
        "al",
        "allo",
        "alla",
        "ai",
        "agli",
        "alle",
        "dal",
        "dallo",
        "dalla",
        "dai",
        "dagli",
        "dalle",
        "nel",
        "nello",
        "nella",
        "nei",
        "negli",
        "nelle",
        "sul",
        "sullo",
        "sulla",
        "sui",
        "sugli",
        "sulle",
        "e",
        "ed",
        "o",
        "ma",
        "che",
        "cui",
        "quale",
        "quali",
        "non",
        "si",
        "ci",
        "vi",
        "ne",
        "ha",
        "hanno",
        "è",
        "sono",
        "era",
        "erano",
        "stato",
        "stata",
        "stati",
        "state",
        "sia",
        "siano",
        "the",
        "an",
        "of",
        "and",
        "is",
        "to",
        "for",
        "on",
        "at",
        "pagina",
        "slide",
        "corso",
        "lezione",
        "prof",
        "professore",
        "professoressa",
    }
)


class ResponseEvaluator:
    """Evaluates student's oral response against target concept and ground-truth passages."""

    def __init__(self, llm_evaluator_fn=None) -> None:
        self.llm_evaluator_fn = llm_evaluator_fn

    def evaluate_response(
        self,
        student_response: str,
        target_concept: ConceptNode,
        ground_truth: Sequence[GroundTruthPassage],
        contrasting_concepts: Sequence[ConceptNode] | None = None,
        pause_duration: float = 0.0,
        expected_key_points: Sequence[str] | None = None,
        ideal_answer: str = "",
    ) -> EvaluationDetail:
        """Lightweight dual-path evaluation classifying student's oral response.

        Args:
            student_response: Raw transcript of student's answer.
            target_concept: The ConceptNode currently being examined.
            ground_truth: Retrieved text passages from the course materials.
            contrasting_concepts: Related concepts that are easily confused.
            pause_duration: Measured latency (seconds) before student started speaking.

        Returns:
            EvaluationDetail containing classification, confidence, and diagnostic cues.
        """
        resp_lower = student_response.lower().strip()

        # 0. Normalize common STT phonetic distortions and transcription artifacts
        for pat, repl in STT_CORRECTIONS.items():
            resp_lower = re.sub(pat, repl, resp_lower)

        # 1. Detect Hesitation Signals (Audio pauses or verbal fillers)
        filler_count = sum(
            len(re.findall(rf"\b{re.escape(w)}\b", resp_lower))
            for w in HESITATION_WORDS
        )
        is_hesitant = (
            (filler_count >= 2)
            or (pause_duration > 2.2 and len(resp_lower) < 25)
            or (len(resp_lower) < 15 and filler_count >= 1)
        )

        # 2. Check for Misconception (Confusion with contrasting concept)
        contrasting_matches: list[str] = []
        if contrasting_concepts:
            for cw in contrasting_concepts:
                if cw.name.lower() in resp_lower or cw.id.lower() in resp_lower:
                    contrasting_matches.append(cw.name)

        target_terms = {
            token
            for token in re.findall(r"\w+", target_concept.name.lower())
            if token not in STOP_WORDS and len(token) > 2
        }
        target_mentioned = any(
            token in resp_lower or (len(token) >= 4 and token[:4] in resp_lower)
            for token in target_terms
        )
        if contrasting_matches and not target_mentioned:
            return EvaluationDetail(
                evaluation_result=EvaluationResultType.MISCONCEPTION,
                assessed_concept_id=target_concept.id,
                confidence=0.90,
                reasoning=f"Student confused '{target_concept.name}' with contrasting concept '{contrasting_matches[0]}'.",
                missing_concepts=[target_concept.name],
                hesitation_detected=is_hesitant,
                filler_word_count=filler_count,
                pause_duration=pause_duration,
            )

        # 3. Check for Hesitation
        if is_hesitant and (filler_count >= 2 or len(resp_lower) < 45):
            return EvaluationDetail(
                evaluation_result=EvaluationResultType.HESITANT,
                assessed_concept_id=target_concept.id,
                confidence=0.85,
                reasoning="Prolonged hesitation or high frequency of verbal fillers detected.",
                missing_concepts=[],
                hesitation_detected=True,
                filler_word_count=filler_count,
                pause_duration=pause_duration,
            )

        # 4. Multi-Faceted Semantic & Ground-Truth Matching
        gt_corpus = " ".join([gt.text.lower() for gt in ground_truth])
        rubric_text = " ".join(expected_key_points or [])
        full_reference_text = (
            f"{target_concept.name.lower()} {target_concept.summary.lower()} "
            f"{ideal_answer.lower()} {rubric_text.lower()} {gt_corpus}"
        )

        ref_words = set(re.findall(r"\w+", full_reference_text))
        meaningful_ref_terms = {
            t for t in ref_words if t not in STOP_WORDS and len(t) > 2
        }

        resp_words = set(re.findall(r"\w+", resp_lower))
        meaningful_resp_words = {
            t for t in resp_words if t not in STOP_WORDS and len(t) > 2
        }

        # Match conceptual stems (e.g. "scalabil" in "scalabilità", "relazion" in "relazionali")
        matched_ref_terms: set[str] = set()
        matched_resp_words: set[str] = set()

        for rw in meaningful_resp_words:
            for ref_t in meaningful_ref_terms:
                if rw == ref_t or (
                    len(rw) >= 4
                    and len(ref_t) >= 4
                    and (ref_t.startswith(rw[:4]) or rw.startswith(ref_t[:4]))
                ):
                    matched_ref_terms.add(ref_t)
                    matched_resp_words.add(rw)

        total_semantic_matches = len(matched_resp_words)
        total_content_words = len(meaningful_resp_words)
        covered_aspects_list = sorted(matched_resp_words)
        uncovered_aspects_list = sorted(meaningful_ref_terms - matched_ref_terms)[:6]

        # The plan rubric is more useful than whole-document keyword overlap.
        # A point counts only when its meaningful terms are represented in the
        # student's own answer, so copying the ideal answer still needs application.
        rubric_coverage = 1.0
        if expected_key_points:
            covered_points = 0
            for point in expected_key_points:
                point_terms = {
                    token
                    for token in re.findall(r"\w+", point.lower())
                    if token not in STOP_WORDS and len(token) > 2
                }
                point_coverage = sum(
                    1
                    for point_term in point_terms
                    if any(
                        response_term == point_term
                        or (
                            len(response_term) >= 4
                            and len(point_term) >= 4
                            and response_term[:4] == point_term[:4]
                        )
                        for response_term in meaningful_resp_words
                    )
                )
                if point_terms and point_coverage / len(point_terms) >= 0.5:
                    covered_points += 1
            rubric_coverage = covered_points / len(expected_key_points)

        # Check for textbook verbatim repetition (MEMORIZED)
        is_verbatim = False
        clean_resp = resp_lower.strip().rstrip(".:;,")
        for gt in ground_truth:
            clean_gt = gt.text.lower().strip().rstrip(".:;,")
            if len(clean_resp) > 30 and (
                clean_resp == clean_gt or clean_resp in clean_gt
            ):
                is_verbatim = True
                break

        if is_verbatim:
            return EvaluationDetail(
                evaluation_result=EvaluationResultType.MEMORIZED,
                assessed_concept_id=target_concept.id,
                confidence=0.90,
                reasoning="Student repeated textbook definition verbatim without personal explanation.",
                covered_aspects=covered_aspects_list,
                uncovered_aspects=[],
                hesitation_detected=is_hesitant,
                filler_word_count=filler_count,
                pause_duration=pause_duration,
            )

        # ---------------------------------------------------------------------
        # Balanced Evaluation: Neither trivial keyword-throwing nor verbatim repetition
        # ---------------------------------------------------------------------

        # ACCURATE: Student provides a coherent explanation articulating the technical mechanism
        # Requires: At least 3 distinct conceptual terms AND at least 6 meaningful content words (or dense coverage on short concepts)
        is_accurate = (not expected_key_points or rubric_coverage >= 0.6) and (
            (total_semantic_matches >= 3 and total_content_words >= 6)
            or (
                total_semantic_matches >= 2
                and len(meaningful_ref_terms) <= 3
                and total_content_words >= 4
            )
            or (total_semantic_matches >= 4 and total_content_words >= 5)
        )

        if is_accurate:
            return EvaluationDetail(
                evaluation_result=EvaluationResultType.ACCURATE,
                assessed_concept_id=target_concept.id,
                confidence=0.92,
                reasoning="Accurate and articulate conceptual explanation with functional grounding.",
                covered_aspects=covered_aspects_list,
                uncovered_aspects=[],
                missing_concepts=[],
                hesitation_detected=is_hesitant,
                filler_word_count=filler_count,
                pause_duration=pause_duration,
            )

        # PARTIAL: Student touched macro-topics or keywords but lacked full technical articulation
        # (e.g. 2 keywords without deep elaboration, or 1 concept with >= 5 content words)
        is_partial = (total_semantic_matches >= 2 and total_content_words >= 3) or (
            total_semantic_matches >= 1 and total_content_words >= 5
        )

        if is_partial:
            return EvaluationDetail(
                evaluation_result=EvaluationResultType.PARTIAL,
                assessed_concept_id=target_concept.id,
                confidence=0.82,
                reasoning="Student mentioned relevant macro-concepts but lacked detailed technical articulation.",
                covered_aspects=covered_aspects_list,
                uncovered_aspects=uncovered_aspects_list,
                missing_concepts=[target_concept.name],
                hesitation_detected=is_hesitant,
                filler_word_count=filler_count,
                pause_duration=pause_duration,
            )

        # VAGUE: Isolated keyword or generic phrase without conceptual substance
        if total_semantic_matches >= 1 or total_content_words >= 3:
            return EvaluationDetail(
                evaluation_result=EvaluationResultType.VAGUE,
                assessed_concept_id=target_concept.id,
                confidence=0.75,
                reasoning="Generic or isolated keyword-based answer without functional explanation.",
                covered_aspects=covered_aspects_list,
                uncovered_aspects=uncovered_aspects_list,
                missing_concepts=[target_concept.name],
                hesitation_detected=is_hesitant,
                filler_word_count=filler_count,
                pause_duration=pause_duration,
            )

        # If answer is off-topic or empty
        if len(resp_words) < 4:
            return EvaluationDetail(
                evaluation_result=EvaluationResultType.HESITANT,
                assessed_concept_id=target_concept.id,
                confidence=0.75,
                reasoning="Minimal student response.",
                covered_aspects=[],
                uncovered_aspects=uncovered_aspects_list,
                hesitation_detected=True,
                filler_word_count=filler_count,
                pause_duration=pause_duration,
            )

        return EvaluationDetail(
            evaluation_result=EvaluationResultType.VAGUE,
            assessed_concept_id=target_concept.id,
            confidence=0.70,
            reasoning="Answer lacked specific causal mechanism and ground-truth alignment.",
            covered_aspects=covered_aspects_list,
            uncovered_aspects=uncovered_aspects_list,
            missing_concepts=[target_concept.name],
            hesitation_detected=is_hesitant,
            filler_word_count=filler_count,
            pause_duration=pause_duration,
        )
