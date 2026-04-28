"""DeepSeek LLM client (OpenAI-compatible API)."""

import os
from dataclasses import dataclass


@dataclass
class DeepSeekConfig:
    """Configuration for DeepSeek API."""

    api_key: str
    model: str = "deepseek-chat"
    base_url: str = "https://api.deepseek.com/v1"
    temperature: float = 0.7
    max_tokens: int = 1024

    @classmethod
    def from_env(cls) -> "DeepSeekConfig":
        api_key = os.environ.get("DEEPSEEK_API_KEY")
        if not api_key:
            raise ValueError(
                "DEEPSEEK_API_KEY environment variable not set.\n"
                "Get your key at https://platform.deepseek.com/api_keys"
            )
        model = os.environ.get("DEEPSEEK_MODEL", "deepseek-chat")
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
    ) -> str:
        messages: list[dict] = []
        if system_message:
            messages.append({"role": "system", "content": system_message})
        messages.append({"role": "user", "content": prompt})

        response = self._client.chat.completions.create(
            model=self.config.model,
            messages=messages,
            temperature=temperature if temperature is not None else self.config.temperature,
            max_tokens=max_tokens if max_tokens is not None else self.config.max_tokens,
        )
        content = response.choices[0].message.content
        if content is None:
            raise ValueError("DeepSeek returned empty content")
        return content
