# Product Spec: Prompt IDE and Scenario Testing

_Status: Proposed_

_Last updated: March 11, 2026._

## Summary

PromptForge should evolve from a prompt evaluation workbench into a prompt
development environment:

- an agent helps the user research, rewrite, and iterate on prompts
- the agent's actions are visible, inspectable, and permissioned
- prompt changes are versioned, inspectable, and reversible
- a playground exists for ad hoc prompt trials before formalizing tests
- scenario tests act like prompt behavior tests
- run review makes regressions obvious before shipping

In one line:

PromptForge should feel like Codex for prompt authoring and pytest for prompt
behavior.

## Product problem

Teams changing prompts face two linked problems:

- prompt edits create unpredictable output variance
- there is rarely a reliable definition of "better" beyond a few manual spot checks

That creates three failure modes:

- a prompt sounds better in one chat but regresses in important cases
- a team cannot explain why a new prompt should replace the old one
- prompt work stays artisanal instead of becoming repeatable product work

## Product thesis

PromptForge should help one user or one small team do two jobs in one tool:

1. Co-author prompts with an agent that can reason, research, inspect prompt
   files, stage edits, and run targeted checks.
2. Verify prompt changes with repeatable scenario tests that compare a candidate
   against a known baseline.

The builder side should be exploratory.

The evaluator side should be constrained, reproducible, and boring.

That separation is required for trust.

## Target user

Primary user:

- an engineer, prompt engineer, or technical product builder shipping one or
  more LLM workflows in production

Secondary user:

- a product stakeholder who needs readable evidence about whether a prompt
  change should ship

This is not yet a broad enterprise eval platform. The ideal first customer is a
small-to-mid team that wants rigor without buying a hosted control plane.

## Jobs to be done

- "Help me improve this prompt without starting from scratch every time."
- "Show me whether my latest prompt change is actually better."
- "Let me define the scenarios that matter and test them repeatedly."
- "Help me review failures quickly so I can decide whether to ship."

## Non-goals

- Human approval workflow or multi-user governance
- Hosted collaboration or cloud execution plane
- General model observability across all application traces
- Replacing a full CI system

## Product principles

- Prompt changes should be diffable.
- Evaluation should be baseline-relative, not vibes-relative.
- The builder agent and the evaluation runner should not share behavior.
- Agent actions should be visible, attributable, and bounded by clear
  permissions.
- One screen should have one main job.
- A user should be able to try ideas in a scratchpad before encoding them as
  scenario tests.
- Failing cases should be easier to inspect than passing summaries.
- Promotion from candidate to baseline should be an explicit product action.
- The app should feel native to macOS, not like a dashboard crammed into one
  window.

## Current product shape

Today PromptForge already has important pieces:

- versioned prompt packs
- prompt-scoped metadata in `prompt.json`
- an agent chat with staged proposals
- quick benchmark and full evaluation actions
- deterministic plus rubric-based scoring
- reproducible local artifacts
- a macOS app with `overview` and `editor` modes

That is a strong foundation, but the current product still reads as:

"prompt eval workbench with an editor"

The target product should read as:

"prompt IDE with built-in scenario testing and review"

## Core product objects

The product should center on these objects:

### Prompt

The prompt being authored, including:

- system prompt
- user template
- prompt intent
- linked scenario suites
- baseline prompt reference

### Prompt branch

A working candidate derived from a baseline prompt. This is the unit of
iteration, comparison, and promotion.

### Agent session

The interactive, tool-using conversation that helps the user:

- inspect prompt files
- propose edits
- explain tradeoffs
- run spot checks
- research domain details when needed

### Playground session

An ad hoc prompt trial surface for:

- trying one-off inputs before they become formal scenarios
- previewing multiple samples of the same prompt
- comparing candidate and baseline behavior quickly
- promoting useful scratch examples into scenario cases

### Scenario suite

A named set of cases representing the behaviors that matter for this prompt.

Examples:

