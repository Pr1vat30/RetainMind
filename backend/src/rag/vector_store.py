"""Vector database interfaces and implementations for semantic ground-truth retrieval.

Provides an abstract BaseVectorStore, an InMemoryVectorStore with cosine similarity,
and a production QdrantVectorStore client.
"""

from __future__ import annotations

import abc
import logging
import math
from collections.abc import Sequence

from config import config
from rag.embeddings import BaseEmbeddingService, get_embedding_service
from rag.models import DocumentChunk, GroundTruthPassage

logger = logging.getLogger("agent.rag.vector_store")


class BaseVectorStore(abc.ABC):
    """Abstract base class for vector database operations."""

    @abc.abstractmethod
    async def index_chunks(self, chunks: Sequence[DocumentChunk]) -> int:
        """Embed and store document chunks in the vector collection."""
        pass

    @abc.abstractmethod
    async def search(
        self,
        query: str,
        limit: int = 3,
        concept_id_filter: str | None = None,
    ) -> list[GroundTruthPassage]:
        """Search for top-k matching ground-truth passages."""
        pass

    @abc.abstractmethod
    async def get_by_id(self, chunk_id: str) -> DocumentChunk | None:
        """Fetch a specific chunk by its ID."""
        pass

    @abc.abstractmethod
    async def count(self) -> int:
        """Return total number of chunks stored."""
        pass

    @abc.abstractmethod
    async def clear(self) -> None:
        """Clear all stored vectors and records."""
        pass


class InMemoryVectorStore(BaseVectorStore):
    """Lightweight in-memory vector store with cosine similarity."""

    def __init__(self, embedding_service: BaseEmbeddingService | None = None) -> None:
        self.embedding_service = embedding_service or get_embedding_service(
            config.embedding_provider, config.embedding_dimension
        )
        self._chunks: dict[str, DocumentChunk] = {}
        self._vectors: dict[str, list[float]] = {}
        self._query_cache: dict[str, list[float]] = {}

    def _cosine_similarity(self, a: list[float], b: list[float]) -> float:
        dot = sum(x * y for x, y in zip(a, b))
        norm_a = math.sqrt(sum(x * x for x in a))
        norm_b = math.sqrt(sum(y * y for y in b))
        if norm_a < 1e-8 or norm_b < 1e-8:
            return 0.0
        return dot / (norm_a * norm_b)

    async def index_chunks(self, chunks: Sequence[DocumentChunk]) -> int:
        if not chunks:
            return 0
        texts = [c.text for c in chunks]
        vectors = await self.embedding_service.embed_texts(texts)
        for chunk, vec in zip(chunks, vectors):
            self._chunks[chunk.chunk_id] = chunk
            self._vectors[chunk.chunk_id] = vec
        logger.info("Indexed %d chunks into InMemoryVectorStore", len(chunks))
        return len(chunks)

    async def search(
        self,
        query: str,
        limit: int = 3,
        concept_id_filter: str | None = None,
    ) -> list[GroundTruthPassage]:
        if not self._chunks:
            return []

        if query in self._query_cache:
            query_vec = self._query_cache[query]
        else:
            query_vec = await self.embedding_service.embed_query(query)
            if len(self._query_cache) >= 512:
                self._query_cache.pop(next(iter(self._query_cache)))
            self._query_cache[query] = query_vec
        scored: list[tuple[float, DocumentChunk]] = []

        for chunk_id, chunk in self._chunks.items():
            if concept_id_filter and (
                concept_id_filter not in chunk.concept_ids
                and concept_id_filter.lower() not in chunk.text.lower()
            ):
                continue

            vec = self._vectors.get(chunk_id, [])
            sim = self._cosine_similarity(query_vec, vec)
            # Add lexical boost if query keywords are in the text
            query_words = set(query.lower().split())
            text_words = set(chunk.text.lower().split())
            if query_words and text_words:
                overlap = len(query_words.intersection(text_words)) / len(query_words)
                sim += 0.2 * overlap
            scored.append((sim, chunk))

        scored.sort(key=lambda x: x[0], reverse=True)
        results: list[GroundTruthPassage] = []
        for score, chunk in scored[:limit]:
            results.append(
                GroundTruthPassage(
                    chunk_id=chunk.chunk_id,
                    text=chunk.text,
                    score=float(score),
                    section_title=chunk.section_title,
                    concept_id=chunk.concept_ids[0] if chunk.concept_ids else None,
                )
            )
        return results

    async def get_by_id(self, chunk_id: str) -> DocumentChunk | None:
        return self._chunks.get(chunk_id)

    async def count(self) -> int:
        return len(self._chunks)

    async def clear(self) -> None:
        self._chunks.clear()
        self._vectors.clear()
        self._query_cache.clear()


