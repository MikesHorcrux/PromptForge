from promptforge.datasets.loader import load_dataset
from promptforge.prompts.loader import load_prompt_pack, render_user_prompt


def test_render_prompt_pack_validates_and_renders() -> None:
    prompt_pack = load_prompt_pack("v1")
    dataset = load_dataset("datasets/core.jsonl")

    rendered = render_user_prompt(prompt_pack, dataset.cases[0])

    assert "Avery Chen" in rendered
    assert "Write a support reply for the case below." in rendered
    assert "## Summary" in rendered
    assert "## Answer" in rendered
    assert "## Next Steps" in rendered
    assert "Refunds are available within 30 calendar days" in rendered


def test_render_prompt_pack_exposes_nested_input_payload(tmp_path) -> None:
    prompt_root = tmp_path / "prompts" / "draft"
    prompt_root.mkdir(parents=True, exist_ok=True)
    (prompt_root / "manifest.yaml").write_text(
        "apiVersion: 1\nversion: draft\nname: Draft\ndescription: test\noutput_format: markdown\nrequired_sections: []\n",
        encoding="utf-8",
    )
    (prompt_root / "system.md").write_text("You are helpful.\n", encoding="utf-8")
    (prompt_root / "user_template.md").write_text(
        "{{ input | tojson if input is mapping else input }}\n",
        encoding="utf-8",
    )
    (prompt_root / "variables.schema.json").write_text(
        "{\n  \"type\": \"object\",\n  \"additionalProperties\": true\n}\n",
        encoding="utf-8",
    )

    prompt_pack = load_prompt_pack(prompt_root)
    dataset = load_dataset("datasets/core.jsonl")

    rendered = render_user_prompt(prompt_pack, dataset.cases[0])

    assert "customer_name" in rendered
    assert "Avery" in rendered
