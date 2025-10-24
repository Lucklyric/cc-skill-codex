# Advanced Configuration Examples

---

## ⚠️ CRITICAL: Always Use `codex exec`

**ALL commands in this document use `codex exec` - this is mandatory in Claude Code.**

❌ **NEVER**: `codex -m ...` or `codex --flag ...` (will fail with "stdout is not a terminal")
✅ **ALWAYS**: `codex exec -m ...` or `codex exec --flag ...` (correct non-interactive mode)

Claude Code's bash environment is non-terminal. Plain `codex` commands will NOT work.

---

## Custom Model Selection

### Example 1: Force GPT-5 for Code Task

**User Request**: "Use GPT-5 (not Codex) to review this code for architecture issues"

**Skill Executes**:
```bash
codex exec -m gpt-5 -s read-only \
  -c model_reasoning_effort=high \
  "Review this code for architecture issues"
```

**Why**: Even though it's code-related, user wants architectural review (high-reasoning) rather than code editing.

---

### Example 2: Explicit GPT-5-Codex for Implementation

**User Request**: "Use GPT-5-Codex to implement the authentication module"

**Skill Executes**:
```bash
codex exec -m gpt-5-codex -s workspace-write \
  -c model_reasoning_effort=high \
  "Implement the authentication module"
```

**Why**: Implementation requires file writing and code generation (gpt-5-codex specialty).

---

## Workspace Write Permission

### Example 3: Allow File Modifications

**User Request**: "Have Codex refactor this codebase (allow file writing)"

**Skill Executes**:
```bash
codex exec -m gpt-5-codex -s workspace-write \
  -c model_reasoning_effort=high \
  "Refactor this codebase for better maintainability"
```

**Permission**: `workspace-write` allows Codex to modify files directly.

⚠️ **Warning**: Only use `workspace-write` when you trust the operation and want file modifications.

---

### Example 4: Read-Only Code Review

**User Request**: "Review this code for security vulnerabilities (read-only)"

**Skill Executes**:
```bash
codex exec -m gpt-5 -s read-only \
  -c model_reasoning_effort=high \
  "Review this code for security vulnerabilities"
```

**Permission**: `read-only` prevents file modifications - safer for review tasks.

---

## Web Search Integration

### Example 5: Research Latest Patterns

**User Request**: "Research latest Python async patterns and implement them (enable web search)"

**Skill Executes**:
```bash
codex exec -m gpt-5-codex -s workspace-write \
  -c model_reasoning_effort=high \
  --search \
  "Research latest Python async patterns and implement them"
```

**Feature**: `--search` flag enables web search for up-to-date information.

---

### Example 6: Security Best Practices Research

**User Request**: "Use web search to find latest JWT security best practices, then review this auth code"

**Skill Executes**:
```bash
codex exec -m gpt-5 -s read-only \
  -c model_reasoning_effort=high \
  --search \
  "Find latest JWT security best practices and review this auth code"
```

---

## Reasoning Effort Control

### Example 7: Maximum Reasoning for Complex Algorithm

**User Request**: "Design an optimal algorithm for distributed consensus (maximum reasoning)"

**Skill Executes**:
```bash
codex exec -m gpt-5 -s read-only \
  -c model_reasoning_effort=high \
  "Design an optimal algorithm for distributed consensus"
```

**Default**: Already uses `high` reasoning effort.

---

### Example 8: Quick Code Review (Lower Reasoning)

**User Request**: "Quick syntax check on this code (low reasoning)"

**Skill Executes**:
```bash
codex exec -m gpt-5 -s read-only \
  -c model_reasoning_effort=low \
  "Quick syntax check on this code"
```

**Use Case**: Fast turnaround for simple tasks.

---

## Verbosity Control

### Example 9: Detailed Explanation

**User Request**: "Explain this algorithm in detail (high verbosity)"

**Skill Executes**:
```bash
codex exec -m gpt-5 -s read-only \
  -c model_reasoning_effort=high \
  -c model_verbosity=high \
  "Explain this algorithm in detail"
```

**Output**: Comprehensive, detailed explanation.

---

### Example 10: Concise Summary

**User Request**: "Briefly review this code (low verbosity)"

**Skill Executes**:
```bash
codex exec -m gpt-5 -s read-only \
  -c model_reasoning_effort=high \
  -c model_verbosity=low \
  "Review this code"
```

**Output**: Concise, focused feedback.

---

## Working Directory Control

### Example 11: Specific Project Directory

**User Request**: "Work in the backend directory and review the API code"

**Skill Executes**:
```bash
codex exec -m gpt-5 -s read-only \
  -c model_reasoning_effort=high \
  -C ./backend \
  "Review the API code"
```

**Feature**: `-C` flag sets working directory for Codex.

---

## Approval Policy

### Example 12: Request Approval for Shell Commands

**User Request**: "Implement the build script (ask before running commands)"

**Skill Executes**:
```bash
codex exec -m gpt-5-codex -s workspace-write \
  -c model_reasoning_effort=high \
  -a on-request \
  "Implement the build script"
```

**Safety**: `-a on-request` requires approval before executing shell commands.

---

## Combined Advanced Configuration

### Example 13: Full-Featured Request

