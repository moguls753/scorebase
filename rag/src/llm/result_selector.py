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
Your job is to pick the BEST matches and explain why each one fits the user's needs.
</role>

<rules>
- Return between 1 and 3 picks. Choose only candidates that genuinely fit the user's query. If only 1 or 2 fit, return only those — do not pad with weak alternatives.
- Each `explanation` is final user-facing copy. Write it as a polished recommendation, not as deliberation. Never include words like "Wait", "However", "I should pick instead", "Let me re-evaluate", "I note this is not", or refer to picks you considered and rejected.
- Each pick must reference a meaningfully distinct work — do not return three editions/versions of the same piece unless the user explicitly asked for editions.
- Focus each explanation on WHY this score fits: difficulty, style, instrumentation, duration, use case.
- Address the user directly ("This piece would work well for your student…").
- Use the `summary` field to acknowledge any limitations of the result set (e.g. "The catalog has only a few matches for this query"). Do not put limitations in an individual explanation.
- Use the `score_id` exactly as it appears in the search results. Do not invent or modify IDs.
- Write `summary` and every `explanation` in the same language as the user's query.
- Output valid JSON in the exact format specified.
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
    }}
  ],
  "summary": "<1 sentence summary, e.g. 'I found 3 beginner-friendly Bach pieces perfect for piano students.'>"
}}
</output_format>"""

    REFINEMENT_PROMPT_TEMPLATE = """<role>
You are a music librarian assistant for ScoreBase. The user previously got score
recommendations and has now refined their request. Pick BETTER matches from a fresh
candidate pool that satisfy both the original intent and the refinement.
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

The refinement adds a constraint to the original request. Picks must satisfy BOTH the
original intent (mood, character, style, instrument) AND the new constraint. Do not
abandon the original intent unless the refinement explicitly contradicts it.
</refinement>

<rules>
- Below are fresh candidates from a new vector search using the enriched query.
- Return between 1 and 3 picks. Choose only candidates that genuinely fit BOTH the original intent and the refinement. If only 1 or 2 fit, return only those — do not pad with weak alternatives.
- Each `explanation` is final user-facing copy. Write it as a polished recommendation, not as deliberation. Never include words like "Wait", "However", "I should pick instead", "Let me re-evaluate", "to strictly honor your refinement", or "I note this is not". Do not include picks you considered and rejected.
- You MAY briefly contrast with a prior pick if it adds clarity (e.g. "More accessible than the Op.10 set I suggested before"), but contrast is optional. Do not force it onto every pick.
- Use the `summary` to acknowledge the refinement and any limitations (e.g. "The catalog has only a few works that match both your original request and the refinement").
- Use the `score_id` exactly as it appears in the candidates. Do not invent or modify IDs.
- Write `summary` and every `explanation` in the same language as the user's refinement (or the original query if the refinement is too short to tell).
- Output valid JSON in the exact format specified below.
</rules>

<candidates>
{results_json}
</candidates>

<output_format>
{{
  "recommendations": [
    {{"score_id": <id>, "title": "<title>", "explanation": "<final user-facing reason>"}}
  ],
  "summary": "<1 sentence summary acknowledging the refinement>"
}}
</output_format>"""

    _JSON_RESPONSE_FORMAT: dict = {"type": "json_object"}
    _RETRY_HINT = (
        "\n\nYour previous response was not valid JSON. "
        "Output ONLY the JSON object specified above, with no surrounding text."
    )

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

    def _chat_for_json(self, prompt: str) -> tuple[str, dict | None]:
        """Call the LLM expecting a JSON object, with one retry on parse failure.

        Tries with response_format=json_object first (DeepSeek/OpenAI-compatible).
        If the client doesn't accept the kwarg, falls back to plain chat.
        Returns ``(raw_response, parsed_or_None)``.
        """
        try:
            response = self.client.chat(
                prompt=prompt,
                system_message=None,
                response_format=self._JSON_RESPONSE_FORMAT,
            )
        except TypeError:
            response = self.client.chat(prompt=prompt, system_message=None)

        parsed = self._parse_response(response)
        if isinstance(parsed, dict) and "recommendations" in parsed:
            return response, parsed

        # Retry once with explicit format hint
        logger.warning("First-pass JSON parse failed; retrying with hint")
        retry_prompt = prompt + self._RETRY_HINT
        try:
            response = self.client.chat(
                prompt=retry_prompt,
                system_message=None,
                response_format=self._JSON_RESPONSE_FORMAT,
            )
        except TypeError:
            response = self.client.chat(prompt=retry_prompt, system_message=None)

        parsed = self._parse_response(response)
        return response, parsed

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

            response, parsed = self._chat_for_json(prompt)

            if not isinstance(parsed, dict) or "recommendations" not in parsed:
                logger.warning(f"Failed to parse selection response: {response[:200]}")
                return SelectionResult(
                    recommendations=[],
                    summary="I found some matches but had trouble formatting the response.",
                    success=False,
                    error="Parse error"
                )

            valid_ids = {r.get("score_id") for r in search_results if r.get("score_id") is not None}
            recommendations = []
            for rec in parsed.get("recommendations", []):
                sid = rec.get("score_id")
                if sid not in valid_ids:
                    logger.warning(f"Dropping pick with non-candidate score_id={sid!r} for query: {query[:50]}")
                    continue
                recommendations.append(Recommendation(
                    score_id=sid,
                    title=rec.get("title") or "Untitled",
                    explanation=rec.get("explanation", ""),
                    rank=len(recommendations) + 1,
                ))
                if len(recommendations) >= num_recommendations:
                    break

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
            response, parsed = self._chat_for_json(prompt)

            if not isinstance(parsed, dict) or "recommendations" not in parsed:
                logger.warning(f"Failed to parse refinement response: {response[:200]}")
                return SelectionResult(
                    recommendations=[],
                    summary="I tried to refine but had trouble formatting the response.",
                    success=False,
                    error="Parse error",
                )

            valid_ids = {r.get("score_id") for r in search_results if r.get("score_id") is not None}
            recommendations = []
            for rec in parsed.get("recommendations", []):
                sid = rec.get("score_id")
                if sid not in valid_ids:
                    logger.warning(f"Dropping refinement pick with non-candidate score_id={sid!r}")
                    continue
                recommendations.append(Recommendation(
                    score_id=sid,
                    title=rec.get("title") or "Untitled",
                    explanation=rec.get("explanation", ""),
                    rank=len(recommendations) + 1,
                ))
                if len(recommendations) >= num_recommendations:
                    break

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
