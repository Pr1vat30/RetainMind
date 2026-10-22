"""Document parsing and semantic boundary chunking.

Extracts text from PDF, Markdown, and TXT files, performs Unicode NFKC normalization,
filters slide boilerplate/artifacts, normalizes bullet glyphs, and segments content
along semantic header boundaries (H1, H2, H3) and paragraph blocks.
"""

from __future__ import annotations

import io
import logging
import re
import unicodedata
import uuid
from pathlib import Path

from rag.models import DocumentChunk

logger = logging.getLogger("agent.rag.ingestion.parser")

# Non-content boilerplate patterns commonly found in academic lecture slides
ACADEMIC_BOILERPLATE_PATTERNS: tuple[re.Pattern, ...] = (
    re.compile(r"^a\.a\s*\d{4}/\d{4}", re.IGNORECASE),
    re.compile(r"^prof(\.|\.ssa|\.re)?\s+.*", re.IGNORECASE),
    re.compile(r"^basi di dati\s*\d*", re.IGNORECASE),
    re.compile(r"^(the end|fine|domande\?|questions\?)$", re.IGNORECASE),
    re.compile(r"^why\s+(rdbms|nosql)\??$", re.IGNORECASE),
)

# Bullet glyphs to normalize
BULLET_GLYPHS_REGEX = re.compile(
    r"[\u2022\u2023\u25aa\u25a0\u25a1\u25cb\u2744\uf0a7\uf0a8\uf0d8\uf0b7\uf0fc]"
)


