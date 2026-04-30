"""Tests for ResultSelector.select_with_refinement (prompt content + happy path)."""

import json
from unittest.mock import MagicMock

from src.llm.result_selector import ResultSelector


def make_selector(mock_response: str):
    client = MagicMock()
    client.chat.return_value = mock_response
    return ResultSelector(client=client), client


def test_prompt_includes_original_query_and_refinement():
    response = json.dumps({
        "recommendations": [{"score_id": 1, "title": "t", "explanation": "e"}],
        "summary": "ok",
    })
    selector, client = make_selector(response)

    selector.select_with_refinement(
        original_query="easy bach",
        refinement="for a 6-year-old",
        previous_summary="three pieces",
        previous_recommendations=[
            {"score_id": 11, "title": "Invention 1", "explanation": "grade 4 fits", "rank": 1}
        ],
        search_results=[{"score_id": 99, "content": "fresh", "similarity": 0.9, "title": "x"}],
    )

    prompt = client.chat.call_args.kwargs["prompt"]
    assert "easy bach" in prompt
    assert "for a 6-year-old" in prompt
    assert "three pieces" in prompt
    assert "Invention 1" in prompt
    assert "grade 4 fits" in prompt
    # Refinement is now framed as adding a constraint, not diverging.
    assert "diverge" not in prompt.lower()
    assert "constraint" in prompt.lower()


def test_returns_selection_result_on_success():
    response = json.dumps({
        "recommendations": [
            {"score_id": 9, "title": "Notebook", "explanation": "Genuinely beginner."}
        ],
        "summary": "Easier picks.",
    })
    selector, _ = make_selector(response)

    result = selector.select_with_refinement(
        original_query="q", refinement="r", previous_summary="s",
        previous_recommendations=[{"score_id": 1, "title": "a", "explanation": "b"}],
        search_results=[{"score_id": 9, "content": "x", "similarity": 0.8, "title": "Notebook"}],
    )

    assert result.success is True
    assert len(result.recommendations) == 1
    assert result.recommendations[0].score_id == 9