- "Core support replies"
- "Extraction JSON contract"
- "Sales objection handling"
- "Safety edge cases"

### Scenario case

One representative input with optional context, expectations, tags, and notes.

### Assertion

A test-like rule attached to a scenario case or suite. Assertions can be:

- deterministic
- rubric-based
- comparative against a baseline

### Run

One execution of a prompt or prompt comparison against one scenario suite under
fixed settings.

### Review

A curated view of failures, regressions, deltas, and notable wins from a run.

### Decision

A recorded ship decision on a candidate branch, such as:

- keep iterating
- accept with known regressions
- promote to baseline
- reject and restore

## Proposed product surfaces

PromptForge should have three primary surfaces.

### 1. Prompt Studio

Purpose:

- author and refine prompts with an agent

Layout:

- left: chat with the builder agent
- right: prompt canvas

Capabilities:

- normal agent chat
- explicit file diffs and staged edits
- branch from baseline
- restore older revision
- use a built-in playground for ad hoc prompt trials
- run spot checks on selected scenarios
- ask the agent to explain why a prompt change may help or hurt

This is the daily working surface.

### 2. Scenario Tests

Purpose:

- define what "good" means in repeatable, test-like form

Layout:

- suite list in sidebar
- scenario list in primary pane
- selected scenario and assertions in inspector

Capabilities:

- create scenario suites
- add or edit cases
- generate new cases from transcripts, failure history, pasted examples, or
  imported datasets
- tag cases by feature, risk, or customer segment
- define assertions for correctness, tone, format, token budget, latency, cost,
  and safety
- choose evaluation mode: single prompt, baseline vs candidate, or repeated
  trials

This is where product quality is encoded.

### 3. Run Review

Purpose:

- decide whether a prompt change should ship

Layout:

- left: failing and regressed cases first
- center: selected case with baseline output, candidate output, and diff
- right: assertion results, scores, cost, token usage, and notes

Capabilities:

- sort by regressions, hard failures, highest cost increase, or largest score
  delta
- inspect why a case failed
- connect a prompt diff to likely changed behaviors
- collapse passing noise
- record a ship decision and promote candidate to baseline when acceptable

This is the release decision surface.

## User flow

### Flow 1: Improve a prompt

1. Open a prompt in Prompt Studio.
2. Chat with the builder agent.
3. Try ad hoc inputs in the playground.
4. Stage and apply edits to the prompt canvas.
5. Run spot checks on a few scenarios.
6. Save a candidate branch.

### Flow 2: Validate a candidate

1. Open Scenario Tests.
2. Select the relevant suite.
3. Add or refine scenarios if new failure modes appeared during editing.
4. Run baseline vs candidate.
5. Review assertion and score deltas.
6. Open Run Review to inspect failures.

### Flow 3: Ship or revert

1. Review regressed cases.
2. Record whether failures are acceptable and why.
3. Promote candidate to baseline, reject it, or continue iterating.

## Functional requirements

### Builder agent

The builder agent must be able to:

- read prompt files and prompt metadata
- propose and stage file changes
- explain the reasoning behind a change
- use a bounded toolset for file inspection, prompt trials, benchmark lookup,
  and optional external research
- run targeted scenario checks from chat
- inspect prior runs and failure cases
- use external research when explicitly needed

The builder agent may be flexible and tool-using.

### Builder agent controls and provenance

If PromptForge is going to feel like a prompt-authoring agent rather than a
chat box, the product must show what the builder agent did.

The user should be able to see:

- which files the agent inspected
- which files the agent proposed changing
- which scenarios or runs the agent referenced
- whether the agent used outside research
- what changed between before and after

The builder agent should support product-level control over:

- allowed tools
- permission mode for file edits and external research
- model choice
- reasoning effort or depth
- whether changes are auto-staged or proposal-only

The builder agent should write a lightweight action log into the local session
history so work remains inspectable.

### Playground

PromptForge should include a playground inside Studio for ad hoc prompt trials.

