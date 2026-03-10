from pathlib import Path
from subprocess import CompletedProcess

from dotenv import dotenv_values

from promptforge.setup_wizard import run_setup_wizard


def test_setup_wizard_writes_openai_config(tmp_path: Path, monkeypatch) -> None:
    env_path = tmp_path / ".env"
    example_path = tmp_path / ".env.example"
    example_path.write_text("OPENAI_API_KEY=\nPF_PROVIDER=openai\n", encoding="utf-8")

    answers = iter([
        "openai",
        "",
        "",
        "",
        "n",
        "n",
    ])
    secrets = iter(["sk-test-openai"])

    monkeypatch.setattr("builtins.input", lambda prompt="": next(answers))
    monkeypatch.setattr("getpass.getpass", lambda prompt="": next(secrets))

    calls: list[list[str]] = []

    def fake_run(*args, **kwargs):
        command = args[0]
        calls.append(command)
        return CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr("subprocess.run", fake_run)

    exit_code = run_setup_wizard(env_path=env_path, example_env_path=example_path)

    saved = dotenv_values(env_path)
    assert exit_code == 0
    assert saved["PF_PROVIDER"] == "openai"
    assert saved["OPENAI_API_KEY"] == "sk-test-openai"
    assert saved["PF_JUDGE_PROVIDER"] == ""
    assert calls == []


def test_setup_wizard_can_launch_codex_login(tmp_path: Path, monkeypatch) -> None:
    env_path = tmp_path / ".env"
    example_path = tmp_path / ".env.example"
    example_path.write_text("PF_PROVIDER=openai\nPF_CODEX_BIN=codex\n", encoding="utf-8")

    answers = iter([
        "codex",
        "",
        "",
        "",
        "",
        "codex",
        "n",
    ])
    monkeypatch.setattr("builtins.input", lambda prompt="": next(answers))
    monkeypatch.setattr("getpass.getpass", lambda prompt="": "")
    monkeypatch.setattr("shutil.which", lambda name: "/usr/bin/codex" if name == "codex" else None)

    state = {"status_calls": 0}
    commands: list[list[str]] = []

    def fake_run(*args, **kwargs):
        command = args[0]
        commands.append(command)
        if command[:3] == ["codex", "login", "status"]:
            state["status_calls"] += 1
            if state["status_calls"] == 1:
                return CompletedProcess(command, 1, stdout="", stderr="Not logged in")
            return CompletedProcess(command, 0, stdout="Logged in using ChatGPT", stderr="")
        if command[:2] == ["codex", "login"]:
            return CompletedProcess(command, 0, stdout="", stderr="")
        return CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr("subprocess.run", fake_run)

    exit_code = run_setup_wizard(env_path=env_path, example_env_path=example_path)

    saved = dotenv_values(env_path)
    assert exit_code == 0
    assert saved["PF_PROVIDER"] == "codex"
    assert saved["PF_JUDGE_PROVIDER"] == ""
    assert ["codex", "login"] in commands
