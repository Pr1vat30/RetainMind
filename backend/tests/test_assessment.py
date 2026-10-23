import json
from pathlib import Path

import pytest

from assessment import (
    BayesianKnowledgeTracing,
    OralExaminerFSM,
    ResponseEvaluator,
    SessionAssessmentManager,
    SessionReportGenerator,
    SessionStatus,
)
from planning.models import (
    ConceptPlanItem,
    ExaminationPlan,
    PlanItemStatus,
    PlannedQuestion,
)
from rag import (
    ConceptNode,
    ConceptStatus,
    DocumentChunk,
    EvaluationResultType,
    GroundTruthPassage,
    InMemoryGraphStore,
    InMemoryVectorStore,
    PedagogicalState,
)


def test_response_evaluator_classifications():
    evaluator = ResponseEvaluator()
    target = ConceptNode(
        id="entropia",
        name="Entropia",
        summary="Misura del disordine molecolare e dispersione termica.",
    )
    contrasting = [
        ConceptNode(id="entalpia", name="Entalpia", summary="Contenuto termico H.")
    ]
    ground_truth = [
        GroundTruthPassage(
            chunk_id="chk1",
            text="L'entropia definisce la degradazione dell'energia in un sistema isolato.",
        )
    ]

    # 1. Accurate answer
    acc_res = evaluator.evaluate_response(
        student_response="L'entropia rappresenta il grado di disordine molecolare e la dispersione termica in un sistema termodinamico.",
        target_concept=target,
        ground_truth=ground_truth,
        contrasting_concepts=contrasting,
    )
    assert acc_res.evaluation_result == EvaluationResultType.ACCURATE

    # 2. Hesitant answer
    hes_res = evaluator.evaluate_response(
        student_response="Ehm... forse... uhm... non so bene.",
        target_concept=target,
        ground_truth=ground_truth,
        contrasting_concepts=contrasting,
    )
    assert hes_res.evaluation_result == EvaluationResultType.HESITANT

    # 3. Misconception (confused with contrasting concept entalpia)
    misc_res = evaluator.evaluate_response(
        student_response="L'entropia misura l'entalpia totale del sistema a pressione costante.",
        target_concept=target,
        ground_truth=ground_truth,
        contrasting_concepts=contrasting,
    )
    assert misc_res.evaluation_result == EvaluationResultType.MISCONCEPTION

    # 4. Memorized verbatim answer
    mem_res = evaluator.evaluate_response(
        student_response="L'entropia definisce la degradazione dell'energia in un sistema isolato.",
        target_concept=target,
        ground_truth=ground_truth,
        contrasting_concepts=contrasting,
    )
    assert mem_res.evaluation_result == EvaluationResultType.MEMORIZED

    # 5. Vague answer
    vague_res = evaluator.evaluate_response(
        student_response="Parla di entropia e cose fisiche.",
        target_concept=target,
        ground_truth=ground_truth,
        contrasting_concepts=contrasting,
    )
    assert vague_res.evaluation_result == EvaluationResultType.VAGUE


def test_response_evaluator_flexible_and_stt_tolerance():
    """Verify that student explanations with STT artifacts and flexible paraphrasing are correctly recognized as ACCURATE."""
    evaluator = ResponseEvaluator()
    target = ConceptNode(
        id="database_nosql",
        name="DATABASE NOSQL",
        summary="Tecnologie per gestione di grandi volumi di dati e superamento limiti RDBMS.",
    )
    ground_truth = [
        GroundTruthPassage(
            chunk_id="gt1",
            text="NoSQL non è uno specifico linguaggio, ma è il termine che raggruppa un insieme di tecnologie eterogenee per gestire grandi volumi di dati non strutturati o dinamici, offrendo scalabilità orizzontale e superando i limiti di rigidità dei database relazionali.",
            concept_ids=["database_nosql"],
        )
    ]

    # Real voice transcription with phonetic STT artifacts (não esse que ele, screto)
    real_stt_response = (
        "I databae i database não esse que ele non rappresenta un singolo linguaggio, "
        "ma un insieme di tecnologie eterogenee nato per superare i limiti di rigidità del database relazionali. "
        "Sono progettati specificamente per gestire grandi volumi di dati, big data e strutture dati dinamiche "
        "o non strutturate prive di uno screto prefissato offrendo classica"
    )

    result = evaluator.evaluate_response(
        student_response=real_stt_response,
        target_concept=target,
        ground_truth=ground_truth,
    )

    assert result.evaluation_result == EvaluationResultType.ACCURATE
    assert result.confidence >= 0.85


