PYTHON ?= python3.11

bootstrap:
	$(PYTHON) -m venv .venv
	. .venv/bin/activate && pip install --upgrade pip && pip install -e '.[dev]'

test:
	. .venv/bin/activate && pytest -q

doctor:
	. .venv/bin/activate && pf doctor