The playground should support:

- one-off input trials
- side-by-side candidate and baseline output preview
- multiple samples from the same prompt to expose variance early
- token, cost, and latency visibility for each sample
- promoting a scratch input into a formal scenario case

### Evaluation runner

The evaluation runner must:

- operate from fixed prompt, suite, model, and config inputs
- produce reproducible artifacts
- support deterministic assertions and rubric judging
- support baseline vs candidate comparisons
- support repeated trials to measure variance
- report tokens, cost, latency, hard failures, and score deltas

The runner should not improvise.

### Assertions

PromptForge should support assertions at launch for:

- correctness
- format validity
- required content
- prohibited content
- tone alignment
- token ceiling
- latency ceiling
- cost ceiling
- safety markers

Later assertions can include:

- citation quality
- tool-use correctness
- structured extraction fidelity
- consistency across repeated runs

### Scenario suite bootstrapping

Scenario tests should not require full manual authoring from day one.

The product should help users create suites from:

- pasted real-world examples
- failing benchmark cases
- chat or playground transcripts
- imported dataset rows
- agent-suggested edge cases based on recent regressions

That bootstrapping workflow matters for adoption.

### Variance handling

One of the product's core promises should be variance awareness, not just
single-run scoring.

The product should be able to say:

- this prompt is better on average
- this prompt is less stable than the baseline
- this prompt improved tone but increased hard failures

That means repeated trials and spread metrics should be first-class for selected
scenario suites.

Variance needs to exist at both levels:

- suite-level averages and spread
- case-level stability so users can see which scenarios are flaky

The review flow should be able to call out unstable scenarios directly.

### Review and promotion

PromptForge should not stop at reporting deltas.

It should support:

- recording a ship decision for a candidate
- promoting a candidate to the new baseline
- restoring the previous baseline
- attaching a short rationale to the promotion or rejection
- showing which prompt diff likely contributed to the biggest regressions

## UX requirements

### Information architecture

The app should move from two top-level modes, `overview` and `editor`, to a
clearer task model:

- `Studio`
- `Tests`
- `Review`

Settings should stay separate from those working modes.

### Design direction

PromptForge should feel like a native macOS product for focused creative work,
not a dense monitoring dashboard.

The design should optimize for:

- calm, high-signal layouts
- one primary task per screen
- toolbar-driven actions instead of large in-content control clusters
- progressive disclosure through inspectors, sheets, and secondary panes
- clear visual hierarchy with minimal persistent status chrome

The current experience should be simplified aggressively:

- move primary actions into the window toolbar
- reduce header density inside content views
- remove most always-visible status pills from the main workspace
- reserve dense operational detail for inspectors, review views, and settings
- prefer explicit product actions like `Create Revision`, `Run Suite`, and
  `Promote` over generic `Save` actions

### macOS flow

The UI should follow a native single-context flow:

- sidebar for prompts, suites, and recent runs
- one primary workspace at a time
- details in inspectors, not extra dashboard cards everywhere
- sheets for setup and lightweight creation flows
- clear back navigation between Studio, Tests, and Review

The default app shell should behave like a three-column macOS workspace:

- navigation sidebar for prompts, suites, and runs
- central work area for the active task
- inspector for context, settings, and secondary detail

### Studio layout

The editor should remain split view, but the right pane should be a real prompt
canvas rather than a long stacked form.

The canvas should support:

- prompt sections
- reusable prompt blocks and examples where appropriate
- inline diffs
- quick apply and revert
- embedded playground controls
- scenario quick-run entry points

### Studio scratchpad

Studio should include a scratchpad area where the user can:

- paste an input
- run the current candidate prompt
- optionally run the baseline alongside it
- request multiple samples
- save that input as a scenario case if it proves important

The Studio surface should feel like:

- left: structured builder-agent conversation
- center: prompt canvas
- right: inspector with branch, linked suites, failures, and quick-run context

The builder-agent conversation should not be a raw transcript alone. Each agent
step should be able to show structured attachments such as:

