#!/usr/bin/env bash
#
# setup.sh — bootstrap a dev machine with Claude Code, Hermes Agent and GitHub CLI.
#
# The script first asks which operating system you're on (Ubuntu or macOS) via a
# whiptail TUI menu, then drives the rest of the install flow accordingly.
#
# Re-running is safe: tools already on your PATH are skipped.

set -euo pipefail

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  C_RESET="$(printf '\033[0m')"
  C_BLUE="$(printf '\033[1;34m')"
  C_YELLOW="$(printf '\033[1;33m')"
  C_RED="$(printf '\033[1;31m')"
  C_GREEN="$(printf '\033[1;32m')"
else
  C_RESET="" C_BLUE="" C_YELLOW="" C_RED="" C_GREEN=""
fi

info()    { printf '%s==>%s %s\n'  "$C_BLUE"   "$C_RESET" "$*"; }
warn()    { printf '%sWARN:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
error()   { printf '%sERROR:%s %s\n' "$C_RED"   "$C_RESET" "$*" >&2; }
success() { printf '%s✓%s %s\n'     "$C_GREEN"  "$C_RESET" "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

# Global set by select_os(): "ubuntu" or "macos"
OS=""

# Absolute path to this repo (for installing agents/ into ~/.claude/agents).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Step 1 — OS selection (runs before any install)
# ---------------------------------------------------------------------------
select_os() {
  # Sensible default based on the running kernel; user still confirms.
  local default="ubuntu"
  case "$(uname -s)" in
    Darwin) default="macos" ;;
    Linux)  default="ubuntu" ;;
  esac

  if have whiptail; then
    # whiptail prints the chosen tag to stderr by convention; swap fds so we
    # can capture it from stdout.
    local choice
    if choice="$(whiptail --title "Setup — Operating System" \
        --menu "Select your operating system to continue:" 12 60 2 \
        "ubuntu" "Ubuntu / Debian" \
        "macos"  "macOS" \
        --default-item "$default" \
        3>&1 1>&2 2>&3)"; then
      OS="$choice"
    else
      error "OS selection cancelled. Aborting."
      exit 1
    fi
  else
    # Plain fallback when whiptail is unavailable.
    warn "whiptail not found — falling back to a text menu."
    PS3="Select your operating system (number): "
    select opt in "Ubuntu / Debian" "macOS"; do
      case "$opt" in
        "Ubuntu / Debian") OS="ubuntu"; break ;;
        "macOS")           OS="macos";  break ;;
        *) echo "Please choose 1 or 2." ;;
      esac
    done
  fi

  [ -n "$OS" ] || { error "No OS selected. Aborting."; exit 1; }
  info "Operating system set to: ${C_GREEN}${OS}${C_RESET}"
}

# ---------------------------------------------------------------------------
# Step 2 — pre-flight (OS-aware prerequisites)
# ---------------------------------------------------------------------------
preflight() {
  info "Checking prerequisites..."

  # curl is needed by both the Claude and Hermes installers.
  if ! have curl; then
    if [ "$OS" = "ubuntu" ]; then
      info "Installing curl via apt..."
      sudo apt-get update && sudo apt-get install -y curl
    else
      error "curl is required but not found, and is normally pre-installed on macOS."
      exit 1
    fi
  fi
  success "curl present."

  # jq is needed to merge ~/.claude/settings.json and is used by the statusline.
  if ! have jq; then
    info "Installing jq..."
    if [ "$OS" = "ubuntu" ]; then
      sudo apt-get update && sudo apt-get install -y jq
    elif have brew; then
      brew install jq
    else
      warn "jq not found and Homebrew unavailable — Claude Code config steps will be skipped."
    fi
  fi
  have jq && success "jq present."

  # Homebrew is required for 'gh' on macOS.
  if [ "$OS" = "macos" ] && ! have brew; then
    warn "Homebrew not found — it's required to install the GitHub CLI on macOS."
    read -r -p "Install Homebrew now? [y/N] " reply
    case "$reply" in
      [yY]*)
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        ;;
      *)
        warn "Skipping Homebrew — 'gh' installation will be skipped on macOS."
        ;;
    esac
  fi
}

