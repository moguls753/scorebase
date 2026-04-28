"""Generic LLM client protocol.

Every concrete client (Groq, DeepSeek, LMStudio, …) must implement `chat`.
The factory returns whichever provider is active per `LLM_PROVIDER`.
"""

from typing import Protocol


class LLMClient(Protocol):
    def chat(
        self,
        prompt: str,
        system_message: str | None = None,
        **kwargs,
    ) -> str: ...
