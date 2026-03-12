# Product Spec

_Status: Historical design notes, not the primary source of truth._

_Last reviewed against commit `4995d46a2ca16a3f56824412acc547118ed6d804`._

This file remains in the repo as historical product-direction context.

If you need the current implementation shape, start with:

- [README](../README.md)
- [Architecture](architecture.md)
- [Runtime and pipeline](runtime-and-pipeline.md)
- [FAQ](faq.md)

Why this file is not the primary source of truth:

- parts of the proposed UI and product language predate the current navigator/chat/editor/inspector workspace
- the implementation has already pivoted into a more concrete prompt-project model
- architecture, runtime, and operations behavior are now documented directly from code elsewhere in `docs/`

Historical themes preserved here:

- PromptForge should feel like a prompt IDE rather than a one-off eval script
- prompt editing and prompt evaluation should be separate concerns
- scenario suites should behave like saved behavior tests
- promotion and review should be explicit

For current behavior, prefer the implementation-grounded docs instead of this file.
