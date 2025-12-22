"""Description Generator - single LLM call with code-based validation.

Generates 3-5 sentence descriptions for musical scores.
Simple garbage detection validates outputs without LLM critic overhead.
"""

import json
import logging
from dataclasses import dataclass, field
from typing import Any, Callable

from .groq_client import GroqClient
from .lmstudio_client import LMStudioClient
from .metadata_transformer import transform_metadata

logger = logging.getLogger(__name__)

# Difficulty terms that should appear in valid descriptions
DIFFICULTY_TERMS = frozenset({
    "easy", "beginner", "simple",
    "intermediate", "moderate",
    "advanced", "challenging",
    "virtuoso", "demanding", "expert",
})

# Jargon to reject (computed metric names, not real music terms)
JARGON_TERMS = frozenset({
    "chromatic complexity",
    "polyphonic density",
    "voice independence",
})


@dataclass
class GenerationResult:
    """Result of description generation."""

    score_id: int
    description: str
    success: bool
    difficulty_level: str
    validation_issues: list[str] = field(default_factory=list)
    error: str | None = None


def validate_description(description: str) -> list[str]:
    """Code-based garbage checks for generated descriptions.

    Returns list of issues found (empty = valid).
    """
    issues = []

    # Check 1: Not empty or too short
    if not description or len(description) < 50:
        issues.append("too_short")
        return issues  # Fatal - skip other checks

    # Check 2: Not too long (runaway generation)
    if len(description) > 800:
        issues.append("too_long")

    # Check 3: Has a difficulty term
    desc_lower = description.lower()
    if not any(term in desc_lower for term in DIFFICULTY_TERMS):
        issues.append("missing_difficulty")

    # Check 4: No jargon
    for term in JARGON_TERMS:
        if term in desc_lower:
            issues.append(f"jargon:{term}")
            break  # One jargon issue is enough

    # Check 5: Looks like prose (not a bullet list)
    if description.count("-") > 3 and description.count(".") < 2:
        issues.append("bullet_list")

    return issues


class DescriptionGenerator:
    """Generates searchable descriptions with code-based validation."""

    PROMPT_TEMPLATE = """<role>
You write brief, searchable descriptions for a sheet music catalog used by music teachers, choir directors, and church musicians. Follow the <rules/> and the <steps/> to generate an answer. You can find some positive examples in the <examples/> section.
</role>

<rules>
- Write 3–5 sentences in a paragraph of text that describes this piece of music so that a reader can get an accurate impression of the piece of music.
- Include: (1) DIFFICULTY (exactly one: easy/beginner, intermediate, advanced, virtuoso), (2) CHARACTER (mood), (3) BEST FOR (who/when), (4) KEY DETAILS (duration, voicing/instrumentation, period/style if notable).
- Use words teachers search (e.g., "easy piano piece", "peaceful choir anthem", "dramatic recital showpiece") and avoid jargon (no "ambitus", "chromatic complexity").
- Write natural prose. Do NOT copy metadata field names like "monophonic texture", "stepwise motion", "high chromaticism", "medium syncopation". Translate these into plain descriptions.
- Only use what is in the <data/> section to describe the piece of music.
- Avoid extra claims beyond metadata.
- Do not produce a bullet point list.
- Generate the output in the required <output_format/>
</rules>

<steps>
1) Read the metadata and identify instrumentation/voicing, genre/style, key/time, texture, range, page count, and any duration if present.
2) Choose exactly one DIFFICULTY label from: easy/beginner, intermediate, advanced, virtuoso (based on the difficulty_level field).
3) Pick 1–2 CHARACTER words that match the piece based on metadata cues.
4) Decide BEST FOR (who/when) using common teacher terms, without inventing specifics.
5) Write 3–5 sentences that naturally include DIFFICULTY, CHARACTER, BEST FOR, and KEY DETAILS, using searchable phrases.
6) Final check if your response matches the requirements, see <rules/>.
</steps>

<examples>
- "Easy beginner piano piece in C major, gentle and flowing. Perfect for first-year students or sight-reading practice. About 2 minutes."
- "Advanced SATB anthem, joyful and energetic. Great for Easter or festive concerts. Soprano reaches B5. Around 4 minutes."
- "Intermediate violin sonata, lyrical and expressive. Suitable for student recitals or auditions. Romantic period style."
</examples>

<data>
{metadata_json}
</data>

<output_format>
{{"description": "..."}}
</output_format>"""

    def __init__(self, client: GroqClient | LMStudioClient | None = None):
        """Initialize with LLM client.

        Args:
            client: LLM client instance. Defaults to GroqClient if None.
        """
        self.client = client or GroqClient()

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

    def generate(self, raw_metadata: dict[str, Any]) -> GenerationResult:
        """Generate a description for a score.

        Single LLM call with code-based validation.

        Args:
            raw_metadata: Raw score metadata dict from database

        Returns:
            GenerationResult with description and validation status
        """
        score_id = raw_metadata.get("id", 0)

        # Transform to prompt-ready format
        transformed = transform_metadata(raw_metadata)
        metadata_json = json.dumps(transformed, indent=2, default=str)

        # Get difficulty from transformed data
        difficulty_words = transformed.get("difficulty_level", ["intermediate"])
        difficulty_level = difficulty_words[0] if difficulty_words else "intermediate"

        try:
            # Single LLM call
            prompt = self.PROMPT_TEMPLATE.format(metadata_json=metadata_json)
            response = self.client.chat(prompt=prompt, system_message=None)

            # Parse response
            parsed = self._parse_json(response)
            description = parsed.get("description", "") if parsed else response
            description = description.strip() if description else ""

            # Validate with code checks
            issues = validate_description(description)

            if issues:
                logger.warning(f"Score {score_id} validation: {issues}\n  Text: {description}")
            else:
                logger.info(f"Score {score_id} generated:\n  {description}")

            return GenerationResult(
                score_id=score_id,
                description=description,
                success=len(issues) == 0,
                difficulty_level=difficulty_level,
                validation_issues=issues,
            )

        except Exception as e:
            logger.error(f"Score {score_id} failed: {e}")
            return GenerationResult(
                score_id=score_id,
                description="",
                success=False,
                difficulty_level=difficulty_level,
                error=str(e)[:200],
            )

    def generate_batch(
        self,
        scores: list[dict],
        on_progress: Callable[[int, int, GenerationResult], None] | None = None,
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
            result = self.generate(score_dict)
            results.append(result)

            # Progress logging
            status = "✓" if result.success else "✗"
            title = (score_dict.get("title") or "Untitled")[:40]
            logger.info(f"[{i}/{total}] {status} Score {result.score_id}: {title}")

            if on_progress:
                on_progress(i, total, result)

        return results
