"""Tests for ResultSelector.select() defenses."""

import json
from unittest.mock import MagicMock

from src.llm.result_selector import ResultSelector


def make_selector(mock_response: str):
    client = MagicMock()
    client.chat.return_value = mock_response
    return ResultSelector(client=client), client


def test_drops_picks_with_unknown_score_ids():
    response = json.dumps({
        "recommendations": [
            {"score_id": 9999, "title": "Phantom", "explanation": "from outside the pool"},
            {"score_id": 42,   "title": "Real",    "explanation": "from the pool"},
        ],
        "summary": "ok",
    })
    selector, _ = make_selector(response)

    result = selector.select(
        query="anything",
        search_results=[{"score_id": 42, "content": "x", "similarity": 0.9, "title": "Real"}],
    )

    assert result.success is True
    assert [r.score_id for r in result.recommendations] == [42]


def test_returns_fewer_than_three_picks_when_llm_does():
    response = json.dumps({
        "recommendations": [
            {"score_id": 1, "title": "One", "explanation": "the only fit"},
        ],
        "summary": "Only one good match for this query.",
    })
    selector, _ = make_selector(response)

    result = selector.select(
        query="niche query",
        search_results=[
            {"score_id": 1, "content": "fitting", "similarity": 0.9, "title": "One"},
            {"score_id": 2, "content": "off-topic", "similarity": 0.5, "title": "Two"},
        ],
    )

    assert result.success is True
    assert len(result.recommendations) == 1
    assert result.recommendations[0].rank == 1


def test_retries_once_when_initial_response_is_unparseable():
    client = MagicMock()
    client.chat.side_effect = [
        "this is not JSON at all",
        json.dumps({
            "recommendations": [{"score_id": 7, "title": "Fixed", "explanation": "ok"}],
            "summary": "Recovered after retry.",
        }),
    ]
    selector = ResultSelector(client=client)

    result = selector.select(
        query="q",
        search_results=[{"score_id": 7, "content": "c", "similarity": 0.8, "title": "t"}],
    )

    assert result.success is True
    assert client.chat.call_count == 2
    assert result.recommendations[0].score_id == 7


def test_retries_when_first_response_is_empty():
    client = MagicMock()
    client.chat.side_effect = [
        "",  # DeepSeek empty-content path
        json.dumps({
            "recommendations": [{"score_id": 5, "title": "Recovered", "explanation": "ok"}],
            "summary": "Recovered after empty first response.",
        }),
    ]
    selector = ResultSelector(client=client)

    result = selector.select(
        query="q",
        search_results=[{"score_id": 5, "content": "c", "similarity": 0.8, "title": "t"}],
    )

    assert result.success is True
    assert client.chat.call_count == 2
    assert result.recommendations[0].score_id == 5


def test_returns_parse_error_when_both_attempts_fail():
    client = MagicMock()
    client.chat.return_value = "still not JSON"
    selector = ResultSelector(client=client)

    result = selector.select(
        query="q",
        search_results=[{"score_id": 1, "content": "c", "similarity": 0.8, "title": "t"}],
    )

    assert result.success is False
    assert result.error == "Parse error"
    assert client.chat.call_count == 2


def test_falls_back_to_plain_chat_if_response_format_unsupported():
    client = MagicMock()
    client.chat.side_effect = [
        TypeError("unexpected keyword argument 'response_format'"),
        json.dumps({
            "recommendations": [{"score_id": 1, "title": "x", "explanation": "y"}],
            "summary": "s",
        }),
    ]
    selector = ResultSelector(client=client)

    result = selector.select(
        query="q",
        search_results=[{"score_id": 1, "content": "c", "similarity": 0.8, "title": "t"}],
    )

    assert result.success is True
    second_call_kwargs = client.chat.call_args_list[1].kwargs
    assert "response_format" not in second_call_kwargs


def test_passes_response_format_when_supported():
    client = MagicMock()
    client.chat.return_value = json.dumps({
        "recommendations": [{"score_id": 1, "title": "x", "explanation": "y"}],
        "summary": "s",
    })
    selector = ResultSelector(client=client)

    selector.select(
        query="q",
        search_results=[{"score_id": 1, "content": "c", "similarity": 0.8, "title": "t"}],
    )

    kwargs = client.chat.call_args.kwargs
    assert kwargs.get("response_format") == {"type": "json_object"}