def test_response_evaluator_balanced_discrimination():
    """Verify that casual keyword mentioning is classified as PARTIAL, whereas articulated explanation is ACCURATE."""
    evaluator = ResponseEvaluator()
    target = ConceptNode(
        id="database_nosql",
        name="DATABASE NOSQL",
        summary="Tecnologie per gestione di grandi volumi di dati e superamento limiti RDBMS.",
    )
    ground_truth = [
        GroundTruthPassage(
            chunk_id="gt1",
            text="NoSQL non è uno specifico linguaggio, ma è il termine che raggruppa un insieme di tecnologie eterogenee per gestire grandi volumi di dati non strutturati o dinamici, offrendo scalabilità orizzontale e superando i limiti di rigidità dei database relazionali.",
            concept_ids=["database_nosql"],
        )
    ]

    # 1. Casual keyword throwing (only mentions macro-topics without articulation) -> PARTIAL
    casual_res = evaluator.evaluate_response(
        student_response="NoSQL per i big data e scalabilità.",
        target_concept=target,
        ground_truth=ground_truth,
    )
    assert casual_res.evaluation_result == EvaluationResultType.PARTIAL

    # 2. Articulated explanation -> ACCURATE
    articulated_res = evaluator.evaluate_response(
        student_response="I database NoSQL nascono per superare i limiti di rigidità degli RDBMS tradizionali, consentendo di memorizzare grandi volumi di dati dinamici con scalabilità orizzontale.",
        target_concept=target,
        ground_truth=ground_truth,
    )
    assert articulated_res.evaluation_result == EvaluationResultType.ACCURATE

    # 3. Super-vague response -> VAGUE
    vague_res = evaluator.evaluate_response(
        student_response="È un tipo di database.",
        target_concept=target,
        ground_truth=ground_truth,
    )
    assert vague_res.evaluation_result == EvaluationResultType.VAGUE


@pytest.mark.asyncio
async def test_bayesian_knowledge_tracing_and_propagation():
    gstore = InMemoryGraphStore()
    c_base = ConceptNode(id="calore", name="Calore", mastery_score=0.60)
    c_adv = ConceptNode(
        id="entropia",
        name="Entropia",
        mastery_score=0.70,
        prerequisites=["calore"],
    )
    await gstore.upsert_concepts([c_base, c_adv])

    bkt = BayesianKnowledgeTracing(
        graph_store=gstore,
        accurate_gain=0.35,
        hesitation_decay=0.90,
        mistake_decay=0.60,
        prerequisite_threshold=0.45,
    )

    # Test accurate gain
    updated, delta = await bkt.update_concept_mastery(
        "calore", EvaluationResultType.ACCURATE
    )
    assert delta > 0
    assert updated.mastery_score > 0.60

    # Test severe mistake decay dropping below threshold (0.60 * 0.60 = 0.36 < 0.45)
    updated2, _delta2 = await bkt.update_concept_mastery(
        "calore", EvaluationResultType.MISCONCEPTION
    )
    assert updated2.mastery_score < 0.45

    # Check that advanced concept dependent on calore is blocked
    adv_node = await gstore.get_concept("entropia")
    assert adv_node.status == ConceptStatus.BLOCKED_BY_PREREQUISITE


