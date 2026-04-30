"""LLM client factory.

Pick the active LLM provider based on the LLM_BACKEND env var (default: deepseek).
Matches the Rails-side `app/services/llm_client.rb` convention.
Imports are lazy so unused clients don't get loaded.
"""

import os
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .llm_client import LLMClient


_PROVIDER_KEY_VARS: dict[str, str | None] = {
    "deepseek": "DEEPSEEK_API_KEY",
    "groq": "GROQ_API_KEY",
    "lmstudio": None,  # local; no API key
}


def active_provider() -> str:
    return os.environ.get("LLM_BACKEND", "deepseek").lower()


def required_api_key_env_var() -> str | None:
    """Env var name for the API key the active provider needs, or None if no key required."""
    return _PROVIDER_KEY_VARS.get(active_provider())


def default_client() -> "LLMClient":
    """Construct the LLM client for the active provider.

    Raises:
        ValueError: if LLM_PROVIDER is unknown.
    """
    provider = active_provider()
    if provider == "deepseek":
        from .deepseek_client import DeepSeekClient
        return DeepSeekClient()
    if provider == "groq":
        from .groq_client import GroqClient
        return GroqClient()
    if provider == "lmstudio":
        from .lmstudio_client import LMStudioClient
        return LMStudioClient()
    raise ValueError(
        f"Unknown LLM_BACKEND: {provider!r}. "
        f"Supported: {', '.join(sorted(_PROVIDER_KEY_VARS))}."
    )
