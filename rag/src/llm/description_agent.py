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

    WRITER_SYSTEM = """You are a music librarian writing brief descriptions for a sheet music search engine.
Write 2-3 natural sentences that help music teachers find appropriate pieces.

Rules:
- Only describe what's in the metadata (don't invent information)
- Include explicit difficulty words: beginner/easy, intermediate, advanced, or virtuoso
- Write naturally for search queries like "easy Bach for piano" or "SATB Easter piece"

Some metadata fields may be missing - that's fine, just describe what's available."""

    CRITIC_SYSTEM = """You validate music score descriptions for accuracy and searchability.

Check these 3 things:
1. ACCURATE: Does description only mention what's in the metadata? (no invented info)
2. DIFFICULTY: Does it use the correct difficulty level word for the expected level?
3. SEARCHABLE: Would teachers find this with queries like "easy Bach for piano"?

Respond JSON only: {"is_valid": true/false, "feedback": "specific issue or 'Good'"}"""

    def __init__(self):
        """Initialize with Groq client."""
        self.client = GroqClient()

    def _format_metadata(self, metadata: ScoreMetadata) -> str:
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
        metadata_str = self._format_metadata(metadata)
        difficulty_words = ", ".join(DifficultyMapping.get_words(expected_level)[:3])

        feedback: str | None = None
        description: str = ""

        for attempt in range(1, self.MAX_RETRIES + 1):
            try:
                # === WRITER ===
                writer_prompt = f"""Write 2-3 sentences describing this score.

Available metadata:
{metadata_str}

Required difficulty level: {expected_level}
(Use words like: {difficulty_words})"""

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

Metadata provided:
{metadata_str}

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
