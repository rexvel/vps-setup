# vps-agents-setup

Bootstrap a fresh **Ubuntu** or **macOS** machine into a ready-to-use AI-agent
workstation. One interactive script installs the core tooling — **Claude Code**,
**Hermes Agent**, and the **GitHub CLI** — applies a known-good Claude Code
configuration, and ships custom **subagents** you can drop into `~/.claude/agents/`.

## Repository structure

```
vps-agents-setup/
├── README.md          # this file
├── setup.sh           # interactive cross-platform bootstrap installer
├── agents/
│   ├── README.md      # reference: Claude Code subagents + the Scout pattern
│   ├── scout.md       # Scout — a web-research subagent definition
│   └── surfer.md      # Surfer — an interactive web-browsing subagent (agent-browser)
├── commands/          # custom slash commands → ~/.claude/commands/
│   ├── todo-convert.md
│   ├── send-to-notion.md
│   └── list-commands.md
└── scripts/           # helper scripts for commands → ~/.claude/scripts/
    └── list-commands.sh
```

## Quick start

```bash
git clone git@github.com:rexvel/vps-setup.git vps-agents-setup
cd vps-agents-setup
./setup.sh
```

The script first asks (via a whiptail TUI) whether you're on **Ubuntu** or
**macOS**, then drives the rest of the flow accordingly. Re-running is safe —
anything already installed is detected and skipped.

## What `setup.sh` does

| Stage | Action |
| :--- | :--- |
| **OS selection** | whiptail menu (Ubuntu / macOS), with a plain-text `select` fallback. The choice drives every package-manager decision. |
| **Prerequisites** | Ensures `curl` and `jq`; on macOS, offers to install Homebrew (needed for `gh`). |
| **Claude Code** | Official installer — `curl -fsSL https://claude.ai/install.sh \| bash`. |
| **Hermes Agent** | [Nous Research](https://hermes-agent.org/) installer (`uv` + Python 3.11; no sudo). |
| **GitHub CLI** | apt repository on Ubuntu, `brew install gh` on macOS. |
| **Bun** | Installs Bun (`bun.sh`) and symlinks it into `/usr/local/bin` — the runtime some plugin MCP channel servers (e.g. the official Telegram plugin) need to launch. |
| **agent-browser** | Installs [Vercel's agent-browser](https://github.com/vercel-labs/agent-browser) (browser-automation CLI for AI agents, symlinked into `/usr/local/bin`) and downloads its Chrome for Testing. |
| **agent-browser config** | Persistent browser profile (`~/.agent-browser/profiles/default` — logins survive sessions/reboots), stable downloads dir, pinned daemon socket dir (`/etc/profile.d/agent-browser.sh`), and the `agent-browser-headful` Xvfb toggle for bot-walls. The proxy knob lives in `~/.agent-browser/config.json`. |
| **Claude config** | Merges `~/.claude/settings.json` (model `opus[1m]`, dark theme, custom statusline, `Bash(agent-browser:*)` allow-rule), installs the statusline script, registers the local `memory` MCP server, adds the official plugin marketplace + the agent-browser skill, syncs `agents/*.md` into `~/.claude/agents/`, installs curated **Agent Skills** via the [`skills`](https://skills.sh) CLI (currently `setup-pre-commit`), and syncs `commands/*.md` + `scripts/*.sh` into `~/.claude/commands/` and `~/.claude/scripts/`. |

It finishes with a summary of resolved tool paths/versions and next-step hints
(`claude`, `hermes setup`, `gh auth login`).

> **Idempotent & merge-safe:** existing tools are skipped, and `settings.json`
> is deep-merged with `jq` so your other keys are preserved.

## Agents

The [`agents/`](./agents) folder holds custom Claude Code **subagent**
definitions plus a full reference doc. Currently shipped:

- **[`scout.md`](./agents/scout.md)** — *Scout*, a research & search specialist
  (`WebSearch, WebFetch, Read, Bash, Glob, Grep`; `model: opus[1m]`, `effort: max`).
  Hand it a research brief and it gathers, verifies, and returns
  source-attributed findings without touching code or system state.
- **[`surfer.md`](./agents/surfer.md)** — *Surfer*, an interactive web-browsing
  specialist (`Bash, Read`; `model: opus[1m]`, `effort: max`). Drives a real
  persistent headless Chrome via the `agent-browser` CLI: logins, forms,
  multi-step flows, screenshots, JS-rendered extraction. Prefer Scout for plain
  fetch-and-read; pick Surfer when the task needs interaction, authentication,
  or real rendering.

`setup.sh` installs these automatically (`sync_agents`, skipping `README.md`).
To sync them by hand instead:

```bash
mkdir -p ~/.claude/agents
cp agents/scout.md agents/surfer.md ~/.claude/agents/
```

See [`agents/README.md`](./agents/README.md) for the subagent file format,
frontmatter fields, invocation methods, and the Scout research-agent pattern in
depth — all grounded in the official Claude Code documentation.

## Skills

`setup.sh` also installs curated **Agent Skills** through the
[`skills`](https://skills.sh) CLI (`configure_skills`). Each skill is fetched
from its source repository into `~/.agents/skills/<name>` and symlinked into
`~/.claude/skills/<name>`, where Claude Code loads it on the next session.
Currently shipped:

- **`setup-pre-commit`** ([mattpocock/skills](https://github.com/mattpocock/skills/blob/main/skills/misc/setup-pre-commit/SKILL.md))
  — set up Husky pre-commit hooks with lint-staged (Prettier), type-checking and
  tests in the current repo.

The install is idempotent (a skill already present in `~/.claude/skills/` is
skipped). To add more, append `"<owner>/<repo> <skill-name>"` lines to the
`skills_spec` array in `configure_skills`. To install one by hand:

```bash
npx skills@latest add mattpocock/skills --skill setup-pre-commit --agent claude-code --global --yes
```

## Commands

`setup.sh` syncs custom **slash commands** (`sync_commands`) from
[`commands/`](./commands) into `~/.claude/commands/`, plus any helper scripts
from [`scripts/`](./scripts) into `~/.claude/scripts/` (commands load at the next
Claude session start). Currently shipped:

- **`/todo-convert <text>`** — grills you about a task via the `grill-me` skill,
  then converts it into a structured, checkable todo-list and offers to save it
  to Notion.
- **`/send-to-notion <text>`** — saves the given text/data to a new Notion page
  (auto-titled), no confirmation prompt.
- **`/list-commands`** — lists custom commands + personal skills (runs
  `scripts/list-commands.sh`); plugin/built-in commands stay under `/help`.

To sync them by hand instead:

```bash
mkdir -p ~/.claude/commands ~/.claude/scripts
cp commands/*.md ~/.claude/commands/
cp scripts/*.sh  ~/.claude/scripts/
```

> The `/todo-convert` and `/send-to-notion` commands use the **Notion**
> connector, which syncs from your claude.ai account (`/mcp` to authenticate).

## Requirements

- A fresh **Ubuntu/Debian** or **macOS** machine with `sudo` (Ubuntu) access.
- Network access (the installers fetch from the internet).
- `whiptail` is used for the OS menu when present; otherwise a text prompt is used.

## Notes

- **Account integrations** (Figma, Notion, Gmail, Google Drive/Calendar,
  Atlassian) are *not* scripted — they sync from your claude.ai account once you
  sign in. After `claude` launches, run `/mcp` to authenticate them.
- The `memory` MCP server requires Node.js/`npx` at runtime.
</content>
