# Agents

This repository bootstraps a fresh VPS with [Claude Code](https://code.claude.com/docs) and a set of custom **subagents**. This document is a practical reference for what subagents are, how their definition files are structured, and how the "Scout" research-agent pattern works. It is written against the official Anthropic documentation; see [Sources](#sources).

## What subagents are

Subagents are specialized AI assistants that Claude Code can delegate focused subtasks to. Each subagent **runs in its own context window** with its **own system prompt**, its **own tool access**, and independent permissions. When Claude encounters a task that matches a subagent's `description`, it can delegate that task; the subagent works independently and returns only its final message to the main conversation.

They are worth using because they:

- **Preserve context** — exploration, searching, test output, and log noise stay in the subagent's window. Only the summary returns to your main conversation.
- **Enforce constraints** — you can restrict which tools a subagent may use.
- **Reuse configurations** — user-level subagents are available across every project on the machine.
- **Specialize behavior** — a focused system prompt tunes the agent for one domain.
- **Control cost/latency** — route cheap, high-volume work to a faster model such as Haiku.

Claude Code ships several **built-in subagents** that it uses automatically when appropriate: **Explore** (fast, read-only codebase search on Haiku), **Plan** (read-only research used in plan mode), and **general-purpose** (all tools; complex multi-step work). A key constraint: **subagents cannot spawn other subagents** — for nested delegation, chain subagents from the main conversation instead.

## Subagent definition file format

A subagent is a **Markdown file with YAML frontmatter**. The frontmatter is configuration; the Markdown body **is the agent's system prompt**. Subagents receive only this prompt plus basic environment details (such as the working directory) — not the full Claude Code system prompt.

```markdown
---
name: code-reviewer
description: Reviews code for quality and best practices
tools: Read, Glob, Grep
model: sonnet
---

You are a code reviewer. When invoked, analyze the code and provide
specific, actionable feedback on quality, security, and best practices.
```

### Where files live, and precedence

Subagent files are discovered from several locations. When two subagents share the same `name`, the **higher-priority** location wins:

| Location | Scope | Priority |
| :--- | :--- | :--- |
| Managed settings (`.claude/agents/` in the managed-settings dir) | Organization-wide | 1 (highest) |
| `--agents` CLI flag (JSON, session only) | Current session | 2 |
| `.claude/agents/` | Current project | 3 |
| `~/.claude/agents/` | All your projects (user-level) | 4 |
| A plugin's `agents/` directory | Where the plugin is enabled | 5 (lowest) |

- **User-level** (`~/.claude/agents/`) — personal agents available in every project. **This is where a VPS bootstrap should install shared agents** (see [VPS bootstrap](#how-this-maps-to-a-vps-bootstrap)).
- **Project-level** (`.claude/agents/`) — codebase-specific agents; check them into version control so the team shares them. Discovered by walking up from the working directory.

Both `.claude/agents/` and `~/.claude/agents/` are scanned **recursively**, so you may organize files into subfolders (e.g. `agents/research/`). The subfolder does **not** affect identity — identity comes only from the `name` field — so keep `name` values unique across the whole tree.

> Note: subagent files are loaded **at session start**. If you add or edit a file directly on disk, restart the Claude Code session to pick it up. (Agents created through the `/agents` UI take effect immediately.)

### Frontmatter fields

Only `name` and `description` are required.

| Field | Required | Meaning |
| :--- | :--- | :--- |
| `name` | **Yes** | Unique identifier, lowercase letters and hyphens. The filename does not have to match. |
| `description` | **Yes** | Tells Claude **when to delegate** to this subagent. This is what drives automatic delegation, so make it specific. |
| `tools` | No | Allowlist of tools the subagent may use. **If omitted, the subagent inherits all tools** available to the main conversation. |
| `model` | No | `sonnet`, `opus`, `haiku`, `fable`, a full model ID (e.g. `claude-opus-4-8`), or `inherit`. **Defaults to `inherit`** (same model as the main conversation). |
| `color` | No | Display color in the task list / transcript. One of `red`, `blue`, `green`, `yellow`, `purple`, `orange`, `pink`, `cyan`. |

The docs also support these optional fields: `disallowedTools` (denylist), `permissionMode`, `maxTurns`, `skills` (preload skill content), `mcpServers`, `hooks`, `memory` (`user`/`project`/`local` persistent memory directory), `background`, `effort` (`low`/`medium`/`high`/`xhigh`/`max` reasoning effort for the agent), `isolation` (`worktree`), and `initialPrompt`.

> On the `effort` field: some agent setups add `effort` to bias an agent toward deeper or cheaper reasoning. It overrides the session effort level while the agent is active (but is itself overridden by the `CLAUDE_CODE_EFFORT_LEVEL` environment variable). Available levels depend on the model.

### Choosing a model

`model` resolves in this order: the `CLAUDE_CODE_SUBAGENT_MODEL` env var (if set) → a per-invocation `model` parameter → the definition's `model` frontmatter → the main conversation's model. On the Anthropic API, the `opus` alias currently resolves to **Opus 4.8** and `sonnet` to **Sonnet 4.6**; pin a version with a full ID such as `claude-opus-4-8` when you need determinism.

## How subagents are invoked

**Automatic / proactive delegation.** Claude decides when to delegate based on your request, the current context, and each subagent's `description`. To encourage proactive use, include a phrase like **"use proactively"** (or "Use immediately after…") in the `description`.

**Explicit invocation.** Three patterns, escalating in force:

- **Natural language** — name the agent in your prompt; Claude usually delegates: `Use the scout subagent to research X`. Claude still writes the actual task prompt the subagent receives.
- **@-mention** — type `@` and pick the agent (or `@agent-<name>`). This *guarantees* that specific agent runs for the task.
- **Session-wide** — `claude --agent <name>` (or the `agent` setting in `.claude/settings.json`) makes the whole session adopt that agent's system prompt, tools, and model.

**The `/agents` command.** Running `/agents` opens a tabbed manager: a **Running** tab (view/stop live subagents) and a **Library** tab (view all built-in/user/project/plugin agents, create new ones with guided setup or Claude-generated config, edit configuration and tool access, and delete custom agents). This is the recommended way to create and manage agents interactively. You can also disable a specific agent via `permissions.deny` using `Agent(<name>)`.

## Tool access

The `tools` field is an **allowlist**: list the tools and the subagent can use only those. **Omit `tools` entirely and the subagent inherits every tool** available to the main conversation (including MCP tools). Use `disallowedTools` for the inverse — inherit everything *except* a few. If both are set, `disallowedTools` is applied first, then `tools` resolves against what remains.

A few tools depend on the interactive session and are **never** available to subagents even if listed (e.g. `Agent`, `AskUserQuestion`, the plan-mode entry/exit tools). Because subagents can't spawn subagents, listing `Agent` in a subagent's `tools` has no effect.

Common tool combinations from the docs:

| Use case | Tools |
| :--- | :--- |
| Read-only analysis | `Read, Grep, Glob` |
| Test execution | `Bash, Read, Grep` |
| Code modification | `Read, Edit, Write, Grep, Glob` |
| Full access | omit `tools` (inherits all) |

## The Scout / research-agent pattern

A research agent is a read-and-search specialist whose job is to gather information in an isolated context and return a tight, source-attributed summary — keeping dozens of fetched pages out of the main conversation. Anthropic's own SDK docs describe exactly this with a `research-assistant` example: it "can explore dozens of files without any of that content accumulating in the main conversation … The parent receives a concise summary, not every file the subagent read." The main subagents docs use the same shape under the name `safe-researcher`, configured with `tools: Read, Grep, Glob, Bash`.

For a VPS that does **internet** research, give the agent web tools in addition to the local read/search tools. The [`scout.md`](./scout.md) definition shipped in this folder follows exactly this pattern:

```markdown
---
name: scout
description: >-
  Research and search specialist. Use Scout whenever a task requires finding
  information on the internet, downloading and reading documents, or gathering
  and synthesizing source material. Give Scout a clear research brief: the
  question, scope, and the desired output format.
tools: WebSearch, WebFetch, Read, Bash, Glob, Grep
model: opus[1m]
effort: max
color: cyan
---

You are Scout, a research subagent specializing in internet search and
document analysis. Find information, verify it across independent sources,
and return well-organized, source-attributed findings.
```

Notes on this configuration:

- `WebSearch` is for discovery (returns titles + URLs); `WebFetch` reads a specific page and answers a prompt against it. `Read`, `Glob`, and `Grep` cover local files; `Bash` lets Scout download/convert documents (e.g. `curl`, `pdftotext`, `pandoc`) when needed. Notably absent are `Edit` and `Write`, which keeps the agent read-only by construction.
- `model: opus[1m]` gives Scout a 1M-token context window for large research sweeps, and `effort: max` biases it toward thorough synthesis. Drop to `sonnet`/`inherit` for cheaper, lighter research.

### Writing a good research brief

Because a subagent starts with a **fresh context** — it does not see the parent conversation's history, prior tool results, or files already read — the **delegation prompt is the only channel** of information to it. A good brief therefore states everything the agent needs:

1. **Question** — the specific core question(s) to answer, with any necessary background facts, file paths, or URLs included inline.
2. **Scope & constraints** — what's in and out of scope; which sources to prefer or avoid; how far to dig; any recency requirement.
3. **Desired output format** — the exact shape you want back (e.g. "a Markdown table", "bullet list with one source per claim", "lead with the direct answer"). The parent receives the subagent's final message verbatim, so specifying format pays off directly.

**Best practices (from the official docs):** design focused agents that excel at one task; write detailed `description`s so delegation triggers correctly; grant only the tools the agent needs; and check project agents into version control. For high-volume work ("run the test suite and report only failures"), delegate so the noise stays out of the main context. For independent investigations, spawn several research agents in parallel and let Claude synthesize — though remember each returned summary still consumes main-context tokens.

## How this maps to a VPS bootstrap

To make custom agents available **immediately** on a freshly provisioned machine, install their definition files into the **user-level** directory `~/.claude/agents/`. Because that scope applies to every project on the machine, no per-repo setup is needed.

A bootstrap script (e.g. the repo's [`setup.sh`](../setup.sh)) should:

1. **Create the directory:** `mkdir -p ~/.claude/agents`
2. **Copy the agent `.md` files** from this repo into it, e.g. `install -m 0644 agents/*.md ~/.claude/agents/` (or `cp`). Subfolders are fine — the tree is scanned recursively and identity comes from each file's `name`.
3. **Keep `name` values unique** across all installed files, since duplicate names within one scope are silently de-duplicated.
4. **Start a fresh session.** Files added directly to disk are loaded at session start, so the agents are active the next time `claude` launches.

After this, the agents are usable everywhere on the box: by automatic delegation, by name, by `@agent-<name>`, or session-wide via `claude --agent <name>`. To verify, run `/agents` and confirm they appear under the user scope in the Library tab.

## Sources

- [Create custom subagents — Claude Code Docs](https://code.claude.com/docs/en/sub-agents)
- [Subagents in the SDK — Claude Agent SDK Docs](https://code.claude.com/docs/en/agent-sdk/subagents)
- [Model configuration — Claude Code Docs](https://code.claude.com/docs/en/model-config)
</content>
</invoke>
