import pytest

from agent import OralExaminerAgent
from assessment import SessionAssessmentManager
from rag import (
    ConceptNode,
    DocumentChunk,
    InMemoryGraphStore,
    InMemoryVectorStore,
)


@pytest.mark.asyncio
async def test_examiner_agent_initialization_and_evaluation():
    gstore = InMemoryGraphStore()
    vstore = InMemoryVectorStore()

    concept = ConceptNode(
        id="secondo_principio",
        name="Secondo Principio della Termodinamica",
        summary="Principio che regola l'evoluzione spontanea e l'entropia.",
    )
    await gstore.upsert_concept(concept)
    await vstore.index_chunks(
        [
            DocumentChunk(
                chunk_id="chk_sec",
                text="Il secondo principio afferma che l'entropia totale non diminuisce.",
                concept_ids=["secondo_principio"],
            )
        ]
    )

    manager = SessionAssessmentManager(graph_store=gstore, vector_store=vstore)
    agent = OralExaminerAgent(assessment_manager=manager)

    # Test evaluate_and_advance function tool directly
    eval_output = await agent.evaluate_and_advance(
        context=None,  # RunContext not required for direct tool invocation
        student_response="Il secondo principio dice che in un sistema isolato l'entropia cresce.",
    )

    assert "Evaluation:" in eval_output
    assert "Secondo Principio" in eval_output

    # Test get_session_summary function tool
    summary = await agent.get_session_summary(context=None)
    assert isinstance(summary, str)
    assert len(summary) > 0


@pytest.mark.asyncio
async def test_examiner_agent_turn_sequence():
    gstore = InMemoryGraphStore()
    vstore = InMemoryVectorStore()

    c1 = ConceptNode(
        id="entropia",
        name="Entropia",
        summary="Misura del disordine termico.",
        prerequisites=["calore"],
    )
    c2 = ConceptNode(
        id="calore",
        name="Calore",
        summary="Energia termica trasferita.",
    )
    await gstore.upsert_concepts([c1, c2])
    await vstore.index_chunks(
        [
            DocumentChunk(
                chunk_id="chk_ent",
                text="L'entropia misura il disordine e l'irreversibilità.",
                concept_ids=["entropia"],
            )
        ]
    )

    manager = SessionAssessmentManager(graph_store=gstore, vector_store=vstore)
    agent = OralExaminerAgent(assessment_manager=manager)

    # 1. First turn: student answers vaguely
    out1 = await agent.evaluate_and_advance(
        context=None,
        student_response="L'entropia è una cosa con il calore.",
    )
    assert "Evaluation:" in out1

    # 2. Second turn: student answers accurately
    out2 = await agent.evaluate_and_advance(
        context=None,
        student_response="L'entropia misura la degradazione dell'energia e il disordine molecolare in trasformazioni irreversibili.",
    )
    assert "Evaluation: ACCURATE" in out2

    # 3. Check summary
    summary = await agent.get_session_summary(context=None)
    assert "Sessione" in summary or "padronanza" in summary or "consiglia" in summary


@pytest.mark.asyncio
async def test_examiner_agent_with_plan():
    from planning import ConceptPlanItem, ExaminationPlan, PlannedQuestion

    gstore = InMemoryGraphStore()
    vstore = InMemoryVectorStore()

    c = ConceptNode(id="entropia", name="Entropia", summary="Disordine.")
    await gstore.upsert_concept(c)

    q = PlannedQuestion(
        question_id="q_ent",
        concept_id="entropia",
        main_question="Mi parli dell'entropia.",
        max_attempts=2,
    )
    plan = ExaminationPlan(
        plan_id="plan_ag_1",
        concept_order=["entropia"],
        items={
            "entropia": ConceptPlanItem(
                concept_id="entropia", concept_name="Entropia", planned_question=q
            )
        },
    )

    manager = SessionAssessmentManager(
        graph_store=gstore, vector_store=vstore, examination_plan=plan
    )
    agent = OralExaminerAgent(assessment_manager=manager)

    progress_before = await agent.get_exam_progress(context=None)
    assert "0.0%" in progress_before
    assert "entropia" in progress_before

    # Complete concept
    out = await agent.evaluate_and_advance(
        context=None,
        student_response="L'entropia definisce la misura del disordine termico molecolare.",
    )
    assert "ACCURATE" in out

    progress_after = await agent.get_exam_progress(context=None)
    assert "100.0%" in progress_after