def test_fsm_transitions():
    fsm = OralExaminerFSM(max_scaffolding_attempts=2)
    concept = ConceptNode(id="c1", name="Concetto 1")
    prereq = ConceptNode(id="p1", name="Prerequisito 1")
    contrast = ConceptNode(id="cw1", name="Contrastante 1")
    causal = ConceptNode(id="eff1", name="Effetto 1")
    multihop = ConceptNode(id="mh1", name="MultiHop 1")

    # 1. Accurate -> Multi-Hop Synthesis
    state, next_node, rel = fsm.determine_next_transition(
        current_concept=concept,
        evaluation=EvaluationResultType.ACCURATE,
        consecutive_failures=0,
        prerequisites=[prereq],
        causal_targets=[causal],
        contrasting_concepts=[contrast],
        multi_hop_neighbors=[multihop],
        all_concepts=[concept, prereq, multihop],
    )
    assert state == PedagogicalState.MULTI_HOP_SYNTHESIS
    assert next_node == "mh1"
    assert rel == "MULTI_HOP"

    # 2. Vague -> Causal Narrowing
    state, next_node, rel = fsm.determine_next_transition(
        current_concept=concept,
        evaluation=EvaluationResultType.VAGUE,
        consecutive_failures=1,
        prerequisites=[prereq],
        causal_targets=[causal],
        contrasting_concepts=[contrast],
        multi_hop_neighbors=[],
        all_concepts=[concept],
    )
    assert state == PedagogicalState.CAUSAL_NARROWING
    assert rel == "CAUSES"

    # 3. Hesitant -> Scaffolding (1st failure)
    state, next_node, rel = fsm.determine_next_transition(
        current_concept=concept,
        evaluation=EvaluationResultType.HESITANT,
        consecutive_failures=1,
        prerequisites=[prereq],
        causal_targets=[],
        contrasting_concepts=[],
        multi_hop_neighbors=[],
        all_concepts=[concept],
    )
    assert state == PedagogicalState.SCAFFOLDING

    # 4. Hesitant -> Prerequisite Fallback (>2 consecutive failures)
    state, next_node, rel = fsm.determine_next_transition(
        current_concept=concept,
        evaluation=EvaluationResultType.HESITANT,
        consecutive_failures=3,
        prerequisites=[prereq],
        causal_targets=[],
        contrasting_concepts=[],
        multi_hop_neighbors=[],
        all_concepts=[concept],
    )
    assert state == PedagogicalState.PREREQUISITE_FALLBACK
    assert next_node == "p1"
    assert rel == "REQUIRES"

    # 5. Misconception -> Conceptual Collision
    state, next_node, rel = fsm.determine_next_transition(
        current_concept=concept,
        evaluation=EvaluationResultType.MISCONCEPTION,
        consecutive_failures=1,
        prerequisites=[],
        causal_targets=[],
        contrasting_concepts=[contrast],
        multi_hop_neighbors=[],
        all_concepts=[concept],
    )
    assert state == PedagogicalState.CONCEPTUAL_COLLISION
    assert rel == "CONTRASTS_WITH"


@pytest.mark.asyncio
async def test_session_assessment_manager_full_turn():
    gstore = InMemoryGraphStore()
    vstore = InMemoryVectorStore()

    c1 = ConceptNode(
        id="trasformazione_reversibile",
        name="Trasformazione Reversibile",
        summary="Trasformazione quasi-statica senza dissipazione di calore.",
        mastery_score=0.40,
    )
    c2 = ConceptNode(
        id="secondo_principio",
        name="Secondo Principio",
        summary="L'entropia dell'universo aumenta.",
        prerequisites=["trasformazione_reversibile"],
        mastery_score=0.50,
    )

    await gstore.upsert_concepts([c1, c2])
    await vstore.index_chunks(
        [
            DocumentChunk(
                chunk_id="chk_rev",
                text="In una trasformazione reversibile l'entropia totale si conserva.",
                concept_ids=["trasformazione_reversibile"],
            )
        ]
    )

    manager = SessionAssessmentManager(graph_store=gstore, vector_store=vstore)
    init_ctx = await manager.initialize_session()
    assert init_ctx.current_concept.id in (
        "trasformazione_reversibile",
        "secondo_principio",
    )

    # Force current concept to trasformazione_reversibile
    manager.current_concept_id = "trasformazione_reversibile"

    # Execute a turn with accurate student response
    ctx, turn_state = await manager.process_student_turn(
        student_transcript="Una trasformazione reversibile è una trasformazione quasi-statica ideale senza attrito o dissipazione termica."
    )

    assert turn_state.assessed_concept_id == "trasformazione_reversibile"
    assert turn_state.evaluation_result == EvaluationResultType.ACCURATE
    assert turn_state.mastery_delta > 0
    assert turn_state.graph_relation_followed in (
        "REQUIRES",
        "CAUSES",
        "MULTI_HOP",
        "NONE",
    )
    assert ctx.pedagogical_state is not None
    assert len(manager.history) == 1

    # Check diagnostic report generation
    reporter = SessionReportGenerator(gstore)
    rep = await reporter.generate_diagnostic_report(manager.history)
    assert "average_mastery" in rep
    assert "spoken_summary" in rep


