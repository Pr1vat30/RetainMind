"""Ingestion pipeline coordinating document parsing, vector indexing, and graph population.

Combines DocumentParser, KnowledgeExtractor, BaseVectorStore, and BaseGraphStore
to process raw course files (PDF/MD/TXT) into structured knowledge stores.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from rag.graph_store import BaseGraphStore
from rag.ingestion.extractor import KnowledgeExtractor
from rag.ingestion.parser import DocumentParser
from rag.models import ConceptNode, ConceptRelation, DocumentChunk
from rag.vector_store import BaseVectorStore

logger = logging.getLogger("agent.rag.ingestion.pipeline")


class IngestionPipeline:
    """Orchestrates end-to-end document parsing, vector indexing, and graph population."""

    def __init__(
        self,
        vector_store: BaseVectorStore,
        graph_store: BaseGraphStore,
        parser: DocumentParser | None = None,
        extractor: KnowledgeExtractor | None = None,
    ) -> None:
        self.vector_store = vector_store
        self.graph_store = graph_store
        self.parser = parser or DocumentParser()
        self.extractor = extractor or KnowledgeExtractor()

    async def ingest_document(
        self,
        content: str,
        document_id: str,
        structured_ontology: dict[str, Any] | None = None,
        use_llm: bool = True,
        llm_model: str = "gemini-3.5-flash-lite",
    ) -> dict[str, Any]:
        """Ingests a document text and optional structured ontology schema."""
        # 1. Parse into semantic chunks
        chunks: list[DocumentChunk] = self.parser.parse_markdown(
            text=content, document_id=document_id
        )

        # 2. Extract concepts & relations (from structured schema or LLM)
        concepts: list[ConceptNode] = []
        relations: list[ConceptRelation] = []
        if structured_ontology:
            concepts, relations, _ = self.extractor.parse_structured_json(
                structured_ontology
            )
        else:
            concepts, relations, _ = self.extractor.extract_with_llm(
                chunks=chunks, model=llm_model
            )

        # Map concept IDs to chunks by keyword search
        for chunk in chunks:
            chunk_concepts = []
            for c in concepts:
                if (
                    c.name.lower() in chunk.text.lower()
                    or c.id.lower() in chunk.text.lower()
                ):
                    chunk_concepts.append(c.id)
            chunk.concept_ids = chunk_concepts

        # 3. Index chunks into Vector Store (Qdrant)
        indexed_count = await self.vector_store.index_chunks(chunks)

        # 4. Upsert concepts & relations into Graph Store (Neo4j)
        for concept in concepts:
            await self.graph_store.upsert_concept(concept)
        for rel in relations:
            await self.graph_store.add_relation(rel)

        return {
            "document_id": document_id,
            "chunks_count": indexed_count,
            "concepts_count": len(concepts),
            "relations_count": len(relations),
        }

    async def ingest_file(
        self,
        file_path: str,
        document_id: str | None = None,
        structured_ontology: dict[str, Any] | None = None,
        use_llm: bool = True,
        llm_model: str = "gemini-3.5-flash-lite",
    ) -> dict[str, Any]:
        """Ingests a file (PDF, MD, TXT) from disk."""
        doc_id = document_id or Path(file_path).stem
        chunks = self.parser.parse_file(file_path, document_id=doc_id)

        concepts: list[ConceptNode] = []
        relations: list[ConceptRelation] = []
        if structured_ontology:
            concepts, relations, _ = self.extractor.parse_structured_json(
                structured_ontology
            )
        else:
            concepts, relations, _ = self.extractor.extract_with_llm(
                chunks=chunks, model=llm_model
            )

        for chunk in chunks:
            chunk_concepts = []
            for c in concepts:
                if (
                    c.name.lower() in chunk.text.lower()
                    or c.id.lower() in chunk.text.lower()
                ):
                    chunk_concepts.append(c.id)
            chunk.concept_ids = chunk_concepts

        indexed_count = await self.vector_store.index_chunks(chunks)

        for concept in concepts:
            await self.graph_store.upsert_concept(concept)
        for rel in relations:
            await self.graph_store.add_relation(rel)

        return {
            "document_id": doc_id,
            "chunks_count": indexed_count,
            "concepts_count": len(concepts),
            "relations_count": len(relations),
        }