class DocumentParser:
    """Parses PDFs, markdown, text, tables, and LaTeX documents into structured semantic chunks."""

    def __init__(self, target_chunk_size: int = 400, min_chunk_size: int = 50) -> None:
        self.target_chunk_size = target_chunk_size
        self.min_chunk_size = min_chunk_size

    def clean_and_normalize(self, text: str) -> str:
        """Clean and normalize extracted raw text while preserving formulas and structure."""
        if not text:
            return ""
        # Unicode normalization (NFKC)
        normalized = unicodedata.normalize("NFKC", text)

        # Normalize special bullet characters to clean markdown bullet
        normalized = BULLET_GLYPHS_REGEX.sub("- ", normalized)

        # Fix strange hyphens and non-standard whitespace
        normalized = re.sub(r"[\r\f\v]", "\n", normalized)
        normalized = re.sub(r"[ \t]+", " ", normalized)

        # Clean spaces before punctuation
        normalized = re.sub(r"\s+([,.:;?!])", r"\1", normalized)

        # Clean bullet spacing: "-  " -> "- "
        normalized = re.sub(r"^-\s+", "- ", normalized, flags=re.MULTILINE)

        # Preserve double newlines for paragraph breaks
        normalized = re.sub(r"\n{3,}", "\n\n", normalized)
        return normalized.strip()

    def _is_boilerplate_line(self, line: str) -> bool:
        """Checks if a line is academic boilerplate (prof names, year, course name)."""
        stripped = line.strip()
        if not stripped:
            return True
        return any(pat.match(stripped) for pat in ACADEMIC_BOILERPLATE_PATTERNS)

    def _reassemble_wrapped_lines(self, lines: list[str]) -> list[str]:
        """Reassembles lines wrapped by PDF fixed-width formatting into complete sentences."""
        reassembled: list[str] = []
        current_item: list[str] = []

        for line in lines:
            if line.startswith(("-", "#")) or not current_item:
                if current_item:
                    reassembled.append(" ".join(current_item))
                    current_item = []
                current_item.append(line)
            else:
                current_item.append(line)

        if current_item:
            reassembled.append(" ".join(current_item))

        return reassembled

    def parse_pdf(
        self,
        file_path_or_bytes: str | Path | bytes | io.BytesIO,
        document_id: str = "pdf_doc",
        default_section: str = "General",
    ) -> list[DocumentChunk]:
        """Extract text and structure from PDF with clean section detection and metadata."""
        try:
            from pypdf import PdfReader
        except ImportError as exc:
            raise ImportError(
                "pypdf package is required for PDF parsing. Install with `uv add pypdf`"
            ) from exc

        if isinstance(file_path_or_bytes, (str, Path)):
            reader = PdfReader(str(file_path_or_bytes))
        elif isinstance(file_path_or_bytes, bytes):
            reader = PdfReader(io.BytesIO(file_path_or_bytes))
        else:
            reader = PdfReader(file_path_or_bytes)

        full_doc_lines: list[str] = []
        for page_num, page in enumerate(reader.pages, start=1):
            page_text = page.extract_text() or ""
            cleaned_page = self.clean_and_normalize(page_text)
            if not cleaned_page:
                continue

            raw_lines = [
                line_str.strip()
                for line_str in cleaned_page.splitlines()
                if line_str.strip()
            ]
            filtered_lines: list[str] = []
            slide_title = ""

            for line in raw_lines:
                if self._is_boilerplate_line(line):
                    continue
                if (
                    not slide_title
                    and not line.startswith("-")
                    and len(line.split()) <= 7
                ):
                    # Clean title e.g. "SQL vs NoSQL (2)" -> "SQL vs NoSQL"
                    clean_t = re.sub(r"\s*\(\d+\)$", "", line).strip()
                    slide_title = clean_t
                filtered_lines.append(line)

            if not filtered_lines:
                continue

            reassembled = self._reassemble_wrapped_lines(filtered_lines)
            section_header = slide_title if slide_title else f"Sezione {page_num}"
            full_doc_lines.append(f"\n## {section_header}\n" + "\n".join(reassembled))

        combined_text = "\n".join(full_doc_lines)
        return self.parse_markdown(
            text=combined_text,
            document_id=document_id,
            default_section=default_section,
        )

    def parse_file(
        self,
        file_path: str | Path,
        document_id: str | None = None,
    ) -> list[DocumentChunk]:
        """Auto-detect format and parse file (PDF, MD, TXT)."""
        path = Path(file_path)
        doc_id = document_id or path.stem

        if not path.exists():
            raise FileNotFoundError(f"Document file not found at: {path}")

        if path.suffix.lower() == ".pdf":
            return self.parse_pdf(path, document_id=doc_id)

        content = path.read_text(encoding="utf-8", errors="replace")
        return self.parse_markdown(content, document_id=doc_id)

    def parse_markdown(
        self,
        text: str,
        document_id: str = "doc_1",
        default_section: str = "General",
    ) -> list[DocumentChunk]:
        """Split text along semantic header boundaries (H1, H2, H3), tables, and paragraphs."""
        cleaned = self.clean_and_normalize(text)
        lines = cleaned.splitlines()
        chunks: list[DocumentChunk] = []

        current_section = default_section
        current_buffer: list[str] = []

        def flush_buffer():
            nonlocal current_buffer
            chunk_text = "\n".join(current_buffer).strip()
            if len(chunk_text) >= self.min_chunk_size or chunks == []:
                token_est = len(chunk_text.split())
                chunks.append(
                    DocumentChunk(
                        chunk_id=f"chk_{uuid.uuid4().hex[:8]}",
                        document_id=document_id,
                        section_title=current_section,
                        text=chunk_text,
                        token_count=token_est,
                    )
                )
            current_buffer = []

        header_pattern = re.compile(r"^(#{1,3})\s+(.+)$")

        for line in lines:
            header_match = header_pattern.match(line.strip())
            if header_match:
                if current_buffer:
                    flush_buffer()
                current_section = header_match.group(2).strip()
                current_buffer.append(line)
            else:
                current_buffer.append(line)
                combined = "\n".join(current_buffer)
                if len(combined.split()) >= self.target_chunk_size:
                    flush_buffer()

        if current_buffer:
            flush_buffer()

        return chunks