@pytest.mark.asyncio
async def test_plan_guided_assessment_progression(tmp_path):
    from planning import (
        ConceptPlanItem,
        ExaminationPlan,
        PlanItemStatus,
        PlannedQuestion,
    )

    gstore = InMemoryGraphStore()
    vstore = InMemoryVectorStore()

    c1 = ConceptNode(id="concetto_a", name="Concetto A", summary="Primo concetto.")
    c2 = ConceptNode(id="concetto_b", name="Concetto B", summary="Secondo concetto.")
    await gstore.upsert_concepts([c1, c2])

    q1 = PlannedQuestion(
        question_id="q_a",
        concept_id="concetto_a",
        main_question="Domanda su A",
        scaffolding_hints=["Indizio su A"],
        max_attempts=2,
    )
    q2 = PlannedQuestion(
        question_id="q_b",
        concept_id="concetto_b",
        main_question="Domanda su B",
        max_attempts=2,
    )

    plan = ExaminationPlan(
        plan_id="plan_prog_1",
        concept_order=["concetto_a", "concetto_b"],
        items={
            "concetto_a": ConceptPlanItem(
                concept_id="concetto_a", concept_name="Concetto A", planned_question=q1
            ),
            "concetto_b": ConceptPlanItem(
                concept_id="concetto_b", concept_name="Concetto B", planned_question=q2
            ),
        },
    )

    manager = SessionAssessmentManager(
        graph_store=gstore, vector_store=vstore, examination_plan=plan
    )

    # 1. Turn 1 on Concetto A: Student is hesitant (attempt 1) -> Should stay on Concetto A and deliver scaffold
    ctx1, ts1 = await manager.process_student_turn("Ehm... forse...")
    assert ts1.assessed_concept_id == "concetto_a"
    assert manager.current_concept_id == "concetto_a"
    assert plan.items["concetto_a"].current_attempt == 1
    assert "Indizio su A" in ctx1.pedagogical_directive

    # 2. Turn 2 on Concetto A: Student is vague again (attempt 2 reaches max_attempts) -> Defers A to cyclic queue and advances to Concetto B
    ctx2, ts2 = await manager.process_student_turn("Cose vaghe e non so.")
    assert ts2.assessed_concept_id == "concetto_a"
    assert plan.items["concetto_a"].status == PlanItemStatus.DEFERRED
    assert len(plan.deferred_queue) == 1
    assert manager.current_concept_id == "concetto_b"
    assert plan.current_index == 1
    assert "Nessun problema" in ctx2.pedagogical_directive

    # 3. Turn 3 on Concetto B: Student is accurate -> Marks MASTERED and completes plan
    _ctx3, ts3 = await manager.process_student_turn(
        "Concetto B è il secondo concetto fondamentale spiegato in dettaglio."
    )
    assert ts3.assessed_concept_id == "concetto_b"
    assert plan.items["concetto_b"].status == PlanItemStatus.MASTERED

    # Test session persistence
    state_file = tmp_path / "session_state.json"
    manager.save_session_state(state_file)

    loaded_manager = SessionAssessmentManager(graph_store=gstore, vector_store=vstore)
    loaded_manager.load_session_state(state_file)
    assert loaded_manager.examination_plan.plan_id == "plan_prog_1"


