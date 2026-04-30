"""Endpoint tests for POST /smart-refine."""

import pytest
from fastapi.testclient import TestClient

from src.api.main import app


@pytest.fixture
def client():
    return TestClient(app)


@pytest.fixture
def valid_body():
    return {
        "original_query": "easy bach for piano",
        "refinement": "for a 6-year-old",
        "previous_summary": "Three Bach pieces.",
        "previous_recommendations": [
            {"score_id": 1, "title": "Invention 1", "explanation": "Grade 4 fits.", "rank": 1},
            {"score_id": 2, "title": "Minuet",       "explanation": "Approachable.",  "rank": 2},
            {"score_id": 3, "title": "Prelude",      "explanation": "Beautiful.",     "rank": 3},
        ],
    }


@pytest.fixture
def stub_pipeline(monkeypatch):
    def fake_smart_refine(**kwargs):
        return {
            "recommendations": [
                {"score_id": 9, "title": "Notebook", "explanation": "Genuinely beginner.", "rank": 1}
            ],
            "summary": "Three easier pieces.",
            "success": True,
        }

    from src.pipeline import search as search_module
    monkeypatch.setattr(search_module, "smart_refine", fake_smart_refine, raising=False)


def test_happy_path(client, valid_body, stub_pipeline, monkeypatch):
    monkeypatch.setenv("DEEPSEEK_API_KEY", "test")
    response = client.post("/smart-refine", json=valid_body)
    assert response.status_code == 200
    data = response.json()
    assert set(data.keys()) >= {"query", "recommendations", "summary", "success"}
    assert data["success"] is True


@pytest.mark.parametrize("missing", [
    "original_query", "refinement", "previous_summary", "previous_recommendations"
])
def test_missing_required_field(client, valid_body, missing):
    body = {k: v for k, v in valid_body.items() if k != missing}
    response = client.post("/smart-refine", json=body)
    assert response.status_code == 422


def test_original_query_too_long(client, valid_body):
    valid_body["original_query"] = "x" * 501
    response = client.post("/smart-refine", json=valid_body)
    assert response.status_code == 422


def test_refinement_too_long(client, valid_body):
    valid_body["refinement"] = "x" * 301
    response = client.post("/smart-refine", json=valid_body)
    assert response.status_code == 422


def test_summary_too_long(client, valid_body):
    valid_body["previous_summary"] = "x" * 1001
    response = client.post("/smart-refine", json=valid_body)
    assert response.status_code == 422


def test_explanation_too_long(client, valid_body):
    valid_body["previous_recommendations"][0]["explanation"] = "x" * 501
    response = client.post("/smart-refine", json=valid_body)
    assert response.status_code == 422


def test_too_many_recommendations(client, valid_body):
    valid_body["previous_recommendations"] = [
        {"score_id": i, "title": "t", "explanation": "e", "rank": i} for i in range(6)
    ]
    response = client.post("/smart-refine", json=valid_body)
    assert response.status_code == 422


def test_empty_recommendations(client, valid_body):
    valid_body["previous_recommendations"] = []
    response = client.post("/smart-refine", json=valid_body)
    assert response.status_code == 422


def test_503_when_pipeline_raises(client, valid_body, monkeypatch):
    monkeypatch.setenv("DEEPSEEK_API_KEY", "test")

    def boom(**_kwargs):
        raise RuntimeError("LLM exploded")

    from src.pipeline import search as search_module
    monkeypatch.setattr(search_module, "smart_refine", boom, raising=False)

    response = client.post("/smart-refine", json=valid_body)
    assert response.status_code == 503


def test_schema_parity_with_smart_search(client, valid_body, stub_pipeline, monkeypatch):
    """Response keys/types must match /smart-search."""
    monkeypatch.setenv("DEEPSEEK_API_KEY", "test")
    response = client.post("/smart-refine", json=valid_body).json()

    expected_top_level = {"query", "recommendations", "summary", "success"}
    assert set(response.keys()) == expected_top_level

    rec = response["recommendations"][0]
    assert set(rec.keys()) >= {"score_id", "title", "explanation", "rank"}
