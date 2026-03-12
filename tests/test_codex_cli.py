from subprocess import CompletedProcess

from promptforge.runtime.codex_cli import (
    CodexDeviceAuthResult,
    codex_begin_device_auth,
    codex_login_status,
    codex_login_with_api_key,
)


def test_codex_login_status_strips_ansi_sequences(monkeypatch) -> None:
    monkeypatch.setattr("promptforge.runtime.codex_cli.resolve_codex_bin", lambda _: "/tmp/codex")

    def fake_run(*args, **kwargs):
        return CompletedProcess(
            args[0],
            0,
            stdout="\x1b[94mLogged in using ChatGPT\x1b[0m",
            stderr="",
        )

    monkeypatch.setattr("promptforge.runtime.codex_cli.subprocess.run", fake_run)

    ready, detail = codex_login_status("codex")

    assert ready is True
    assert detail == "Logged in using ChatGPT"


def test_codex_login_with_api_key_uses_stdin_and_rechecks_status(monkeypatch) -> None:
    monkeypatch.setattr("promptforge.runtime.codex_cli.resolve_codex_bin", lambda _: "/tmp/codex")
    captured: dict[str, str] = {}

    def fake_run(*args, **kwargs):
        command = args[0]
        if command == ["/tmp/codex", "login", "--with-api-key"]:
            captured["input"] = kwargs["input"]
            return CompletedProcess(command, 0, stdout="Codex login completed.", stderr="")
        if command == ["/tmp/codex", "login", "status"]:
            return CompletedProcess(command, 0, stdout="Logged in using ChatGPT", stderr="")
        raise AssertionError(f"Unexpected command: {command}")

    monkeypatch.setattr("promptforge.runtime.codex_cli.subprocess.run", fake_run)

    ready, detail = codex_login_with_api_key("codex", api_key="sk-test-openai")

    assert ready is True
    assert detail == "Logged in using ChatGPT"
    assert captured["input"] == "sk-test-openai\n"


def test_codex_begin_device_auth_extracts_browser_details(monkeypatch) -> None:
    monkeypatch.setattr("promptforge.runtime.codex_cli.resolve_codex_bin", lambda _: "/tmp/codex")

    def fake_run(*args, **kwargs):
        return CompletedProcess(
            args[0],
            0,
            stdout=(
                "\x1b[90mWelcome\x1b[0m\n"
                "1. Open this link in your browser and sign in to your account\n"
                "   https://auth.openai.com/codex/device\n"
                "2. Enter this one-time code\n"
                "   SZZY-QEPOG\n"
            ),
            stderr="",
        )

    monkeypatch.setattr("promptforge.runtime.codex_cli.subprocess.run", fake_run)

    started = codex_begin_device_auth("codex")

    assert started == CodexDeviceAuthResult(
        verification_uri="https://auth.openai.com/codex/device",
        user_code="SZZY-QEPOG",
        instructions="Open https://auth.openai.com/codex/device and enter code SZZY-QEPOG.",
    )
