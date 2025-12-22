"""Result Selector - LLM-powered reranking and explanation.

Takes vector search results and user query, picks the best matches
with conversational explanations.
"""

import json
import logging
from dataclasses import dataclass

from .groq_client import GroqClient

logger = logging.getLogger(__name__)


@dataclass
class Recommendation:
    """A single score recommendation."""
    score_id: int
    title: str
    explanation: str
    rank: int


@dataclass
class SelectionResult:
    """Result of the selection process."""
    recommendations: list[Recommendation]
    summary: str
    success: bool
    error: str | None = None


class ResultSelector:
    """Selects and explains the best matches from vector search results."""

    PROMPT_TEMPLATE = """<role>
You are a helpful music librarian assistant for ScoreBase, a sheet music catalog.
A user is searching for sheet music, and you have {num_results} potential matches from the database.
Your job is to pick the 3 BEST matches and explain why each one fits the user's needs.
</role>

<rules>
- Select exactly 3 scores that best match the user's query
- If fewer than 3 are good matches, still pick the 3 closest (explain limitations)
- Write a brief, friendly explanation for each (1-2 sentences)
- Focus on WHY it matches: difficulty, style, instrumentation, duration, use case
- Address the user directly ("This piece would work well for your student...")
- Be honest if a match is imperfect ("While not exactly beginner-level, this...")
- Write a 1-sentence summary at the end
- Output valid JSON in the exact format specified
</rules>

<user_query>
{user_query}
</user_query>

<search_results>
{results_json}
</search_results>

<output_format>
{{
  "recommendations": [
    {{
      "score_id": <id>,
      "title": "<title from results>",
      "explanation": "<why this matches the query, 1-2 sentences>"
    }},
    {{
      "score_id": <id>,
      "title": "<title>",
      "explanation": "<explanation>"
    }},
    {{
      "score_id": <id>,
      "title": "<title>",
      "explanation": "<explanation>"
    }}
  ],
  "summary": "<1 sentence summary, e.g. 'I found 3 beginner-friendly Bach pieces perfect for piano students.'>"
}}
</output_format>"""

    def __init__(self, client: GroqClient | None = None):
        """Initialize with LLM client.

        Args:
            client: LLM client instance. Defaults to GroqClient if None.
        """
        self.client = client or GroqClient()

    def _parse_response(self, response: str) -> dict | None:
        """Extract JSON from LLM response."""
        if not response:
            return None

        # Try direct parse
        try:
            return json.loads(response)
        except json.JSONDecodeError:
            pass

        # Find JSON object in text
        start = response.find("{")
        end = response.rfind("}") + 1
        if start != -1 and end > start:
            try:
                return json.loads(response[start:end])
            except json.JSONDecodeError:
                pass

        return None

    def select(
        self,
        query: str,
        search_results: list[dict],
        num_recommendations: int = 3
    ) -> SelectionResult:
        """Select best matches from search results.

        Args:
            query: User's original search query
            search_results: List of dicts with score_id, content, similarity, title
            num_recommendations: Number of recommendations (default 3)

        Returns:
            SelectionResult with recommendations and summary
        """
        if not search_results:
            return SelectionResult(
                recommendations=[],
                summary="No scores found matching your search.",
                success=True
            )

        # Format results for prompt (include only what LLM needs)
        formatted_results = []
        for i, r in enumerate(search_results, 1):
            formatted_results.append({
                "rank": i,
                "score_id": r.get("score_id"),
                "title": r.get("title", "Untitled"),
                "description": r.get("content", ""),
                "similarity": round(r.get("similarity", 0), 3)
            })

        results_json = json.dumps(formatted_results, indent=2)

        try:
            prompt = self.PROMPT_TEMPLATE.format(
                num_results=len(search_results),
                user_query=query,
                results_json=results_json
            )

            response = self.client.chat(prompt=prompt, system_message=None)
            parsed = self._parse_response(response)

            if not parsed or "recommendations" not in parsed:
                logger.warning(f"Failed to parse selection response: {response[:200]}")
                return SelectionResult(
                    recommendations=[],
                    summary="I found some matches but had trouble formatting the response.",
                    success=False,
                    error="Parse error"
                )

            # Build recommendation objects
            recommendations = []
            for i, rec in enumerate(parsed.get("recommendations", [])[:num_recommendations], 1):
                recommendations.append(Recommendation(
                    score_id=rec.get("score_id", 0),
                    title=rec.get("title", "Untitled"),
                    explanation=rec.get("explanation", ""),
                    rank=i
                ))

            summary = parsed.get("summary", "Here are my recommendations.")

            logger.info(f"Selected {len(recommendations)} recommendations for query: {query[:50]}")

            return SelectionResult(
                recommendations=recommendations,
                summary=summary,
                success=True
            )

        except Exception as e:
            logger.error(f"Selection failed: {e}")
            return SelectionResult(
                recommendations=[],
                summary="Sorry, I encountered an error while selecting recommendations.",
                success=False,
                error=str(e)[:200]
            )

    def format_response(self, result: SelectionResult) -> str:
        """Format selection result as readable text.

        Args:
            result: SelectionResult from select()

        Returns:
            Human-readable string
        """
        if not result.success or not result.recommendations:
            return result.summary

        lines = [result.summary, ""]

        for rec in result.recommendations:
            lines.append(f"**{rec.rank}. {rec.title}** (ID: {rec.score_id})")
            lines.append(f"   {rec.explanation}")
            lines.append("")

        return "\n".join(lines)