- files inspected
- proposal summary
- diff preview
- quick-run result
- research note

### Tests layout

The Tests surface should feel closer to a native test navigator than a report.

Recommended structure:

- left: scenario suites
- center: case list with pass, fail, regressed, and flaky states
- right: assertion editor, case metadata, and tags

This view should prioritize authoring and triage over summary charts.

### Review layout

The current benchmark summary and history cards should become secondary.

The first thing the user should see in review is:

- what failed
- what regressed
- why

The second thing they should see is:

- what changed in the prompt
- what likely caused the regression
- what the ship decision options are

The Review surface should be strongly opinionated:

- left: failing and regressed cases first
- center: baseline output, candidate output, and diff
- right: assertions, tokens, cost, variance, and decision controls

Review should end in a decision, not just a report.

### Controls and commands

PromptForge should rely on native controls before textual commands.

Preferred interaction model:

- toolbar actions for common tasks
- context menus for case- and prompt-specific actions
- keyboard shortcuts for frequent workflow steps
- a command bar for advanced actions

Slash commands can remain as a power-user layer, but they should not be the
primary interaction model.

### Visual system

The visual system should move away from heavy black-and-blue dashboard styling.

Recommended direction:

- restrained use of color in working views
- warm neutrals and soft material treatments
- amber as the primary accent, used sparingly
- SF Pro for interface text and SF Mono only where code-like content needs it
- gradients and illustration reserved for onboarding, empty states, and key
  moments rather than everyday editing surfaces

The working UI should feel precise, calm, and durable.

### Terminology

The product should use more intuitive labels for core actions and states.

Examples:

- `Run Bench` -> `Quick Check`
- `Full Eval` -> `Run Suite`
- `Weak Cases` -> `Needs Attention`
- `Delta` -> `Change vs Baseline`
- generic `Save Prompt` actions should become autosave, `Create Revision`, or
  another more explicit workflow term depending on intent

### Forgie mascot

Forgie should act as a brand and guidance character, not a permanent decorative
element in the core workspace.

Use Forgie in:

- onboarding
- empty states
- "no tests yet" or "review complete" states
- subtle guidance moments

Do not keep Forgie persistently visible in the main authoring workspace.

The lantern is the strongest metaphor in the mascot system. It should represent
guidance, inspection, and surfacing issues.

Forgie should have at least three product-ready forms:

- a simplified app icon or brand mark
- a clean onboarding illustration
- a compact agent-status glyph built around the lantern motif

The richer illustration style should be reserved for marketing, onboarding, and
special states. Day-to-day product UI should use cleaner, simpler Forgie assets.

## Data model updates needed

The current data model is close for prompt packs and runs, but it is missing
product-level objects needed for scenario testing.

Needed additions:

- `ScenarioSuite`
- `ScenarioCase`
- `AssertionDefinition`
- `PlaygroundExample` or equivalent scratch input artifact
- `PromptBranch` or equivalent candidate metadata
- `BuilderActionLog`
- `TrialSummary` for repeated-run variance
- `ReviewSummary` for curated failures and regressions
- `DecisionRecord` for ship, reject, or promote outcomes

Likely file additions:

- `scenarios/<suite>.json` or `scenarios/<suite>.yaml`
- per-prompt suite links in `prompt.json` or a new prompt metadata file
- local playground history under `var/forge/<session_id>/`
- review artifacts under `var/runs/<run_id>/`

`prompt.json` likely needs to expand beyond:

- purpose
- expected behavior
- success criteria

It should likely also hold:

- linked baseline prompt
- primary scenario suites
- prompt owner or audience metadata
- release notes summary
- builder-agent defaults such as model, permission mode, and research policy

## Runtime updates needed

### Evaluation pipeline

Add support for:

- scenario suite selection
- assertions attached to cases or suites
- playground-run execution for ad hoc inputs
- repeated trial execution
- baseline vs candidate reporting as a first-class path

