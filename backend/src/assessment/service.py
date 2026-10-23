"""Session Management Service.

Provides a unified programmatic interface for terminal CLI commands, future Web/UI controllers,
and API endpoints to control oral examination session lifecycle (status, pause, resume,
repeat/restart with dynamic adaptation, history inspection, and cross-iteration comparison).
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from assessment.report import SessionReportGenerator
from assessment.state import (
    SessionAssessmentManager,
    SessionStatus,
    is_silence_or_noise,
)
from config import config
from rag import create_graph_store, create_vector_store

logger = logging.getLogger("agent.assessment.service")


class SessionService:
    """Service layer for inspecting and mutating examination session state."""

    def __init__(
        self,
        state_file_path: str | Path | None = None,
        plan_file_path: str | Path | None = None,
        events_file_path: str | Path | None = None,
        execution_mode: str = "console",
        course_id: str | None = None,
    ) -> None:
        from assessment.courses import CourseManager

        target_course_id = course_id or CourseManager.get_active_course_id()
        if target_course_id:
            course_dir = CourseManager.get_course_dir(target_course_id)
            default_state = course_dir / "state.json"
            default_plan = course_dir / "plan.json"
            default_events = course_dir / "events.jsonl"
        else:
            default_state = CourseManager.DATA_DIR / "session_state.json"
            default_plan = CourseManager.DATA_DIR / "examination_plan.json"
            default_events = CourseManager.DATA_DIR / "session_events.jsonl"

        self.course_id = target_course_id
        self._custom_state_path = state_file_path is not None
        self.state_file_path = (
            Path(state_file_path)
            if state_file_path is not None
            else default_state
        )
        self.plan_file_path = (
            Path(plan_file_path)
            if plan_file_path is not None
            else default_plan
        )
        self.events_file_path = (
            Path(events_file_path)
            if events_file_path is not None
            else default_events
        )
        self.execution_mode = execution_mode

    def _load_manager(self) -> SessionAssessmentManager:
        """Helper to instantiate SessionAssessmentManager with existing state and graph stores."""
        g_store = create_graph_store(
            "neo4j" if config.neo4j_uri != "bolt://localhost:7687" else "memory"
        )
        v_store = create_vector_store(
            "qdrant" if config.qdrant_url != "http://localhost:6333" else "memory"
        )

        plan = None
        if self.plan_file_path.exists():
            try:
                from planning import ExaminationPlanner

                plan = ExaminationPlanner.load_plan_from_file(self.plan_file_path)
            except Exception as err:
                logger.warning(
                    "Could not load plan file %s: %s", self.plan_file_path, err
                )

        manager = SessionAssessmentManager(
            graph_store=g_store,
            vector_store=v_store,
            examination_plan=plan,
            state_file_path=self.state_file_path,
            events_file_path=self.events_file_path,
            execution_mode=self.execution_mode,
        )

        if self.state_file_path.exists():
            manager.load_session_state(self.state_file_path)

        return manager

    def get_status(self) -> dict[str, Any]:
        """Returns the current state and metrics of the active examination session."""
        if not self.state_file_path.exists():
            return {
                "has_active_session": False,
                "status": "NOT_INITIALIZED",
                "message": "Nessuna sessione d'esame attiva o salvata trovata.",
            }

        # Fast-path: read directly from state JSON without instantiating Neo4j / Qdrant stores
        try:
            import json

            state_data = json.loads(self.state_file_path.read_text(encoding="utf-8"))
            plan_data = state_data.get("examination_plan") or {}
            concept_order = plan_data.get("concept_order") or []
            curr_idx = (plan_data.get("current_index", 0) + 1) if concept_order else 0
            total_items = len(concept_order)
            deferred = [
                d.get("concept_id") if isinstance(d, dict) else str(d)
                for d in plan_data.get("deferred_queue", [])
            ]

            # Resolve pure academic question for current concept (without conversational chatter)
            curr_cid = state_data.get("current_concept_id")
            items = plan_data.get("items") or {}
            curr_question = ""
            if curr_cid and curr_cid in items:
                curr_question = items[curr_cid].get("planned_question", {}).get("main_question", "")
            if not curr_question and self.plan_file_path.exists():
                try:
                    p_data = json.loads(self.plan_file_path.read_text(encoding="utf-8"))
                    p_items = p_data.get("items") or {}
                    if curr_cid and curr_cid in p_items:
                        curr_question = p_items[curr_cid].get("planned_question", {}).get("main_question", "")
                    elif not curr_cid and p_data.get("concept_order"):
                        first_cid = p_data["concept_order"][0]
                        curr_question = p_items.get(first_cid, {}).get("planned_question", {}).get("main_question", "")
                except Exception:
                    pass

            return {
                "has_active_session": True,
                "student_id": state_data.get("student_id", "student_default"),
                "status": state_data.get("status", "ACTIVE"),
                "current_iteration": state_data.get("current_iteration", 1),
                "current_concept_id": state_data.get("current_concept_id"),
                "current_question": curr_question,
                "pedagogical_state": state_data.get("current_pedagogical_state", "EXPLORATION"),
                "turns_in_current_iteration": len(state_data.get("history", [])),
                "total_iterations_completed": len(state_data.get("iterations_history", [])),
                "plan_progress_percentage": plan_data.get("progress_percentage", 0.0),
                "plan_step": f"{curr_idx}/{total_items}" if total_items else "N/A",
                "deferred_queue": deferred,
            }
        except Exception as e:
            logger.debug("Fast-path get_status fallback: %s", e)
            manager = self._load_manager()
            plan_progress = (
                manager.examination_plan.progress_percentage
                if manager.examination_plan
                else 0.0
            )
            total_items = (
                len(manager.examination_plan.concept_order)
                if manager.examination_plan
                else 0
            )
            curr_idx = (
                (manager.examination_plan.current_index + 1)
                if manager.examination_plan
                else 0
            )

            curr_q_fallback = ""
            if manager.examination_plan and manager.current_concept_id:
                item = manager.examination_plan.items.get(manager.current_concept_id)
                if item and hasattr(item, "planned_question") and hasattr(item.planned_question, "main_question"):
                    curr_q_fallback = item.planned_question.main_question
            elif manager.examination_plan and manager.examination_plan.current_item:
                item = manager.examination_plan.current_item
                if hasattr(item, "planned_question") and hasattr(item.planned_question, "main_question"):
                    curr_q_fallback = item.planned_question.main_question

            return {
                "has_active_session": True,
                "student_id": manager.student_id,
                "status": manager.status.value,
                "current_iteration": manager.current_iteration,
                "current_concept_id": manager.current_concept_id,
                "current_question": curr_q_fallback,
                "pedagogical_state": manager.current_pedagogical_state.value,
                "turns_in_current_iteration": len(manager.history),
                "total_iterations_completed": len(manager.iterations_history),
                "plan_progress_percentage": plan_progress,
                "plan_step": f"{curr_idx}/{total_items}" if total_items else "N/A",
                "deferred_queue": (
                    [d.concept_id for d in manager.examination_plan.deferred_queue]
                    if manager.examination_plan
                    else []
                ),
            }

    async def pause(self, reason: str = "") -> dict[str, Any]:
        """Pauses the active examination session and persists the state."""
        manager = self._load_manager()
        ctx, _ = await manager.pause_session(reason=reason)
        return {
            "success": True,
            "status": manager.status.value,
            "paused_concept_id": manager.current_concept_id,
            "iteration": manager.current_iteration,
            "spoken_directive": ctx.pedagogical_directive,
        }

    async def resume(self) -> dict[str, Any]:
        """Resumes a paused examination session."""
        if not self.state_file_path.exists():
            raise FileNotFoundError("Nessuna sessione salvata da riprendere.")

        manager = self._load_manager()
        if (
            manager.status != SessionStatus.PAUSED
            and manager.status != SessionStatus.ACTIVE
        ):
            logger.info("Resuming session that was in state: %s", manager.status.value)

        ctx, _ = await manager.resume_session()
        return {
            "success": True,
            "status": manager.status.value,
            "current_concept_id": manager.current_concept_id,
            "iteration": manager.current_iteration,
            "spoken_directive": ctx.pedagogical_directive,
        }

    async def repeat(self, adapt: bool = True) -> dict[str, Any]:
        """Restarts the examination as a new iteration with dynamic adaptation."""
        manager = self._load_manager()
        ctx, _ = await manager.restart_examination(adapt_from_previous=adapt)
        return {
            "success": True,
            "status": manager.status.value,
            "new_iteration": manager.current_iteration,
            "total_archived_iterations": len(manager.iterations_history),
            "first_concept_id": manager.current_concept_id,
            "spoken_directive": ctx.pedagogical_directive,
        }

    def get_history(self) -> list[dict[str, Any]]:
        """Returns all completed and active discussions history.
        Uses CourseManager to return the unified list of Document Discussion Items.
        """
        if not getattr(self, "_custom_state_path", False):
            try:
                from assessment.courses import CourseManager

                courses = CourseManager.list_courses()
                if courses:
                    return CourseManager.get_discussions_history()
                return []
            except Exception as e:
                logger.debug("Falling back to local state_file_path for history: %s", e)

        if not self.state_file_path.exists():
            return []
        manager = self._load_manager()
        history_list: list[dict[str, Any]] = []

        cid = (
            self.course_id
            or (manager.examination_plan.document_id if manager.examination_plan and manager.examination_plan.document_id else None)
            or (self.state_file_path.parent.name if self.state_file_path.parent.name not in ("data", "backend") else None)
            or "default"
        )

        for it in manager.iterations_history:
            turns = it.get("history", [])
            ts = it.get("timestamp") or (
                turns[-1].get("timestamp", turns[0].get("timestamp", ""))
                if turns
                else ""
            )
            it_num = it.get("iteration", 1)
            title = (
                it.get("title") or it.get("plan_title") or f"Conversazione #{it_num}"
            )
            history_list.append(
                {
                    "id": cid,
                    "course_id": cid,
                    "iteration": it_num,
                    "status": "COMPLETED",
                    "is_current": False,
                    "average_mastery": it.get("average_mastery", 0.0),
                    "mastered_concepts": it.get("mastered_concepts", []),
                    "weak_concepts": it.get("weak_concepts", []),
                    "turns_completed": len(turns),
                    "timestamp": ts,
                    "title": title,
                    "plan_title": it.get("plan_title", title),
                    "concepts": it.get("concepts", []),
                }
            )

        # Current ongoing iteration overview
        if manager.status in (SessionStatus.ACTIVE, SessionStatus.PAUSED):
            curr_ts = ""
            mastered: list[str] = []
            weak: list[str] = []
            avg_m: float = 0.0

            if manager.history:
                curr_ts = manager.history[-1].get(
                    "timestamp", manager.history[0].get("timestamp", "")
                )
                evaluated_turns = [
                    t for t in manager.history if t.get("evaluation_result")
                ]
                for t in evaluated_turns:
                    res = str(t.get("evaluation_result", "")).upper()
                    cname = t.get("concept_name") or t.get("concept_id", "")
                    if not cname:
                        continue
                    if res in ("ACCURATE", "MASTERED") and cname not in mastered:
                        mastered.append(cname)
                    elif (
                        res
                        in ("MISCONCEPTION", "VAGUE", "HESITANT", "WEAK", "OFF_TOPIC")
                        and cname not in weak
                    ):
                        weak.append(cname)

                total_concepts = (
                    len(manager.examination_plan.concept_order)
                    if manager.examination_plan
                    and manager.examination_plan.concept_order
                    else len(evaluated_turns)
                )
                if total_concepts > 0 and len(evaluated_turns) > 0:
                    avg_m = round(len(mastered) / total_concepts, 2)

            curr_title = (
                manager.examination_plan.title
                if manager.examination_plan
                else f"Conversazione #{manager.current_iteration}"
            )
            curr_concepts = []
            if manager.examination_plan:
                for co_id in manager.examination_plan.concept_order:
                    if co_id in manager.examination_plan.items:
                        it_obj = manager.examination_plan.items[co_id]
                        curr_concepts.append(
                            {
                                "concept_id": co_id,
                                "concept_name": it_obj.concept_name,
                                "difficulty": getattr(it_obj, "difficulty", 1.0),
                                "main_question": (
                                    it_obj.planned_question.main_question
                                    if hasattr(it_obj, "planned_question")
                                    and hasattr(
                                        it_obj.planned_question, "main_question"
                                    )
                                    else ""
                                ),
                            }
                        )

            history_list.append(
                {
                    "id": cid,
                    "course_id": cid,
                    "iteration": manager.current_iteration,
                    "status": manager.status.value,
                    "is_current": True,
                    "average_mastery": avg_m,
                    "mastered_concepts": mastered,
                    "weak_concepts": weak,
                    "turns_completed": len(manager.history),
                    "active_concept_id": manager.current_concept_id,
                    "timestamp": curr_ts,
                    "title": curr_title,
                    "plan_title": curr_title,
                    "concepts": curr_concepts,
                }
            )
        return history_list

    async def compare(self) -> dict[str, Any]:
        """Compares current iteration with previous iteration performance."""
        if not self.state_file_path.exists():
            return {
                "has_previous_iterations": False,
                "spoken_comparison": "Nessuna sessione trovata per il confronto.",
            }

        manager = self._load_manager()
        report_gen = SessionReportGenerator(graph_store=manager.graph_store)
        return await report_gen.compare_iterations(
            current_history=manager.history,
            iterations_history=manager.iterations_history,
        )

    async def get_diagnostic_report(self) -> dict[str, Any]:
        """Generates the full diagnostic report and RCA across iterations."""
        if not self.state_file_path.exists():
            return {
                "spoken_summary": "Nessun dato di sessione disponibile.",
                "total_turns": 0,
            }

        manager = self._load_manager()
        report_gen = SessionReportGenerator(graph_store=manager.graph_store)
        return await report_gen.generate_diagnostic_report(
            session_history=manager.history,
            iterations_history=manager.iterations_history,
        )

    def get_conversation_transcript(
        self, iteration: int | None = None, course_id: str | None = None
    ) -> list[dict[str, Any]]:
        """Returns the chronological turn-by-turn conversation transcript.

        Args:
            iteration: If provided, returns turns for that specific iteration or course.
            course_id: If provided, returns turns for that specific course/document.
                       If None, returns all turns from all iterations and current session.
        """
        if course_id:
            try:
                from assessment.courses import CourseManager

                turns = CourseManager.get_course_transcript(course_id)
                if turns:
                    return turns
            except Exception:
                pass

        if iteration is not None:
            try:
                from assessment.courses import CourseManager

                history = CourseManager.get_discussions_history()
                for h in history:
                    if h.get("iteration") == iteration:
                        turns = CourseManager.get_course_transcript(h.get("id"))
                        if turns:
                            return turns
            except Exception:
                pass

        if not self.state_file_path.exists():
            return []

        # Fast-path: read directly from state JSON file without instantiating Neo4j / Qdrant stores
        try:
            import json

            state_data = json.loads(self.state_file_path.read_text(encoding="utf-8"))
            all_turns: list[dict[str, Any]] = []

            # Archived iterations
            for it in state_data.get("iterations_history", []):
                it_num = it.get("iteration", 1)
                if iteration is None or iteration == it_num:
                    for turn in it.get("history", []):
                        t_copy = dict(turn)
                        t_copy["iteration"] = it_num
                        all_turns.append(t_copy)

            # Current iteration
            curr_it = state_data.get("current_iteration", 1)
            if iteration is None or iteration == curr_it:
                for turn in state_data.get("history", []):
                    t_copy = dict(turn)
                    t_copy["iteration"] = curr_it
                    all_turns.append(t_copy)

            return [
                t
                for t in all_turns
                if not is_silence_or_noise(
                    t.get("student_response")
                    or t.get("student_transcript")
                    or t.get("transcript")
                    or ""
                )
            ]
        except Exception as e:
            logger.debug("Fast-path transcript read fallback: %s", e)
            manager = self._load_manager()
            all_turns: list[dict[str, Any]] = []

            # Archived iterations
            for it in manager.iterations_history:
                it_num = it.get("iteration", 1)
                if iteration is None or iteration == it_num:
                    for turn in it.get("history", []):
                        t_copy = dict(turn)
                        t_copy["iteration"] = it_num
                        all_turns.append(t_copy)

            # Current iteration
            if iteration is None or iteration == manager.current_iteration:
                for turn in manager.history:
                    t_copy = dict(turn)
                    t_copy["iteration"] = manager.current_iteration
                    all_turns.append(t_copy)

            return [
                t
                for t in all_turns
                if not is_silence_or_noise(
                    t.get("student_response")
                    or t.get("student_transcript")
                    or t.get("transcript")
                    or ""
                )
            ]

    def export_transcript_markdown(self, iteration: int | None = None) -> str:
        """Exports the conversation transcript formatted as rich Markdown dialogue for inspection and study review."""
        turns = self.get_conversation_transcript(iteration=iteration)
        if not turns:
            return (
                "# 📜 Trascrizione della Sessione d'Esame\n\n"
                "*Nessuna conversazione registrata.*"
            )

        lines = [
            "# 📜 Trascrizione Completa della Sessione d'Esame Orale",
            f"**Totale Scambi Registrati:** {len(turns)}",
            "",
            "---",
        ]

        curr_iter = None
        for t in turns:
            t_iter = t.get("iteration", 1)
            if t_iter != curr_iter:
                curr_iter = t_iter
                lines.append(f"\n## 📁 Iterazione {curr_iter}\n")

            t_num = t.get("turn", "?")
            c_name = t.get("concept_name") or t.get("concept_id") or "Apertura"
            ts = t.get("timestamp", "")
            ts_display = ts.split("T")[-1][:8] if "T" in ts else ts

            ai_q = t.get("ai_question") or t.get("directive") or ""
            student_a = t.get("student_response") or t.get("transcript") or ""
            eval_res = t.get("evaluation") or t.get("evaluation_result") or "N/A"
            delta = t.get("mastery_delta")
            delta_str = f" ({delta:+.2f})" if delta is not None else ""
            state = t.get("pedagogical_state") or t.get("next_state") or ""

            lines.append(f"### [Turno {t_num}] {ts_display} - Concetto: *{c_name}*")
            if ai_q:
                lines.append(f'**👨‍🏫 Docente AI:** "{ai_q}"\n')
            if student_a:
                lines.append(f'**🎓 Studente:** "{student_a}"\n')
            lines.append(
                f"> 📊 **Valutazione:** `{eval_res}`{delta_str} | **Stato:** `{state}`\n"
            )
            lines.append("---")

        return "\n".join(lines)

    def get_events(self, limit: int = 50) -> list[dict[str, Any]]:
        """Returns the recent logged events across Console, Local Server, or Cloud."""
        import json

        events: list[dict[str, Any]] = []
        if self.events_file_path.exists():
            try:
                with open(self.events_file_path, encoding="utf-8") as f:
                    for line in f:
                        line_str = line.strip()
                        if line_str:
                            events.append(json.loads(line_str))
            except Exception as err:
                logger.warning(
                    "Could not read events file %s: %s", self.events_file_path, err
                )
        elif self.state_file_path.exists():
            manager = self._load_manager()
            events = list(manager.events)

        return events[-limit:] if limit > 0 else events

    async def start_new_discussion(self, course_id: str | None = None) -> dict[str, Any]:
        """Starts a completely fresh, isolated discussion on the current document plan.
        Archives any existing discussion if it had turns or was active, resets BKT mastery,
        and generates a clean, unique room name for LiveKit.
        """
        import time
        from assessment.courses import CourseManager

        if course_id:
            CourseManager.set_active_course(course_id)
            cdir = CourseManager.get_course_dir(course_id)
            self.state_file_path = cdir / "state.json"
            self.plan_file_path = cdir / "plan.json"
            self.events_file_path = cdir / "events.jsonl"
            self._custom_state_path = True
        else:
            course_id = CourseManager.get_active_course_id()

        manager = self._load_manager()
        ctx, _ = await manager.restart_examination(adapt_from_previous=False)
        ts_now = int(time.time())
        room_name = f"oral-exam-{course_id}-{ts_now}"

        return {
            "success": True,
            "course_id": course_id,
            "iteration": manager.current_iteration,
            "room_name": room_name,
            "title": (
                manager.examination_plan.title
                if manager.examination_plan
                else "Esame Orale"
            ),
            "current_concept_id": manager.current_concept_id,
            "spoken_directive": ctx.pedagogical_directive,
        }

    def delete_iteration(self, iteration: int | str) -> dict[str, Any]:
        """Deletes a single discussion iteration or course document item from history and disk."""
        # 1. Check if iteration is a course_id string
        if isinstance(iteration, str) and not iteration.isdigit():
            try:
                from assessment.courses import CourseManager

                if CourseManager.delete_course(iteration):
                    return {
                        "success": True,
                        "course_id": iteration,
                        "message": f"Discussione del documento '{iteration}' eliminata definitivamente.",
                    }
            except Exception as e:
                logger.debug("CourseManager delete_course failed: %s", e)

        # 2. Check if iteration matches a course in CourseManager by numeric index
        try:
            from assessment.courses import CourseManager

            it_num = int(iteration)
            history = CourseManager.get_discussions_history()
            for h in history:
                if h.get("iteration") == it_num:
                    cid = h.get("id")
                    CourseManager.delete_course(cid)
                    return {
                        "success": True,
                        "iteration": it_num,
                        "course_id": cid,
                        "message": f"Discussione '{h.get('title')}' eliminata definitivamente.",
                    }
        except Exception:
            pass

        if not self.state_file_path.exists():
            return {"success": False, "message": "Nessuna sessione trovata."}

        it_num = int(iteration) if str(iteration).isdigit() else 1
        manager = self._load_manager()
        before_count = len(manager.iterations_history)
        manager.iterations_history = [
            it for it in manager.iterations_history if it.get("iteration") != it_num
        ]

        # If deleted iteration is the active iteration, clear current conversation history
        if manager.current_iteration == it_num:
            manager.history = []
            manager.status = SessionStatus.COMPLETED
            if manager.examination_plan and manager.examination_plan.concept_order:
                manager.current_concept_id = manager.examination_plan.concept_order[0]

        manager.save_session_state(self.state_file_path)

        # Remove from course-specific sessions directory
        try:
            from assessment.courses import CourseManager

            CourseManager.delete_session(it_num)
        except Exception as e:
            logger.debug("CourseManager delete_session skipped: %s", e)

        logger.info(
            "Deleted iteration %d from server (was %d, now %d)",
            it_num,
            before_count,
            len(manager.iterations_history),
        )
        return {
            "success": True,
            "deleted_iteration": it_num,
            "remaining_iterations": len(manager.iterations_history),
            "message": f"Discussione #{it_num} eliminata definitivamente dal server.",
        }

    def reset_all(self, delete_plan: bool = True) -> dict[str, Any]:
        """Clears all session states, events, and optionally examination plan."""
        removed = []
        if self.state_file_path.exists():
            self.state_file_path.unlink()
            removed.append(str(self.state_file_path))
        if self.events_file_path.exists():
            self.events_file_path.unlink()
            removed.append(str(self.events_file_path))
        if delete_plan and self.plan_file_path.exists():
            self.plan_file_path.unlink()
            removed.append(str(self.plan_file_path))

        try:
            from assessment.courses import CourseManager

            CourseManager.purge_all(delete_plans=delete_plan)
        except Exception as e:
            logger.debug("CourseManager purge_all skipped: %s", e)

        return {
            "success": True,
            "message": "Stato della sessione e cronologia completamente resettati.",
            "removed_files": removed,
        }
