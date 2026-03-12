from __future__ import annotations

import getpass
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Callable

from dotenv import dotenv_values, set_key

from promptforge.core.config import settings
from promptforge.core.models import ProviderName
from promptforge.runtime.codex_cli import codex_login_status
from promptforge.ui import print_banner, print_info, print_setup_summary, print_success, print_warning


InputFn = Callable[[str], str]
SecretFn = Callable[[str], str]

PROVIDER_LABELS: dict[ProviderName, str] = {
    "openai": "OpenAI API",
    "codex": "Codex login",
    "openrouter": "OpenRouter",
}
INVALID_MODEL_INPUTS = {"y", "yes", "n", "no"}


def run_setup_wizard(
    *,
    env_path: Path,
    example_env_path: Path,
    input_fn: InputFn | None = None,
    secret_fn: SecretFn | None = None,
) -> int:
    input_fn = input_fn or input
    secret_fn = secret_fn or getpass.getpass
    _ensure_env_file(env_path=env_path, example_env_path=example_env_path)
    env_values = _load_env_values(env_path)

    print_banner("Setup")
    print_info(f"Config file: {env_path}")

    provider = _prompt_choice(
        "Choose a default provider",
        ["openai", "codex", "openrouter"],
        default=env_values.get("PF_PROVIDER", settings.provider or "openai"),
        input_fn=input_fn,
    )
    same_judge_provider = _prompt_yes_no(
        "Use the same provider for judging?",
        default=True,
        input_fn=input_fn,
    )
    judge_provider = provider
    if not same_judge_provider:
        judge_provider = _prompt_choice(
            "Choose a judge provider",
            ["openai", "codex", "openrouter"],
            default=env_values.get("PF_JUDGE_PROVIDER") or provider,
            input_fn=input_fn,
        )

    generation_model = _prompt_text(
        "Default generation model",
        default=_suggest_model_default(
            existing=env_values.get("OPENAI_BASE_MODEL"),
            provider=provider,
            purpose="generation",
        ),
        input_fn=input_fn,
        validator=_validate_model_name,
    )
    judge_model = _prompt_text(
        "Default judge model",
        default=_suggest_model_default(
            existing=env_values.get("OPENAI_JUDGE_MODEL"),
            provider=judge_provider,
            purpose="judge",
        ),
        input_fn=input_fn,
        validator=_validate_model_name,
    )

    updates: dict[str, str] = {
        "PF_PROVIDER": provider,
        "PF_JUDGE_PROVIDER": "" if judge_provider == provider else judge_provider,
        "OPENAI_BASE_MODEL": generation_model,
        "OPENAI_JUDGE_MODEL": judge_model,
        "PF_CODEX_BIN": env_values.get("PF_CODEX_BIN", settings.codex_bin),
    }

    required_providers = {provider, judge_provider}

    if "openai" in required_providers:
        _configure_openai_key(
            env_values=env_values,
            updates=updates,
            input_fn=input_fn,
            secret_fn=secret_fn,
        )

    if "openrouter" in required_providers:
        _configure_openrouter(
            env_values=env_values,
            updates=updates,
            input_fn=input_fn,
            secret_fn=secret_fn,
        )

    if "codex" in required_providers:
        _configure_codex_login(
            env_values=env_values,
            updates=updates,
            input_fn=input_fn,
            secret_fn=secret_fn,
        )

    for key, value in updates.items():
        set_key(str(env_path), key, value, quote_mode="auto")

    print_setup_summary(
        provider=PROVIDER_LABELS[provider],
        judge_provider=PROVIDER_LABELS[judge_provider],
        generation_model=generation_model,
        judge_model=judge_model,
        openai_saved=bool(updates.get("OPENAI_API_KEY")),
        openrouter_saved=bool(updates.get("OPENROUTER_API_KEY")),
    )

    if _prompt_yes_no("Run `pf doctor` now?", default=True, input_fn=input_fn):
        subprocess.run(
            [
                sys.executable,
                "-m",
                "promptforge.cli",
                "doctor",
                "--provider",
                provider,
                "--judge-provider",
                judge_provider,
                "--model",
                generation_model,
            ],
            check=False,
        )
    else:
        print_info("Run `pf doctor` next to verify auth, inputs, and model access.")
    return 0


def _ensure_env_file(*, env_path: Path, example_env_path: Path) -> None:
    if env_path.exists():
        return
    if example_env_path.exists():
        env_path.write_text(example_env_path.read_text(encoding="utf-8"), encoding="utf-8")
        return
    env_path.write_text("", encoding="utf-8")


def _load_env_values(env_path: Path) -> dict[str, str]:
    return {key: value for key, value in dotenv_values(env_path).items() if value is not None}


def _default_model_for_provider(provider: ProviderName, *, purpose: str) -> str:
    if provider == "openrouter":
        return "openai/gpt-5-mini" if purpose == "judge" else "openai/gpt-5"
    if provider == "codex":
        return "gpt-5-mini"
    return "gpt-5-mini" if purpose == "judge" else "gpt-5.4"


def _suggest_model_default(*, existing: str | None, provider: ProviderName, purpose: str) -> str:
    if existing and existing.strip().lower() not in INVALID_MODEL_INPUTS:
        return existing.strip()
    return _default_model_for_provider(provider, purpose=purpose)


def _validate_model_name(value: str) -> str | None:
    stripped = value.strip()
    if stripped.lower() in INVALID_MODEL_INPUTS:
        return "Enter an actual model name, or press Enter to keep the default."
    return None


def _mask_secret(value: str | None) -> str:
    if not value:
        return "(not set)"
    if len(value) <= 8:
        return "*" * len(value)
    return f"{value[:4]}...{value[-4:]}"


