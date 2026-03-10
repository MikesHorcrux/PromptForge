from promptforge.datasets.loader import load_dataset
from promptforge.prompts.loader import load_prompt_pack, render_user_prompt


def test_render_prompt_pack_validates_and_renders() -> None:
    prompt_pack = load_prompt_pack("v1")
    dataset = load_dataset("datasets/core.jsonl")

    rendered = render_user_prompt(prompt_pack, dataset.cases[0])

    assert "Avery" in rendered
    assert "Summary, Answer, and Next Steps" in rendered
    assert "Refunds are available within 30 days" in rendered

