"""Result Selector - LLM-powered reranking and explanation.

Takes vector search results and user query, picks the best matches
with conversational explanations.
"""

import json
import logging
from dataclasses import dataclass

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

    REFINEMENT_PROMPT_TEMPLATE = """<role>
You are a music librarian assistant for ScoreBase. The user previously got 3 score
recommendations and has now refined their request. Pick 3 BETTER matches from a fresh
candidate pool that fit the refinement.
</role>

<previous_turn>
The user originally searched: {original_query}

You previously responded with this summary:
"{previous_summary}"

And selected these scores with these explanations:
{previous_picks}
</previous_turn>

<refinement>
The user has now refined: "{refinement}"

The refinement tells you which dimension of your previous picks was wrong (difficulty,
instrumentation, period, style, length, etc.). Use it as a target to *diverge from*
your previous reasoning — not to reinforce it.
</refinement>

<rules>
- Below are 15 fresh candidates from a new vector search using the enriched query.
- Pick the 3 BEST matches that fit the original intent PLUS the refinement.
- In each new explanation, briefly contrast with what you offered before so the user
  sees you understood their correction. For example:
  "Unlike the grade-4 Bach I suggested earlier, this Notebook minuet is genuinely beginner..."
- Output valid JSON in the exact format specified below.
</rules>

<candidates>
{results_json}
</candidates>

<output_format>
{{
  "recommendations": [
    {{"score_id": <id>, "title": "<title>", "explanation": "<contrast-aware explanation>"}},
    {{"score_id": <id>, "title": "<title>", "explanation": "<…>"}},
    {{"score_id": <id>, "title": "<title>", "explanation": "<…>"}}
  ],
  "summary": "<1 sentence summary acknowledging the refinement>"
}}
</output_format>"""

    def __init__(self, client=None):
        """Initialize with an LLM client; default uses LLM_PROVIDER env var (default 'deepseek')."""
        if client is None:
            from .factory import default_client
            client = default_client()
        self.client = client

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

    def select_with_refinement(
        self,
        original_query: str,
        refinement: str,
        previous_summary: str,
        previous_recommendations: list[dict],
        search_results: list[dict],
        num_recommendations: int = 3,
    ) -> SelectionResult:
        """Select best matches given a previous turn and a refinement."""
        if not search_results:
            return SelectionResult(
                recommendations=[],
                summary="No fresh candidates found for the refinement.",
                success=True,
            )

        previous_picks = "\n".join(
            f'{i+1}. score_id={r["score_id"]}, title="{r["title"]}": "{r["explanation"]}"'
            for i, r in enumerate(previous_recommendations)
        )

        formatted = []
        for i, r in enumerate(search_results, 1):
            formatted.append({
                "rank": i,
                "score_id": r.get("score_id"),
                "title": r.get("title", "Untitled"),
                "description": r.get("content", ""),
                "similarity": round(r.get("similarity", 0), 3),
            })
        results_json = json.dumps(formatted, indent=2)

        try:
            prompt = self.REFINEMENT_PROMPT_TEMPLATE.format(
                original_query=original_query,
                previous_summary=previous_summary,
                previous_picks=previous_picks,
                refinement=refinement,
                results_json=results_json,
            )
            response = self.client.chat(prompt=prompt, system_message=None)
            parsed = self._parse_response(response)

            if not parsed or "recommendations" not in parsed:
                logger.warning(f"Failed to parse refinement response: {response[:200]}")
                return SelectionResult(
                    recommendations=[],
                    summary="I tried to refine but had trouble formatting the response.",
                    success=False,
                    error="Parse error",
                )

            recommendations = []
            for i, rec in enumerate(parsed.get("recommendations", [])[:num_recommendations], 1):
                recommendations.append(Recommendation(
                    score_id=rec.get("score_id", 0),
                    title=rec.get("title", "Untitled"),
                    explanation=rec.get("explanation", ""),
                    rank=i,
                ))

            return SelectionResult(
                recommendations=recommendations,
                summary=parsed.get("summary", "Refined recommendations."),
                success=True,
            )
        except Exception as e:
            logger.error(f"Refinement selection failed: {e}")
            return SelectionResult(
                recommendations=[],
                summary="Sorry, the refinement encountered an error.",
                success=False,
                error=str(e)[:200],
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
