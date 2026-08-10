# cc-dev-tools

Claude Code marketplace containing development tools and AI integrations for advanced workflows.

## Overview

This marketplace provides Claude Code plugins for enhanced development capabilities through external AI CLI integrations and automation tools.

## Available Plugins

| Plugin | Description | Type |
|--------|-------------|------|
| [Gemini](#gemini-plugin) | Google Gemini 3.1 Pro AI integration for research and reasoning | Skill |
| [Nano Banana](#nano-banana-plugin) | Standalone image generation via MCP (no Gemini CLI needed) | MCP + Skill |
| [Telegram Notifier](#telegram-notifier-plugin) | Telegram notifications for Claude Code events | Hooks |

> **Moved (v3.0.0):** the `codex` and `tmux` plugins migrated to the
> [super-tmux marketplace](https://github.com/Lucklyric/tmux-agent) as the
> `tmux-agent` and `tmux-core` plugins — see [Migration](#migration-codex--tmux--super-tmux).

---

### Gemini Plugin

Google Gemini 3.1 Pro AI integration through Gemini CLI for research, reasoning, and web search.

**Core Features:**
- **Gemini 3.1 Pro Default**: Uses `gemini-3.1-pro-preview` for ALL tasks (highest capability)
- **Version-Based Mapping**: User requests like "use 3" automatically map to the latest 3.x model
- **Session Continuation**: Resume previous conversations with `-r latest`
- **Web Search Integration**: Built-in web search for research and documentation lookup

**Quick Start:**
```bash
npm install -g @google/gemini-cli@latest  # Requires v0.33.0+
gemini login
```

**Usage:**
```
> Gemini, explain the observer pattern with examples
```

| Info | Value |
|------|-------|
| Path | [`plugins/gemini/`](plugins/gemini/) |
| Version | 2.1.0 |
| Skills | Gemini (reasoning) |
| Models | Gemini 3.1 Pro, 3 Pro, 2.5 Pro/Flash |

**Full Documentation**: [Gemini Plugin README](plugins/gemini/README.md)

---

### Nano Banana Plugin

Standalone image generation plugin using the [Nano Banana MCP server](https://github.com/gemini-cli-extensions/nanobanana). Runs directly as an MCP server — no Gemini CLI dependency.

**Core Features:**
- **Direct MCP Integration**: 7 native image tools without CLI overhead
- **Text-to-Image**: Generate batch images with style and variation controls
- **Image Editing**: Modify and restore photos with natural language
- **Icon Generation**: App icons, favicons, UI elements in multiple sizes
- **Diagrams & Patterns**: Technical diagrams, seamless textures, visual stories

**Quick Start:**
```bash
export GEMINI_API_KEY=your_key  # Requires Node.js v18+
```

**Usage:**
```
> Generate 3 variations of a sunset over mountains
> Create an app icon for a coffee shop
> Draw a flowchart for user authentication
```

| Info | Value |
|------|-------|
| Path | [`plugins/nanobanana/`](plugins/nanobanana/) |
| Version | 1.4.0 |
| Tools | generate_image, edit_image, restore_image, generate_icon, generate_pattern, generate_story, generate_diagram |
| Commands | /generate, /edit, /restore, /icon, /pattern, /story, /diagram, /nanobanana |

**Full Documentation**: [Nano Banana Plugin README](plugins/nanobanana/README.md)

---

### Telegram Notifier Plugin

Receive Telegram notifications when Claude Code completes responses, subagent tasks finish, or system notifications occur.

**Core Features:**
- **Stop Hook**: Notifies when Claude Code completes a response
- **SubagentStop Hook**: Notifies when subagent tasks complete
- **Notification Hook**: Forwards Claude Code system notifications
- **Custom Messages**: Customize notification messages via environment variables
- **Dry-Run Mode**: Test configuration without sending real notifications

**Quick Start:**
```bash
# Set environment variables
export CC_TELEGRAM_BOT_TOKEN="your-bot-token"
export CC_TELEGRAM_CHAT_ID="your-chat-id"
```

**Environment Variables:**

| Variable | Required | Description |
|----------|----------|-------------|
| `CC_TELEGRAM_BOT_TOKEN` | Yes | Bot API token from BotFather |
| `CC_TELEGRAM_CHAT_ID` | Yes | Target chat ID for notifications |
| `CC_TELEGRAM_STOP_MSG` | No | Custom message for Stop events |
| `CC_TELEGRAM_SUBAGENT_MSG` | No | Custom message for SubagentStop events |
| `CC_TELEGRAM_NOTIFY_MSG` | No | Custom message for Notification events |
| `CC_TELEGRAM_DRY_RUN` | No | Set to `true` to log without sending |

| Info | Value |
|------|-------|
| Path | [`plugins/telegram-notifier/`](plugins/telegram-notifier/) |
| Version | 0.4.0 |
| Type | Hooks only (no skills or agents) |

**Full Documentation**: [Telegram Notifier README](plugins/telegram-notifier/README.md)

---

## Migration: codex + tmux → super-tmux

As of marketplace **3.0.0** the `codex` and `tmux` plugins live in the
[super-tmux marketplace](https://github.com/Lucklyric/tmux-agent) (engine + kind
profiles + layered skills, both plugins at 1.0.0). One-time reinstall per machine:

```bash
/plugin uninstall codex
/plugin uninstall tmux
/plugin marketplace add Lucklyric/tmux-agent
/plugin install tmux-agent@super-tmux   # tmux-core auto-installs as a dependency
```

Everything is preserved: the codex command surface (`codex-tmux.sh`, all verbs, exit
codes, `CC_CODEX_*` env vars), pane markers (existing panes are found by the new
install), and the skills (now loading as `tmux-agent:codex` etc.). The last
cc-dev-tools release carrying the plugins is tagged `codex-v3.11.0`.

---

## Installation

### Step 1: Add this marketplace
```bash
/marketplace add https://github.com/Lucklyric/cc-dev-tools
```

### Step 2: Install plugins
```bash
# Install Gemini plugin
/plugin install gemini@cc-dev-tools

# Install Nano Banana plugin
/plugin install nanobanana@cc-dev-tools

# Install Telegram Notifier plugin
/plugin install telegram-notifier@cc-dev-tools
```

### Step 3: Restart Claude Code

## Repository Structure

```
cc-dev-tools/                          # Marketplace root
├── .claude-plugin/
│   └── marketplace.json               # Marketplace metadata
├── README.md                          # This file
├── LICENSE                            # Apache 2.0
└── plugins/
    ├── gemini/                        # Gemini CLI integration
    │   ├── .claude-plugin/
    │   │   └── plugin.json
    │   ├── README.md
    │   └── skills/gemini/              # Reasoning & research skill
    │       ├── SKILL.md
    │       └── references/
    │
    ├── nanobanana/                    # Standalone image generation (MCP)
    │   ├── .claude-plugin/
    │   │   └── plugin.json
    │   ├── .mcp.json                  # MCP server definition
    │   ├── commands/                  # Slash commands (/generate, /edit, etc.)
    │   ├── mcp-server/                # Bundled MCP server (Node.js)
    │   ├── README.md
    │   └── skills/nanobanana/
    │       ├── SKILL.md
    │       └── references/
    │
    └── telegram-notifier/             # Telegram notifications
        ├── .claude-plugin/
        │   └── plugin.json
        ├── hooks/
        │   └── hooks.json             # Stop, SubagentStop, Notification hooks
        └── README.md
```

## How It Works

**Three-tier hierarchy**: Marketplace → Plugin → Components (Skills/Hooks)

1. You add the **marketplace** (`cc-dev-tools`) from GitHub
2. You install a **plugin** (e.g., `gemini`, `nanobanana`, or `telegram-notifier`)
3. The plugin provides **components**:
   - **Skills**: Invoked by Claude when triggered (gemini, nanobanana)
   - **Hooks**: Event-driven automation (telegram-notifier)

## Migration from cc-skill-codex

**Repository Renamed**: This repository was renamed from `cc-skill-codex` to `cc-dev-tools` on 2025-11-18.

**For existing clones**, update your remote URL:
```bash
git remote set-url origin git@github.com:Lucklyric/cc-dev-tools.git
```

GitHub automatically redirects the old URL, so existing clones will continue to work.

## Contributing

Contributions welcome! This marketplace follows Claude Code's official plugin structure.

## License

Apache 2.0

## Version

**Marketplace**: 3.0.0

| Plugin | Version |
|--------|---------|
| Gemini | 2.1.0 |
| Nano Banana | 1.4.0 |
| Telegram Notifier | 0.4.0 |

## Links

- **Repository**: https://github.com/Lucklyric/cc-dev-tools
- **Issues**: https://github.com/Lucklyric/cc-dev-tools/issues
- **Author**: 0xasun