@pytest.mark.asyncio
async def test_cyclic_deferred_queue_progression():
    """Verify cyclic retry: Concept A fails -> switches to B & C -> after 2 correct answers, returns to A."""
    gstore = InMemoryGraphStore()
    vstore = InMemoryVectorStore()

    c_list = [
        ConceptNode(
            id="concetto_a", name="Concetto A", summary="Spiegazione di Concetto A"
        ),
        ConceptNode(
            id="concetto_b", name="Concetto B", summary="Spiegazione di Concetto B"
        ),
        ConceptNode(
            id="concetto_c", name="Concetto C", summary="Spiegazione di Concetto C"
        ),
    ]
    await gstore.upsert_concepts(c_list)
    await vstore.index_chunks(
        [
            DocumentChunk(
                chunk_id=f"chk_{c.id}",
                text=f"{c.name} spiegazione dettagliata.",
                metadata={"concept_id": c.id},
            )
            for c in c_list
        ]
    )

    q1 = PlannedQuestion(
        question_id="q_a",
        concept_id="concetto_a",
        main_question="Domanda A",
        scaffolding_hints=["Indizio A"],
        max_attempts=2,
    )
    q2 = PlannedQuestion(
        question_id="q_b",
        concept_id="concetto_b",
        main_question="Domanda B",
        max_attempts=2,
    )
    q3 = PlannedQuestion(
        question_id="q_c",
        concept_id="concetto_c",
        main_question="Domanda C",
        max_attempts=2,
    )

    plan = ExaminationPlan(
        plan_id="plan_cyclic_1",
        title="Esame Ciclico",
        concept_order=["concetto_a", "concetto_b", "concetto_c"],
        items={
            "concetto_a": ConceptPlanItem(
                concept_id="concetto_a", concept_name="Concetto A", planned_question=q1
            ),
            "concetto_b": ConceptPlanItem(
                concept_id="concetto_b", concept_name="Concetto B", planned_question=q2
            ),
            "concetto_c": ConceptPlanItem(
                concept_id="concetto_c", concept_name="Concetto C", planned_question=q3
            ),
        },
    )

    manager = SessionAssessmentManager(
        graph_store=gstore, vector_store=vstore, examination_plan=plan
    )

    # 1. Fail Concetto A twice -> Defer to cyclic queue, move to Concetto B
    await manager.process_student_turn("Non lo so")
    ctx_fail2, _ = await manager.process_student_turn("Non lo so proprio")
    assert plan.items["concetto_a"].status == PlanItemStatus.DEFERRED
    assert manager.current_concept_id == "concetto_b"
    assert "Nessun problema" in ctx_fail2.pedagogical_directive

    # 2. Answer Concetto B correctly (1st correct answer since deferral) -> Next is Concetto C
    _ctx_b, ts_b = await manager.process_student_turn(
        "Concetto B spiegazione dettagliata e chiara."
    )
    assert ts_b.assessed_concept_id == "concetto_b"
    assert plan.items["concetto_b"].status == PlanItemStatus.MASTERED
    assert manager.current_concept_id == "concetto_c"

    # 3. Answer Concetto C correctly (2nd correct answer since deferral -> reaches required 2 correct answers)
    ctx_c, ts_c = await manager.process_student_turn(
        "Concetto C spiegazione dettagliata e corretta."
    )
    assert ts_c.assessed_concept_id == "concetto_c"
    assert plan.items["concetto_c"].status == PlanItemStatus.MASTERED
    # Should automatically trigger cyclic spaced repetition retry for Concetto A!
    assert ts_c.next_target_node == "concetto_a"
    assert "torniamo un attimo indietro su Concetto A" in ctx_c.pedagogical_directive


@pytest.mark.asyncio
async def test_session_pause_and_resume(tmp_path):
    from assessment import SessionStatus

    gstore = InMemoryGraphStore()
    vstore = InMemoryVectorStore()
    c1 = ConceptNode(id="sharding", name="Sharding", summary="Partizionamento.")
    await gstore.upsert_concept(c1)
    await vstore.index_chunks(
        [
            DocumentChunk(
                chunk_id="chk_s",
                text="Lo sharding distribuisce i dati orizzontalmente.",
                concept_ids=["sharding"],
            )
        ]
    )

    state_file = tmp_path / "test_session_state.json"
    manager = SessionAssessmentManager(
        graph_store=gstore,
        vector_store=vstore,
        state_file_path=state_file,
    )
    await manager.initialize_session()

    # 1. User asks for a pause
    ctx_pause, ts_pause = await manager.process_student_turn("Facciamo una pausa")
    assert manager.status == SessionStatus.PAUSED
    assert ts_pause.graph_relation_followed == "SESSION_PAUSE"
    assert "messo in pausa" in ctx_pause.pedagogical_directive
    assert state_file.exists()

    # 2. Restore state from file in a new manager
    new_manager = SessionAssessmentManager(
        graph_store=gstore,
        vector_store=vstore,
        state_file_path=state_file,
    )
    new_manager.load_session_state(state_file)
    assert new_manager.status == SessionStatus.PAUSED
    assert new_manager.current_concept_id == "sharding"

    # 3. Resume session
    ctx_resume, ts_resume = await new_manager.process_student_turn("Riprendiamo")
    assert new_manager.status == SessionStatus.ACTIVE
    assert "Bentornato" in ctx_resume.pedagogical_directive
    assert ts_resume.graph_relation_followed == "SESSION_RESUME"


