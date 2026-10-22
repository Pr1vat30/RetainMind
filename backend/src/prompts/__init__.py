"""System instructions and prompts for the Oral Examiner Study Assistant."""

from .evaluator import EVALUATOR_SYSTEM_INSTRUCTIONS
from .examiner import (
    ORAL_EXAMINER_SYSTEM_INSTRUCTIONS,
    build_examiner_turn_prompt,
)

__all__ = [
    "EVALUATOR_SYSTEM_INSTRUCTIONS",
    "ORAL_EXAMINER_SYSTEM_INSTRUCTIONS",
    "build_examiner_turn_prompt",
]
