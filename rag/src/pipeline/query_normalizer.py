"""Query-side normalization for embedding lookup.

The catalog is indexed with English-language descriptions, so the multilingual
embedder ('paraphrase-multilingual-MiniLM-L12-v2') produces weak matches when a
German query uses a cognate that maps to a different English word in the index
(e.g. 'Streichquartett' embeds closer to 'choir motets' than to 'string quartet').

We normalize embedder input only; the original query is still shown to the LLM
so user intent is preserved in the conversational layer.
"""

import re

# German → English. Longer phrases first so multi-word matches win over substrings.
DE_EN_TERMS: dict[str, str] = {
    # Genres / forms
    "Streichquartett": "string quartet",
    "Klaviersonate": "piano sonata",
    "Violinsonate": "violin sonata",
    "Klavierkonzert": "piano concerto",
    "Konzertstück": "concert piece",
    "Trauermusik": "funeral music",
    "Hochzeitsmarsch": "wedding march",
    "Hochzeitsmusik": "wedding music",
    "Klaviermusik": "piano music",
    "Orgelchoral": "organ chorale",
    "Orgelmusik": "organ music",
    "Sonaten": "sonatas",
    "Sonate": "sonata",
    "Etüden": "etudes",
    "Etüde": "etude",
    "Menuett": "minuet",
    "Fuge": "fugue",
    "Choral": "chorale",
    "Motette": "motet",
    "Motetten": "motets",
    "Madrigal": "madrigal",
    "Hymne": "hymn",
    "Psalm": "psalm",
    "Walzer": "waltz",
    "Lied": "song",
    "Lieder": "songs",
    # Instruments
    "Klavier": "piano",
    "Geige": "violin",
    "Violine": "violin",
    "Bratsche": "viola",
    "Cello": "cello",
    "Violoncello": "cello",
    "Kontrabass": "double bass",
    "Orgel": "organ",
    "Cembalo": "harpsichord",
    "Flöte": "flute",
    "Klarinette": "clarinet",
    "Trompete": "trumpet",
    "Posaune": "trombone",
    "Streicher": "strings",
    "Bläser": "winds",
    "Holzbläser": "woodwinds",
    "Blechbläser": "brass",
    # Voices / ensembles
    "Sopran": "soprano",
    "Mezzosopran": "mezzo-soprano",
    "Bariton": "baritone",
    "Bass": "bass",
    "Chor": "choir",
    # Difficulty / pedagogy
    "Anfänger": "beginner",
    "Fortgeschrittene": "advanced",
    "leichte": "easy",
    "leichter": "easy",
    "leicht": "easy",
    "einfache": "simple",
    "einfacher": "simple",
    "einfach": "simple",
    "schwierig": "difficult",
    # Misc
    "Hochzeit": "wedding",
    "schottische": "Scottish",
    "barock": "Baroque",
    "klassik": "Classical",
    "romantik": "Romantic",
    "Renaissance": "Renaissance",
    "Weihnachten": "Christmas",
    "Weihnachtsmusik": "Christmas music",
}


def _build_pattern(terms: dict[str, str]) -> re.Pattern:
    sorted_terms = sorted(terms.keys(), key=len, reverse=True)
    escaped = "|".join(re.escape(t) for t in sorted_terms)
    # \b doesn't behave well around umlauts, so we guard with whitespace/punctuation
    # boundaries explicitly. Lookbehind/lookahead must be the same width across alternatives,
    # so we use a single character class.
    return re.compile(rf"(?<![A-Za-zÄÖÜäöüß])({escaped})(?![A-Za-zÄÖÜäöüß])", re.IGNORECASE)


_PATTERN = _build_pattern(DE_EN_TERMS)
_LOOKUP = {k.lower(): v for k, v in DE_EN_TERMS.items()}


def normalize_for_embedding(query: str) -> str:
    """Substitute German cognates with English equivalents for embedding.

    Idempotent on already-English text. Preserves casing of non-matched tokens.
    """
    if not query:
        return query

    def repl(match: re.Match) -> str:
        return _LOOKUP[match.group(0).lower()]

    return _PATTERN.sub(repl, query)
