---
name: cc-skill-codex
description: Invoke Codex CLI for complex coding tasks requiring high reasoning capabilities. Use when user asks to use Codex, work with Codex, mentions Codex in any context, requests complex implementation challenges, advanced reasoning, GPT-5 capabilities, or needs high-reasoning model assistance. Always trigger when user says "codex", "use codex", "work with codex", "ask codex", or any codex-related request. Supports session continuation for iterative development.
---

# cc-skill-codex: Codex CLI Integration for Claude Code

## When to Use This Skill

This skill should be invoked when:
- User explicitly mentions "Codex" or requests Codex assistance
- User needs help with complex coding tasks, algorithms, or architecture
- User requests "high reasoning" or "advanced implementation" help
- User mentions "GPT-5" capabilities or complex problem-solving
- User wants to continue a previous Codex conversation

## How It Works

### Detecting New Codex Requests

When a user makes a request that falls into one of the above categories, determine the task type:

**General Tasks** (architecture, design, reviews, explanations):
- Use model: `gpt-5` (high-reasoning general model)
- Example requests: "Design a queue data structure", "Review this architecture", "Explain this algorithm"

**Code Editing Tasks** (file modifications, implementation):
- Use model: `gpt-5-codex` (optimized for code editing)
- Example requests: "Edit this file to add feature X", "Implement the function", "Refactor this code"

### Bash CLI Command Structure

**IMPORTANT**: Always use `codex exec` for non-interactive execution. Claude Code's bash environment is non-terminal, so the interactive `codex` command will fail with "stdout is not a terminal" error.

#### For General Reasoning Tasks (Default)

```bash
codex exec -m gpt-5 -s read-only \
  -c model_reasoning_effort=high \
  "<user's prompt>"
```

#### For Code Editing Tasks

```bash
codex exec -m gpt-5-codex -s workspace-write \
  -c model_reasoning_effort=high \
  "<user's prompt>"
```