# ---------------------------------------------------------------------------
# Step 3 — install functions (each is idempotent)
# ---------------------------------------------------------------------------
install_claude() {
  info "Installing Claude Code..."
  if have claude; then
    success "Claude Code already installed — skipping."
    return 0
  fi
  curl -fsSL https://claude.ai/install.sh | bash
  success "Claude Code installer finished."
}

install_hermes() {
  info "Installing Hermes Agent..."
  if have hermes; then
    success "Hermes already installed — skipping."
    return 0
  fi
  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
  success "Hermes installer finished."
}

install_bun() {
  # Bun is the runtime for plugin MCP channel servers (e.g. the official
  # telegram plugin) — without it those servers silently fail to launch.
  info "Installing Bun..."
  if have bun; then
    success "Bun already installed — skipping."
    return 0
  fi
  curl -fsSL https://bun.sh/install | bash
  # The installer puts bun in ~/.bun/bin and only edits shell rc files; link it
  # into /usr/local/bin so non-interactive processes (MCP launches) find it too.
  if [ -x "$HOME/.bun/bin/bun" ] && [ -w /usr/local/bin ]; then
    ln -sf "$HOME/.bun/bin/bun" /usr/local/bin/bun
  fi
  success "Bun installer finished."
}

install_agent_browser() {
  # agent-browser (vercel-labs) drives a real headless Chrome for AI agents:
  # the browsing backend for the 'surfer' subagent (and usable by Hermes).
  info "Installing agent-browser (browser automation CLI)..."
  if ! have npm; then
    warn "npm not found — skipping agent-browser install."
    return 0
  fi
  if have agent-browser; then
    success "agent-browser already installed — skipping ($(agent-browser --version 2>/dev/null || echo 'version n/a'))."
  else
    # engines.node declares >=24; on Node 22 npm prints an EBADENGINE warning
    # that is safe to ignore — the runtime is a native Rust binary, not Node.
    npm install -g agent-browser
    # npm's global bin dir (e.g. ~/.hermes/node/bin) is not on PATH for
    # non-interactive processes; link into /usr/local/bin like we do for bun.
    local bin; bin="$(npm prefix -g)/bin/agent-browser"
    if [ -x "$bin" ] && [ -w /usr/local/bin ]; then
      ln -sf "$bin" /usr/local/bin/agent-browser
    fi
    success "agent-browser installed ($(agent-browser --version 2>/dev/null || echo 'version n/a'))."
  fi
  # One-time Chrome for Testing download (lands in ~/.agent-browser/browsers/;
  # agent-browser does NOT reuse the Playwright browser cache).
  if ls "$HOME/.agent-browser/browsers"/chrome-*/ >/dev/null 2>&1; then
    success "agent-browser Chrome already downloaded — skipping."
  else
    info "Downloading Chrome for Testing (one-time, ~180 MB)..."
    if [ "$OS" = "ubuntu" ]; then
      agent-browser install --with-deps
    else
      agent-browser install
    fi
    success "Chrome for Testing downloaded."
  fi
}

