import pytest

from rag import InMemoryGraphStore, InMemoryVectorStore
from rag.ingestion import DocumentParser, IngestionPipeline, KnowledgeExtractor


def test_document_parser():
    parser = DocumentParser(target_chunk_size=50, min_chunk_size=10)
    doc_text = """\
# Termodinamica Generale
La termodinamica studia le trasformazioni dell'energia e del calore.

## Secondo Principio ed Entropia
L'entropia di un sistema isolato non decresce mai nel tempo: dS >= 0.
Questo principio impedisce la creazione di moto perpetuo di seconda specie.

## Entalpia e Trasformazioni Isobara
L'entalpia H = U + pV descrive lo scambio termico a pressione costante.
"""
    chunks = parser.parse_markdown(doc_text, document_id="physics_101")
    assert len(chunks) >= 2
    section_titles = [c.section_title for c in chunks]
    assert any("Entropia" in st or "Termodinamica" in st for st in section_titles)


def test_knowledge_extractor():
    sample_json = {
        "concepts": [
            {
                "id": "termodinamica_entropia",
                "name": "Entropia",
                "summary": "Misura del disordine o della dispersione energetica.",
                "prerequisites": ["calore", "equilibrio"],
                "contrasts_with": ["entalpia"],
            }
        ],
        "relations": [
            {
                "source": "termodinamica_entropia",
                "target": "secondo_principio",
                "type": "DEFINES",
            }
        ],
        "causal_chains": [
            {
                "cause": "trasformazione_irreversibile",
                "effect": "aumento_entropia_universo",
                "condition": "sistema_isolato",
            }
        ],
    }

    concepts, relations, causal_chains = KnowledgeExtractor.parse_structured_json(
        sample_json
    )

    assert len(concepts) == 1
    assert concepts[0].id == "termodinamica_entropia"
    assert "calore" in concepts[0].prerequisites
    assert "entalpia" in concepts[0].contrasts_with

    assert len(causal_chains) == 1
    assert causal_chains[0].cause == "trasformazione_irreversibile"
    assert causal_chains[0].condition == "sistema_isolato"

    assert len(relations) >= 4  # 2 prereq + 1 contrast + 1 defines + 1 causal


@pytest.mark.asyncio
async def test_ingestion_pipeline_end_to_end():
    vstore = InMemoryVectorStore()
    gstore = InMemoryGraphStore()
    pipeline = IngestionPipeline(vector_store=vstore, graph_store=gstore)

    doc_text = """\
# Entropia e Trasformazioni
L'entropia definisce la freccia del tempo nei sistemi termodinamici.
"""
    ontology = {
        "concepts": [
            {
                "id": "entropia",
                "name": "Entropia",
                "summary": "Freccia del tempo e disordine.",
                "prerequisites": [],
                "contrasts_with": [],
            }
        ]
    }

    result = await pipeline.ingest_document(
        content=doc_text,
        document_id="doc_thermo",
        structured_ontology=ontology,
    )

    assert result["chunks_count"] >= 1
    assert result["concepts_count"] == 1
    assert await vstore.count() >= 1

    stored_concept = await gstore.get_concept("entropia")
    assert stored_concept is not None
    assert stored_concept.name == "Entropia"


@pytest.mark.asyncio
async def test_ingestion_pipeline_defaults_to_configured_plan_model():
    from config import config

    selected_models = []

    class CapturingExtractor:
        def extract_with_llm(self, *, chunks, model):
            selected_models.append(model)
            return [], [], []

    pipeline = IngestionPipeline(
        vector_store=InMemoryVectorStore(),
        graph_store=InMemoryGraphStore(),
        extractor=CapturingExtractor(),
    )

    await pipeline.ingest_document(
        content="# Corso\nMateriale didattico del corso.",
        document_id="course_model_default",
    )

    assert selected_models == [config.plan_generation_model]


@pytest.mark.asyncio
async def test_pdf_parsing_and_file_ingestion(tmp_path):
    from pypdf import PdfWriter

    # Generate a lightweight PDF in memory
    pdf_path = tmp_path / "course_notes.pdf"
    writer = PdfWriter()
    writer.add_blank_page(width=200, height=200)
    with open(pdf_path, "wb") as f:
        writer.write(f)

    parser = DocumentParser()
    cleaned = parser.clean_and_normalize(
        "   Testo   con \r\n spazi   anomali.  \n\n\n\nAltro testo. "
    )
    assert "spazi anomali." in cleaned
    assert "\n\n" in cleaned
    assert "\n\n\n" not in cleaned

    # Ingest file test with structured ontology
    vstore = InMemoryVectorStore()
    gstore = InMemoryGraphStore()
    pipeline = IngestionPipeline(vector_store=vstore, graph_store=gstore, parser=parser)

    # Test with text file
    txt_path = tmp_path / "notes.txt"
    txt_path.write_text(
        "# Capitolo 1: Termodinamica\nIntroduzione alle leggi della fisica.",
        encoding="utf-8",
    )

    ontology = {
        "concepts": [
            {
                "id": "termo",
                "name": "Termodinamica",
                "summary": "Leggi della fisica.",
                "prerequisites": [],
                "contrasts_with": [],
            }
        ]
    }
    res = await pipeline.ingest_file(str(txt_path), structured_ontology=ontology)
    assert res["chunks_count"] >= 1
    assert res["document_id"] == "notes"
    assert res["concepts_count"] == 1


def test_clean_and_parse_json_resilience():
    # 1. Unescaped newline and tabs inside JSON string
    raw_with_newlines = '{\n  "title": "Machine Learning",\n  "description": "Prima riga\nSeconda riga\tcon tab",\n  "concepts": []\n}'
    parsed1 = KnowledgeExtractor._clean_and_parse_json(raw_with_newlines)
    assert parsed1["title"] == "Machine Learning"
    assert "Prima riga" in parsed1["description"]

    # 2. Trailing commas in arrays and objects
    raw_with_trailing_commas = (
        '{\n  "title": "Data Science",\n  "tags": ["ml", "ai", ],\n}'
    )
    parsed2 = KnowledgeExtractor._clean_and_parse_json(raw_with_trailing_commas)
    assert parsed2["title"] == "Data Science"
    assert len(parsed2["tags"]) == 2

    # 3. Markdown fenced code block
    raw_markdown = '```json\n{\n  "title": "Fenced Block"\n}\n```'
    parsed3 = KnowledgeExtractor._clean_and_parse_json(raw_markdown)
    assert parsed3["title"] == "Fenced Block"