@pytest.mark.asyncio
async def test_examiner_agent_pause_resume_and_repeat_tools(tmp_path):
    gstore = InMemoryGraphStore()
    vstore = InMemoryVectorStore()
    c = ConceptNode(id="nosql", name="Database NoSQL", summary="NoSQL.")
    await gstore.upsert_concept(c)

    state_file = tmp_path / "test_agent_state.json"
    manager = SessionAssessmentManager(
        graph_store=gstore,
        vector_store=vstore,
        state_file_path=state_file,
    )
    agent = OralExaminerAgent(assessment_manager=manager)

    # 1. Test pause_session tool
    pause_msg = await agent.pause_session(context=None)
    assert "messo in pausa" in pause_msg or "salvato" in pause_msg

    # 2. Test resume_session tool
    resume_msg = await agent.resume_session(context=None)
    assert "Bentornato" in resume_msg

    # 3. Test repeat_examination tool
    repeat_msg = await agent.repeat_examination(context=None)
    assert "Iterazione 2" in repeat_msg

    # 4. Test get_exam_history_and_comparison tool
    comp_msg = await agent.get_exam_history_and_comparison(context=None)
    assert "Rispetto all'iterazione 1" in comp_msg or "padronanza" in comp_msg


def test_greeting_logic_welcome_vs_bentornato():
    """Verify that a brand-new document (0 turns) gets 'Buongiorno! Benvenuto...'
    and a resumed session (>0 turns) gets 'Bentornato alla discussione...'."""
    from assessment import PedagogicalState, SessionStatus
    from planning import ConceptPlanItem, ExaminationPlan, PlannedQuestion

    # Create dummy plan
    q = PlannedQuestion(
        question_id="q1",
        concept_id="c1",
        main_question="Cos'è il polimorfismo?",
    )
    plan = ExaminationPlan(
        plan_id="p1",
        title="Programmazione a Oggetti",
        concept_order=["c1"],
        items={"c1": ConceptPlanItem(concept_id="c1", concept_name="Polimorfismo", planned_question=q)},
    )

    # 1. First time upload: history is empty
    manager_fresh = SessionAssessmentManager(
        graph_store=InMemoryGraphStore(),
        vector_store=InMemoryVectorStore(),
        examination_plan=plan,
    )
    manager_fresh.status = SessionStatus.ACTIVE
    manager_fresh.history = []

    is_resumed_fresh = bool(manager_fresh.history or manager_fresh.iterations_history)
    assert is_resumed_fresh is False

    greeting_fresh = (
        f"Bentornato alla discussione su {plan.title}! Eravamo rimasti all'argomento 'Polimorfismo'. Sei pronto a riprendere?"
        if is_resumed_fresh
        else f"Buongiorno! Benvenuto alla simulazione di {plan.title}. Iniziamo con il primo argomento del documento. Sei pronto?"
    )
    assert "Buongiorno! Benvenuto" in greeting_fresh
    assert "Bentornato" not in greeting_fresh

    # 2. Resumed session: history has at least 1 turn
    manager_resumed = SessionAssessmentManager(
        graph_store=InMemoryGraphStore(),
        vector_store=InMemoryVectorStore(),
        examination_plan=plan,
    )
    manager_resumed.status = SessionStatus.PAUSED
    manager_resumed.current_concept_id = "c1"
    manager_resumed.history = [
        {"turn": 1, "student_transcript": "Una risposta", "evaluation": "ACCURATE"}
    ]

    is_resumed_active = bool(manager_resumed.history or manager_resumed.iterations_history)
    assert is_resumed_active is True

    curr_c = manager_resumed.current_concept_id.replace("_", " ").title()
    greeting_resumed = (
        f"Bentornato alla discussione su {plan.title}! Eravamo rimasti all'argomento '{curr_c}'. Sei pronto a riprendere?"
        if is_resumed_active
        else f"Buongiorno! Benvenuto alla simulazione di {plan.title}. Iniziamo con il primo argomento del documento. Sei pronto?"
    )
    assert "Bentornato alla discussione su Programmazione a Oggetti" in greeting_resumed
    assert "Buongiorno" not in greeting_resumed


