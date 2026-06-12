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

configure_claude() {
  info "Configuring Claude Code..."
  if ! have claude; then
    warn "claude not on PATH yet — skipping config. Restart your shell and re-run this script to apply it."
    return 0
  fi
  install_statusline
  configure_settings
  configure_mcp
  configure_claude_md
  configure_plugins
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
  echo
  info "Claude Code config applied: model opus[1m], dark theme, statusline, 'memory' MCP, official plugin marketplace."
  echo
  info "Next steps:"
  echo "  • If a command isn't found, restart your shell or 'source' your rc file"
  echo "    (claude/hermes install into ~/.local/bin)."
  echo "  • claude              — start Claude Code (then sign in)"
  echo "  • Account integrations (Figma/Notion/Gmail/Drive/Calendar/Atlassian) sync"
  echo "    from your claude.ai account — run /mcp inside Claude Code to authenticate them."
  echo "  • hermes setup        — configure your Hermes LLM provider"
  echo "  • gh auth login       — authenticate the GitHub CLI"
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
  configure_claude || error "Claude Code configuration failed."
  summary
}

main "$@"
