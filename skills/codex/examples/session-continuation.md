# Session Continuation Examples

> **⚠️ IMPORTANT**: All examples use `codex exec` for non-interactive execution. Claude Code's bash environment is non-terminal, so the interactive `codex` command will fail. Always use `codex exec` when invoking from Claude Code.

## Example 1: Basic Session Continuation

### Initial Request
**User**: "Help me design a queue data structure in Python"

**Skill Executes**:
```bash
codex exec -m gpt-5 -s read-only \
  -c model_reasoning_effort=high \
  "Help me design a queue data structure in Python"
```

**Codex Response**: Provides queue design with multiple approaches.

**Session Auto-Saved**: Codex CLI saves this session automatically.

---

### Follow-Up Request
**User**: "Continue with that queue - now add thread-safety"

**Skill Detects**: Continuation keywords ("continue with that")

**Skill Executes**:
```bash
codex resume --last
```

**Codex Response**: Resumes previous session, maintains context about the queue design, and adds thread-safety implementation building on the previous discussion.

**Context Maintained**: All previous conversation history is available to Codex.

---

## Example 2: Multi-Turn Iterative Development

### Turn 1: Initial Design
**User**: "Design a REST API for a blog system"

```bash
codex exec -m gpt-5 -s read-only \
  -c model_reasoning_effort=high \
  "Design a REST API for a blog system"
```

**Output**: API endpoint design, resource modeling, etc.

---

### Turn 2: Add Authentication
**User**: "Add authentication to that API design"

**Skill Executes**:
```bash
codex resume --last
```

**Output**: Codex continues from previous API design and adds JWT/OAuth authentication strategy.

---

### Turn 3: Add Error Handling
**User**: "Now add comprehensive error handling"

**Skill Executes**:
```bash
codex resume --last
```

**Output**: Codex builds on previous API + auth design and adds error handling patterns.

---

### Turn 4: Implementation
**User**: "Implement the user authentication endpoint"

**Skill Executes**:
```bash
codex resume --last
```

**Output**: Codex uses all previous context to implement the auth endpoint with full understanding of the API design.

**Result**: After 4 turns, you have a complete API with design, auth, error handling, and initial implementation - all with maintained context.

---

## Example 3: Explicit Resume Command

### When to Use Interactive Picker

If you have multiple Codex sessions and want to choose which one to continue:

**User**: "Show me my Codex sessions and let me pick which to resume"

**Manual Command** (run outside skill):
```bash
codex resume
```

This opens an interactive picker showing:
```
Recent Codex Sessions:
1. Queue data structure design (30 minutes ago)
2. REST API for blog system (2 hours ago)
3. Binary search tree implementation (yesterday)

Select session to resume:
```

---

## Example 4: Resuming After Claude Code Restart

### Scenario
1. You worked on a queue design with Codex
2. Closed Claude Code
3. Reopened Claude Code days later

### Resume Request
**User**: "Continue where we left off with the queue implementation"

**Skill Executes**:
```bash
codex resume --last
```

**Result**: Codex resumes the most recent session (the queue work) with full context maintained across Claude Code restarts.

**Why It Works**: Codex CLI persists session history independently of Claude Code.

---

## Continuation Keywords

The skill detects continuation requests when you use phrases like:

- "Continue with that"
- "Resume the previous session"
- "Keep going"
- "Add to that"
- "Now add X" (implies building on previous)
- "Continue where we left off"
- "Follow up on that"

---

## Decision Tree: New Session vs. Resume

```
User makes request
│
├─ Contains continuation keywords?
│  │
│  ├─ YES → Use `codex resume --last`
│  │
│  └─ NO → Check context
│     │
│     ├─ References previous Codex work?
│     │  │
│     │  ├─ YES → Use `codex resume --last`
│     │  │
│     │  └─ NO → New session: `codex -m ... "prompt"`
│
└─ User explicitly says "new" or "fresh"?
   │
   └─ YES → Force new session even if continuation keywords present
```

---

## Session History Management

### Automatic Save
- Every Codex session is automatically saved by Codex CLI
- No manual session ID tracking needed
- Sessions persist across:
  - Claude Code restarts
  - Terminal sessions
  - System reboots

### Accessing History
```bash
# Resume most recent (recommended for skill)
codex resume --last

# Interactive picker (manual use)
codex resume

# List sessions (manual use)
codex list
```

---

## Best Practices

### 1. Use Clear Continuation Language

**Good**:
- "Continue with that queue implementation - add unit tests"
- "Resume the API design session and add rate limiting"

**Less Clear**:
- "Add tests" (ambiguous - new or continue?)
- "Rate limiting" (no continuation context)

### 2. Build Incrementally

Start with high-level design, then iterate:
1. Design (new session)
2. Add feature A (resume)
3. Add feature B (resume)
4. Implement (resume with full context)

### 3. Leverage Context Accumulation

Each resumed session has ALL previous context:
- Design decisions
- Trade-offs discussed
- Code patterns chosen
- Error handling approaches

This allows Codex to provide increasingly sophisticated, context-aware assistance.

---

## Troubleshooting

### "No previous sessions found"

**Cause**: Codex CLI history is empty (no prior sessions)

**Fix**: Start a new session first:
```bash
codex exec -m gpt-5 "Design a queue"
```

Then subsequent "continue" requests will work.

---

### Session Not Resuming Correctly

**Symptoms**: Resume works but context seems lost

**Possible Causes**:
- Multiple sessions mixed together
- User explicitly requested "fresh start"

**Fix**: Use interactive picker to select correct session:
```bash
codex resume
```

---

### Multiple Sessions Confusion

**Scenario**: Working on two projects, want to resume specific one

**Solution**:
1. Be explicit: "Resume the queue design session" (skill will use --last)
2. Or manually: `codex resume` → pick correct session

---

## Next Steps

- **Advanced config**: See [advanced-config.md](./advanced-config.md)
- **Basic examples**: See [basic-usage.md](./basic-usage.md)
- **Full docs**: See [../SKILL.md](../SKILL.md)
