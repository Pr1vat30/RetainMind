import pytest

from rag import (
    ConceptNode,
    ConceptRelation,
    DocumentChunk,
    HybridRAGRetriever,
    InMemoryGraphStore,
    InMemoryVectorStore,
    MockEmbeddingService,
    PedagogicalState,
    RelationType,
)


@pytest.mark.asyncio
async def test_in_memory_vector_store():
    embedder = MockEmbeddingService(dimension=64)
    vstore = InMemoryVectorStore(embedding_service=embedder)

    chunks = [
        DocumentChunk(
            chunk_id="chk_1",
            text="Il secondo principio della termodinamica stabilisce che l'entropia dell'universo aumenta nelle trasformazioni irreversibili.",
            concept_ids=["termodinamica_entropia"],
            section_title="Termodinamica",
        ),
        DocumentChunk(
            chunk_id="chk_2",
            text="L'entalpia è una funzione di stato definita come la somma dell'energia interna e del prodotto pressione-volume.",
            concept_ids=["entalpia"],
            section_title="Termodinamica",
        ),
    ]

    indexed = await vstore.index_chunks(chunks)
    assert indexed == 2
    assert await vstore.count() == 2

    # Search query for entropia
    results = await vstore.search("entropia irreversibile", limit=1)
    assert len(results) == 1
    assert results[0].chunk_id == "chk_1"
    assert "entropia" in results[0].text.lower()


@pytest.mark.asyncio
async def test_in_memory_graph_store_relations_and_multihop():
    gstore = InMemoryGraphStore()

    c1 = ConceptNode(
        id="entropia",
        name="Entropia",
        summary="Misura del disordine molecolare.",
        prerequisites=["calore", "stato_equilibrio"],
        contrasts_with=["entalpia"],
    )
    c2 = ConceptNode(id="calore", name="Calore", summary="Energia in transito.")
    c3 = ConceptNode(
        id="stato_equilibrio",
        name="Stato di Equilibrio",
        summary="Condizione stazionaria.",
    )
    c4 = ConceptNode(id="entalpia", name="Entalpia", summary="Contenuto termico.")
    c5 = ConceptNode(
        id="secondo_principio", name="Secondo Principio", summary="Legge sull'entropia."
    )

    await gstore.upsert_concepts([c1, c2, c3, c4, c5])

    # Add causal relation: entropia -> secondo_principio
    await gstore.add_relation(
        ConceptRelation(
            source_id="entropia",
            target_id="secondo_principio",
            rel_type=RelationType.CAUSES,
            condition="trasformazione_irreversibile",
        )
    )

    # Test prerequisites
    prereqs = await gstore.get_prerequisites("entropia")
    prereq_ids = [p.id for p in prereqs]
    assert "calore" in prereq_ids
    assert "stato_equilibrio" in prereq_ids

    # Test contrasts
    contrasts = await gstore.get_contrasting_concepts("entropia")
    assert any(c.id == "entalpia" for c in contrasts)

    # Test causal targets
    causal = await gstore.get_causal_targets("entropia")
    assert any(c.id == "secondo_principio" for c in causal)

    # Test 2-hop multi-hop traversal
    multihop = await gstore.get_multi_hop_neighbors("calore", max_hops=2)
    multihop_ids = [m.id for m in multihop]
    assert "entropia" in multihop_ids or "secondo_principio" in multihop_ids


@pytest.mark.asyncio
async def test_hybrid_retriever():
    embedder = MockEmbeddingService(dimension=64)
    vstore = InMemoryVectorStore(embedding_service=embedder)
    gstore = InMemoryGraphStore()

    c = ConceptNode(
        id="entropia",
        name="Entropia",
        summary="Funzione di stato associata al disordine.",
        prerequisites=["calore"],
        contrasts_with=["entalpia"],
    )
    c_prereq = ConceptNode(id="calore", name="Calore", summary="Scambio termico.")
    c_contrast = ConceptNode(
        id="entalpia", name="Entalpia", summary="Funzione termodinamica H."
    )

    await gstore.upsert_concepts([c, c_prereq, c_contrast])
    await vstore.index_chunks(
        [
            DocumentChunk(
                chunk_id="chk_ent",
                text="L'entropia S in una trasformazione reversibile è integrale di dQ/T.",
                concept_ids=["entropia"],
            )
        ]
    )

    retriever = HybridRAGRetriever(graph_store=gstore, vector_store=vstore)

    ctx = await retriever.retrieve_context_for_concept(
        concept_id="entropia",
        pedagogical_state=PedagogicalState.EXPLORATION,
    )

    assert ctx.current_concept.id == "entropia"
    assert len(ctx.prerequisites) == 1
    assert ctx.prerequisites[0].id == "calore"
    assert len(ctx.contrasting_concepts) == 1
    assert ctx.contrasting_concepts[0].id == "entalpia"
    assert len(ctx.ground_truth_chunks) >= 1
    assert "dQ/T" in ctx.ground_truth_chunks[0].text
    assert "Entropia" in ctx.pedagogical_directive
