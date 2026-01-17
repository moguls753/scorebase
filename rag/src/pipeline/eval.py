"""Evaluation script for RAG search quality.

Measures recall and diagnoses why searches fail.

Usage:
    python -m src.pipeline.eval
    python -m src.pipeline.eval --verbose
    python -m src.pipeline.eval --top-k 20
"""

import argparse
from dataclasses import dataclass

from .search import search


@dataclass
class TestCase:
    query: str
    expected_ids: list[int]
    description: str  # What makes this piece distinctive


# Test cases: queries that SHOULD find specific pieces based on their search_text
# Updated to use actually indexed score IDs
TEST_CASES = [
    TestCase(
        query="Bach piano suite allemande courante sarabande gigue Baroque",
        expected_ids=[10219, 10492, 10822],
        description="French Suite No.4 BWV 815 - lists dance movements"
    ),
    TestCase(
        query="Bach fugue piano advanced Grade 6",
        expected_ids=[1951, 3802, 5029, 5956],
        description="Bach Prelude and Fugue BWV 862 - Grade 6-8 piano"
    ),
    TestCase(
        query="Renaissance madrigal SATB a cappella Italian",
        expected_ids=[2681, 3706],
        description="Marenzio Piango che Amor - Renaissance madrigal SATB"
    ),
    TestCase(
        query="Schutz German motet SATB Baroque choir",
        expected_ids=[3565, 4358],
        description="Schutz Lobt Gott in seinem Heiligtum - German motet"
    ),
    TestCase(
        query="easy beginner piano Grade 1 simple",
        expected_ids=[16977, 35212, 20776],
        description="Patapan - Grade 1-2 piano piece"
    ),
    TestCase(
        query="piano duet Classical era Grade 2",
        expected_ids=[51538],
        description="Brandi Duet Presto - Grade 2-3 piano duet"
    ),
    TestCase(
        query="Mozart minuet piano Classical",
        expected_ids=[79700],
        description="Mozart Minuet - Grade 2-3 Classical piano"
    ),
    TestCase(
        query="Lully Baroque minuet D minor dance",
        expected_ids=[93162],
        description="Lully Minuet D minor - Baroque dance"
    ),
    TestCase(
        query="Christmas carol piano easy Patapan",
        expected_ids=[16977],
        description="Patapan - Christmas carol Grade 1-2"
    ),
    TestCase(
        query="Debussy impressionist piano suite",
        expected_ids=[4326],
        description="Suite bergamasque - Debussy impressionist"
    ),
]


@dataclass
class SearchResult:
    score_id: int
    title: str
    similarity: float
    content: str


@dataclass
class EvalResult:
    test_case: TestCase
    found: bool
    rank: int | None  # Position where expected was found (1-indexed), None if not found
    expected_similarity: float | None
    top_results: list[SearchResult]
    query_terms_in_expected: list[str]  # Which query terms appear in expected's search_text
    query_terms_missing: list[str]  # Which query terms are NOT in expected's search_text


def get_expected_content(score_id: int) -> str | None:
    """Fetch search_text for expected score from database."""
    import sqlite3
    from .. import config

    db_path = config.RAILS_DB_PATH
    conn = sqlite3.connect(db_path)
    cursor = conn.execute(
        "SELECT search_text FROM scores WHERE id = ?",
        [score_id]
    )
    row = cursor.fetchone()
    conn.close()
    return row[0] if row else None


def check_term_presence(query: str, content: str) -> tuple[list[str], list[str]]:
    """Check which query terms appear in content.

    Returns (found_terms, missing_terms)
    """
    if not content:
        return [], query.lower().split()

    # Extract meaningful terms (skip stopwords)
    stopwords = {'a', 'an', 'the', 'with', 'for', 'and', 'or', 'in', 'on', 'at', 'to', 'of'}
    query_terms = [t.lower() for t in query.split() if t.lower() not in stopwords and len(t) > 2]

    content_lower = content.lower()

    found = [t for t in query_terms if t in content_lower]
    missing = [t for t in query_terms if t not in content_lower]

    return found, missing