### Artifact model

Current artifacts are useful but not optimized for fast product review.

Add:

- assertion-level result summaries
- variance summaries
- case-level output diffs
- review-friendly regression ranking
- prompt-diff-to-regression correlation summaries
- decision artifacts for promotion and rejection

### Scoring model

The scoring layer should keep deterministic plus rubric scoring, but expose the
results in test language:

- passed assertions
- failed assertions
- regressions
- flaky or unstable cases

That language is better for product decisions than one blended score alone.

The scoring and review layers should also be able to answer:

- which prompt changes most likely affected this case
- whether the regression is widespread or isolated
- whether the candidate is improving average score by trading away stability

## App and helper updates needed

### macOS app

Update the app shell to:

- replace `Overview` / `Editor` segmentation with `Studio` / `Tests` /
  `Review`
- reduce dashboard density
- make Run Review a dedicated surface
- make scenario authoring first-class rather than implicit through datasets
- add a Studio playground
- surface builder-agent action history and permissions
- add explicit promotion and rejection actions in Review

### Helper RPC

Add helper methods for:

- listing scenario suites
- loading and saving scenario definitions
- running spot checks on selected scenarios
- running playground trials
- running repeated trials
- opening structured review results
- exposing builder-agent tool actions and permissions
- recording promotion decisions

### CLI

Keep the CLI for batch and CI use, but update its mental model to include:

- scenario suites as first-class inputs
- test-style output
- branch or baseline-aware compare flows
- repeated trial controls
- review and promotion metadata where appropriate

Possible commands:

- `pf scenario list`
- `pf scenario run --suite core --prompt v2`
- `pf test --prompt v2 --suite support-core`
- `pf review --run <run_id>`
- `pf playground --prompt v2`
- `pf promote --prompt v2 --from-branch draft-a`

## Documentation and positioning updates needed

The product language should shift from "prompt engineering workbench" to
"prompt development environment" or "prompt IDE."

Update:

- `README.md` positioning and hero language
- docs reading path for product and design intent
- onboarding copy in the macOS app
- benchmark terminology to scenario-test terminology where appropriate
- builder-agent terminology so it is clear when the system is chatting, editing,
  researching, or evaluating

Suggested positioning line:

PromptForge is a macOS-first prompt IDE where you co-author prompts with an
agent and validate changes with repeatable scenario tests.

## Phased rollout

### Phase 1: Reposition and simplify

- tighten product language
- simplify app navigation
- turn the current editor into Studio
- move benchmark review into a dedicated review flow
- add the playground and explicit builder-agent action visibility

### Phase 2: Scenario tests

- add scenario suite files and editor
- add assertions
- add suite-aware runs
- add suite bootstrapping from examples, failures, and transcripts

### Phase 3: Variance and promotion

- add repeated trials
- show stability and spread metrics
- add candidate promotion to baseline
- add decision records and diff-to-regression explanations

## Success metrics

- time from prompt change to validated decision
- percentage of prompt changes evaluated against a suite before shipping
- number of regressions caught before release
- number of scenario suites created per active prompt
- repeat-run stability for critical prompts
- percentage of prompt changes that go through explicit review and ship decision
- percentage of new scenario cases created from playground or failure-review flows

## Open questions

- Should scenario suites be stored separately from datasets or compiled into
  datasets at runtime?
- Should prompt branches live as full prompt-pack clones or as lighter-weight
  workspace revisions until promoted?
- Which assertions should be deterministic-only in v1 of scenario testing?
- How much external research should the builder agent be allowed to do by
  default?
- How should PromptForge attribute likely regressions back to specific prompt
  edits without over-claiming causality?
- Which builder-agent permissions should be default-on versus opt-in?

## Bottom line

PromptForge should not be sold primarily as "a tool that runs prompt
benchmarks."

It should be built and described as:

- an agent-assisted prompt authoring environment
- with scenario tests that behave like prompt behavior tests
- and a review flow designed for shipping decisions
