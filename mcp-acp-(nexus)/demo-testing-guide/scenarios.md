# Screenrecording Demo Scenarios

Demo scenarios showcasing mcp-acp-nexus with Claude Desktop and an MCP Filesystem Server. The proxy enforces access policies transparently while the user works naturally.

## Setup

```bash
# 1. Create the demo workspace
chmod +x demo-testing-guide/create-demo-workspace.sh
demo-testing-guide/create-demo-workspace.sh

# 2. Add a proxy for your filesystem server
mcp-acp proxy add --name filesystem \
  --server-name filesystem-server \
  --connection-type stdio \
  --command npx \
  --args "-y,@modelcontextprotocol/server-filesystem,/tmp/mcp-demo-workspace"

# 3. Copy the demo policy
cp demo-testing-guide/demo-policy.json \
  ~/Library/Application\ Support/mcp-acp/proxies/filesystem/policy.json

# 4. Configure Claude Desktop (~/Library/Application Support/Claude/claude_desktop_config.json)
#    {
#      "mcpServers": {
#        "filesystem": {
#          "command": "/path/to/mcp-acp",
#          "args": ["start", "--proxy", "filesystem"]
#        }
#      }
#    }
#    Find your path with: which mcp-acp

# 5. Restart Claude Desktop to pick up the config
```

See `demo-config.json` for the proxy configuration and `demo-policy.json` for the full 27-rule policy.