def evaluate_single(test_case: TestCase, top_k: int = 10) -> EvalResult:
    """Evaluate a single test case."""
    try:
        results = search(test_case.query, top_k=top_k)
    except Exception as e:
        print(f"  ERROR searching: {e}")
        results = []

    top_results = [
        SearchResult(
            score_id=r["score_id"],
            title=r["title"],
            similarity=r["similarity"],
            content=r["content"][:200] if r["content"] else ""
        )
        for r in results
    ]

    # Check if any expected ID was found
    result_ids = [r["score_id"] for r in results]
    found = False
    rank = None
    expected_similarity = None

    for exp_id in test_case.expected_ids:
        if exp_id in result_ids:
            found = True
            rank = result_ids.index(exp_id) + 1  # 1-indexed
            expected_similarity = results[rank - 1]["similarity"]
            break

    # Check term presence in expected document
    expected_content = get_expected_content(test_case.expected_ids[0])
    found_terms, missing_terms = check_term_presence(test_case.query, expected_content or "")

    return EvalResult(
        test_case=test_case,
        found=found,
        rank=rank,
        expected_similarity=expected_similarity,
        top_results=top_results,
        query_terms_in_expected=found_terms,
        query_terms_missing=missing_terms
    )


def print_result(result: EvalResult, verbose: bool = False):
    """Print evaluation result with diagnostics."""
    tc = result.test_case

    if result.found:
        print(f"✓ [{result.rank:2d}] {tc.query[:60]}")
        if verbose:
            print(f"       Similarity: {result.expected_similarity:.3f}")
    else:
        print(f"✗ [--] {tc.query[:60]}")
        print(f"       Expected: {tc.description}")

        # Diagnostic: term presence
        if result.query_terms_in_expected:
            print(f"       Terms IN search_text: {', '.join(result.query_terms_in_expected)}")
        if result.query_terms_missing:
            print(f"       Terms MISSING: {', '.join(result.query_terms_missing)}")

        # Show what ranked instead
        if result.top_results:
            print(f"       Top 3 results instead:")
            for i, r in enumerate(result.top_results[:3], 1):
                print(f"         {i}. [{r.similarity:.3f}] {r.title[:50]} (ID:{r.score_id})")

    if verbose and result.found:
        print(f"       Terms matched: {', '.join(result.query_terms_in_expected)}")
        if result.query_terms_missing:
            print(f"       Terms missing: {', '.join(result.query_terms_missing)}")


def print_summary(results: list[EvalResult], top_k: int):
    """Print summary statistics."""
    total = len(results)
    hits = sum(1 for r in results if r.found)

    print("\n" + "=" * 70)
    print(f"SUMMARY: Recall@{top_k} = {hits}/{total} ({hits/total:.0%})")
    print("=" * 70)

    # Analyze failure patterns
    failures = [r for r in results if not r.found]
    if failures:
        print("\nFAILURE ANALYSIS:")

        # Count failures where terms WERE present
        terms_present_but_not_found = sum(
            1 for r in failures
            if len(r.query_terms_in_expected) >= len(r.query_terms_missing)
        )

        if terms_present_but_not_found:
            print(f"  - {terms_present_but_not_found} cases: query terms ARE in search_text but piece not found")
            print(f"    → Suggests EMBEDDING SIMILARITY problem (template dominates)")

        terms_missing = sum(
            1 for r in failures
            if len(r.query_terms_missing) > len(r.query_terms_in_expected)
        )

        if terms_missing:
            print(f"  - {terms_missing} cases: query terms MISSING from search_text")
            print(f"    → Suggests CONTENT problem (search_text lacks key terms)")

    # Show rank distribution for hits
    hits_results = [r for r in results if r.found]
    if hits_results:
        ranks = [r.rank for r in hits_results]
        print(f"\nHIT DISTRIBUTION:")
        print(f"  Rank 1: {sum(1 for r in ranks if r == 1)}")
        print(f"  Rank 2-5: {sum(1 for r in ranks if 2 <= r <= 5)}")
        print(f"  Rank 6-10: {sum(1 for r in ranks if 6 <= r <= 10)}")
        if top_k > 10:
            print(f"  Rank 11+: {sum(1 for r in ranks if r > 10)}")


def main():
    parser = argparse.ArgumentParser(description="Evaluate RAG search quality")
    parser.add_argument("--top-k", type=int, default=10, help="Number of results to consider")
    parser.add_argument("--verbose", "-v", action="store_true", help="Show detailed output")
    args = parser.parse_args()

    print(f"Evaluating {len(TEST_CASES)} test cases (top_k={args.top_k})")
    print("-" * 70)

    results = []
    for tc in TEST_CASES:
        result = evaluate_single(tc, top_k=args.top_k)
        results.append(result)
        print_result(result, verbose=args.verbose)

    print_summary(results, args.top_k)


if __name__ == "__main__":
    main()
