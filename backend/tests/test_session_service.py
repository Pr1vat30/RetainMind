import json

import pytest

from assessment import SessionAssessmentManager, SessionService
from planning import ConceptPlanItem, ExaminationPlan, PlannedQuestion
from rag import ConceptNode, InMemoryGraphStore, InMemoryVectorStore


@pytest.fixture
def test_setup(tmp_path):
    gstore = InMemoryGraphStore()
    vstore = InMemoryVectorStore()

    c1 = ConceptNode(id="sharding", name="Sharding", summary="Partizionamento dati.")
    c2 = ConceptNode(id="acid", name="ACID", summary="Transazioni ACID.")
    gstore._concepts["sharding"] = c1
    gstore._concepts["acid"] = c2

    q1 = PlannedQuestion(
        question_id="q1",
        concept_id="sharding",
        main_question="Cosa è lo sharding?",
        max_attempts=2,
    )
    q2 = PlannedQuestion(
        question_id="q2",
        concept_id="acid",
        main_question="Cosa sono le transazioni ACID?",
        max_attempts=2,
    )
    plan = ExaminationPlan(
        plan_id="p1",
        concept_order=["sharding", "acid"],
        items={
            "sharding": ConceptPlanItem(
                concept_id="sharding", concept_name="Sharding", planned_question=q1
            ),
            "acid": ConceptPlanItem(
                concept_id="acid", concept_name="ACID", planned_question=q2
            ),
        },
    )

    state_path = tmp_path / "session_state.json"
    plan_path = tmp_path / "examination_plan.json"
    events_path = tmp_path / "session_events.jsonl"
    plan_path.write_text(json.dumps(plan.model_dump()), encoding="utf-8")

    manager = SessionAssessmentManager(
        graph_store=gstore,
        vector_store=vstore,
        examination_plan=plan,
        state_file_path=state_path,
        events_file_path=events_path,
        execution_mode="console",
    )
    manager.save_session_state(state_path)

    service = SessionService(
        state_file_path=state_path,
        plan_file_path=plan_path,
        events_file_path=events_path,
        execution_mode="console",
    )
    return service, state_path, events_path, manager


@pytest.mark.asyncio
async def test_session_service_status_and_lifecycle(test_setup):
    service, _state_path, events_path, _manager = test_setup

    # 1. Status initially
    status = service.get_status()
    assert status["has_active_session"] is True
    assert status["status"] == "ACTIVE"
    assert status["current_iteration"] == 1
    assert status["current_concept_id"] == "sharding"

    # 2. Pause via service
    pause_res = await service.pause(reason="Pausa pranzo")
    assert pause_res["success"] is True
    assert pause_res["status"] == "PAUSED"
    assert pause_res["paused_concept_id"] == "sharding"

    status_paused = service.get_status()
    assert status_paused["status"] == "PAUSED"

    # 3. Resume via service
    resume_res = await service.resume()
    assert resume_res["success"] is True
    assert resume_res["status"] == "ACTIVE"

    # 4. Repeat via service
    repeat_res = await service.repeat(adapt=True)
    assert repeat_res["success"] is True
    assert repeat_res["new_iteration"] == 2
    assert repeat_res["total_archived_iterations"] == 1

    # 5. History via service
    history = service.get_history()
    assert len(history) == 2  # 1 archived + 1 current ongoing
    assert history[0]["iteration"] == 1
    assert history[1]["is_current"] is True

    # 6. Compare via service
    comp = await service.compare()
    assert comp["has_previous_iterations"] is True
    assert comp["compared_iteration"] == 1

    # 7. Full Diagnostic report via service
    rep = await service.get_diagnostic_report()
    assert "average_mastery" in rep
    assert "spoken_summary" in rep

    # 8. Conversation Transcript via service
    turns = service.get_conversation_transcript()
    assert isinstance(turns, list)

    md_export = service.export_transcript_markdown()
    assert "Trascrizione" in md_export

    # 9. Verify Universal Event Log
    events = service.get_events()
    assert len(events) >= 3
    event_types = [e["event_type"] for e in events]
    assert "SESSION_PAUSED" in event_types
    assert "SESSION_RESUMED" in event_types
    assert "SESSION_RESTARTED" in event_types
    for e in events:
        assert e["execution_mode"] == "console"
        assert "timestamp" in e

    # Check that events_path file exists in tmp_path
    assert events_path.exists()
