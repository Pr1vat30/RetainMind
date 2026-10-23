from __future__ import annotations

import argparse
import asyncio
import logging
from pathlib import Path

from config import config
from planning import ExaminationPlanner
from rag import create_graph_store, create_vector_store
from rag.ingestion import IngestionPipeline

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger("ingest")


async def main() -> None:
    parser = argparse.ArgumentParser(
        description="Ingest course materials (PDF, Markdown, TXT) and generate an Examination Plan."
    )
    parser.add_argument(
        "file_path",
        type=str,
        help="Path to the document (e.g. materials/physics.pdf, notes.md)",
    )
    parser.add_argument(
        "--title",
        type=str,
        default="Esame Orale Universitario",
        help="Title of the examination",
    )
    parser.add_argument(
        "--plan-out",
        type=str,
        default="examination_plan.json",
        help="Output path for the generated examination plan JSON",
    )
    parser.add_argument(
        "--model",
        type=str,
        default=config.plan_generation_model,
        help=f"LLM model name for concept extraction (default: {config.plan_generation_model})",
    )

    args = parser.parse_args()
    doc_path = Path(args.file_path)

    if not doc_path.exists():
        logger.error("File not found: %s", doc_path)
        return

    logger.info("Starting ingestion of: %s", doc_path)
    vstore = create_vector_store()
    gstore = create_graph_store()
    pipeline = IngestionPipeline(vector_store=vstore, graph_store=gstore)

    # Ingest document
    result = await pipeline.ingest_file(
        str(doc_path),
        llm_model=args.model,
    )
    logger.info(
        "Ingestion completed: %d chunks indexed, %d concepts identified.",
        result["chunks_count"],
        result["concepts_count"],
    )

    # Generate Examination Plan
    planner = ExaminationPlanner(graph_store=gstore, vector_store=vstore)
    plan = await planner.generate_plan(
        document_id=result["document_id"],
        title=args.title,
    )

    # Save plan
    out_path = Path(args.plan_out)
    ExaminationPlanner.save_plan_to_file(plan, out_path)
    logger.info("Examination Plan saved to: %s", out_path)
    logger.info("Topological concept order: %s", plan.concept_order)
    logger.info("You can now run: uv run python src/agent.py dev")


if __name__ == "__main__":
    asyncio.run(main())
