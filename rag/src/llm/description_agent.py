"""Description Generator Agent with LLM Critic.

Generates 2-3 sentence descriptions for musical scores,
validated by an LLM critic for accuracy and searchability.

Flow:
1. Writer generates 2-3 sentences from available metadata
2. Critic checks: accurate? correct difficulty? searchable?
3. If invalid, writer regenerates with critic feedback
4. Max 3 attempts
"""

import json
import logging
import traceback
from dataclasses import dataclass
from typing import Callable

from .schemas import ScoreMetadata, DifficultyMapping
from .groq_client import GroqClient

logger = logging.getLogger(__name__)


@dataclass
class GenerationResult:
    """Result of description generation."""

    score_id: int
    description: str
    success: bool
    attempts: int
    difficulty_level: str
    critic_feedback: str | None = None
    error: str | None = None


class DescriptionGeneratorAgent:
    """Generates searchable descriptions with LLM validation."""

    MAX_RETRIES = 3

    WRITER_SYSTEM = """You write brief, searchable descriptions for a sheet music catalog used by music teachers, choir directors, and church musicians.

Write 2-3 sentences that help users find this piece. Include:
1. DIFFICULTY: Use exactly one: easy/beginner, intermediate, advanced, or virtuoso
2. CHARACTER: The mood (gentle, dramatic, lively, peaceful, joyful, melancholic, etc.)
3. BEST FOR: Who should play this or when (teaching, recital, church service, competition, sight-reading, weddings, funerals, etc.)
4. KEY DETAILS: Duration, voicing (SATB, piano, etc.), period/style if notable

Use words teachers search: "easy piano piece", "peaceful choir anthem", "dramatic recital showpiece". Avoid jargon (no "ambitus", "chromatic complexity").

Examples:
- "Easy beginner piano piece in C major, gentle and flowing. Perfect for first-year students or sight-reading practice. About 2 minutes."
- "Advanced SATB anthem, joyful and energetic. Great for Easter or festive concerts. Soprano reaches B5. Around 4 minutes."
- "Intermediate violin sonata, lyrical and expressive. Suitable for student recitals or auditions. Romantic period style."

Only describe what's in the metadata."""

    CRITIC_SYSTEM = """Check if a music score description is searchable.

Verify:
1. Has ONE difficulty: easy/beginner, intermediate, advanced, or virtuoso
2. Has mood words (gentle, dramatic, peaceful, lively, etc.)
3. Mentions audience or occasion (teaching, recital, church, etc.)
4. Plain language, no jargon

JSON only: {"is_valid": true/false, "feedback": "issue or 'Good'"}"""

    def __init__(self):
        """Initialize with Groq client."""
        self.client = GroqClient()

    def _format_metadata(self, metadata: ScoreMetadata, difficulty_words: list[str]) -> str:
        """Format metadata for prompt, only non-null fields."""
        fields = metadata.get_non_null_fields()

        # Skip internal/complex fields that don't help description
        skip = {
            "id", "extraction_status", "extracted_at", "music21_version",
            "musicxml_source", "extraction_error", "key_correlations",
            "chord_symbols", "interval_distribution", "rhythm_distribution",
            "pitch_range_per_part", "voice_ranges", "extracted_lyrics",
            "key_confidence", "accidental_count", "unique_pitches",
            "note_count", "note_density", "measure_count",
            "polyphonic_density", "voice_independence", "stepwise_motion_ratio",
            "harmonic_rhythm", "sections_count", "repeats_count",
            "syllable_count", "clefs_used", "cadence_types",
            # complexity is unreliable (PDMX data) - use melodic_complexity instead
            "complexity",
        }

        clean = {k: v for k, v in fields.items() if k not in skip}
        # Add computed difficulty at the top
        clean = {"difficulty_level": difficulty_words, **clean}
        return json.dumps(clean, indent=2, default=str)

    def _parse_json(self, text: str) -> dict | None:
        """Extract JSON from LLM response."""
        if not text:
            return None

        # Try direct parse
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            pass

        # Find JSON object in text
        start = text.find("{")
        end = text.rfind("}") + 1
        if start != -1 and end > start:
            try:
                return json.loads(text[start:end])
            except json.JSONDecodeError:
                pass

        return None

    def generate(self, metadata: ScoreMetadata) -> GenerationResult:
        """Generate and validate a description for a score.

        Args:
            metadata: Score metadata from database

        Returns:
            GenerationResult with description and status
        """
        expected_level = DifficultyMapping.get_level(metadata.melodic_complexity)
        difficulty_words = DifficultyMapping.get_words(expected_level)[:3]
        metadata_str = self._format_metadata(metadata, difficulty_words)

        feedback: str | None = None
        description: str = ""

        for attempt in range(1, self.MAX_RETRIES + 1):
            try:
                # === WRITER ===
                writer_prompt = metadata_str

                if feedback:
                    writer_prompt += f"\n\nFix this issue: {feedback}"

                description = self.client.chat(
                    prompt=writer_prompt,
                    system_message=self.WRITER_SYSTEM,
                )

                if not description:
                    feedback = "Empty response, please try again"
                    logger.warning(f"  Attempt {attempt}: Empty response from writer")
                    continue

                description = description.strip()
                logger.info(f"  Attempt {attempt} writer: {description[:150]}...")

                # === CRITIC ===
                critic_prompt = f"""Check this description.

Expected difficulty: {expected_level}

Description:
\"\"\"{description}\"\"\"

Return: {{"is_valid": true/false, "feedback": "..."}}"""

                critic_response = self.client.chat(
                    prompt=critic_prompt,
                    system_message=self.CRITIC_SYSTEM,
                )

                result = self._parse_json(critic_response)
                logger.info(f"  Attempt {attempt} critic: {result}")

                if result and result.get("is_valid"):
                    return GenerationResult(
                        score_id=metadata.id,
                        description=description,
                        success=True,
                        attempts=attempt,
                        difficulty_level=expected_level,
                        critic_feedback=result.get("feedback"),
                    )

                # Get feedback for retry
                feedback = result.get("feedback") if result else "Invalid critic response, try with correct difficulty"
                logger.warning(f"  Attempt {attempt} rejected: {feedback}")

            except (RuntimeError, ValueError) as e:
                # API/model errors - retry with feedback
                logger.warning(f"Score {metadata.id} attempt {attempt}: {e}")
                feedback = f"Error: {str(e)[:100]}"
                continue
            except Exception as e:
                # Unexpected error - log full traceback and fail fast
                logger.error(f"Score {metadata.id} unexpected error: {e}\n{traceback.format_exc()}")
                return GenerationResult(
                    score_id=metadata.id,
                    description="",
                    success=False,
                    attempts=attempt,
                    difficulty_level=expected_level,
                    error=f"Unexpected error: {str(e)[:200]}",
                )

        # Max attempts reached - return best effort
        return GenerationResult(
            score_id=metadata.id,
            description=description or "(generation failed)",
            success=False,
            attempts=self.MAX_RETRIES,
            difficulty_level=expected_level,
            critic_feedback=feedback,
        )

    def generate_batch(
        self,
        scores: list[dict],
        on_progress: Callable[[int, int, "GenerationResult"], None] | None = None,
    ) -> list[GenerationResult]:
        """Generate descriptions for multiple scores.

        Args:
            scores: List of score dicts from database
            on_progress: Optional callback(index, total, result)

        Returns:
            List of GenerationResult objects
        """
        results = []
        total = len(scores)

        for i, score_dict in enumerate(scores, 1):
            try:
                metadata = ScoreMetadata(**score_dict)
            except Exception as e:
                # Handle malformed score data
                results.append(GenerationResult(
                    score_id=score_dict.get("id", 0),
                    description="",
                    success=False,
                    attempts=0,
                    difficulty_level="intermediate",
                    error=f"Invalid metadata: {e}",
                ))
                continue

            result = self.generate(metadata)
            results.append(result)

            # Progress logging
            status = "✓" if result.success else "✗"
            title = (metadata.title or "Untitled")[:40]
            print(f"[{i}/{total}] {status} Score {metadata.id}: {title} ({result.attempts} attempts)")

            if on_progress:
                on_progress(i, total, result)

        return results
