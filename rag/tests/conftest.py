"""Stub heavy ML deps before any test imports them.

The endpoint tests only need the FastAPI app + Pydantic validation; importing
the real pipeline would drag in haystack / sentence-transformers / chromadb,
which aren't required (or installed) for endpoint-level tests.
"""

import sys
from unittest.mock import MagicMock

for mod in (
    "haystack",
    "haystack.components.embedders",
    "haystack_integrations.document_stores.chroma",
    "haystack_integrations.components.retrievers.chroma",
):
    sys.modules.setdefault(mod, MagicMock())