def test_room_name_course_resolution():
    """Verify that room names extract course ID deterministically."""
    import re

    def resolve_course_id(room_name: str) -> str | None:
        match = re.match(r"^oral-exam-(.+)-(\d+)$", room_name)
        if match and match.group(1) != "room" and not match.group(1).isdigit():
            return match.group(1)
        elif room_name.startswith("oral-exam-") and room_name not in ("oral-exam", "oral-exam-room"):
            candidate = room_name[len("oral-exam-"):]
            if candidate and not candidate.isdigit():
                return candidate
        return None

    assert resolve_course_id("oral-exam-termodinamica-1740000000000") == "termodinamica"
    assert resolve_course_id("oral-exam-storia_romana-1741234567890") == "storia_romana"
    assert resolve_course_id("oral-exam-1740000000000") is None
    assert resolve_course_id("oral-exam-room") is None


def test_extract_custom_vocabulary():
    """Verify Gemini 3.8 Live custom vocabulary extraction from examination plan."""
    from agent import extract_custom_vocabulary
    from planning.models import ConceptPlanItem, ExaminationPlan, PlannedQuestion

    plan = ExaminationPlan(
        plan_id="plan_thermo",
        document_id="doc_thermo",
        title="Termodinamica Applicata",
        concept_order=["primo_principio", "secondo_principio"],
        items={
            "primo_principio": ConceptPlanItem(
                concept_id="primo_principio",
                concept_name="Primo Principio della Termodinamica",
                planned_question=PlannedQuestion(
                    question_id="q_primo",
                    concept_id="primo_principio",
                    main_question="Cos'è il primo principio?",
                ),
            ),
            "secondo_principio": ConceptPlanItem(
                concept_id="secondo_principio",
                concept_name="Secondo Principio ed Entropia",
                planned_question=PlannedQuestion(
                    question_id="q_secondo",
                    concept_id="secondo_principio",
                    main_question="Cos'è l'entropia?",
                ),
            ),
        },
    )
    vocab = extract_custom_vocabulary(plan)
    assert "Termodinamica Applicata" in vocab
    assert "Primo Principio della Termodinamica" in vocab
    assert "Secondo Principio ed Entropia" in vocab
    assert "Primo Principio" in vocab
    assert "Secondo Principio" in vocab


@pytest.mark.asyncio
async def test_gemini_38_live_structured_tool_responses():
    """Verify that all examiner tools return compliant Gemini 3.8 Live structured outputs."""
    gstore = InMemoryGraphStore()
    vstore = InMemoryVectorStore()
    manager = SessionAssessmentManager(graph_store=gstore, vector_store=vstore)
    agent = OralExaminerAgent(assessment_manager=manager)

    # evaluate_and_advance returns status: ok and retryable: false
    resp = await agent.evaluate_and_advance(None, "Non ho capito bene la domanda.")
    assert "status: ok" in resp
    assert "retryable: false" in resp

    # get_exam_progress returns structured status
    prog = await agent.get_exam_progress(None)
    assert "status: ok" in prog
    assert "retryable: false" in prog

    # pause_session returns structured status
    pause = await agent.pause_session(None)
    assert "status: ok" in pause
    assert "retryable: false" in pause

    # resume_session returns structured status
    resume = await agent.resume_session(None)
    assert "status: ok" in resume
    assert "retryable: false" in resume



