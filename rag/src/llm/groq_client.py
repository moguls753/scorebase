"""Groq LLM client.

Models: llama-3.3-70b-versatile (primary), llama-3.1-8b-instant (fallback)
"""

import os
from dataclasses import dataclass


@dataclass
class GroqConfig:
    """Configuration for Groq API."""

    api_key: str
    primary_model: str = "llama-3.3-70b-versatile"
    fallback_model: str = "llama-3.1-8b-instant"
    temperature: float = 0.7
    max_tokens: int = 1024

    @classmethod
    def from_env(cls) -> "GroqConfig":
        """Create config from environment variable."""
        api_key = os.environ.get("GROQ_API_KEY")
        if not api_key:
            raise ValueError(
                "GROQ_API_KEY environment variable not set.\n"
                "Get your key at https://console.groq.com/keys"
            )
        return cls(api_key=api_key)


class GroqClient:
    """Groq API client with fallback."""

    def __init__(self, config: GroqConfig | None = None):
        """Initialize client.

        Args:
            config: Optional config. If None, loads from environment.
        """
        from groq import Groq

        if config is None:
            config = GroqConfig.from_env()

        self.config = config
        self._client = Groq(api_key=config.api_key)

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

        Raises:
            Exception: If both primary and fallback models fail
        """
        messages = []
        if system_message:
            messages.append({"role": "system", "content": system_message})
        messages.append({"role": "user", "content": prompt})

        temp = temperature if temperature is not None else self.config.temperature
        tokens = max_tokens if max_tokens is not None else self.config.max_tokens

        # Try primary model
        try:
            response = self._client.chat.completions.create(
                model=self.config.primary_model,
                messages=messages,
                temperature=temp,
                max_tokens=tokens,
            )
            content = response.choices[0].message.content
            if content is None:
                raise ValueError("Model returned empty content")
            return content

        except Exception as primary_error:
            # Try fallback model
            print(f"[Groq] Primary model failed: {primary_error}, trying fallback...")
            try:
                response = self._client.chat.completions.create(
                    model=self.config.fallback_model,
                    messages=messages,
                    temperature=temp,
                    max_tokens=tokens,
                )
                content = response.choices[0].message.content
                if content is None:
                    raise ValueError("Fallback model returned empty content")
                return content

            except Exception as fallback_error:
                raise RuntimeError(
                    f"Both models failed.\n"
                    f"Primary ({self.config.primary_model}): {primary_error}\n"
                    f"Fallback ({self.config.fallback_model}): {fallback_error}"
                )