class QdrantVectorStore(BaseVectorStore):
    """Production Qdrant Vector Store client."""

    def __init__(
        self,
        url: str | None = None,
        api_key: str | None = None,
        collection_name: str | None = None,
        embedding_service: BaseEmbeddingService | None = None,
    ) -> None:
        try:
            from qdrant_client import AsyncQdrantClient
            from qdrant_client.models import Distance, VectorParams
        except ImportError as exc:
            raise ImportError(
                "qdrant-client package is required. Install with `uv add qdrant-client`"
            ) from exc

        self.url = url or config.qdrant_url
        self.api_key = api_key or config.qdrant_api_key or None
        self.collection_name = collection_name or config.qdrant_collection
        self.embedding_service = embedding_service or get_embedding_service(
            config.embedding_provider, config.embedding_dimension
        )
        self.client = AsyncQdrantClient(url=self.url, api_key=self.api_key)
        self._initialized = False
        self._Distance = Distance
        self._VectorParams = VectorParams
        self._query_cache: dict[str, list[float]] = {}

    async def _ensure_collection(self) -> None:
        if self._initialized:
            return
        try:
            collections = await self.client.get_collections()
            collection_names = [c.name for c in collections.collections]
            if self.collection_name not in collection_names:
                await self.client.create_collection(
                    collection_name=self.collection_name,
                    vectors_config=self._VectorParams(
                        size=self.embedding_service.dimension,
                        distance=self._Distance.COSINE,
                    ),
                )
                logger.info("Created Qdrant collection: %s", self.collection_name)
            self._initialized = True
        except Exception as err:
            logger.warning("Qdrant collection setup notice: %s", err)
            self._initialized = True

    async def index_chunks(self, chunks: Sequence[DocumentChunk]) -> int:
        if not chunks:
            return 0
        from qdrant_client.models import PointStruct

        await self._ensure_collection()
        texts = [c.text for c in chunks]
        vectors = await self.embedding_service.embed_texts(texts)

        points = []
        for _i, (chunk, vec) in enumerate(zip(chunks, vectors)):
            points.append(
                PointStruct(
                    id=abs(hash(chunk.chunk_id)) % (2**63 - 1),
                    vector=vec,
                    payload={
                        "chunk_id": chunk.chunk_id,
                        "document_id": chunk.document_id,
                        "section_title": chunk.section_title,
                        "text": chunk.text,
                        "token_count": chunk.token_count,
                        "concept_ids": chunk.concept_ids,
                        "metadata": chunk.metadata,
                    },
                )
            )

        await self.client.upsert(collection_name=self.collection_name, points=points)
        logger.info(
            "Indexed %d chunks into Qdrant (%s)", len(points), self.collection_name
        )
        return len(points)

    async def search(
        self,
        query: str,
        limit: int = 3,
        concept_id_filter: str | None = None,
    ) -> list[GroundTruthPassage]:
        from qdrant_client.models import FieldCondition, Filter, MatchValue

        await self._ensure_collection()
        if query in self._query_cache:
            query_vec = self._query_cache[query]
        else:
            query_vec = await self.embedding_service.embed_query(query)
            if len(self._query_cache) >= 512:
                self._query_cache.pop(next(iter(self._query_cache)))
            self._query_cache[query] = query_vec

        query_filter = None
        if concept_id_filter:
            query_filter = Filter(
                must=[
                    FieldCondition(
                        key="concept_ids",
                        match=MatchValue(value=concept_id_filter),
                    )
                ]
            )

        search_result = await self.client.search(
            collection_name=self.collection_name,
            query_vector=query_vec,
            query_filter=query_filter,
            limit=limit,
        )

        results = []
        for point in search_result:
            payload = point.payload or {}
            concept_ids = payload.get("concept_ids", [])
            results.append(
                GroundTruthPassage(
                    chunk_id=str(payload.get("chunk_id", point.id)),
                    text=payload.get("text", ""),
                    score=float(point.score),
                    section_title=payload.get("section_title", ""),
                    concept_id=concept_ids[0] if concept_ids else None,
                )
            )
        return results

    async def get_by_id(self, chunk_id: str) -> DocumentChunk | None:
        from qdrant_client.models import FieldCondition, Filter, MatchValue

        await self._ensure_collection()
        res = await self.client.scroll(
            collection_name=self.collection_name,
            scroll_filter=Filter(
                must=[FieldCondition(key="chunk_id", match=MatchValue(value=chunk_id))]
            ),
            limit=1,
        )
        points, _ = res
        if not points:
            return None
        payload = points[0].payload or {}
        return DocumentChunk(
            chunk_id=payload.get("chunk_id", chunk_id),
            document_id=payload.get("document_id", ""),
            section_title=payload.get("section_title", ""),
            text=payload.get("text", ""),
            token_count=payload.get("token_count", 0),
            concept_ids=payload.get("concept_ids", []),
            metadata=payload.get("metadata", {}),
        )

    async def count(self) -> int:
        await self._ensure_collection()
        res = await self.client.count(collection_name=self.collection_name)
        return res.count

    async def clear(self) -> None:
        await self._ensure_collection()
        await self.client.delete_collection(collection_name=self.collection_name)
        self._initialized = False


def create_vector_store(
    store_type: str = "memory",
    embedding_service: BaseEmbeddingService | None = None,
) -> BaseVectorStore:
    """Factory to create vector store."""
    if store_type.lower() == "qdrant":
        try:
            return QdrantVectorStore(embedding_service=embedding_service)
        except Exception as err:
            logger.warning(
                "Could not connect to Qdrant (%s), falling back to InMemoryVectorStore",
                err,
            )
            return InMemoryVectorStore(embedding_service=embedding_service)
    return InMemoryVectorStore(embedding_service=embedding_service)
