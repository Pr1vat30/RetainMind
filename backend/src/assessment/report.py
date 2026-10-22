"""Diagnostic reporting, Root Cause Analysis (RCA), and Longitudinal Iteration Comparison.

Aggregates session history, compares progress across multiple exam iterations,
and queries the knowledge graph to diagnose foundational gaps and highlight student improvements.
"""

from __future__ import annotations

import logging
from typing import Any

from rag.graph_store import BaseGraphStore

logger = logging.getLogger("agent.assessment.report")


class SessionReportGenerator:
    """Generates post-examination diagnostic summaries, RCA, and cross-iteration comparisons."""

    def __init__(self, graph_store: BaseGraphStore) -> None:
        self.graph_store = graph_store

    async def compare_iterations(
        self,
        current_history: list[dict[str, Any]],
        iterations_history: list[dict[str, Any]],
    ) -> dict[str, Any]:
        """Compares current exam attempt with previous iterations to track learning evolution.

        Args:
            current_history: Turn log of the current examination session.
            iterations_history: Archived records of previous exam iterations.

        Returns:
            Dictionary with delta mastery, recovered concepts, persistent gaps, and spoken comparison.
        """
        if not iterations_history:
            return {
                "has_previous_iterations": False,
                "spoken_comparison": "Questa è la prima iterazione dell'esame registrata.",
            }

        prev_iter = iterations_history[-1]
        prev_num = prev_iter.get("iteration", len(iterations_history))
        prev_avg = prev_iter.get("average_mastery", 0.0)
        prev_weak = set(prev_iter.get("weak_concepts", []))
        prev_mastered = set(prev_iter.get("mastered_concepts", []))

        all_concepts = await self.graph_store.get_all_concepts()
        curr_mastered = {c.name for c in all_concepts if c.mastery_score >= 0.80}
        curr_weak = {
            c.name
            for c in all_concepts
            if c.mastery_score < 0.45 or c.mistake_count > 0
        }
        curr_avg = (
            sum(c.mastery_score for c in all_concepts) / len(all_concepts)
            if all_concepts
            else 0.0
        )

        mastery_delta = round(curr_avg - prev_avg, 2)
        recovered = list(prev_weak.intersection(curr_mastered))
        persistent_weak = list(prev_weak.intersection(curr_weak))
        regressed = list(prev_mastered.intersection(curr_weak))
        newly_mastered = list(curr_mastered.difference(prev_mastered))

        comparison_points: list[str] = []
        if mastery_delta > 0:
            comparison_points.append(
                f"Rispetto all'iterazione {prev_num}, la tua padronanza media è aumentata di {int(mastery_delta * 100)} punti percentuali."
            )
        elif mastery_delta < 0:
            comparison_points.append(
                f"Rispetto all'iterazione {prev_num}, la padronanza complessiva ha registrato una lieve flessione di {abs(int(mastery_delta * 100))} punti."
            )
        else:
            comparison_points.append(
                f"Rispetto all'iterazione {prev_num}, la padronanza media si mantiene costante."
            )

        if recovered:
            rec_str = ", ".join(f"'{c}'" for c in recovered[:3])
            comparison_points.append(
                f"Ottimo recupero: hai colmato le lacune precedenti su {rec_str}."
            )
        if persistent_weak:
            weak_str = ", ".join(f"'{c}'" for c in persistent_weak[:3])
            comparison_points.append(
                f"Rimangono ancora da consolidare i concetti di {weak_str}."
            )
        if regressed:
            reg_str = ", ".join(f"'{c}'" for c in regressed[:2])
            comparison_points.append(
                f"Attenzione a {reg_str}, dove sono emerse nuove incertezze rispetto alla prova precedente."
            )

        spoken_comparison = " ".join(comparison_points)

        return {
            "has_previous_iterations": True,
            "compared_iteration": prev_num,
            "previous_average_mastery": round(prev_avg, 2),
            "current_average_mastery": round(curr_avg, 2),
            "mastery_delta": mastery_delta,
            "recovered_concepts": recovered,
            "persistent_weak_concepts": persistent_weak,
            "newly_mastered_concepts": newly_mastered,
            "regressed_concepts": regressed,
            "spoken_comparison": spoken_comparison,
        }

    async def generate_diagnostic_report(
        self,
        session_history: list[dict[str, Any]],
        iterations_history: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        """Generates a structured report and conversational summary of the exam session.

        Args:
            session_history: Chronological log of student answers, scores, and transitions.
            iterations_history: Optional history of previous iterations for comparative analytics.

        Returns:
            Dictionary containing average mastery, lists of mastered/weak concepts,
            root cause analysis traces, iteration comparison, and a spoken natural language summary.
        """
        all_concepts = await self.graph_store.get_all_concepts()
        rca_data = await self.graph_store.get_root_cause_analysis()

        mastered = [c for c in all_concepts if c.mastery_score >= 0.80]
        weak = [
            c for c in all_concepts if c.mastery_score < 0.45 or c.mistake_count > 0
        ]
        in_progress = [
            c
            for c in all_concepts
            if 0.45 <= c.mastery_score < 0.80 and c.mistake_count == 0
        ]

        avg_mastery = (
            sum(c.mastery_score for c in all_concepts) / len(all_concepts)
            if all_concepts
            else 0.0
        )

        # Build diagnostic advice
        advice_points: list[str] = []
        if rca_data:
            for item in rca_data[:3]:
                failed = item.get("failed_concept_name", "Argomento")
                root = item.get("root_cause_name", "Prerequisito")
                advice_points.append(
                    f"Le difficoltà riscontrate su '{failed}' derivano da una lacuna nel prerequisito fondamentale '{root}'."
                )
        elif weak:
            for w in weak[:3]:
                advice_points.append(
                    f"Si consiglia di consolidare i fondamenti di '{w.name}'."
                )
        else:
            advice_points.append(
                "Ottima padronanza complessiva dei concetti esaminati."
            )

        spoken_summary = " ".join(advice_points)

        iteration_comp = None
        if iterations_history:
            iteration_comp = await self.compare_iterations(
                current_history=session_history,
                iterations_history=iterations_history,
            )

        return {
            "total_turns": len(session_history),
            "average_mastery": round(avg_mastery, 2),
            "mastered_concepts": [c.name for c in mastered],
            "weak_concepts": [c.name for c in weak],
            "in_progress_concepts": [c.name for c in in_progress],
            "root_cause_analysis": rca_data,
            "spoken_summary": spoken_summary,
            "iteration_comparison": iteration_comp,
        }
