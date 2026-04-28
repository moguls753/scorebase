"""LLM integration for RAG search."""

from .deepseek_client import DeepSeekClient, DeepSeekConfig
from .factory import active_provider, default_client, required_api_key_env_var
from .groq_client import GroqClient, GroqConfig
from .lmstudio_client import LMStudioClient, LMStudioConfig
from .result_selector import Recommendation, ResultSelector, SelectionResult

__all__ = [
    "DeepSeekClient",
    "DeepSeekConfig",
    "GroqClient",
    "GroqConfig",
    "LMStudioClient",
    "LMStudioConfig",
    "Recommendation",
    "ResultSelector",
    "SelectionResult",
    "active_provider",
    "default_client",
    "required_api_key_env_var",
]
