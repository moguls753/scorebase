"""DeepSeek LLM client (OpenAI-compatible API)."""

import logging
import os
from dataclasses import dataclass

logger = logging.getLogger(__name__)


@dataclass
class DeepSeekConfig:
    """Configuration for DeepSeek API.

    Default model is deepseek-reasoner. Override with DEEPSEEK_MODEL env var
    (e.g. ``DEEPSEEK_MODEL=deepseek-chat`` for the faster non-reasoning model).

    Default temperature is 0.2 because the result-selector task is schema-bound
    and rewards consistency over creativity. Reasoner ignores temperature.
    """

    api_key: str
    model: str = "deepseek-reasoner"
    base_url: str = "https://api.deepseek.com/v1"
    temperature: float = 0.2
    max_tokens: int = 1024

    @classmethod
    def from_env(cls) -> "DeepSeekConfig":
        api_key = os.environ.get("DEEPSEEK_API_KEY")
        if not api_key:
            raise ValueError(
                "DEEPSEEK_API_KEY environment variable not set.\n"
                "Get your key at https://platform.deepseek.com/api_keys"
            )
        model = os.environ.get("DEEPSEEK_MODEL", "deepseek-reasoner")
        return cls(api_key=api_key, model=model)


class DeepSeekClient:
    """DeepSeek API client (OpenAI-compatible)."""

    def __init__(self, config: DeepSeekConfig | None = None):
        from openai import OpenAI

        if config is None:
            config = DeepSeekConfig.from_env()
        self.config = config
        self._client = OpenAI(api_key=config.api_key, base_url=config.base_url)

    def chat(
        self,
        prompt: str,
        system_message: str | None = None,
        temperature: float | None = None,
        max_tokens: int | None = None,
        response_format: dict | None = None,
    ) -> str:
        """Send a chat completion request.

        Args:
            prompt: User message.
            system_message: Optional system message.
            temperature: Override default temperature.
            max_tokens: Override default max tokens.
            response_format: Optional dict, e.g. ``{"type": "json_object"}`` to
                force valid JSON output. The prompt itself must also instruct
                the model to output JSON for this to work reliably on DeepSeek.

        Returns:
            Model response text. Returns "" (not None) when DeepSeek returns
            empty content so callers can treat this as a parse failure rather
            than an exception.
        """
        messages: list[dict] = []
        if system_message:
            messages.append({"role": "system", "content": system_message})
        messages.append({"role": "user", "content": prompt})

        kwargs: dict = {
            "model": self.config.model,
            "messages": messages,
            "temperature": temperature if temperature is not None else self.config.temperature,
            "max_tokens": max_tokens if max_tokens is not None else self.config.max_tokens,
        }
        # deepseek-reasoner ignores response_format and (per DeepSeek's docs)
        # may reject it; skip the kwarg for any reasoner model.
        if response_format is not None and "reasoner" not in self.config.model:
            kwargs["response_format"] = response_format

        response = self._client.chat.completions.create(**kwargs)
        choice = response.choices[0]
        content = choice.message.content
        if content is None:
            logger.warning(
                "DeepSeek returned empty content (finish_reason=%s, model=%s)",
                getattr(choice, "finish_reason", None),
                self.config.model,
            )
            return ""
        return content
