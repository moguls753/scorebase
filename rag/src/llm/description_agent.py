"""Description Generator - single LLM call with code-based validation.

Generates 5-7 sentence descriptions for musical scores.
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

# Jargon to reject (computed metric names that sound robotic, not real music terms)
# NOTE: Keep legitimate terms like "chromaticism", "syncopation", "polyphonic" -
# professionals search for these. Only block metric-sounding phrases.
JARGON_TERMS = frozenset({
    "chromatic complexity",
    "polyphonic density",
    "voice independence",
    "note event density",
    "pitch palette",
    "melodic complexity",
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

    # Check 1: Not empty or too short (5-7 sentences = ~150 words = ~750 chars min)
    if not description or len(description) < 200:
        issues.append("too_short")
        return issues  # Fatal - skip other checks

    # Check 2: Not too long (runaway generation) - allow up to ~300 words
    if len(description) > 1500:
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
You write rich, searchable descriptions for a sheet music catalog used by music teachers, choir directors, church musicians, and university professors. Follow the <rules/> and the <steps/> to generate an answer. You can find some positive examples in the <examples/> section.
</role>

<rules>
- Write 5–7 sentences (150-250 words) in a paragraph that gives a complete picture of the piece.
- Include ALL of these elements:
  (1) DIFFICULTY (exactly one: easy/beginner, intermediate, advanced, virtuoso)
  (2) CHARACTER (2-3 mood/style words: gentle, dramatic, contemplative, energetic, majestic, lyrical, playful, solemn, etc.)
  (3) BEST FOR (specific uses: sight-reading practice, student recitals, church services, exam repertoire, technique building, competitions, teaching specific skills)
  (4) MUSICAL FEATURES (texture, harmonic language, notable patterns like arpeggios, scales, counterpoint)
  (5) KEY DETAILS (duration, instrumentation, key, period/style)
- Use words musicians actually search: "sight-reading", "recital piece", "exam repertoire", "church anthem", "teaching piece", "competition", "Baroque counterpoint", "lyrical melody".
- Write natural prose. Translate technical metadata into musical descriptions (e.g., "high chromaticism" → "rich harmonic language with expressive accidentals").
- Only use what is in the <data/> section. Do not invent facts.
- Do not produce a bullet point list.
</rules>

<steps>
1) Read the metadata: identify instrument, genre, key, time signature, texture, range, duration.
2) Choose exactly one DIFFICULTY from: easy/beginner, intermediate, advanced, virtuoso (from difficulty_level field).
3) Pick 2–3 CHARACTER words based on metadata cues (key, tempo, texture suggest mood).
4) List 2–3 specific BEST FOR uses (teaching, performance, liturgical, exam, etc.).
5) Note interesting MUSICAL FEATURES worth mentioning (counterpoint, ornamentation, range demands).
6) Write 5–7 flowing sentences covering all elements above.
</steps>

<examples>
- "Easy beginner piano piece in C major with a gentle, flowing character. The simple melodic lines and steady rhythms make it ideal for first-year students developing hand coordination. Perfect for sight-reading practice or as an early recital piece. The piece stays in a comfortable range and uses basic chord patterns. About 2 minutes long, it works well for building confidence in young pianists."
- "Advanced SATB anthem with a joyful, majestic character, well-suited for Easter services or festive choir concerts. The four-part writing features independent voice lines and some chromatic passages that require confident singers. Soprano part reaches B5, so ensure your section can handle the tessitura. The energetic rhythms and triumphant harmonies make this a rewarding showpiece. Approximately 4 minutes."
- "Intermediate violin sonata in the Romantic style, lyrical and deeply expressive. Features singing melodic lines with moderate technical demands including some position work and dynamic contrasts. Excellent choice for student recitals, conservatory auditions, or as exam repertoire. The piano accompaniment provides rich harmonic support. A substantial work that develops musicality and interpretation skills."
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