@pytest.mark.asyncio
async def test_technical_stop_does_not_pause():
    """Verify that mentioning technical terms like 'early stopping' or 'bootstrap' does NOT trigger pause."""
    gstore = InMemoryGraphStore()
    vstore = InMemoryVectorStore()
    c1 = ConceptNode(id="ml", name="Machine Learning", summary="Modelli ML.")
    await gstore.upsert_concept(c1)
    manager = SessionAssessmentManager(graph_store=gstore, vector_store=vstore)
    await manager.initialize_session()

    # Mentioning early stopping should evaluate student answer, NOT pause the session
    ctx, ts = await manager.process_student_turn("Per prevenire l'overfitting usiamo l'early stopping.")
    assert manager.status == SessionStatus.ACTIVE
    assert ts.graph_relation_followed != "SESSION_PAUSE"

    # Mentioning bootstrap should NOT pause
    ctx2, ts2 = await manager.process_student_turn("Possiamo usare il bootstrap e bagging per ensemble.")
    assert manager.status == SessionStatus.ACTIVE
    assert ts2.graph_relation_followed != "SESSION_PAUSE"


@pytest.mark.asyncio
async def test_session_repeat_and_dynamic_adaptation(tmp_path):
    gstore = InMemoryGraphStore()
    vstore = InMemoryVectorStore()
    c1 = ConceptNode(id="acid", name="ACID Transactions", summary="Transazioni ACID.")
    c2 = ConceptNode(
        id="nosql", name="Database NoSQL", summary="Database non relazionali."
    )
    await gstore.upsert_concepts([c1, c2])
    await vstore.index_chunks(
        [
            DocumentChunk(
                chunk_id="c_acid",
                text="Atomicity, Consistency, Isolation, Durability.",
                concept_ids=["acid"],
            ),
            DocumentChunk(
                chunk_id="c_nosql",
                text="Documenti, grafi e key-value.",
                concept_ids=["nosql"],
            ),
        ]
    )

    q1 = PlannedQuestion(
        question_id="q_acid",
        concept_id="acid",
        main_question="Cosa sono le proprietà ACID?",
        narrowing_questions=["Mi spieghi l'isolamento?"],
        max_attempts=2,
    )
    q2 = PlannedQuestion(
        question_id="q_nosql",
        concept_id="nosql",
        main_question="Cosa sono i database NoSQL?",
        max_attempts=2,
    )
    plan = ExaminationPlan(
        plan_id="plan_rep",
        concept_order=["acid", "nosql"],
        items={
            "acid": ConceptPlanItem(
                concept_id="acid",
                concept_name="ACID Transactions",
                planned_question=q1,
            ),
            "nosql": ConceptPlanItem(
                concept_id="nosql",
                concept_name="Database NoSQL",
                planned_question=q2,
            ),
        },
    )

    state_file = tmp_path / "test_repeat_state.json"
    manager = SessionAssessmentManager(
        graph_store=gstore,
        vector_store=vstore,
        examination_plan=plan,
        state_file_path=state_file,
    )

    # 1. Start iteration 1
    await manager.process_student_turn("Sì, sono pronto")
    # Fail ACID
    await manager.process_student_turn("Non lo so proprio")
    await manager.process_student_turn("Non saprei")

    # Pass NoSQL
    await manager.process_student_turn(
        "I database NoSQL archiviano documenti, chiavi-valore o grafi senza schemi fissi."
    )

    assert len(manager.history) >= 4
    assert manager.current_iteration == 1

    # 2. Student triggers repeat
    ctx_rep, ts_rep = await manager.process_student_turn(
        "Voglio ripetere l'esame da capo"
    )
    assert manager.current_iteration == 2
    assert len(manager.iterations_history) == 1
    assert manager.iterations_history[0]["iteration"] == 1
    assert "ACID Transactions" in manager.iterations_history[0]["weak_concepts"]
    assert "Iterazione 2" in ctx_rep.pedagogical_directive
    assert ts_rep.graph_relation_followed == "SESSION_RESTART"
    assert manager.examination_plan.current_index == 0


