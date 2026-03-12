PYTHON ?= python3.11

bootstrap:
	$(PYTHON) -m venv .venv
	. .venv/bin/activate && pip install --upgrade pip && pip install -e '.[dev]'

test:
	. .venv/bin/activate && pytest -q

doctor:
	. .venv/bin/activate && pf doctor

app-build:
	xcodebuild -project apps/macos/PromptForge/PromptForge.xcodeproj -scheme PromptForge -sdk macosx build CODE_SIGNING_ALLOWED=NO
