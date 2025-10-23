# Codex Integration Plugin for Claude Code

**Version**: 1.0.0
**Plugin Type**: Skill
**License**: Apache 2.0

Invoke Codex CLI for complex coding tasks requiring high reasoning capabilities. Supports GPT-5 and GPT-5-Codex with intelligent model selection, session continuation, and safe defaults.

## Prerequisites

Before using this plugin, ensure:

1. **Codex CLI installed** and available in PATH
   ```bash
   codex --version
   ```

2. **Authenticated with Codex**
   ```bash
   codex login
   ```

3. **Claude Code v1.0+** installed

## Installation

### Option 1: Plugin Installation (Recommended)

Install directly via Claude Code's plugin system:

```bash
# Clone the plugin repository
git clone https://github.com/Lucklyric/cc-skill-codex.git

# Add as local plugin in Claude Code
/plugin add ./cc-skill-codex

# Enable the plugin
/plugin enable codex
```

**Restart Claude Code** to activate the skill.

### Option 2: Manual Installation

For manual installation without the plugin system:

```bash
# Clone the repository
git clone https://github.com/Lucklyric/cc-skill-codex.git

# Copy skill directory to Claude Code skills folder
mkdir -p ~/.claude/skills
cp -r cc-skill-codex/skills/codex ~/.claude/skills/

# Restart Claude Code
```

## Verify Installation

After restarting Claude Code:

```bash
# Check if skill is loaded
/help

# Look for "Codex Integration" in the skills section
```

Or simply try using it:
> "Use Codex to help me design a binary search tree"

## Basic Usage

### Example 1: Simple Coding Help (General Reasoning)

**User**: "Help me design a queue data structure in Python"

**What Happens**:
1. Claude detects the coding task
2. Skill is invoked autonomously
3. Codex CLI is called with gpt-5 (general high-reasoning):
   ```bash
   codex -m gpt-5 -s read-only \
     -c model_reasoning_effort=high \
     "Help me design a queue data structure in Python"
   ```
4. Codex responds with high-reasoning architectural guidance
5. Session is auto-saved for potential continuation

---

### Example 1b: Code Editing Task

**User**: "Edit my Python file to implement the queue with thread-safety"

**What Happens**:
1. Skill detects code editing request
2. Uses gpt-5-codex (optimized for coding):
   ```bash
   codex -m gpt-5-codex -s workspace-write \
     -c model_reasoning_effort=high \
     "Edit my Python file to implement the queue with thread-safety"
   ```
3. Codex performs code editing with specialized model

---

### Example 2: Continue a Session

**User**: "Now add thread-safety to that queue"

**What Happens**:
1. Claude detects continuation context
2. Skill resumes previous session:
   ```bash
   codex resume --last
   ```
3. Codex continues from previous context and adds thread-safety

---

### Example 3: Explicit Codex Request

**User**: "Use Codex to design a REST API for a blog system"

**What Happens**:
1. Explicit "Codex" mention triggers skill
2. Codex invoked with coding-optimized settings
3. High-reasoning analysis provides comprehensive API design

---

## Advanced Configuration

### Custom Model Selection

**User**: "Use GPT-5-Codex to edit this specific file"

**Skill Executes**:
```bash
codex -m gpt-5-codex -s workspace-write \
  -c model_reasoning_effort=high \
  "Edit file.py to refactor the main function"
```

**Note**: Skill defaults to `gpt-5` for general tasks, `gpt-5-codex` for code editing

---

### Workspace Write Permission

**User**: "Have Codex refactor this codebase (allow file writing)"

**Skill Executes**:
```bash
codex -m gpt-5-codex -s workspace-write \
  -c model_reasoning_effort=high \
  "Refactor this codebase for better maintainability"
```

⚠️ **Warning**: `workspace-write` allows Codex to modify files. Use with caution.

---

### Enable Web Search

**User**: "Research latest Python async patterns and implement them (enable web search)"

**Skill Executes**:
```bash
codex -m gpt-5-codex -s read-only \
  -c model_reasoning_effort=high \
  --search \
  "Research latest Python async patterns and implement them"
```

---

## Session Management

### Resume Last Session

```
User: "Continue where we left off"
```

Skill automatically uses: `codex resume --last`

### Choose from Multiple Sessions

If you want to resume a specific session from history:

```bash
# Run manually (outside skill)
codex resume
```

This opens an interactive picker.

---

## Troubleshooting

### Error: Command not found

**Symptom**: `codex: command not found`

**Fix**:
```bash
# Install Codex CLI
# [Installation instructions from Codex documentation]
```

---

### Error: Not authenticated

**Symptom**: "Run 'codex login' to authenticate"

**Fix**:
```bash
codex login
```

Follow the authentication flow.

---

### Skill Not Discovered

**Symptom**: Claude doesn't invoke the skill automatically

**Check**:
1. Skill file location:
   ```bash
   ls ~/.claude/skills/codex/SKILL.md
   ```

2. YAML frontmatter is valid

3. Restart Claude Code

---

### Session Not Resuming

**Symptom**: "No previous sessions found"

**Cause**: Codex CLI history is empty

**Fix**: Start a new session first, then resume

---

## Best Practices

### 1. Use Descriptive Requests

**Good**: "Help me implement a thread-safe queue with priority support in Python"
**Vague**: "Code help"

### 2. Indicate Continuation Clearly

**Good**: "Continue with that queue implementation - add unit tests"
**Unclear**: "Add tests" (might start new session)

### 3. Specify Permissions When Needed

**Good**: "Refactor this code (allow file writing)"
**Risky**: Assuming permissions without specifying

### 4. Leverage High Reasoning

The skill defaults to high reasoning effort - perfect for:
- Complex algorithms
- Architecture design
- Performance optimization
- Security reviews

---

## What's Next?

After basic usage:

1. **Explore Session History**:
   ```bash
   codex resume  # Interactive picker
   ```

2. **Customize Configuration**: Create a Codex profile in `~/.codex/config.toml`

3. **Combine with Other Skills**: Use alongside other Claude Code skills for comprehensive workflows

---

## Quick Reference

| Command | Purpose |
|---------|---------|
| `codex -m gpt-5 ...` | New session (general reasoning, default) |
| `codex -m gpt-5-codex ...` | New session (code editing, specialized) |
| `codex resume --last` | Continue recent session |
| `codex resume` | Choose session (interactive) |
| `-s read-only` | Safe mode (default) |
| `-s workspace-write` | Allow file modifications |
| `-c model_reasoning_effort=high` | High reasoning (default) |
| `--search` | Enable web search |

---

## Support

- **Skill Issues**: [GitHub Issues](https://github.com/Lucklyric/cc-skill-codex/issues)
- **Codex CLI Docs**: See `resources/codex-help.md`
- **Claude Code Docs**: [claude.com/claude-code](https://claude.com/claude-code)
