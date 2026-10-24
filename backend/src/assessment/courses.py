"""Course and Session Storage Manager.

Maintains strict, modular separation between different courses/documents and their
respective examination plans and session histories.

Directory Structure:
data/
  active_course.json
  courses/
    <course_id>/
      metadata.json
      plan.json
      state.json
      sessions/
        session_1.json
        session_2.json
        ...
"""

from __future__ import annotations

import contextlib
import json
import logging
import re
import shutil
from datetime import datetime
from pathlib import Path
from typing import Any

from assessment.state import is_silence_or_noise

logger = logging.getLogger("agent.assessment.courses")


class CourseManager:
    """Manages course/file directories, isolated plans, and separated session histories."""

    DATA_DIR = Path("data")
    COURSES_DIR = Path("data/courses")
    ACTIVE_COURSE_FILE = Path("data/active_course.json")
    ROOT_PLAN_FILE = Path("data/examination_plan.json")
    ROOT_STATE_FILE = Path("data/session_state.json")

    @classmethod
    def ensure_directories(cls) -> None:
        """Ensure base directories exist."""
        cls.DATA_DIR.mkdir(parents=True, exist_ok=True)
        cls.COURSES_DIR.mkdir(parents=True, exist_ok=True)

    @classmethod
    def slugify(cls, text: str) -> str:
        """Converts arbitrary course/file name into a safe, deterministic directory slug."""
        slug = re.sub(r"[^a-zA-Z0-9_-]+", "_", text).strip("_").lower()
        return slug or "course_default"

    @classmethod
    def get_active_course_id(cls) -> str | None:
        """Returns the currently active course ID, or None if no course is loaded."""
        cls.ensure_directories()
        if cls.ACTIVE_COURSE_FILE.exists():
            try:
                data = json.loads(cls.ACTIVE_COURSE_FILE.read_text(encoding="utf-8"))
                cid = data.get("active_course_id")
                if cid and cid != "default_course" and (cls.COURSES_DIR / cid).exists():
                    return cid
            except Exception as e:
                logger.warning("Could not read active_course.json: %s", e)

        # Fallback: check if any valid course directory exists in data/courses
        existing = [
            d
            for d in cls.COURSES_DIR.iterdir()
            if d.is_dir()
            and d.name != "default_course"
            and (
                (d / "metadata.json").exists()
                or (d / "plan.json").exists()
                or (d / "state.json").exists()
            )
        ]
        if existing:
            first_id = existing[0].name
            cls.set_active_course(first_id)
            return first_id

        # Fallback: if root examination_plan exists, migrate it to course
        candidate_plan_file = (
            cls.ROOT_PLAN_FILE
            if cls.ROOT_PLAN_FILE.exists()
            else Path("examination_plan.json")
        )
        if candidate_plan_file.exists():
            default_id = "corso_attuale"
            try:
                plan_data = json.loads(candidate_plan_file.read_text(encoding="utf-8"))
                title = plan_data.get("title", "Esame Orale")
                default_id = cls.slugify(title)
            except Exception:
                title = "Esame Orale"
            cls.create_or_update_course(
                course_id=default_id,
                title=title,
                filename=candidate_plan_file.name,
                file_path=str(candidate_plan_file),
                plan_dict=plan_data if "plan_data" in locals() else None,
            )
            return default_id

        return None

    @classmethod
    def get_course_dir(cls, course_id: str | None = None) -> Path:
        """Returns the Path to a specific or active course directory."""
        cls.ensure_directories()
        cid = course_id or cls.get_active_course_id()
        if not cid or cid == "default_course":
            return cls.DATA_DIR
        cdir = cls.COURSES_DIR / cid
        cdir.mkdir(parents=True, exist_ok=True)
        (cdir / "sessions").mkdir(parents=True, exist_ok=True)
        return cdir

    @classmethod
    def set_active_course(cls, course_id: str | None, title: str = "") -> None:
        """Sets the active course ID and syncs its plan and state to root files."""
        cls.ensure_directories()
        if not course_id or course_id == "default_course":
            if cls.ACTIVE_COURSE_FILE.exists():
                cls.ACTIVE_COURSE_FILE.unlink()
            return

        cdir = cls.COURSES_DIR / course_id
        if not cdir.exists():
            cdir.mkdir(parents=True, exist_ok=True)
            (cdir / "sessions").mkdir(parents=True, exist_ok=True)

        meta_file = cdir / "metadata.json"
        course_title = title
        if not course_title and meta_file.exists():
            try:
                mdata = json.loads(meta_file.read_text(encoding="utf-8"))
                course_title = mdata.get("title", "")
            except Exception:
                pass

        cls.ACTIVE_COURSE_FILE.write_text(
            json.dumps(
                {
                    "active_course_id": course_id,
                    "title": course_title,
                    "updated_at": datetime.now().isoformat(),
                },
                indent=2,
            ),
            encoding="utf-8",
        )

        # Mirror plan and state to root files for CLI backward compatibility.
        course_plan = cdir / "plan.json"
        if course_plan.exists():
            shutil.copy2(course_plan, cls.ROOT_PLAN_FILE)
            logger.info("Mirrored %s to %s", course_plan, cls.ROOT_PLAN_FILE)

        course_state = cdir / "state.json"
        if course_state.exists():
            shutil.copy2(course_state, cls.ROOT_STATE_FILE)
            logger.info("Mirrored %s to %s", course_state, cls.ROOT_STATE_FILE)

    @classmethod
    def create_or_update_course(
        cls,
        course_id: str,
        title: str,
        filename: str,
        file_path: str,
        plan_dict: dict[str, Any] | None = None,
    ) -> Path:
        """Initializes a dedicated course directory, persists plan and metadata,
        and sets it as the active course.
        """
        cls.ensure_directories()
        cdir = cls.COURSES_DIR / course_id
        cdir.mkdir(parents=True, exist_ok=True)
        sessions_dir = cdir / "sessions"
        sessions_dir.mkdir(parents=True, exist_ok=True)

        # 1. Metadata
        metadata = {
            "id": course_id,
            "title": title,
            "filename": filename,
            "file_path": str(file_path),
            "created_at": datetime.now().isoformat(),
            "updated_at": datetime.now().isoformat(),
        }
        (cdir / "metadata.json").write_text(
            json.dumps(metadata, indent=2), encoding="utf-8"
        )

        # 2. Plan
        if plan_dict:
            plan_file = cdir / "plan.json"
            plan_file.write_text(
                json.dumps(plan_dict, indent=2, ensure_ascii=False), encoding="utf-8"
            )
            # Mirror to root
            cls.ROOT_PLAN_FILE.write_text(
                json.dumps(plan_dict, indent=2, ensure_ascii=False), encoding="utf-8"
            )

        # 3. Set Active
        cls.set_active_course(course_id, title=title)
        return cdir

    @classmethod
    def sync_from_manager(
        cls, manager: Any, snapshot_dict: dict[str, Any] | None = None
    ) -> None:
        """Synchronizes SessionAssessmentManager state to course folder and metadata."""
        try:
            cid = None
            if getattr(manager, "course_id", None):
                cid = manager.course_id
            elif getattr(manager, "state_file_path", None):
                p = Path(manager.state_file_path)
                if p.parent.parent.name == "courses":
                    cid = p.parent.name
            if not cid and getattr(manager, "examination_plan", None):
                plan = manager.examination_plan
                if getattr(plan, "document_id", None) and plan.document_id not in (
                    "doc_default",
                    "greedy",
                    "examination_plan",
                ):
                    cid = cls.slugify(plan.document_id)
                elif getattr(plan, "title", None) and plan.title != "esame orale":
                    cid = cls.slugify(plan.title)
            if not cid:
                cid = cls.get_active_course_id()
            if not cid:
                return

            cdir = cls.COURSES_DIR / cid
            cdir.mkdir(parents=True, exist_ok=True)
            sessions_dir = cdir / "sessions"
            sessions_dir.mkdir(parents=True, exist_ok=True)

            manager_dict = (
                snapshot_dict if snapshot_dict is not None else manager.to_dict()
            )

            # Save state.json inside course directory
            state_file = cdir / "state.json"
            state_file.write_text(
                json.dumps(manager_dict, indent=2, ensure_ascii=False), encoding="utf-8"
            )

            # Persist unified discussion snapshot into session_1.json for backwards-compatibility
            all_turns = [
                t
                for t in list(manager.history)
                if not is_silence_or_noise(
                    t.get("student_response")
                    or t.get("student_transcript")
                    or t.get("transcript")
                    or ""
                )
            ]
            for it in manager.iterations_history:
                it_turns = [
                    t
                    for t in it.get("history", [])
                    if not is_silence_or_noise(
                        t.get("student_response")
                        or t.get("student_transcript")
                        or t.get("transcript")
                        or ""
                    )
                ]
                all_turns = it_turns + all_turns

            snapshot = {
                "iteration": 1,
                "status": manager.status.value,
                "is_current": True,
                "title": (
                    manager.examination_plan.title
                    if manager.examination_plan
                    else f"Discussione {cid}"
                ),
                "history": all_turns,
                "turns_completed": len(all_turns),
                "timestamp": datetime.now().isoformat(),
            }
            curr_file = sessions_dir / "session_1.json"
            curr_file.write_text(
                json.dumps(snapshot, indent=2, ensure_ascii=False),
                encoding="utf-8",
            )

            # Update metadata
            meta_file = cdir / "metadata.json"
            if meta_file.exists():
                try:
                    m = json.loads(meta_file.read_text(encoding="utf-8"))
                    m["updated_at"] = datetime.now().isoformat()
                    m["status"] = manager.status.value
                    m["turns_completed"] = len(all_turns)
                    meta_file.write_text(
                        json.dumps(m, indent=2, ensure_ascii=False), encoding="utf-8"
                    )
                except Exception:
                    pass

        except Exception as e:
            logger.warning("Error during CourseManager.sync_from_manager: %s", e)

    @classmethod
    def get_course_transcript(
        cls, course_id: str | None = None
    ) -> list[dict[str, Any]]:
        """Returns all chronological turns for a course/document discussion."""
        cls.ensure_directories()
        cid = course_id or cls.get_active_course_id()
        cdir = cls.COURSES_DIR / cid
        state_file = cdir / "state.json"
        if not state_file.exists():
            return []

        try:
            sdata = json.loads(state_file.read_text(encoding="utf-8"))
            turns: list[dict[str, Any]] = []
            for it in sdata.get("iterations_history", []):
                for t in it.get("history", []):
                    t_copy = dict(t)
                    t_copy["iteration"] = 1
                    turns.append(t_copy)
            for t in sdata.get("history", []):
                t_copy = dict(t)
                t_copy["iteration"] = 1
                turns.append(t_copy)
            clean_turns: list[dict[str, Any]] = []
            for t in turns:
                resp = (
                    t.get("student_response")
                    or t.get("student_transcript")
                    or t.get("transcript")
                    or ""
                )
                if not is_silence_or_noise(resp):
                    clean_turns.append(t)
            return clean_turns
        except Exception as e:
            logger.warning("Error reading transcript for course %s: %s", cid, e)
            return []

    @classmethod
    def delete_course(cls, course_id: str) -> bool:
        """Deletes an entire course/document discussion directory and all associated state."""
        cls.ensure_directories()
        cdir = cls.COURSES_DIR / course_id
        if not cdir.exists():
            return False

        shutil.rmtree(cdir, ignore_errors=True)
        logger.info("Deleted course directory %s", cdir)

        # If deleted course was active, select another existing course or clear
        active_id = None
        if cls.ACTIVE_COURSE_FILE.exists():
            try:
                adata = json.loads(cls.ACTIVE_COURSE_FILE.read_text(encoding="utf-8"))
                active_id = adata.get("active_course_id")
            except Exception:
                pass

        if active_id == course_id:
            remaining = [d.name for d in cls.COURSES_DIR.iterdir() if d.is_dir()]
            if remaining:
                cls.set_active_course(remaining[0])
            else:
                if cls.ACTIVE_COURSE_FILE.exists():
                    cls.ACTIVE_COURSE_FILE.unlink(missing_ok=True)
                if cls.ROOT_STATE_FILE.exists():
                    cls.ROOT_STATE_FILE.unlink(missing_ok=True)
                if cls.ROOT_PLAN_FILE.exists():
                    cls.ROOT_PLAN_FILE.unlink(missing_ok=True)

        return True

    @classmethod
    def get_discussions_history(cls) -> list[dict[str, Any]]:
        """Returns the list of all Document Discussion Items (one per document/course).
        Each item is incrementally updated as conversation turns and evaluations progress.
        """
        cls.ensure_directories()
        active_id = cls.get_active_course_id()
        items: list[dict[str, Any]] = []

        course_dirs = [
            d
            for d in cls.COURSES_DIR.iterdir()
            if d.is_dir()
            and d.name != "default_course"
            and (
                (d / "metadata.json").exists()
                or (d / "plan.json").exists()
                or (d / "state.json").exists()
            )
        ]

        for idx, d in enumerate(course_dirs):
            cid = d.name
            meta_file = d / "metadata.json"
            plan_file = d / "plan.json"
            state_file = d / "state.json"

            meta: dict[str, Any] = {}
            if meta_file.exists():
                with contextlib.suppress(Exception):
                    meta = json.loads(meta_file.read_text(encoding="utf-8"))

            plan_data: dict[str, Any] = {}
            if plan_file.exists():
                with contextlib.suppress(Exception):
                    plan_data = json.loads(plan_file.read_text(encoding="utf-8"))

            state_data: dict[str, Any] = {}
            if state_file.exists():
                with contextlib.suppress(Exception):
                    state_data = json.loads(state_file.read_text(encoding="utf-8"))

            # Gather all conversation turns (current history + any archived iterations)
            all_turns: list[dict[str, Any]] = []
            for it in state_data.get("iterations_history", []):
                all_turns.extend(it.get("history", []))
            all_turns.extend(state_data.get("history", []))
            all_turns = [
                t
                for t in all_turns
                if not is_silence_or_noise(
                    t.get("student_response")
                    or t.get("student_transcript")
                    or t.get("transcript")
                    or ""
                )
            ]

            # Concepts from plan
            concepts_list: list[dict[str, Any]] = []
            concept_order = plan_data.get("concept_order", [])
            plan_items = plan_data.get("items", {})
            for co_id in concept_order:
                c_obj = plan_items.get(co_id, {})
                concepts_list.append(
                    {
                        "concept_id": co_id,
                        "concept_name": c_obj.get("concept_name", co_id),
                        "difficulty": c_obj.get("difficulty", 1.0),
                        "prerequisites": c_obj.get("prerequisites", []),
                        "main_question": (
                            c_obj.get("planned_question", {}).get("main_question", "")
                            if isinstance(c_obj.get("planned_question"), dict)
                            else ""
                        ),
                    }
                )

            # Calculate mastery and evaluated concepts
            mastered: list[str] = []
            weak: list[str] = []
            evaluated_turns = [
                t
                for t in all_turns
                if t.get("evaluation_result") or t.get("evaluation")
            ]
            for t in evaluated_turns:
                res = str(
                    t.get("evaluation_result") or t.get("evaluation") or ""
                ).upper()
                cname = t.get("concept_name") or t.get("concept_id") or ""
                if not cname:
                    continue
                cname_clean = cname.replace("_", " ")
                if res in ("ACCURATE", "MASTERED") and cname_clean not in mastered:
                    mastered.append(cname_clean)
                    if cname_clean in weak:
                        weak.remove(cname_clean)
                elif (
                    res in ("MISCONCEPTION", "VAGUE", "HESITANT", "WEAK", "OFF_TOPIC")
                    and cname_clean not in weak
                ):
                    if cname_clean not in mastered:
                        weak.append(cname_clean)

            total_concepts = (
                len(concepts_list) if concepts_list else (len(evaluated_turns) or 1)
            )
            avg_mastery = (
                round(len(mastered) / total_concepts, 2)
                if total_concepts > 0 and evaluated_turns
                else 0.0
            )

            title = (
                meta.get("title")
                or plan_data.get("title")
                or cid.replace("_", " ").title()
            )
            filename = meta.get("filename", "")
            file_path = meta.get("file_path", "")

            # Timestamp: last turn timestamp or metadata updated_at
            ts = (
                all_turns[-1].get("timestamp", "")
                if all_turns
                else meta.get("updated_at", meta.get("created_at", ""))
            )
            created_at = meta.get("created_at", ts)
            updated_at = meta.get("updated_at", ts)

            status = (
                state_data.get("status")
                or meta.get("status")
                or ("ACTIVE" if cid == active_id else "PAUSED")
            )

            # Collect all distinct session dates (YYYY-MM-DD) for this course
            session_dates_set: set[str] = set()
            for s in (created_at, updated_at, ts):
                if s and len(s) >= 10:
                    session_dates_set.add(s[:10])
            for it in state_data.get("iterations_history", []):
                if (it_ts := it.get("timestamp")) and len(it_ts) >= 10:
                    session_dates_set.add(it_ts[:10])
            for t in all_turns:
                if (t_ts := t.get("timestamp")) and len(t_ts) >= 10:
                    session_dates_set.add(t_ts[:10])
            events_file = d / "events.jsonl"
            if events_file.exists():
                with contextlib.suppress(Exception):
                    for line in events_file.read_text(encoding="utf-8").splitlines():
                        if line.strip():
                            ev = json.loads(line)
                            if (ev_ts := ev.get("timestamp")) and len(ev_ts) >= 10:
                                session_dates_set.add(ev_ts[:10])

            items.append(
                {
                    "id": cid,
                    "course_id": cid,
                    "iteration": idx + 1,
                    "title": title,
                    "filename": filename,
                    "file_path": file_path,
                    "status": status,
                    "is_current": cid == active_id,
                    "turns_completed": len(all_turns),
                    "average_mastery": avg_mastery,
                    "mastered_concepts": mastered,
                    "weak_concepts": weak,
                    "active_concept_id": state_data.get("current_concept_id", ""),
                    "timestamp": ts or updated_at,
                    "created_at": created_at,
                    "updated_at": updated_at,
                    "session_dates": sorted(list(session_dates_set)),
                    "plan_title": title,
                    "total_concepts": len(concepts_list),
                    "concepts": concepts_list,
                }
            )

        # Sort by updated_at / timestamp descending so most recently active discussion is first
        items.sort(
            key=lambda x: str(x.get("updated_at") or x.get("timestamp") or ""),
            reverse=True,
        )
        # Re-assign 1-based sequential iteration indices to match sorted order
        for i, item in enumerate(items):
            item["iteration"] = i + 1

        return items

    @classmethod
    def delete_session(cls, iteration: int, course_id: str | None = None) -> bool:
        """Deletes session_{iteration}.json from course sessions directory."""
        cid = course_id or cls.get_active_course_id()
        session_file = cls.COURSES_DIR / cid / "sessions" / f"session_{iteration}.json"
        if session_file.exists():
            session_file.unlink()
            logger.info("Deleted session file %s", session_file)
            return True
        return False

    @classmethod
    def reset_course_sessions(
        cls, course_id: str | None = None, delete_plan: bool = False
    ) -> None:
        """Clears all sessions for a course, resets its state, and optionally removes its plan."""
        cid = course_id or cls.get_active_course_id()
        cdir = cls.COURSES_DIR / cid
        if cdir.exists():
            sessions_dir = cdir / "sessions"
            if sessions_dir.exists():
                for sf in sessions_dir.glob("session_*.json"):
                    sf.unlink()
            state_file = cdir / "state.json"
            if state_file.exists():
                state_file.unlink()
            if delete_plan:
                plan_file = cdir / "plan.json"
                if plan_file.exists():
                    plan_file.unlink()

        # Mirror cleanup to root
        if cls.ROOT_STATE_FILE.exists():
            cls.ROOT_STATE_FILE.unlink()
        if delete_plan and cls.ROOT_PLAN_FILE.exists():
            cls.ROOT_PLAN_FILE.unlink()

    @classmethod
    def purge_all(cls, delete_plans: bool = True) -> None:
        """Purges all courses, sessions, active pointers, and mirrors. Everything starts 100% empty."""
        cls.ensure_directories()
        if cls.COURSES_DIR.exists():
            shutil.rmtree(cls.COURSES_DIR, ignore_errors=True)
            cls.COURSES_DIR.mkdir(parents=True, exist_ok=True)

        if cls.ACTIVE_COURSE_FILE.exists():
            cls.ACTIVE_COURSE_FILE.unlink()

        if cls.ROOT_STATE_FILE.exists():
            cls.ROOT_STATE_FILE.unlink()

        events_file = cls.DATA_DIR / "session_events.jsonl"
        if events_file.exists():
            events_file.unlink()
        legacy_events = Path("session_events.jsonl")
        if legacy_events.exists():
            legacy_events.unlink()

        if delete_plans and cls.ROOT_PLAN_FILE.exists():
            cls.ROOT_PLAN_FILE.unlink()

        for bak in Path(".").glob("*.json.bak"):
            bak.unlink(missing_ok=True)

        logger.info(
            "Purged all courses and session histories. Backend is completely clean."
        )

    @classmethod
    def list_courses(cls) -> list[dict[str, Any]]:
        """Lists all existing courses with metadata, session count, and active status."""
        cls.ensure_directories()
        active_id = cls.get_active_course_id()
        courses: list[dict[str, Any]] = []

        for d in cls.COURSES_DIR.iterdir():
            if (
                not d.is_dir()
                or d.name == "default_course"
                or (
                    not (d / "metadata.json").exists()
                    and not (d / "plan.json").exists()
                    and not (d / "state.json").exists()
                )
            ):
                continue
            cid = d.name
            meta_file = d / "metadata.json"
            meta: dict[str, Any] = {}
            if meta_file.exists():
                with contextlib.suppress(Exception):
                    meta = json.loads(meta_file.read_text(encoding="utf-8"))

            sessions_dir = d / "sessions"
            session_files = (
                list(sessions_dir.glob("session_*.json"))
                if sessions_dir.exists()
                else []
            )

            plan_file = d / "plan.json"
            has_plan = plan_file.exists()

            courses.append(
                {
                    "id": cid,
                    "title": meta.get("title", cid),
                    "filename": meta.get("filename", ""),
                    "file_path": meta.get("file_path", ""),
                    "has_plan": has_plan,
                    "total_sessions": len(session_files),
                    "is_active": cid == active_id,
                    "created_at": meta.get("created_at", ""),
                    "updated_at": meta.get("updated_at", ""),
                }
            )

        # Sort courses by updated_at descending
        courses.sort(key=lambda c: c.get("updated_at", ""), reverse=True)
        return courses
