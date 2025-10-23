# Installation Guide: Codex Plugin for Claude Code

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/Lucklyric/cc-skill-codex.git
cd cc-skill-codex

# 2. Install via Claude Code plugin system
# In Claude Code, run:
/plugin add .

# 3. Enable the plugin
/plugin enable codex

# 4. Restart Claude Code
```

## Detailed Installation Steps

### Prerequisites Check

Before installation, verify:

```bash
# Check Codex CLI is installed
codex --version

# Check authentication
codex login
```

### Method 1: Plugin System (Recommended)

**Step 1: Clone Repository**
```bash
git clone https://github.com/Lucklyric/cc-skill-codex.git
cd cc-skill-codex
```

**Step 2: Add Plugin to Claude Code**

In Claude Code:
```
/plugin add /full/path/to/cc-skill-codex
```

Or if you're already in the directory:
```
/plugin add .
```

**Step 3: Enable Plugin**
```
/plugin enable codex
```

**Step 4: Restart Claude Code**

Restart Claude Code for the plugin to take effect.

**Step 5: Verify Installation**

In Claude Code:
```
/help
```

Look for "Codex Integration" in the skills section.

Or simply test it:
```
Use Codex to help me design a queue data structure
```

---

### Method 2: Manual Installation

If you prefer not to use the plugin system:

```bash
# Clone repository
git clone https://github.com/Lucklyric/cc-skill-codex.git

# Copy skill to Claude Code skills directory
mkdir -p ~/.claude/skills
cp -r cc-skill-codex/skills/codex ~/.claude/skills/

# Restart Claude Code
```

---

## Plugin Structure

```
cc-skill-codex/
├── .claude-plugin/
│   └── plugin.json          # Plugin metadata
├── .gitignore
├── CLAUDE.md                 # Development guidance
├── LICENSE                   # Apache 2.0
├── README.md                 # Main documentation
├── INSTALL.md               # This file
└── skills/
    └── codex/
        ├── SKILL.md         # Skill definition
        ├── examples/
        │   ├── basic-usage.md
        │   ├── session-continuation.md
        │   └── advanced-config.md
        └── resources/
            ├── claude-skill-doc.md
            ├── codex-config.md
            └── codex-help.md
```

---

## Verification

### Check Plugin Status

```bash
# In Claude Code
/plugin list
```

Should show:
```
codex@local - enabled
```

### Test the Skill

Try these example requests:

**Example 1: General Reasoning**
```
Help me design a binary search tree in Rust
```

**Example 2: Code Editing**
```
Edit this file to add error handling
```

**Example 3: Session Continuation**
```
Continue with that implementation - add unit tests
```

---

## Troubleshooting

### Plugin Not Found

**Symptom**: `/plugin add` returns "plugin not found"

**Fix**: Ensure you're providing the full absolute path:
```bash
/plugin add /Users/yourname/code/cc-skill-codex
```

---

### Skill Not Invoked

**Symptom**: Claude doesn't use the Codex skill automatically

**Fix**:
1. Explicitly mention "Codex" in your request:
   ```
   Use Codex to help me with...
   ```

2. Check skill is loaded:
   ```
   /help
   ```

3. Restart Claude Code

---

### Codex CLI Errors

**Symptom**: "codex: command not found"

**Fix**: Install Codex CLI and ensure it's in PATH:
```bash
# Check installation
which codex

# Add to PATH if needed
export PATH="/path/to/codex:$PATH"
```

**Symptom**: "Not authenticated with Codex"

**Fix**: Run authentication:
```bash
codex login
```

---

## Uninstallation

### Remove Plugin

```bash
# In Claude Code
/plugin disable codex
/plugin remove codex
```

### Remove Manual Installation

```bash
rm -rf ~/.claude/skills/codex
```

---

## Updates

### Update Plugin

```bash
# Navigate to plugin directory
cd /path/to/cc-skill-codex

# Pull latest changes
git pull origin main

# Restart Claude Code
```

Plugin will automatically reload with new version.

---

## Support

- **Issues**: [GitHub Issues](https://github.com/Lucklyric/cc-skill-codex/issues)
- **Documentation**: See [README.md](./README.md)
- **Examples**: See [skills/codex/examples/](./skills/codex/examples/)
- **Codex CLI**: See [skills/codex/resources/codex-help.md](./skills/codex/resources/codex-help.md)