This was tested with [cyanheads/filesystem-mcp-server](https://github.com/cyanheads/filesystem-mcp-server) as the backend. Any MCP filesystem server that exposes the standard file tools (`read_file`, `write_file`, `list_files`, etc.) will work.

### Context message

Start every demo conversation with this so Claude knows where to find files:

> I have a file server connected at /tmp/mcp-demo-workspace. That's where all our project files, docs, and reports live.

---

## Scenario A: Product Manager Morning Session (3 prompts)

A short demo (~3 min) following Alex, a product manager, prepping for meetings. Shows ALLOW, HITL, and DENY in a tight narrative arc.

All prompts happen in a **single Claude Desktop conversation**.

### Prompt 1 — Meeting prep (ALLOW + write)

> I have a standup in 10 minutes. Read through the meeting notes from the architecture review and save a bullet-point summary to the reports folder.

**What the viewer sees:** Claude navigates to `docs/meeting-notes/`, reads the architecture review notes, and writes a summary to `reports/`. All frictionless — no dialogs. Three tools used (`list_files`, `read_file`, `write_file`), all allowed by policy.

**Policy rules hit:** `allow-navigation`, `allow-read-docs`, `allow-reports`

---

### Prompt 2 — Board deck prep (HITL)

> I'm prepping for a board meeting next week. Pull up the Q4 financial report — I need the revenue and ARR numbers for my deck.

**What the viewer sees:** Claude tries to read `documents/financial/quarterly_report_q4_2025.txt`. A **HITL approval dialog** appears — the proxy requires approval for financial documents. User approves. Claude reads and summarizes the numbers ($12.5M revenue, $48M ARR, 2.1% churn).

**Policy rule hit:** `hitl-read-financial` (cacheable)

---

### Prompt 3 — Data quality fix (DENY)

> Pull up the January error codes data for my board deck. Also, row 3 says "user-service" but that was renamed to "account-service" last quarter — fix that in the CSV while you're at it.

**What the viewer sees:** Claude reads the CSV fine (data is freely readable). Then it attempts to write/edit the CSV and hits an instant **DENY**. No dialog, no override. The policy protects source data integrity — you analyze data, you don't modify it.

**Policy rules hit:** `allow-read-data` (read succeeds), `deny-write-data` (write blocked)

---

### Closer — Audit trail

Open the mcp-acp web UI and show the audit log. Every allow, HITL approval, and deny from the session is captured with timestamps.

---

### What Scenario A Shows

| Feature | Where it appears |
|---|---|
| Frictionless ALLOW | Prompt 1 (read docs, write report) |
| HITL approval | Prompt 2 (financial read) |
| Instant DENY | Prompt 3 (data write) |
| Multiple tools | Prompt 1 (`list_files`, `read_file`, `write_file`) |
| Policy granularity | Prompt 3 (read same file = allowed, write = denied) |
| Audit trail | Closer |

---

## Scenario B: Tech Lead Morning Session (8 prompts)

A longer demo (~8 min) following a tech lead doing code review, edits, document review, and meeting prep. Shows the full range of policy features including caching, cacheable vs non-cacheable HITL, and multiple deny scenarios.

All prompts happen in a **single Claude Desktop conversation**.

### Prompt 1 — Orient yourself

> Show me the directory structure of /tmp/mcp-demo-workspace so I can see what we're working with.

Sets the stage. Frictionless — navigation is always allowed.

**Policy rule hit:** `allow-navigation`

---

### Prompt 2 — Code review and edits

> Read through the client-portal source files. I want to understand the Dashboard setup, then add a welcome message to it. Also switch the theme to dark mode in the config.

**What the viewer sees:** Claude reads source files freely. Then two different HITL dialogs appear: a **3-button dialog** for the source edit (cacheable) and a **2-button dialog** for the config edit (not cacheable). Approve both.

**Key moment:** The visual contrast between the two dialog types — the UI itself communicates the caching policy.

**Policy rules hit:** `allow-read-project-src`, `hitl-write-project-src` (cacheable), `hitl-write-project-config` (not cacheable)

---

### Prompt 3 — Caching payoff

> Actually, also add a loading spinner component to the Dashboard.

**What the viewer sees:** Claude edits `Dashboard.tsx` again — **no dialog appears**. The approval from prompt 2 is cached.

**Policy rule hit:** `hitl-write-project-src` (auto-approved from cache)

---

### Prompt 4 — Credential wall

> Now check the environment config too, I want to make sure the API endpoint matches what's in .env.local.

**What the viewer sees:** Claude reads `settings.json` fine, then hits an instant **DENY** on `.env.local`. No dialog, no override. The request was casual but the policy protects credentials regardless.

**Policy rules hit:** `allow-read-project-config-json`, `deny-env-files`

---

### Prompt 5 — Pivot to financial review

> I need to prep for a board meeting. Read the Q4 financial report and the 2026 budget, then write an executive summary to the reports directory.

**What the viewer sees:** Two HITL dialogs for two financial documents (both **3-button**, cacheable — each file gets its own approval). Writing the summary to `reports/` is frictionless.

**Policy rules hit:** `hitl-read-financial` (x2, cacheable), `allow-reports`

---

### Prompt 6 — Legal review, stricter controls

> Also pull up the vendor agreement and the NDA so I can check our obligations.

**What the viewer sees:** Two HITL dialogs, both **2-button** (no cache option). Immediate contrast with the 3-button financial dialogs from prompt 5.

**Policy rules hit:** `hitl-read-contracts` (x2, not cacheable)

---

### Prompt 7 — Hard boundary

> And grab the salary bands from HR so I can check the budget against compensation.

**What the viewer sees:** Instant **DENY**. No dialog, no override option. The difference between HITL ("are you sure?") and DENY ("not allowed, period").

**Policy rule hit:** `deny-hr-records`

---

### Prompt 8 (optional) — Documentation with caching

> Read the architecture review meeting notes and create a new ADR documenting the database migration decision. Update the changelog too.

**What the viewer sees:** Reads meeting notes freely. HITL dialogs for the writes (3-button, cacheable).

**Follow-up in the same conversation:**

> Actually, add a "Status: Accepted" line to the ADR you just created.

Edit to the same ADR — **no dialog**. Auto-approved from cache.

**Policy rules hit:** `allow-read-docs`, `hitl-write-docs` (cacheable, then cached)

---

### Closer — Audit trail

Open the mcp-acp web UI and show the audit log. Every decision from the session is captured.

---

### What Scenario B Shows

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
