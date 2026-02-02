# Screenrecording Demo Scenarios

A single-conversation demo showcasing mcp-acp-nexus with Claude Desktop and an MCP Filesystem Server. The scenario follows a tech lead doing a morning work session — code review, edits, document review, and meeting prep — while the proxy enforces access policies transparently.

## Setup

```bash
# 1. Create the demo workspace
chmod +x demo-testing-guide/create-demo-workspace.sh
demo-testing-guide/create-demo-workspace.sh

# 2. Add a proxy for your filesystem server
mcp-acp proxy add --name filesystem-server \
  --server-name filesystem-server \
  --connection-type stdio \
  --command npx \
  --args "-y,@modelcontextprotocol/server-filesystem,/tmp/mcp-demo-workspace"

# 3. Copy the demo policy
cp demo-testing-guide/demo-policy.json \
  ~/Library/Application\ Support/mcp-acp/proxies/filesystem-server/policy.json

# 4. Configure Claude Desktop (~/Library/Application Support/Claude/claude_desktop_config.json)
#    {
#      "mcpServers": {
#        "filesystem-server": {
#          "command": "/path/to/mcp-acp",
#          "args": ["start", "--proxy", "filesystem-server"]
#        }
#      }
#    }
#    Find your path with: which mcp-acp

# 5. Start the manager or start Claude Desktop only
mcp-acp manager start
```

See `demo-config.json` for the proxy configuration and `demo-policy.json` for the full 27-rule policy.

This was tested with [cyanheads/filesystem-mcp-server](https://github.com/cyanheads/filesystem-mcp-server) as the backend. Any MCP filesystem server that exposes the standard file tools (`read_file`, `write_file`, `edit_file`, `list_directory`, etc.) will work.

---

## The Demo: Morning Work Session

All prompts happen in a **single Claude Desktop conversation**.

### Prompt 1 — Orient yourself

> Show me the directory structure of /tmp/mcp-demo-workspace so I can see what we're working with.

Sets the stage. Frictionless — navigation is always allowed.

---

### Prompt 2 — Code review and edits

> Read through the client-portal source files. I want to understand the Dashboard setup, then add a welcome message to it. Also switch the theme to dark mode in the config.

**What the viewer sees:** Claude reads source files freely. Then two different HITL dialogs appear: a **3-button dialog** for the source edit (cacheable) and a **2-button dialog** for the config edit (not cacheable). Approve both.

**Key moment:** The visual contrast between the two dialog types — the UI itself communicates the caching policy.

---

### Prompt 3 — Caching payoff

> Actually, also add a loading spinner component to the Dashboard.

**What the viewer sees:** Claude edits `Dashboard.tsx` again — **no dialog appears**. The approval from prompt 2 is cached.

---

### Prompt 4 — Credential wall

> Now check the environment config too, I want to make sure the API endpoint matches what's in .env.local.

**What the viewer sees:** Claude reads `settings.json` fine, then hits an instant **DENY** on `.env.local`. No dialog, no override. The request was casual but the policy protects credentials regardless.

---

### Prompt 5 — Pivot to financial review

> I need to prep for a board meeting. Read the Q4 financial report and the 2025 budget, then write an executive summary to the reports directory.

**What the viewer sees:** Two HITL dialogs for two financial documents (both **3-button**, cacheable — each file gets its own approval). Writing the summary to `reports/` is frictionless.

---

### Prompt 6 — Legal review, stricter controls

> Also pull up the vendor agreement and the NDA so I can check our obligations.

**What the viewer sees:** Two HITL dialogs, both **2-button** (no cache option). Immediate contrast with the 3-button financial dialogs from prompt 5.

---

### Prompt 7 — Hard boundary

> And grab the salary bands from HR so I can check the budget against compensation.

**What the viewer sees:** Instant **DENY**. No dialog, no override option. The difference between HITL ("are you sure?") and DENY ("not allowed, period").

---

### Prompt 8 (optional) — Documentation with caching

> Read the architecture review meeting notes and create a new ADR documenting the database migration decision. Update the changelog too.

**What the viewer sees:** Reads meeting notes freely. HITL dialogs for the writes (3-button, cacheable).

**Follow-up in the same conversation:**

> Actually, add a "Status: Accepted" line to the ADR you just created.

Edit to the same ADR — **no dialog**. Auto-approved from cache.

---

### Closer — Audit trail

Open the mcp-acp web UI and show the audit log. Every decision from the session is captured.

---

## What This Demo Shows

| Feature | Where it appears |
|---|---|
| Frictionless ALLOW | Prompts 1, 2 (reads), 5 (report write) |
| Instant DENY | Prompts 4 (.env), 7 (HR records) |
| HITL with caching (3-button) | Prompts 2 (src edit), 5 (financial), 8 (docs) |
| HITL without caching (2-button) | Prompts 2 (config edit), 6 (contracts) |
| Cached auto-approve | Prompts 3 and 8 follow-up |
| Policy granularity | Prompt 5 vs 6 (financial cached vs contracts not) |
| Hard boundary vs soft boundary | Prompt 7 (DENY) vs 5-6 (HITL) |
| Audit trail | Closer |