@pytest.mark.asyncio
async def test_session_iteration_comparison_reporting():
    gstore = InMemoryGraphStore()
    c1 = ConceptNode(
        id="acid",
        name="ACID Transactions",
        summary="Transazioni ACID.",
        mastery_score=0.85,
    )
    c2 = ConceptNode(
        id="nosql",
        name="Database NoSQL",
        summary="Database NoSQL.",
        mastery_score=0.90,
    )
    c3 = ConceptNode(
        id="sharding",
        name="Sharding",
        summary="Partizionamento.",
        mastery_score=0.30,
        mistake_count=1,
    )
    await gstore.upsert_concepts([c1, c2, c3])

    report_gen = SessionReportGenerator(graph_store=gstore)

    iter_1 = {
        "iteration": 1,
        "average_mastery": 0.40,
        "mastered_concepts": [],
        "weak_concepts": ["ACID Transactions", "Database NoSQL", "Sharding"],
        "history": [],
    }

    current_history = [{"turn": 1, "concept_id": "acid", "evaluation": "ACCURATE"}]
    comp = await report_gen.compare_iterations(
        current_history=current_history,
        iterations_history=[iter_1],
    )

    assert comp["has_previous_iterations"] is True
    assert comp["compared_iteration"] == 1
    assert comp["mastery_delta"] > 0.20
    assert "ACID Transactions" in comp["recovered_concepts"]
    assert "Database NoSQL" in comp["recovered_concepts"]
    assert "Sharding" in comp["persistent_weak_concepts"]
    assert "aumentata di" in comp["spoken_comparison"]
    assert "Ottimo recupero" in comp["spoken_comparison"]


@pytest.mark.asyncio
async def test_turn_deduplication_and_noise_filtering():
    """Verify that identical transcripts submitted in rapid succession (<= 2s) are deduplicated,
    and empty / noise strings do not corrupt the examination flow."""
    gstore = InMemoryGraphStore()
    vstore = InMemoryVectorStore()

    c = ConceptNode(id="nosql", name="Database NoSQL", summary="Tecnologie NoSQL.")
    await gstore.upsert_concept(c)

    q = PlannedQuestion(
        question_id="q_nosql",
        concept_id="nosql",
        main_question="Cosa sono i database NoSQL?",
        max_attempts=2,
    )
    plan = ExaminationPlan(
        plan_id="plan_dedup",
        concept_order=["nosql"],
        items={
            "nosql": ConceptPlanItem(
                concept_id="nosql", concept_name="Database NoSQL", planned_question=q
            )
        },
    )

    manager = SessionAssessmentManager(
        graph_store=gstore, vector_store=vstore, examination_plan=plan
    )

    # 1. First turn: Readiness check
    ctx1, _ = await manager.process_student_turn("Sì, possiamo iniziare.")
    assert len(manager.history) == 1
    assert "Perfetto, iniziamo subito!" in ctx1.pedagogical_directive

    # Rapid duplicate of readiness check within 50ms -> Should be deduplicated and return same context
    ctx1_dup, _ = await manager.process_student_turn("Sì, possiamo iniziare.")
    assert len(manager.history) == 1
    assert ctx1_dup.pedagogical_directive == ctx1.pedagogical_directive

    # 2. Second turn: Student gives a vague answer (attempt 1)
    ctx2, _ts2 = await manager.process_student_turn("A causa degli schemi fissi.")
    assert len(manager.history) == 2
    assert plan.items["nosql"].current_attempt == 1

    # Rapid duplicate call (15ms apart) with identical transcript -> Deduplicated! Attempt remains 1, history length remains 2!
    ctx2_dup, _ = await manager.process_student_turn("A causa degli schemi fissi.")
    assert len(manager.history) == 2
    assert plan.items["nosql"].current_attempt == 1
    assert ctx2_dup.pedagogical_directive == ctx2.pedagogical_directive

    # 3. Noise input -> Ignored without advancing attempt
    _ctx_noise, _ = await manager.process_student_turn("<noise>")
    assert len(manager.history) == 2
    assert plan.items["nosql"].current_attempt == 1

    # 4. Silence indicator '-' -> Ignored without advancing attempt or polluting history
    _ctx_dash, _ = await manager.process_student_turn("-")
    assert len(manager.history) == 2
    assert plan.items["nosql"].current_attempt == 1

    # 5. Long dash '—' or ellipsis '...' -> Also ignored
    _ctx_longdash, _ = await manager.process_student_turn("—")
    assert len(manager.history) == 2
    _ctx_dots, _ = await manager.process_student_turn("...")
    assert len(manager.history) == 2


