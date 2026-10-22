import pytest

from planning import (
    ExaminationPlan,
    ExaminationPlanner,
    QuestionDifficulty,
)
from rag import (
    ConceptNode,
    DocumentChunk,
    InMemoryGraphStore,
    InMemoryVectorStore,
)


@pytest.mark.asyncio
async def test_examination_planner_topological_sort():
    gstore = InMemoryGraphStore()
    vstore = InMemoryVectorStore()

    # Create concepts with dependencies:
    # calore (no prereq) -> secondo_principio (requires calore) -> cicli_termodinamici (requires secondo_principio)
    c1 = ConceptNode(
        id="cicli_termodinamici",
        name="Cicli Termodinamici",
        prerequisites=["secondo_principio"],
    )
    c2 = ConceptNode(
        id="secondo_principio", name="Secondo Principio", prerequisites=["calore"]
    )
    c3 = ConceptNode(id="calore", name="Calore", prerequisites=[])

    await gstore.upsert_concepts([c1, c2, c3])
    await vstore.index_chunks(
        [
            DocumentChunk(
                chunk_id="chk1",
                text="Il calore è trasferimento di energia.",
                concept_ids=["calore"],
            ),
            DocumentChunk(
                chunk_id="chk2",
                text="Il secondo principio introduce l'entropia.",
                concept_ids=["secondo_principio"],
            ),
            DocumentChunk(
                chunk_id="chk3",
                text="I cicli termodinamici come Carnot hanno rendimento limitato.",
                concept_ids=["cicli_termodinamici"],
            ),
        ]
    )

    planner = ExaminationPlanner(graph_store=gstore, vector_store=vstore)
    plan = await planner.generate_plan(
        document_id="doc_thermo", title="Esame di Termodinamica"
    )

    assert plan.document_id == "doc_thermo"
    assert len(plan.concept_order) == 3

    # Verify topological order: calore must be first, cicli_termodinamici must be last
    calore_idx = plan.concept_order.index("calore")
    sec_idx = plan.concept_order.index("secondo_principio")
    cicli_idx = plan.concept_order.index("cicli_termodinamici")

    assert calore_idx < sec_idx < cicli_idx

    # Check question difficulties
    assert plan.items["calore"].planned_question.difficulty == QuestionDifficulty.EASY
    assert (
        plan.items["secondo_principio"].planned_question.difficulty
        == QuestionDifficulty.MEDIUM
    )
    assert (
        plan.items["cicli_termodinamici"].planned_question.difficulty
        == QuestionDifficulty.MEDIUM
    )

    # Check question fields
    item_sec = plan.items["secondo_principio"]
    assert "Secondo Principio" in item_sec.planned_question.main_question
    assert len(item_sec.planned_question.scaffolding_hints) > 0
    assert len(item_sec.planned_question.narrowing_questions) > 0
    assert len(item_sec.planned_question.stress_test_questions) > 0


def test_examination_plan_serialization_and_progression(tmp_path):
    plan = ExaminationPlan(
        plan_id="plan_test_1",
        document_id="doc_sample",
        title="Test Plan",
        concept_order=["c1", "c2"],
    )

    assert plan.current_index == 0
    assert plan.progress_percentage == 0.0

    # Advance
    _next_item = plan.advance_to_next()
    assert plan.current_index == 1
    assert not plan.is_completed

    # Save to file & load back
    file_path = tmp_path / "plan.json"
    ExaminationPlanner.save_plan_to_file(plan, file_path)

    loaded = ExaminationPlanner.load_plan_from_file(file_path)
    assert loaded.plan_id == "plan_test_1"
    assert loaded.current_index == 1
    assert loaded.concept_order == ["c1", "c2"]
