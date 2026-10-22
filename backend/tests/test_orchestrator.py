import pytest

from orchestrator.gemini_orchestrator import GeminiOrchestrator
from rag import ConceptNode, DocumentChunk, InMemoryGraphStore, InMemoryVectorStore


@pytest.mark.asyncio
async def test_gemini_orchestrator_planning_and_tracing(tmp_path):
    gstore = InMemoryGraphStore()
    vstore = InMemoryVectorStore()
    orchestrator = GeminiOrchestrator(graph_store=gstore, vector_store=vstore)

    c1 = ConceptNode(
        id="sharding", name="Sharding", summary="Partizionamento orizzontale dei dati."
    )
    await gstore.upsert_concept(c1)
    await vstore.index_chunks(
        [
            DocumentChunk(
                chunk_id="chk1",
                text="Lo sharding permette la scalabilità orizzontale dei database.",
                concept_ids=["sharding"],
            )
        ]
    )

    plan = await orchestrator.planner.generate_plan(
        document_id="doc_nosql", title="Esame NoSQL"
    )
    assert "sharding" in plan.concept_order

    # Update knowledge tracing: student answers accurate
    res = await orchestrator.update_knowledge_tracing(
        concept_id="sharding",
        evaluation_result="ACCURATE",
        plan=plan,
    )
    assert res["concept_id"] == "sharding"
    assert res["evaluation"] == "ACCURATE"
    assert res["mastery_delta"] > 0
    assert plan.items["sharding"].status.value == "MASTERED"