**User Request**: "Use web search to find latest security practices, review my auth module in detail with high reasoning, allow file fixes if needed (ask for approval)"

**Skill Executes**:
```bash
codex exec -m gpt-5-codex -s workspace-write \
  -c model_reasoning_effort=high \
  -c model_verbosity=high \
  -a on-request \
  --search \
  "Find latest security practices, review my auth module in detail, and fix issues"
```

**Features**:
- Web search enabled (`--search`)
- High reasoning (`model_reasoning_effort=high`)
- Detailed output (`model_verbosity=high`)
- File writing allowed (`workspace-write`)
- Requires approval for commands (`-a on-request`)

---

## Decision Tree: When to Use GPT-5 vs GPT-5-Codex

### Use GPT-5 For:

```
┌─────────────────────────────────────┐
│     Architecture & Design           │
│  - System architecture              │
│  - API design                       │
│  - Data structure design            │
│  - Algorithm analysis               │
├─────────────────────────────────────┤
│     Analysis & Review               │
│  - Code reviews                     │
│  - Security audits                  │
│  - Performance analysis             │
│  - Quality assessment               │
├─────────────────────────────────────┤
│     Explanation & Learning          │
│  - Concept explanations             │
│  - Documentation review             │
│  - Trade-off analysis               │
│  - Best practices guidance          │
└─────────────────────────────────────┘
```

### Use GPT-5-Codex For:

```
┌─────────────────────────────────────┐
│     Code Editing                    │
│  - Modify existing files            │
│  - Implement features               │
│  - Refactoring                      │
│  - Bug fixes                        │
├─────────────────────────────────────┤
│     Code Generation                 │
│  - Write new code                   │
│  - Generate boilerplate             │
│  - Create test files                │
│  - Scaffold projects                │
├─────────────────────────────────────┤
│     File Operations                 │
│  - Multi-file changes               │
│  - Batch updates                    │
│  - Migration scripts                │
│  - Build configurations             │
└─────────────────────────────────────┘
```

---

## Sandbox Mode Decision Matrix

| Task | Recommended Sandbox | Rationale |
|------|---------------------|-----------|
| Code review | `read-only` | No modifications needed |
| Architecture design | `read-only` | Planning phase only |
| Security audit | `read-only` | Analysis without changes |
| Implement feature | `workspace-write` | Requires file modifications |
| Refactor code | `workspace-write` | Must edit existing files |
| Generate new files | `workspace-write` | Creates new files |
| Bug fix | `workspace-write` | Edits source files |

---

## Configuration Profiles

### Create a Config Profile

You can create reusable configuration profiles in `~/.codex/config.toml`:

```toml
[profiles.review]
model = "gpt-5"
sandbox = "read-only"
model_reasoning_effort = "high"
model_verbosity = "medium"

[profiles.implement]
model = "gpt-5-codex"
sandbox = "workspace-write"
model_reasoning_effort = "high"
approval_policy = "on-request"
```

### Use Profile in Skill

**User Request**: "Use the review profile to analyze this code"

**Skill Executes**:
```bash
codex -p review "Analyze this code"
```

**Result**: Uses all settings from `[profiles.review]`.

---

## Best Practices

### 1. Match Model to Task Type

- **Thinking/Design** → GPT-5
- **Doing/Coding** → GPT-5-Codex

### 2. Use Safe Defaults, Override Intentionally

- Default to `read-only` unless file writing is explicitly needed
- Default to `high` reasoning for complex tasks
- Reduce reasoning effort only for simple, quick tasks

### 3. Combine Web Search with High Reasoning

For best results researching current practices:
```bash
codex exec -m gpt-5 --search \
  -c model_reasoning_effort=high \
  "Research latest distributed systems patterns"
```

### 4. Request Approval for Risky Operations

Use `-a on-request` when:
- Working with production code
- Running shell commands
- Making broad changes

---

## Common Patterns

### Pattern 1: Research → Design → Implement

**Phase 1 - Research** (GPT-5 + web search):
```bash
codex exec -m gpt-5 --search \
  -c model_reasoning_effort=high \
  "Research latest authentication patterns"
```

**Phase 2 - Design** (GPT-5 + high reasoning):
```bash
codex exec resume --last
# "Design the authentication system based on research"
```

**Phase 3 - Implement** (GPT-5-Codex + workspace-write):
```bash
codex exec -m gpt-5-codex -s workspace-write \
  -c model_reasoning_effort=high \
  "Implement the authentication system we designed"
```

---

### Pattern 2: Review → Fix → Verify

**Review** (GPT-5 + read-only):
```bash
codex exec -m gpt-5 -s read-only \
  "Review this code for security issues"
```

**Fix** (GPT-5-Codex + workspace-write):
```bash
codex exec resume --last
# "Fix the security issues identified"
```

**Verify** (GPT-5 + read-only):
```bash
codex exec resume --last
# "Verify the fixes are correct"
```

---

## Next Steps

- **Basic usage**: See [basic-usage.md](./basic-usage.md)
- **Session continuation**: See [session-continuation.md](./session-continuation.md)
- **Full documentation**: See [../SKILL.md](../SKILL.md)
- **CLI reference**: See [../resources/codex-help.md](../resources/codex-help.md)
- **Config reference**: See [../resources/codex-config.md](../resources/codex-config.md)
