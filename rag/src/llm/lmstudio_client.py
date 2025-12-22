"""LM Studio client using OpenAI-compatible API.

LM Studio runs locally and exposes an OpenAI-compatible endpoint.
No rate limiting needed for local inference.
"""

import os
from dataclasses import dataclass


@dataclass
class LMStudioConfig:
    """Configuration for LM Studio API."""

    base_url: str = "http://localhost:1234/v1"
    model: str = "qwen2.5-7b-instruct"
    temperature: float = 0.7
    max_tokens: int = 1024

    @classmethod
    def from_env(cls) -> "LMStudioConfig":
        """Create config from environment variables."""
        return cls(
            base_url=os.environ.get("LMSTUDIO_BASE_URL", "http://localhost:1234/v1"),
            model=os.environ.get("LMSTUDIO_MODEL", "qwen2.5-7b-instruct"),
        )


class LMStudioClient:
    """LM Studio client with OpenAI-compatible API."""

    def __init__(self, config: LMStudioConfig | None = None):
        """Initialize client.

        Args:
            config: Optional config. If None, uses defaults/environment.
        """
        from openai import OpenAI

        if config is None:
            config = LMStudioConfig.from_env()

        self.config = config
        self._client = OpenAI(
            base_url=config.base_url,
            api_key="lm-studio",  # LM Studio doesn't require a real key
        )

    def chat(
        self,
        prompt: str,
        system_message: str | None = None,
        temperature: float | None = None,
        max_tokens: int | None = None,
    ) -> str:
        """Send a chat completion request.

        Args:
            prompt: User message
            system_message: Optional system message
            temperature: Override default temperature
            max_tokens: Override default max tokens

        Returns:
            Model response text
        """
        messages = []
        if system_message:
            messages.append({"role": "system", "content": system_message})
        messages.append({"role": "user", "content": prompt})

        response = self._client.chat.completions.create(
            model=self.config.model,
            messages=messages,
            temperature=temperature or self.config.temperature,
            max_tokens=max_tokens or self.config.max_tokens,
        )

        content = response.choices[0].message.content
        if content is None:
            raise ValueError("Model returned empty content")
        return content