@pytest.mark.asyncio
async def test_silence_filtering_in_service_and_courses(tmp_path: Path):
    from assessment.courses import CourseManager
    from assessment.service import SessionService
    from assessment.state import is_silence_or_noise

    assert is_silence_or_noise("-") is True
    assert is_silence_or_noise("—") is True
    assert is_silence_or_noise("--") is True
    assert is_silence_or_noise("...") is True
    assert is_silence_or_noise("  -  ") is True
    assert is_silence_or_noise("[silenzio]") is True
    assert is_silence_or_noise("Sì, certo") is False
    assert is_silence_or_noise("ACID indica quattro proprietà fondamentali.") is False

    # Verify CourseManager and SessionService filter out silence turns
    state_file = tmp_path / "state.json"
    state_file.write_text(
        json.dumps(
            {
                "current_iteration": 1,
                "history": [
                    {
                        "turn": 1,
                        "concept_id": "c1",
                        "concept_name": "Concetto 1",
                        "ai_question": "Domanda 1",
                        "student_response": "Risposta valida",
                        "evaluation_result": "ACCURATE",
                    },
                    {
                        "turn": 2,
                        "concept_id": "c1",
                        "concept_name": "Concetto 1",
                        "ai_question": "Domanda 1",
                        "student_response": "-",
                        "evaluation_result": "VAGUE",
                    },
                ],
                "iterations_history": [],
            }
        ),
        encoding="utf-8",
    )

    service = SessionService(state_file_path=state_file)
    transcript = service.get_conversation_transcript()
    assert len(transcript) == 1
    assert transcript[0]["student_response"] == "Risposta valida"


@pytest.mark.asyncio
async def test_resumed_session_readiness_confirmation():
    from planning import ConceptPlanItem, ExaminationPlan, PlannedQuestion

    gstore = InMemoryGraphStore()
    vstore = InMemoryVectorStore()
    c1 = ConceptNode(id="concept_a", name="Concetto A", summary="Descrizione.")
    await gstore.upsert_concepts([c1])

    q1 = PlannedQuestion(
        question_id="q1",
        concept_id="concept_a",
        main_question="Spiegami il Concetto A.",
        scaffolding_hints=["Indizio A."],
    )
    plan = ExaminationPlan(
        plan_id="plan_res_1",
        concept_order=["concept_a"],
        items={
            "concept_a": ConceptPlanItem(
                concept_id="concept_a",
                concept_name="Concetto A",
                planned_question=q1,
            )
        },
    )
    manager = SessionAssessmentManager(
        graph_store=gstore, vector_store=vstore, examination_plan=plan
    )
    manager.current_concept_id = "concept_a"
    manager.history = [
        {
            "turn": 1,
            "concept_id": "concept_a",
            "evaluation": "RESUMED",
            "transcript": "[SESSION_RESUMED]",
        }
    ]
    manager.last_ai_directive = "Bentornato! Sei pronto a riprendere?"

    ctx, ts = await manager.process_student_turn("Sì, possiamo riprendere.")
    assert ts.graph_relation_followed == "PLAN_RESUME"
    assert "Perfetto, riprendiamo!" in ctx.pedagogical_directive
    assert "Spiegami il Concetto A." in ctx.pedagogical_directive
    assert manager.history[-1]["evaluation"] == "READINESS_CONFIRMED"