def _prompt_choice(
    prompt: str,
    options: list[str],
    *,
    default: str,
    input_fn: InputFn,
) -> str:
    print(prompt)
    for index, option in enumerate(options, start=1):
        label = PROVIDER_LABELS.get(option, option)
        suffix = " (default)" if option == default else ""
        print(f"  {index}. {label}{suffix}")

    while True:
        raw = input_fn(f"Select provider [{default}]: ").strip().lower()
        if not raw:
            return default
        if raw in options:
            return raw
        if raw.isdigit():
            idx = int(raw) - 1
            if 0 <= idx < len(options):
                return options[idx]
        print("Enter a listed provider name or number.")


def _prompt_yes_no(prompt: str, *, default: bool, input_fn: InputFn) -> bool:
    suffix = "[Y/n]" if default else "[y/N]"
    while True:
        raw = input_fn(f"{prompt} {suffix} ").strip().lower()
        if not raw:
            return default
        if raw in {"y", "yes"}:
            return True
        if raw in {"n", "no"}:
            return False
        print("Enter yes or no.")


def _prompt_text(
    prompt: str,
    *,
    default: str = "",
    input_fn: InputFn,
    secret_fn: SecretFn | None = None,
    allow_empty: bool = False,
    validator: Callable[[str], str | None] | None = None,
) -> str:
    while True:
        if secret_fn:
            shown_default = "leave blank to keep current value" if default else "leave blank to skip"
            raw = secret_fn(f"{prompt} ({shown_default}): ")
            if not raw and default:
                return default
        else:
            suffix = f" [{default}]" if default else ""
            raw = input_fn(f"{prompt}{suffix}: ").strip()
            if not raw and default:
                return default

        if raw:
            if validator:
                error = validator(raw)
                if error:
                    print(error)
                    continue
            return raw
        if allow_empty:
            return ""
        if default:
            return default
        print("A value is required or press Enter to skip where allowed.")


def _configure_openai_key(
    *,
    env_values: dict[str, str],
    updates: dict[str, str],
    input_fn: InputFn,
    secret_fn: SecretFn,
) -> None:
    existing = env_values.get("OPENAI_API_KEY")
    print(f"OpenAI API key: {_mask_secret(existing)}")
    if existing and not _prompt_yes_no("Update the OpenAI API key?", default=False, input_fn=input_fn):
        return
    key = _prompt_text(
        "Enter the OpenAI API key",
        default="",
        input_fn=input_fn,
        secret_fn=secret_fn,
        allow_empty=True,
    )
    if key:
        updates["OPENAI_API_KEY"] = key


def _configure_openrouter(
    *,
    env_values: dict[str, str],
    updates: dict[str, str],
    input_fn: InputFn,
    secret_fn: SecretFn,
) -> None:
    existing = env_values.get("OPENROUTER_API_KEY")
    print(f"OpenRouter API key: {_mask_secret(existing)}")
    if not existing or _prompt_yes_no("Update the OpenRouter API key?", default=not bool(existing), input_fn=input_fn):
        key = _prompt_text(
            "Enter the OpenRouter API key",
            default="",
            input_fn=input_fn,
            secret_fn=secret_fn,
            allow_empty=True,
        )
        if key:
            updates["OPENROUTER_API_KEY"] = key

    current_base_url = env_values.get("OPENROUTER_BASE_URL", settings.openrouter_base_url)
    updates["OPENROUTER_BASE_URL"] = _prompt_text(
        "OpenRouter base URL",
        default=current_base_url,
        input_fn=input_fn,
    )


def _configure_codex_login(
    *,
    env_values: dict[str, str],
    updates: dict[str, str],
    input_fn: InputFn,
    secret_fn: SecretFn,
) -> None:
    codex_bin = updates["PF_CODEX_BIN"]
    codex_path = shutil.which(codex_bin)
    if codex_path is None:
        print_warning(f"Codex CLI not found on PATH: {codex_bin}")
        print_info("Install Codex and rerun `pf setup`, or choose a different provider.")
        return

    ok, detail = _codex_login_status(codex_bin)
    print_info(f"Codex status: {detail}")
    if ok and not _prompt_yes_no("Refresh Codex login now?", default=False, input_fn=input_fn):
        return

    method = _prompt_choice(
        "How should Codex draw power?",
        ["codex", "openai", "skip"],
        default="codex" if not env_values.get("OPENAI_API_KEY") else "openai",
        input_fn=input_fn,
    )
    if method == "skip":
        return

    if method == "codex":
        subprocess.run([codex_bin, "login"], check=False)
    else:
        existing_key = updates.get("OPENAI_API_KEY") or env_values.get("OPENAI_API_KEY", "")
        if existing_key and _prompt_yes_no("Use the current OpenAI API key for Codex login?", default=True, input_fn=input_fn):
            api_key = existing_key
        else:
            api_key = _prompt_text(
                "Enter the OpenAI API key for Codex login",
                default="",
                input_fn=input_fn,
                secret_fn=secret_fn,
                allow_empty=False,
            )
        subprocess.run(
            [codex_bin, "login", "--with-api-key"],
            input=f"{api_key}\n",
            text=True,
            check=False,
        )
        if "OPENAI_API_KEY" not in updates and not env_values.get("OPENAI_API_KEY"):
            if _prompt_yes_no("Store this API key in .env for direct OpenAI mode too?", default=False, input_fn=input_fn):
                updates["OPENAI_API_KEY"] = api_key

    ok, detail = _codex_login_status(codex_bin)
    if ok:
        print_success(f"Codex status: {detail}")
    else:
        print_warning(f"Codex status: {detail}")


def _codex_login_status(codex_bin: str) -> tuple[bool, str]:
    return codex_login_status(codex_bin)
