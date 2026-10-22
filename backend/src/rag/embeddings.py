"""Dense text embedding service interfaces and implementations.

Provides an abstract BaseEmbeddingService and a deterministic MockEmbeddingService
for offline testing, fast local execution, and vector store operations.
"""

from __future__ import annotations

import abc
import hashlib
import logging
import math
from collections.abc import Sequence

logger = logging.getLogger("agent.rag.embeddings")


class BaseEmbeddingService(abc.ABC):
    """Abstract interface for dense embedding generation."""

    @abc.abstractmethod
    async def embed_texts(self, texts: Sequence[str]) -> list[list[float]]:
        """Generate dense embeddings for a batch of strings."""
        pass

    @abc.abstractmethod
    async def embed_query(self, query: str) -> list[float]:
        """Generate dense embedding for a single search query."""
        pass

    @property
    @abc.abstractmethod
    def dimension(self) -> int:
        """Vector dimensionality."""
        pass


class MockEmbeddingService(BaseEmbeddingService):
    """Deterministic, lightweight pseudo-embedding service for tests and local development."""

    def __init__(self, dimension: int = 384) -> None:
        self._dim = dimension

    @property
    def dimension(self) -> int:
        return self._dim

    def _generate_vector(self, text: str) -> list[float]:
        tokens = text.lower().split()
        vector = [0.0] * self._dim
        if not tokens:
            return vector

        for token in tokens:
            h = hashlib.sha256(token.encode("utf-8")).digest()
            for i in range(min(self._dim, len(h) * 8)):
                byte_idx = i // 8
                bit_idx = i % 8
                bit_val = 1.0 if ((h[byte_idx] >> bit_idx) & 1) else -1.0
                vector[i] += bit_val

        # L2 normalize
        norm = math.sqrt(sum(x * x for x in vector))
        if norm > 1e-8:
            vector = [x / norm for x in vector]
        return vector

    async def embed_texts(self, texts: Sequence[str]) -> list[list[float]]:
        return [self._generate_vector(t) for t in texts]

    async def embed_query(self, query: str) -> list[float]:
        return self._generate_vector(query)


def get_embedding_service(
    provider: str = "mock", dimension: int = 384
) -> BaseEmbeddingService:
    """Factory to obtain an embedding service instance according to configuration."""
    if provider.lower() == "mock":
        return MockEmbeddingService(dimension=dimension)
    # Default fallback to mock embedding service
    return MockEmbeddingService(dimension=dimension)
