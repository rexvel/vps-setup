---
description: Rewrite a rough prompt into a high-quality one that gets better results from Claude — adds a clear task, role, context, explicit output format, and success criteria, structured with the CRAFT framework. Auto-gathers repo context (git state, relevant files, diagnostics) for coding prompts. Outputs the improved prompt only; it does not run it. Use when the user wants to improve, sharpen, or "enhance" a prompt, or invokes /prompt-enhance with prompt text.
argument-hint: "[--framework craft|co-star|rtf|risen] [--ask] <your rough prompt>"
allowed-tools: Read, Grep, Glob, Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*)
---

Take the user's rough prompt and rewrite it into a higher-quality prompt that gets better results from Claude. The raw prompt is in `$ARGUMENTS`. **Output the improved prompt only — never execute it.** If `$ARGUMENTS` is empty, ask the user to paste the prompt they want enhanced, then stop and wait.

Bias toward restraint. Only add what genuinely raises quality. Do **not** bloat an already-clear prompt, and never inject unrequested checklists (security, testing, self-critique) the user did not ask for. A clear prompt may need only small edits — say so and keep it light.

## 1. Parse flags and triage

Strip any leading flags from the prompt text before rewriting:

- `--framework craft|co-star|rtf|risen` — force a specific structure (default is **CRAFT**).
- `--ask` — force the clarify step even if the prompt looks clear.

Classify the remaining prompt: is the user trying to **generate** a prompt from a bare task, or **improve** an existing one? What is the task type — **coding/repo work**, content/copy, analysis, or extraction? How complex is it?

## 2. Gather context (coding/repo prompts only)

If the prompt is about this codebase (modifying/reviewing/debugging code, anything referencing files, features, or the repo), gather concrete context **before** rewriting so the enhanced prompt is self-contained. Pull only what is relevant to the ask:

- `git status` and `git branch --show-current` — what's in flight and where.
- `git diff` (or `git diff` against the base branch) for the files the prompt touches.
- `git log --oneline -10` for recent direction.
- Use Grep/Glob/Read to locate and quote the specific files, functions, or symbols the prompt names.
- Any error text or diagnostics the user pasted.

Fold this into the rewritten prompt's **Context** section as concrete facts (file paths, current behavior, relevant snippets) — do **not** dump the whole repo. For non-coding prompts, skip this step. Prefer resolving missing context from the repo over asking the user.

## 3. Clarify only if genuinely underspecified

If, after gathering repo context, the prompt is still missing something you cannot infer — the goal, audience, key constraints, or target output format — ask **1–3** targeted questions and wait for answers. Never ask more than 3, and never interrogate a prompt that is already clear (unless `--ask` was passed).

## 4. Diagnose the gaps

Scan the prompt for these anti-patterns; note which are present and which are high-impact:

- vague task with no concrete requirements
- no output format specified
- missing context / audience / required expertise level
- conflicting or mutually exclusive instructions ("be brief" + "explain everything")
- implicit or absent success criteria
- no examples for a format- or tone-sensitive task
- multiple unrelated tasks crammed together
- undefined jargon or abbreviations
- no reasoning requested for a genuinely complex task

## 5. Preserve the user's intent

Carry through unchanged: the original ask, any concrete details, any constants/rubrics, and any `{{variables}}` or placeholders. Do not silently change what the prompt is asking for.

## 6. Rewrite using CRAFT

Default to the **CRAFT** structure for every prompt unless `--framework` overrides it:

- **Context** — background, purpose, and (for coding prompts) the repo facts gathered in step 2.
- **Role** — the persona/expertise Claude should adopt (only when it matters).
- **Action** — the single, plainly-stated task.
- **Format** — the precise output shape: length and syntax (JSON / Markdown / bullets / code), plus the **success criteria** (what a good answer looks like).
- **Tone** — only when tone matters.

Override structures when `--framework` is passed: **CO-STAR** (Context, Objective, Style, Tone, Audience, Response) for tone-sensitive copy; **RTF** (Role, Task, Format) for quick low-stakes asks; **RISEN** (Role, Instructions, Steps, End goal, Narrowing) for multi-step procedural work.

Apply fixes in priority order: **clarity → role → context → explicit format + success criteria → structure → examples → step-by-step reasoning.** Add examples only when format/tone is hard to convey in words (and have them reason before they conclude). Add an explicit "think step-by-step" / `<analysis>` step only for complex, multi-step, or debugging tasks. Resolve conflicting instructions, define jargon, and split genuinely unrelated tasks. Fence the CRAFT sections with markdown headers or XML tags (`<context>`, `<task>`, `<constraints>`) so they're clearly separated.

## 7. Self-check, then present

Before presenting, verify: single clear task; role only if it matters; context present; explicit output format; success criteria stated; no conflicts; examples and chain-of-thought present only where warranted; original intent and all `{{variables}}` preserved. Trim anything that doesn't earn its place.

Then output the enhanced prompt **inside a fenced code block** so it's copy-pasteable. Below the block, add one or two lines naming the framework used and the key changes you made (e.g. "Framework: CRAFT. Added the missing output format and success criteria, pinned a reviewer role, and folded in the diff for `auth.ts`."). **Do not run the prompt** — this command only produces the improved text for the user to use wherever they want.