# Helper to flip the browser between headless (default) and headful-under-Xvfb
# — the escalation rung for sites that block headless fingerprints.
install_headful_toggle() {
  # Xvfb is Linux-only; on macOS a headed browser can run natively when needed.
  [ "$OS" = "ubuntu" ] || return 0
  local dst=/usr/local/bin/agent-browser-headful
  if ! [ -w /usr/local/bin ]; then
    warn "/usr/local/bin not writable — skipping headful toggle install."
    return 0
  fi
  cat > "$dst" <<'HEADFUL_EOF'
#!/usr/bin/env bash
# Toggle agent-browser between headless (default) and headful-under-Xvfb.
# Headful is an escalation for bot-walls that sniff headless fingerprints;
# always toggle off afterwards (after a reboot Xvfb is gone and a headed
# config would make every launch fail).
set -euo pipefail
SOCK_DIR="${AGENT_BROWSER_SOCKET_DIR:-$HOME/.agent-browser/run}"
CFG="$HOME/.agent-browser/config.json"

stop_daemons() {
  # 'close' only closes the browser; the daemon must die too so the next
  # command respawns it with the new mode (and, for 'on', with DISPLAY set).
  agent-browser close --all >/dev/null 2>&1 || true
  local p
  for p in "$SOCK_DIR"/*.pid; do
    [ -f "$p" ] && kill "$(cat "$p")" 2>/dev/null || true
  done
  # Wait until Chrome releases the profile: a lingering/orphaned Chrome
  # holds SingletonLock and wedges (or gets hijacked by) the next launch.
  # The pattern is anchored to Chrome's argv[0] under ~/.agent-browser so it
  # can never match a bystander process that merely mentions these paths.
  local chrome_re="^$HOME/\.agent-browser/browsers/" i
  for i in $(seq 1 10); do
    pgrep -f "$chrome_re" >/dev/null 2>&1 || return 0
    sleep 0.5
  done
  pkill -f "$chrome_re" 2>/dev/null || true
  sleep 1
}

case "${1:-}" in
  on)
    command -v Xvfb >/dev/null 2>&1 || { echo "Xvfb not installed (apt-get install -y xvfb)"; exit 1; }
    # Detect a live :99 via its X11 socket — pgrep -f on "Xvfb :99" would
    # false-positive on any bystander process mentioning that string.
    if ! [ -S /tmp/.X11-unix/X99 ]; then
      Xvfb :99 -screen 0 1920x1080x24 >/dev/null 2>&1 &
      sleep 1
    fi
    [ -S /tmp/.X11-unix/X99 ] || { echo "Xvfb :99 failed to start"; exit 1; }
    stop_daemons
    tmp=$(mktemp); jq '.headed = true' "$CFG" > "$tmp" && mv "$tmp" "$CFG"
    # Warm the daemon WITH DISPLAY so every later command runs headed:
    DISPLAY=:99 agent-browser get title >/dev/null 2>&1 || true
    echo "headful ON (Xvfb :99). Run agent-browser normally; 'agent-browser-headful off' to restore."
    ;;
  off)
    stop_daemons
    tmp=$(mktemp); jq '.headed = false' "$CFG" > "$tmp" && mv "$tmp" "$CFG"
    # Anchored so it can only match a real Xvfb argv, never a bystander
    # process whose command line merely mentions the string.
    pkill -f '^Xvfb :99' 2>/dev/null || true
    echo "headless restored."
    ;;
  *)
    echo "usage: agent-browser-headful on|off"
    exit 1
    ;;
esac
HEADFUL_EOF
  chmod +x "$dst"
  success "Installed headful toggle → $dst"
}

# Durable agent-browser defaults: persistent profile (logins survive sessions
# and reboots — persistence is OPT-IN upstream) plus a stable downloads dir.
# The PROXY KNOB lives here too; when a site blocks the VPS IP, enable with:
#   tmp=$(mktemp); jq '.proxy="http://user:pass@host:port"' ~/.agent-browser/config.json > "$tmp" \
#     && mv "$tmp" ~/.agent-browser/config.json && agent-browser close
configure_agent_browser() {
  if ! have jq; then
    warn "jq missing — skipping agent-browser config."
    return 0
  fi
  local dir="$HOME/.agent-browser" cfg tmp desired
  cfg="$dir/config.json"
  mkdir -p "$dir/profiles/default" "$dir/downloads" "$dir/run"
  desired="$(jq -n --arg p "$dir/profiles/default" --arg d "$dir/downloads" \
    '{profile: $p, downloadPath: $d}')"
  tmp="$(mktemp)"
  if [ -f "$cfg" ]; then
    # Deep-merge; our desired keys win, user-added keys (proxy, headed) survive.
    jq -s '.[0] * .[1]' "$cfg" <(printf '%s' "$desired") > "$tmp"
  else
    printf '%s\n' "$desired" > "$tmp"
  fi
  mv "$tmp" "$cfg"
  success "Wrote $cfg (persistent profile, downloads dir)."

  # Pin the daemon socket dir: the default ($XDG_RUNTIME_DIR, /run/user/0) is
  # torn down on logout and absent in unattended sessions (Telegram-triggered
  # Claude runs), which orphans daemons and causes Chrome profile-lock
  # conflicts. A fixed dir under $HOME avoids all of it.
  if [ "$OS" = "ubuntu" ] && [ -w /etc/profile.d ]; then
    printf 'export AGENT_BROWSER_SOCKET_DIR="$HOME/.agent-browser/run"\n' \
      > /etc/profile.d/agent-browser.sh
    success "Pinned AGENT_BROWSER_SOCKET_DIR via /etc/profile.d/agent-browser.sh"
  fi

  install_headful_toggle
}

install_gh_ubuntu() {
  # Official GitHub CLI apt-repo install procedure.
  if ! have wget; then
    sudo apt-get update && sudo apt-get install -y wget
  fi
  sudo mkdir -p -m 755 /etc/apt/keyrings
  local tmp; tmp="$(mktemp)"
  wget -nv -O "$tmp" https://cli.github.com/packages/githubcli-archive-keyring.gpg
  sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg < "$tmp" >/dev/null
  rm -f "$tmp"
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  sudo mkdir -p -m 755 /etc/apt/sources.list.d
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y gh
}

install_gh() {
  info "Installing GitHub CLI (gh)..."
  if have gh; then
    success "GitHub CLI already installed — skipping."
    return 0
  fi
  case "$OS" in
    ubuntu)
      install_gh_ubuntu
      ;;
    macos)
      if have brew; then
        brew install gh
      else
        warn "Homebrew unavailable — skipping GitHub CLI install."
        return 0
      fi
      ;;
  esac
  success "GitHub CLI installer finished."
}

# ---------------------------------------------------------------------------
# Step 4 — Claude Code configuration (settings, statusline, MCP, plugins)
# ---------------------------------------------------------------------------
CLAUDE_DIR="$HOME/.claude"

# Install the custom status line script (renders user@host:cwd | ctx% | limits).
# Depends on jq + coreutils `date`, both standard.
install_statusline() {
  local sl="$CLAUDE_DIR/statusline-command.sh"
  mkdir -p "$CLAUDE_DIR"
  cat > "$sl" <<'STATUSLINE_EOF'
#!/bin/bash
# Claude Code status line.
# Renders: user@host:/cwd  | ctx NN%  | 5h NN% (reset HH:MM)  | 7d NN% (reset Ddmon)
# Usage-limit segments only appear when Claude Code provides them (subscriber + after first response).

input=$(cat)

# --- Pull every value we need in a single jq pass (tab-separated) ---
# Fields are read defensively: alternate key spellings are tried, missing -> empty.
IFS=$'\t' read -r cwd ctx_pct s5_pct s5_reset w7_pct w7_reset < <(
  printf '%s' "$input" | jq -r '
    # context window utilization
    def ctx:
      ( .context_window.used_percentage
        // ( if (.context_window.context_window_size // 0) > 0
             then ((.context_window.total_input_tokens + (.context_window.total_output_tokens // 0)) * 100
                   / .context_window.context_window_size)
             else empty end )
        // empty );
    [ (.cwd // .workspace.current_dir // empty),
      (ctx | if . == "" then "" else (.|floor|tostring) end),
      (.rate_limits.five_hour.used_percentage // empty | if . == "" then "" else (.|floor|tostring) end),
      (.rate_limits.five_hour.resets_at // empty),
      (.rate_limits.seven_day.used_percentage // empty | if . == "" then "" else (.|floor|tostring) end),
      (.rate_limits.seven_day.resets_at // empty)
    ] | @tsv
  '
)

[ -z "$cwd" ] && cwd=$(pwd)

# --- Colors ---
RST=$'\033[00m'
GRN=$'\033[01;32m'
BLU=$'\033[01;34m'
DIM=$'\033[02m'

# Pick a color for a percentage: green <50, yellow 50-79, red >=80.
pct_color() {
  local p=${1%%.*}
  if   [ "$p" -ge 80 ] 2>/dev/null; then printf '\033[01;31m'
  elif [ "$p" -ge 50 ] 2>/dev/null; then printf '\033[01;33m'
  else printf '\033[01;32m'
  fi
}

# Format a unix-epoch reset time, e.g. "14:30" or "Mon 09:00"; empty if no input.
reset_fmt() {
  local epoch=$1 fmt=$2
  [ -z "$epoch" ] && return
  date -d "@$epoch" +"$fmt" 2>/dev/null || date -r "$epoch" +"$fmt" 2>/dev/null
}

# --- Build line ---
line=$(printf '%s%s@%s%s:%s%s%s' "$GRN" "$(whoami)" "$(hostname -s)" "$RST" "$BLU" "$cwd" "$RST")

sep="${DIM} | ${RST}"

if [ -n "$ctx_pct" ]; then
  c=$(pct_color "$ctx_pct")
  line+="${sep}${DIM}ctx ${RST}${c}${ctx_pct}%${RST}"
fi

if [ -n "$s5_pct" ]; then
  c=$(pct_color "$s5_pct")
  r=$(reset_fmt "$s5_reset" "%H:%M")
  line+="${sep}${DIM}5h ${RST}${c}${s5_pct}%${RST}"
  [ -n "$r" ] && line+="${DIM} (↻${r})${RST}"
fi

if [ -n "$w7_pct" ]; then
  c=$(pct_color "$w7_pct")
  r=$(reset_fmt "$w7_reset" "%a")
  line+="${sep}${DIM}7d ${RST}${c}${w7_pct}%${RST}"
  [ -n "$r" ] && line+="${DIM} (↻${r})${RST}"
fi

printf '%s' "$line"
STATUSLINE_EOF
  chmod +x "$sl"
  success "Installed statusline → $sl"
}

# Merge our preferred settings into ~/.claude/settings.json without clobbering
# any other keys already present. Sets the SESSION MODEL (opus[1m] — Opus 4.8
# 1M context), the dark theme, and the statusLine command.
configure_settings() {
  if ! have jq; then
    warn "jq missing — skipping settings.json update."
    return 0
  fi
  local settings="$CLAUDE_DIR/settings.json" desired tmp
  mkdir -p "$CLAUDE_DIR"
  desired="$(jq -n --arg sl "bash $CLAUDE_DIR/statusline-command.sh" \
    '{theme:"dark", model:"opus[1m]", statusLine:{type:"command", command:$sl}}')"
  tmp="$(mktemp)"
  if [ -f "$settings" ]; then
    # Deep-merge; our desired keys win on conflict.
    jq -s '.[0] * .[1]' "$settings" <(printf '%s' "$desired") > "$tmp"
  else
    printf '%s' "$desired" > "$tmp"
  fi
  mv "$tmp" "$settings"
  success "Wrote $settings (model opus[1m], theme dark, statusLine)."
}

# Register the local 'memory' stdio MCP server (idempotent).
configure_mcp() {
  if ! have npx; then
    warn "npx (Node.js) not found — 'memory' MCP server will fail to launch until Node is installed."
  fi
  if claude mcp list 2>/dev/null | grep -q '^memory:'; then
    success "memory MCP server already configured — skipping."
  else
    info "Registering 'memory' MCP server (user scope)..."
    # MEMORY_FILE_PATH pins the knowledge-graph store to a stable path; without it
    # the data lands in npx's ephemeral package dir. --transport stdio sits between
    # --env and the server name (required by the arg parser).
    claude mcp add -s user --env MEMORY_FILE_PATH="$HOME/.claude/memory.jsonl" \
      --transport stdio memory -- npx -y @modelcontextprotocol/server-memory \
      && success "Registered 'memory' MCP server (store: $HOME/.claude/memory.jsonl)." \
      || warn "Could not register memory MCP server."
  fi
}

# Write the user-level CLAUDE.md memory nudge so Claude recalls/saves to the
# 'memory' knowledge-graph server (which does NOT auto-capture). Idempotent and
# non-destructive: creates the file if absent, appends the section if the file
# exists without it, and skips if already present.
configure_claude_md() {
  local md="$CLAUDE_DIR/CLAUDE.md"
  local marker='# Persistent memory (knowledge-graph MCP server `memory`)'
  mkdir -p "$CLAUDE_DIR"
  if [ -f "$md" ] && grep -qF "$marker" "$md"; then
    success "CLAUDE.md memory section already present — skipping."
    return 0
  fi
  # Leading newline so an append is cleanly separated from existing content.
  [ -f "$md" ] && printf '\n' >> "$md"
  cat >> "$md" <<'CLAUDE_MD_EOF'
# Persistent memory (knowledge-graph MCP server `memory`)

A local knowledge-graph memory server is available (tools: `read_graph`, `search_nodes`,
`open_nodes`, `create_entities`, `create_relations`, `add_observations`, plus the `delete_*`
tools). Data persists across sessions at `~/.claude/memory.jsonl`.

- **At the start of a session**, when prior context would help, recall first: call `search_nodes`
  for the relevant topic (or `read_graph` for a broad refresh) before asking me to repeat things.
- **When you learn a durable fact** — my preferences, project decisions, environment details,
  recurring commands, people/services I work with — save it: create/extend entities with
  `create_entities` / `add_observations` and link them with `create_relations`.
- Keep observations short and atomic (one fact each). Don't store secrets/tokens.
- This is for *cross-project, queryable* memory. For per-project working notes, the built-in
  auto-memory at `~/.claude/projects/<project>/memory/` still applies in parallel.
CLAUDE_MD_EOF
  success "Wrote CLAUDE.md memory section → $md"
}

# Register the official plugin marketplace (idempotent).
configure_plugins() {
  if claude plugin marketplace list 2>/dev/null | grep -q 'claude-plugins-official'; then
    success "Official plugin marketplace already registered — skipping."
  else
    info "Registering official plugin marketplace..."
    claude plugin marketplace add anthropics/claude-plugins-official \
      && success "Registered official plugin marketplace." \
      || warn "Could not register plugin marketplace."
  fi
  # To preinstall specific plugins, uncomment and adjust, e.g.:
  #   claude plugin install github@claude-plugins-official
  #   claude plugin install playwright@claude-plugins-official
}

# Allow agent-browser commands without per-command permission prompts (a
# prompt is effectively a denial in unattended Telegram-triggered sessions),
# and pin the daemon socket dir for Claude-spawned shells. The blast radius
# of the allow-rule is the browser + its profile — never arbitrary shell.
# NOTE: jq's '*' merge REPLACES arrays, so permissions.allow needs an
# explicit union to preserve user-added rules.
configure_permissions() {
  if ! have jq; then
    warn "jq missing — skipping permissions update."
    return 0
  fi
  local settings="$CLAUDE_DIR/settings.json" tmp
  mkdir -p "$CLAUDE_DIR"
  [ -f "$settings" ] || printf '{}\n' > "$settings"
  tmp="$(mktemp)"
  jq --arg sock "$HOME/.agent-browser/run" '
    .permissions.allow = ((.permissions.allow // [])
      + ["Bash(agent-browser:*)", "Bash(npx agent-browser:*)"] | unique)
    | .env.AGENT_BROWSER_SOCKET_DIR = $sock
  ' "$settings" > "$tmp" && mv "$tmp" "$settings"
  success "Allowed Bash(agent-browser:*) and pinned socket dir in $settings."
}

# Vercel's official agent-browser skill for Claude Code, via the plugin
# marketplace manifest shipped in vercel-labs/agent-browser. The skill itself
# is a thin stub; the live, version-synced command reference comes from
# `agent-browser skills get core`.
configure_agent_browser_skill() {
  if claude plugin list 2>/dev/null | grep -q 'agent-browser'; then
    success "agent-browser skill (plugin) already installed — skipping."
    return 0
  fi
  info "Installing agent-browser skill (plugin)..."
  claude plugin marketplace add vercel-labs/agent-browser >/dev/null 2>&1 || true
  claude plugin install agent-browser@agent-browser \
    && success "Installed agent-browser skill (plugin)." \
    || warn "Could not install agent-browser plugin. Manual alternative: npx skills add vercel-labs/agent-browser -g -a claude-code -y"
}

# Install curated Agent Skills via the 'skills' CLI (skills.sh). Each skill is
# fetched from its source repo into ~/.agents/skills/<name> and symlinked into
# ~/.claude/skills/<name>; it loads at the next Claude session. Idempotent: a
# skill already present in ~/.claude/skills/ is skipped (avoids a network call).
# To grow the set, add "<owner>/<repo> <skill-name>" lines to skills_spec.
configure_skills() {
  if ! have npx; then
    warn "npx (Node.js) not found — skipping Agent Skills install."
    return 0
  fi
  local skills_spec=(
    "mattpocock/skills setup-pre-commit"
  )
  local entry repo name
  for entry in "${skills_spec[@]}"; do
    read -r repo name <<<"$entry"
    if [ -e "$CLAUDE_DIR/skills/$name" ]; then
      success "Skill '$name' already installed — skipping."
      continue
    fi
    info "Installing skill '$name' from $repo (skills CLI)..."
    if npx -y skills@latest add "$repo" --skill "$name" --agent claude-code --global --yes >/dev/null 2>&1; then
      success "Installed skill → $CLAUDE_DIR/skills/$name"
    else
      warn "Could not install skill '$name' via skills CLI."
    fi
  done
}

# Install repo subagents (agents/*.md → ~/.claude/agents/). New or changed
# agents load at the next Claude session start.
sync_agents() {
  local src="$SCRIPT_DIR/agents" f name
  if ! [ -d "$src" ]; then
    warn "agents/ dir not found next to setup.sh — skipping agent sync."
    return 0
  fi
  mkdir -p "$CLAUDE_DIR/agents"
  for f in "$src"/*.md; do
    [ -e "$f" ] || continue
    name="$(basename "$f")"
    [ "$name" = "README.md" ] && continue
    install -m 0644 "$f" "$CLAUDE_DIR/agents/$name"
    success "Installed agent → $CLAUDE_DIR/agents/$name"
  done
}

configure_claude() {
  info "Configuring Claude Code..."
  if ! have claude; then
    warn "claude not on PATH yet — skipping config. Restart your shell and re-run this script to apply it."
    return 0
  fi
  install_statusline
  configure_settings
  configure_permissions
  configure_mcp
  configure_claude_md
  configure_plugins
  configure_agent_browser_skill
  configure_skills
  sync_agents
}

# ---------------------------------------------------------------------------
# Step 5 — summary
# ---------------------------------------------------------------------------
report_tool() {
  local name="$1" cmd="$2"
  if have "$cmd"; then
    local path ver
    path="$(command -v "$cmd")"
    ver="$("$cmd" --version 2>/dev/null | head -n1 || true)"
    success "$(printf '%-12s %s  (%s)' "$name" "$path" "${ver:-version n/a}")"
  else
    warn "$(printf '%-12s not on PATH yet' "$name")"
  fi
}

summary() {
  echo
  info "Installation summary:"
  report_tool "Claude Code" claude
  report_tool "Hermes"      hermes
  report_tool "GitHub CLI"  gh
  report_tool "Bun"         bun
  report_tool "agent-brwsr" agent-browser
  echo
  info "Claude Code config applied: model opus[1m], dark theme, statusline, 'memory' MCP, official plugin marketplace,"
  info "agent-browser (persistent profile + skill + Bash allow-rule), subagents (scout, surfer) and Agent Skills (setup-pre-commit)."
  echo
  info "Next steps:"
  echo "  • If a command isn't found, restart your shell or 'source' your rc file"
  echo "    (claude/hermes install into ~/.local/bin)."
  echo "  • claude              — start Claude Code (then sign in)"
  echo "  • Account integrations (Figma/Notion/Gmail/Drive/Calendar/Atlassian) sync"
  echo "    from your claude.ai account — run /mcp inside Claude Code to authenticate them."
  echo "  • hermes setup        — configure your Hermes LLM provider"
  echo "  • gh auth login       — authenticate the GitHub CLI"
  echo "  • agent-browser-headful on|off — flip the surfing browser headful (Xvfb)"
  echo "    when a site blocks headless fingerprints; always flip back off."
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  info "Dev machine bootstrap — Claude Code · Hermes · GitHub CLI"
  select_os
  preflight
  # Fail-soft per tool so one failure still lets the others (and summary) run.
  install_claude || error "Claude Code install failed."
  install_hermes || error "Hermes install failed."
  install_gh     || error "GitHub CLI install failed."
  install_bun    || error "Bun install failed."
  install_agent_browser   || error "agent-browser install failed."
  configure_agent_browser || error "agent-browser configuration failed."
  configure_claude || error "Claude Code configuration failed."
  summary
}

main "$@"