**Why `codex exec`?**
- Non-interactive mode required for automation and Claude Code integration
- Produces clean output suitable for parsing
- Works in non-TTY environments (like Claude Code's bash)

### Model Selection Logic

**Use `gpt-5` (default) when:**
- Designing architecture or data structures
- Reviewing code for quality, security, or performance
- Explaining concepts or algorithms
- Planning implementation strategies
- General problem-solving and reasoning

**Use `gpt-5-codex` when:**
- Editing or modifying existing code files
- Implementing specific functions or features
- Refactoring code
- Writing new code with file I/O
- Any task requiring `workspace-write` sandbox

### Default Configuration

All Codex invocations use these defaults unless user specifies otherwise:

| Parameter | Default Value | CLI Flag | Notes |
|-----------|---------------|----------|-------|
| Model | `gpt-5` | `-m gpt-5` | General reasoning tasks |
| Model (code editing) | `gpt-5-codex` | `-m gpt-5-codex` | Code editing tasks |
| Sandbox | `read-only` | `-s read-only` | Safe default (general tasks) |
| Sandbox (code editing) | `workspace-write` | `-s workspace-write` | Allows file modifications |
| Reasoning Effort | `high` | `-c model_reasoning_effort=high` | Maximum reasoning capability |
| Verbosity | `medium` | `-c model_verbosity=medium` | Balanced output detail |

### CLI Flags Reference

| Flag | Values | Description |
|------|--------|-------------|
| `-m, --model` | `gpt-5`, `gpt-5-codex` | Model selection |
| `-s, --sandbox` | `read-only`, `workspace-write`, `danger-full-access` | Sandbox mode |
| `-c, --config` | `key=value` | Config overrides (reasoning_effort, verbosity, etc.) |
| `-C, --cd` | directory path | Working directory |
| `-p, --profile` | profile name | Use config profile |
| `-a, --approval-policy` | `untrusted`, `on-failure`, `on-request`, `never` | Approval behavior |
| `--search` | flag | Enable web search |

### Configuration Parameters

Pass these as `-c key=value`:

- `model_reasoning_effort`: `minimal`, `low`, `medium`, `high` (default: `high`)
- `model_verbosity`: `low`, `medium`, `high` (default: `medium`)
- `model_reasoning_summary`: `auto`, `concise`, `detailed`, `none` (default: `auto`)

## Session Continuation

### Detecting Continuation Requests

When user indicates they want to continue a previous Codex conversation:
- Keywords: "continue", "resume", "keep going", "add to that"
- Follow-up context referencing previous Codex work
- Explicit request like "continue where we left off"

### Resuming Sessions

For continuation requests, use the `codex resume` command:

#### Resume Most Recent Session (Recommended)

```bash
codex resume --last
```

This automatically continues the most recent Codex session with all previous context maintained.

#### Interactive Session Picker

```bash
codex resume
```

Opens an interactive picker when multiple sessions exist. User can select which session to continue.

### Decision Logic: New vs. Continue

**Use `codex -m ... "<prompt>"`** when:
- User makes a new, independent request
- No reference to previous Codex work
- User explicitly wants a "fresh" or "new" session

**Use `codex resume --last`** when:
- User indicates continuation ("continue", "resume", "add to that")
- Follow-up question building on previous Codex conversation
- Iterative development on same task

### Session History Management

- Codex CLI automatically saves session history
- No manual session ID tracking needed
- Sessions persist across Claude Code restarts
- Use `codex resume` to access session history

## Error Handling

### Simple Error Response Strategy

When errors occur, return clear, actionable messages without complex diagnostics:

**Error Message Format:**
```
Error: [Clear description of what went wrong]

To fix: [Concrete remediation action]

[Optional: Specific command example]
```

### Common Errors

#### Command Not Found

```
Error: Codex CLI not found

To fix: Install Codex CLI and ensure it's available in your PATH

Check installation: codex --version
```

#### Authentication Required

```
Error: Not authenticated with Codex

To fix: Run 'codex login' to authenticate

After authentication, try your request again.
```

#### Invalid Configuration

```
Error: Invalid model specified

To fix: Use 'gpt-5' for general reasoning or 'gpt-5-codex' for code editing

Example: codex -m gpt-5 "your prompt here"
```

### Troubleshooting

**Skill not being invoked?**
- Check that request matches trigger keywords (Codex, complex coding, high reasoning, etc.)
- Explicitly mention "Codex" in your request
- Try: "Use Codex to help me with..."

**Session not resuming?**
- Verify you have a previous Codex session: `codex resume` (run outside skill)
- Check if Codex CLI has saved session history
- If no history exists, start a new session first

**Errors during execution?**
- Codex CLI errors are passed through directly
- Check Codex CLI logs for detailed diagnostics
- Verify working directory permissions if using workspace-write

## Examples

### Example 1: General Reasoning Task (Architecture Design)

**User Request**: "Help me design a binary search tree architecture in Rust"

**Skill Executes**:
```bash
codex exec -m gpt-5 -s read-only \
  -c model_reasoning_effort=high \
  "Help me design a binary search tree architecture in Rust"
```

**Result**: Codex provides high-reasoning architectural guidance using gpt-5. Session automatically saved for continuation.

---

### Example 2: Code Editing Task

**User Request**: "Edit this file to implement the BST insert method"

**Skill Executes**:
```bash
codex exec -m gpt-5-codex -s workspace-write \
  -c model_reasoning_effort=high \
  "Edit this file to implement the BST insert method"
```

**Result**: Codex uses gpt-5-codex (optimized for coding) with workspace-write permissions to modify files.

---

### Example 3: Session Continuation

**User Request**: "Continue with the BST - add a deletion method"

**Skill Executes**:
```bash
codex resume --last
```

**Result**: Codex resumes the previous BST session and continues with deletion method implementation, maintaining full context.

---

### Example 4: Custom Configuration

**User Request**: "Use Codex with web search to research and implement async patterns"

**Skill Executes**:
```bash
codex exec -m gpt-5-codex -s workspace-write \
  -c model_reasoning_effort=high \
  --search \
  "Research and implement async patterns"
```

**Result**: Codex uses web search capability for latest information, then implements with high reasoning.

## When to Use GPT-5 vs GPT-5-Codex

### Use GPT-5 (General High-Reasoning) For:
- Architecture and system design
- Code reviews and quality analysis
- Security audits and vulnerability assessment
- Performance optimization strategies
- Algorithm design and analysis
- Explaining complex concepts
- Planning and strategy

### Use GPT-5-Codex (Code-Specialized) For:
- Editing existing code files
- Implementing specific features
- Refactoring and code transformations
- Writing new code with file I/O
- Code generation tasks
- Debugging and fixes requiring file changes

**Default**: When in doubt, use `gpt-5` for general tasks. Switch to `gpt-5-codex` only when specifically editing code.

## Best Practices

### 1. Use Descriptive Requests

**Good**: "Help me implement a thread-safe queue with priority support in Python"
**Vague**: "Code help"

Clear, specific requests get better results from high-reasoning models.

### 2. Indicate Continuation Clearly

**Good**: "Continue with that queue implementation - add unit tests"
**Unclear**: "Add tests" (might start new session)

Explicit continuation keywords help the skill choose the right command.

### 3. Specify Permissions When Needed

**Good**: "Refactor this code (allow file writing)"
**Risky**: Assuming permissions without specifying

Make your intent clear when you need workspace-write permissions.

### 4. Leverage High Reasoning

The skill defaults to high reasoning effort - perfect for:
- Complex algorithms
- Architecture design
- Performance optimization
- Security reviews

## Additional Resources

For more details, see:
- `resources/codex-help.md` - Codex CLI command reference
- `resources/codex-config.md` - Full configuration options
- `resources/claude-skill-doc.md` - Skill development guide
- `README.md` - Installation and quick start guide
