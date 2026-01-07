# Manual E2E Testing Guide

Manual acceptance testing for mcp-acp-core. Run these tests before releases to verify
all functionality works correctly.

Goal: The purpose of this testing is to confirm functional completeness and behavioural correctness at stage completion, not to assess performance or security guarantees.

---

## Test Execution Record

| Field | Value |
|-------|-------|
| **Date** |23.12.2025|
| **Version** |1|
| **Platform** | macOS-15.7.2-arm64-arm-64bit-Mach-O |
| **FastMCP version** |2.13.3|
| **MCP version** |1.22.0|
| **Python version** |3.13.5|


---

## Environment Setup

| Clients | Version |
|---------|---------|
| Claude Desktop | Version 1.0.2339 (1782e2) |
| MCP Inspector | v0.18.0 |

| Backend Servers | Version |
|-----------------|---------|
| @cyanheads/filesystem-mcp-server | 1.0.4 |
| @modelcontextprotocol/server-filesystem | 2025.8.21 |

After testing, append your full config and logs.

---

## Test Results Summary

| Category | Total | Pass | Fail |
|----------|-------|------|------|
| CLI | 7 | 6 | 1 |
| Configuration | 3 | 3 | 0 |
| Policy | 4 | 4 | 0 |
| HITL | 5 | 5 | 0 |
| HTTP Transport | 4 | 4 | 0 |
| Claude Desktop | 11 | 11 | 0 |
| Audit Integrity | 4 | 4 | 0 |
| Additional Tests | 1 | 1 | 0 |
| **TOTAL** | **39** | **38** | **1** |

---

## CLI Tests

### CLI-01: Version Command

**Steps**:
```bash
mcp-acp-core --version
```

**Expected Output**:
```
mcp-acp-core version 0.1.0
```

**Actual Output**:
```
mcp-acp-core 0.1.0
```

**Status**: [x] Pass  [ ] Fail

---

### CLI-02: Help Command

**Steps**:
```bash
mcp-acp-core --help
```

**Expected Output** (contains):
```
Usage: mcp-acp-core [OPTIONS] COMMAND [ARGS]...

  MCP-ACP-Core: Zero Trust Access Control Proxy for MCP.

Options:
  -v, --version  Show version
  -h, --help     Show this message and exit.

Commands:
  config  Configuration management commands.
  init    Initialize proxy configuration.
  start   Start the proxy server manually (for testing).

Quick Start:
  mcp-acp-core init                     Interactive setup wizard
  mcp-acp-core start                    Test the proxy manually

Non-Interactive Setup:
  mcp-acp-core init --non-interactive \
    --log-dir ~/.mcp-acp-core \
    --server-name my-server \
    --connection-type stdio \
    --command npx \
    --args "-y,@modelcontextprotocol/server-filesystem,/tmp"

Connection Types (--connection-type):
  stdio   Spawn local server process (npx, uvx, python)
  http    Connect to remote HTTP server (requires --url)
  both    Auto-detect: tries HTTP first, falls back to STDIO
  ```

**Expected in system.jsonl**:
```json
{"event": "config_created", ...}
```

**Actual Output**:
```
Usage: mcp-acp-core [OPTIONS] COMMAND [ARGS]...

  MCP-ACP-Core: Zero Trust Access Control Proxy for MCP.

Options:
  -v, --version  Show version
  -h, --help     Show this message and exit.

Commands:
  config  Configuration management commands.
  init    Initialize proxy configuration.
  start   Start the proxy server manually (for testing).

Quick Start:
  mcp-acp-core init                     Interactive setup wizard
  mcp-acp-core start                    Test the proxy manually

Non-Interactive Setup:
  mcp-acp-core init --non-interactive \
    --log-dir ~/.mcp-acp-core \
    --server-name my-server \
    --connection-type stdio \
    --command npx \
    --args "-y,@modelcontextprotocol/server-filesystem,/tmp"

Connection Types (--connection-type):
  stdio   Spawn local server process (npx, uvx, python)
  http    Connect to remote HTTP server (requires --url)
  both    Auto-detect: tries HTTP first, falls back to STDIO
```

**Status**: [x] Pass  [ ] Fail

---

### CLI-03: Init Command (Interactive Setup)

**Steps**:
```bash
# Run init
mcp-acp-core init

# Follow prompts (use defaults or test values)

# Verify files created
ls -la ~/Library/Application\ Support/mcp-acp-core/
```

**Expected Result**:
- Interactive prompts for configuration
- Creates `mcp_acp_core_config.json`
- Creates `policy.json`
- Files contain valid JSON


**Actual Output**:
```
backend healthcheck when configuring http leads to configuration creation failure and ugly error display.
other than that works as expected.
```

**Status**: [ ] Pass  [x] Fail

---

### CLI-04: Non-interactive Setup

**Steps**:
```bash
 mcp-acp-core init --non-interactive \
    --log-dir ~/.mcp-acp-core \
    --server-name mcp-filesystem-server \
    --connection-type stdio \
    --command npx \
    --args "-y,@modelcontextprotocol/server-filesystem,<test-workspace>"
```

**Expected Output**:
```
- where are policy.json and config.json saved to
- configured transport types
```

**Expected in system.jsonl**:
```json
{"event": "config_created", ...}
```

**Actual Output**:
```
Configuration saved to $HOME/Library/Application Support/mcp-acp-core/mcp_acp_core_config.json
Policy saved to $HOME/Library/Application Support/mcp-acp-core/policy.json
Transport: stdio
```

**Status**: [x] Pass  [ ] Fail

---

### CLI-05: Config Path Command

**Steps**:
```bash
mcp-acp-core config path
```

**Expected Output**:
```
$HOME/Library/Application Support/mcp-acp-core/mcp_acp_core_config.json
```

**Actual Output**:
```
$HOME/Library/Application Support/mcp-acp-core/mcp_acp_core_config.json
```

**Status**: [x] Pass  [ ] Fail

---

### CLI-06: Config Show Command

**Steps**:
```bash
mcp-acp-core config show
```

**Expected Output** (contains):
- Backend server name
- Transport configuration
- Logging settings

**Actual Output**:
```
mcp-acp-core configuration:

Logging:
  log_dir: ~/.mcp-acp-core
  log_level: DEBUG
  include_payloads: True

  Log files (computed from log_dir):
    audit: $HOME/.mcp-acp-core/mcp_acp_core_logs/audit/operations.jsonl
    client_wire: $HOME/.mcp-acp-core/mcp_acp_core_logs/debug/client_wire.jsonl
    backend_wire: $HOME/.mcp-acp-core/mcp_acp_core_logs/debug/backend_wire.jsonl
    system: $HOME/.mcp-acp-core/mcp_acp_core_logs/system/system.jsonl
    config_history: $HOME/.mcp-acp-core/mcp_acp_core_logs/system/config_history.jsonl

Backend:
  server_name: cyanheads-filesystem-mcp-server
  transport: stdio
  stdio:
    command: node
    args: ['<workspace>/filesystem-mcp-server/dist/index.js']
  http: (not configured)

Proxy:
  name: mcp-acp-core

Config file: $HOME/Library/Application Support/mcp-acp-core/mcp_acp_core_config.json
```

**Status**: [x] Pass  [ ] Fail

---

### CLI-07: Start Command

**Steps**:
```bash
mcp-acp-core start
# (Press Ctrl+C to stop after observing startup)
```

**Expected Output** (contains):
```
Starting MCP-ACP-Core proxy...
proxy version
config version
policy version
additional info
configured backend
backend transport used
```

**Expected in system.jsonl**:
```json
{"event": "config_loaded", ...}
```

**Actual Output**:
```
mcp-acp-core v0.1.0
Config version: v2
Policy version: v2
Backend: my-server
Backend transport: stdio
--------------------------------------------------
Proxy server ready - listening on STDIO

[12/23/25 19:20:22]  INFO     Starting MCP server 'mcp-acp-core' with transport 'stdio'     
```

**Status**: [x] Pass  [ ] Fail

---

## Configuration Tests

### CFG-01: Invalid JSON Config

**Precondition**: Backup valid config first

**Steps**:
```bash
# Backup
cp ~/Library/Application\ Support/mcp-acp-core/mcp_acp_core_config.json /tmp/config_backup.json

# Break JSON
echo "{ invalid json" > ~/Library/Application\ Support/mcp-acp-core/mcp_acp_core_config.json

# Try to start
mcp-acp-core start

# Restore
cp /tmp/config_backup.json ~/Library/Application\ Support/mcp-acp-core/mcp_acp_core_config.json
```

**Expected Output**: Error message about invalid JSON

**Actual Output**:
```
Error: Invalid configuration: Invalid JSON in config file $HOME/Library/Application Support/mcp-acp-core/mcp_acp_core_config.json: Expecting ',' delimiter: line 15 column 3 (char 338))
```

**Status**: [x] Pass  [ ] Fail

---

### CFG-02: Missing Config File

**Steps**:
```bash
# Backup and remove
mv ~/Library/Application\ Support/mcp-acp-core/mcp_acp_core_config.json /tmp/

# Try to start
mcp-acp-core start

# Restore
mv /tmp/mcp_acp_core_config.json ~/Library/Application\ Support/mcp-acp-core/
```

**Expected Output**: Error suggesting to run `mcp-acp-core init`

**Actual Output**:
```
Error: Configuration not found at $HOME/Library/Application Support/mcp-acp-core/mcp_acp_core_config.json.
Run 'mcp-acp-core init' to create a configuration file.
```

**Status**: [x] Pass  [ ] Fail

---

### CFG-03: Invalid Policy JSON

**Steps**:
```bash
# Backup
cp ~/Library/Application\ Support/mcp-acp-core/policy.json /tmp/policy_backup.json

# Break JSON
echo "{ bad policy" > ~/Library/Application\ Support/mcp-acp-core/policy.json

# Try to start
mcp-acp-core start

# Restore
cp /tmp/policy_backup.json ~/Library/Application\ Support/mcp-acp-core/policy.json
```

**Expected Output**: Error about invalid policy JSON

**Actual Output**:
```
Error: Invalid policy: Invalid policy configuration in $HOME/Library/Application Support/mcp-acp-core/policy.json:
  - rules.2.effect: Field required

Edit the policy file or run 'mcp-acp-core init' to 
```

**Status**: [x] Pass  [ ] Fail

---

## Policy Tests

### POL-01: Allow Rule Matches

**Tool**: MCP Inspector or Claude Desktop

**Steps**:
1. Call `read_file` on `<test-workspace>/hello-world.md`

**Expected Result**: File content returned

**Status**: [x] Pass  [ ] Fail

---

### POL-02: Deny Rule Matches (secrets)

**Steps**:
1. Call `read_file` on `<test-workspace>/secrets/credentials.txt`

**Expected Result**: Permission denied error

**Actual Output**:
```
Policy denied: tools/call on<test-workspace>/tmp-dir/secrets/credentials.txt
```

**Status**: [x] Pass  [ ] Fail

---

### POL-03: Default Deny (No Rule Matches)

**Steps**:
1. Call `read_file` on `/tmp/outside-projects.txt` (outside allowed path)

**Expected Result**: Permission denied

**Actual Output**:
```
"Policy denied: tools/call on /tmp/outside-projects.txt"
```

**Status**: [x] Pass  [ ] Fail

---

### POL-04: HITL Rule Triggers Dialog

**Steps**:
1. Call `write_file` to `<test-workspace>/test-pol05.txt`
2. Observe dialog appears

**Expected Result**: macOS dialog appears with approval request

**Expected Dialog Content**:
```
Tool: write_file
Path:<test-workspace>/tmp-dir/test-pol05.txt
Rule: hitl-write-project
User: <username>

Auto-deny in 30s
[Return] Deny  •  [Tab+Return] Allow
```

**Actual Output**:
```
"Successfully wrote content to<test-workspace>/tmp-dir/test-pol05.txt"
```

**Status**: [x] Pass  [ ] Fail

---

## HITL Tests

### HITL-01: User Approves

**Steps**:
1. Call `write_file` to `<test-workspace>/hitl-approved.txt` with content "test"
2. Click **Allow** in dialog

**Expected Result**: File created successfully

**Status**: [x] Pass  [ ] Fail

---

### HITL-02: User Denies

**Steps**:
1. Call `write_file` to `<test-workspace>/hitl-denied.txt`
2. Click **Deny** in dialog

**Expected Result**: Error returned, file NOT created

**Actual Output**:
```
"User denied: tools/call on<test-workspace>/tmp-dir/hitl-denied.txt"
```

**Status**: [x] Pass  [ ] Fail

---

### HITL-03: Timeout (Auto-Deny)

**Precondition**: Set `hitl.timeout_seconds` to 10 for faster testing (optional)

**Steps**:
1. Call `write_file` to `<test-workspace>/hitl-timeout.txt`
2. **Do nothing** - wait for timeout

**Expected Result**: Dialog closes, request denied

**Status**: [x] Pass  [ ] Fail

---

### HITL-04: Special Characters in Path

**Steps**:
1. Call `write_file` to `<test-workspace>/file with spaces.txt`
2. Observe dialog displays correctly

**Expected Result**: Path shown correctly, no escaping issues

**Status**: [x] Pass  [ ] Fail

---

## HTTP Transport Tests

These tests verify HTTP/SSE transport mode (alternative to stdio).

### HTTP-01: Configure HTTP Backend

**Precondition**: Backend MCP server running on HTTP (e.g., `http://localhost:3010/mcp`)

---

### HTTP-02: Start with HTTP Transport

**Steps**:
```bash
mcp-acp-core start
```


**Status**: [x] Pass  [ ] Fail

---

### HTTP-03: HTTP Backend Connection Failure

**Steps**:
1. Configure HTTP URL to non-existent server: `http://localhost:9999/mcp`
2. Start proxy and attempt operation

**Expected Result**: Graceful error handling, logged to system.jsonl

**Actual Output**:
```
"Client failed to connect: All connection attempts failed"
```

**Status**: [x] Pass  [ ] Fail

---

### HTTP-04: Switch Between Transports

**Purpose**: Verify seamless switching between stdio and HTTP

**Steps**:
1. Test with stdio transport 
2. Switch to HTTP transport
3. Restart proxy
4. Verify same policy enforcement works

**Expected Result**: Both transports enforce identical policies

**Status**: [x] Pass  [ ] Fail

---

## Claude Desktop Tests

### CD-01: MCP Server Appears

**Precondition**: Claude Desktop config includes mcp-acp-core

**Steps**:
1. Open Claude Desktop
2. Check MCP server status

**Expected Result**: mcp-acp-core server shown as connected

**Status**: [x] Pass  [ ] Fail

---

### CD-02: Conversational Read

**Steps**:
1. Ask Claude: "Read the file<test-workspace>/tmp-dir/hello-world.md"

**Expected Result**: Claude shows file content

**Status**: [x] Pass  [ ] Fail

---

### CD-03: Conversational Write with Approval

**Steps**:
1. Ask Claude: "Create a file<test-workspace>/tmp-dir/claude-test.txt with content 'Hello from Claude'"
2. Approve in dialog

**Expected Result**: Claude confirms file created


**Verification**:
```bash
cat<test-workspace>/tmp-dir/claude-test.txt
```

**Status**: [x] Pass  [ ] Fail

---

### CD-04: Conversational Write with Denial

**Steps**:
1. Ask Claude: "Create a file<test-workspace>/tmp-dir/denied-by-user.txt"
2. Deny in dialog

**Expected Result**: Claude reports operation was denied

**Status**: [x] Pass  [ ] Fail

---

### CD-05: Access Denied Path

**Steps**:
1. Ask Claude: "Read<test-workspace>/tmp-dir/secrets/credentials.txt"

**Expected Result**: Claude reports access denied

**Actual Response**:
```
It looks like the file creation was denied. This could be due to permission restrictions on that path or the operation being blocked by the system. Would you like me to try creating the file in a different location?
```

**Status**: [x] Pass  [ ] Fail

---

### CD-06: Multiple Operations (Dialog Fatigue)

**Steps**:
1. Ask Claude: "Create three files in<test-workspace>/tmp-dir/: a.txt, b.txt, c.txt"
2. Observe separate dialog for each file

**Expected Result**: Three separate HITL dialogs appear

**Actual Response**:
```
Here's the result:

a.txt — created successfully
b.txt — denied (the operation was blocked)
c.txt — created successfully

Would you like me to retry creating b.txt or investigate why it was denied?
```

note: claude waits for one operation to be completed before starting the next...

**Status**: [x] Pass  [ ] Fail

---

### CD-07: Tool Chaining (Read-Modify-Write)

**Purpose**: Test Claude's ability to chain multiple tools with different policy outcomes

**Steps**:
1. Ask Claude: "Read<test-workspace>/tmp-dir/hello-world.md, add a timestamp at the end, and write it back"

**Expected Result**:
- First tool call: `read_file` - allowed (no dialog)
- Second tool call: `write_file` - HITL dialog appears
- After approval: File is updated with timestamp

**Verification**:
```bash
# Check both operations logged with same session_id
tail -5 ~/.mcp-acp-core/mcp_acp_core_logs/audit/decisions.jsonl | jq '.session_id'
```
**Status**: [x] Pass  [ ] Fail

---

### CD-08: Complex Tool Chain (List-Read-Transform-Write)

**Purpose**: Test longer tool chain with multiple allowed operations before HITL

**Steps**:
1. Ask Claude: "List files in<test-workspace>/tmp-dir/, find any .md file, read it, summarize the content, and write the summary to summary.txt"

**Expected Result**:
- `list_directory` - allowed (if policy allows, or denied)
- `read_file` - allowed
- `write_file` - HITL dialog

**Note**: Claude may call tools in different orders. Observe the actual sequence in logs.

**Status**: [x] Pass  [ ] Fail

---

### CD-09: Denied Operation in Chain

**Purpose**: Test how Claude handles denial mid-chain

**Steps**:
1. Ask Claude: "Read<test-workspace>/tmp-dir/secrets/credentials.txt and tell me what's in it"

**Expected Result**:
- `read_file` to secrets path - **denied by policy**
- Claude reports access was denied
- No HITL dialog (deny is immediate)

**Status**: [x] Pass  [ ] Fail

---

### CD-10: Claude Retry Behavior After Denial

**Purpose**: Observe how Claude responds and whether it retries after policy denial

**Steps**:
1. Ask Claude: "Read the file<test-workspace>/tmp-dir/secrets/credentials.txt and show me the contents"
2. Observe Claude's response after denial
3. In same conversation, ask: "Try again to read that file"

**Expected Result**:
- First attempt: Claude reports access denied
- Second attempt: Claude should either:
  - Explain it cannot access that path (ideal)
  - Retry and get denied again (acceptable but wasteful)
  - NOT claim it succeeded or make up content

**Observe**:
- Does Claude explain WHY access was denied?
- Does Claude suggest alternatives?
- Does Claude keep retrying in a loop? (bad)

**Status**: [x] Pass  [ ] Fail

---

### CD-11: Claude Behavior on HITL Timeout Mid-Conversation

**Purpose**: Test Claude's response when user doesn't respond to HITL dialog

**Precondition**: Set shorter hitl timeout for faster testing:


**Steps**:
1. Ask Claude: "Create a file<test-workspace>/tmp-dir/timeout-test.txt with 'hello'"
2. When HITL dialog appears, **do nothing** - let it timeout
3. Observe Claude's response after timeout

**Expected Result**:
- Claude receives timeout/denial error
- Claude reports the operation was not completed
- Claude does NOT claim the file was created

**Observe**:
- How does Claude explain the timeout?
- Does Claude offer to retry?
- Is Claude's message helpful to the user?

**Status**: [x] Pass  [ ] Fail


---

## HITL Queue Tests

These tests verify behavior when multiple HITL requests arrive in succession.

### HITL-10: Queued HITL Requests (Sequential Response)

**Purpose**: Test dialog queue when Claude triggers multiple writes

**Precondition**: For faster testing, temporarily reduce timeout:
```json
"hitl": { "timeout_seconds": 10 }
```

**Steps**:
1. Ask Claude: "Create three files:<test-workspace>/tmp-dir/q1.txt with 'first', q2.txt with 'second', q3.txt with 'third'"
2. Observe dialog behavior:
   - Do dialogs appear one at a time (queued)?
   - Or do they overlap/stack?
3. Respond to each:
   - First dialog: **Allow**
   - Second dialog: **Deny**
   - Third dialog: **Let timeout**

**Expected Result**:
- Dialogs appear sequentially (one at a time)
- First file created (allowed)
- Second file NOT created (denied)
- Third file NOT created (timeout)

**Verification**:
```bash
ls<test-workspace>/tmp-dir/q*.txt
# Should only show q1.txt
```

**Status**: [x] Pass  [ ] Fail

**Note**: Dialogs appear sequentially because Claude Desktop/Code serializes requests -
it waits for each operation to complete before sending the next. This means true
concurrent HITL requests never occur. 

---

### Mixed Results in Queue

**Purpose**: Verify each queued request is handled independently

**Steps**:
1. Ask Claude: "Create files test-a.txt, test-b.txt, test-c.txt in tmp-dir with contents A, B, C"
2. Respond: Allow, Deny, Allow

**Expected Result**:
- test-a.txt created (A)
- test-b.txt NOT created
- test-c.txt created (C)

**Verification**:
```bash
cat<test-workspace>/tmp-dir/test-a.txt  # Should show: A
ls<test-workspace>/tmp-dir/test-b.txt   # Should not exist
cat<test-workspace>/tmp-dir/test-c.txt  # Should show: C
```

**Status**: [x] Pass  [ ] Fail

---

## Audit Log Integrity Tests

These tests verify the fail-closed audit log integrity system. The proxy shuts down
when audit logs are compromised (deleted, moved, or replaced) to maintain audit trail integrity.

**Key Files**:
- Audit logs: `~/.mcp-acp-core/mcp_acp_core_logs/audit/` (operations.jsonl, decisions.jsonl)
- System logs: `~/.mcp-acp-core/mcp_acp_core_logs/system/` (system.jsonl, etc.)
- Last crash breadcrumb: `~/.mcp-acp-core/mcp_acp_core_logs/.last_crash`
- Emergency audit (fallback): `~/Library/Application Support/mcp-acp-core/emergency_audit.jsonl`

**Exit Code**: 10 (AuditFailure)

---

### AUD-01: Single Audit File Deletion

**Purpose**: Verify proxy shuts down when a single audit file is deleted

**Precondition**: Proxy running, note PID: `pgrep -f "mcp-acp-core"`

**Steps**:
1. Start proxy and connect via MCP Inspector
2. Note the proxy PID
3. In a terminal, delete the operations log:
   ```bash
   rm ~/.mcp-acp-core/mcp_acp_core_logs/audit/operations.jsonl
   ```
4. In MCP Inspector, call any tool (e.g., `read_file`)

**Expected Result**:
- MCP Inspector shows error: `MCP error -32002: Audit failure` or similar
- Proxy process exits (PID no longer exists)
- `.last_crash` file created

**Verification**:
```bash
# Check proxy exited
pgrep -f "mcp-acp-core"
# Should return nothing

# Check last_crash file
cat ~/.mcp-acp-core/mcp_acp_core_logs/.last_crash
# Should contain failure reason mentioning missing file
```

**Expected .last_crash Content**:
```
<timestamp>
failure_type: audit_failure
exit_code: 10
reason: Audit log compromised - missing: audit/operations.jsonl
```

"Audit log failure - operation logged to fallback, proxy shutting down"
"MCP error -32602: Invalid request parameters"
2025-12-23T18:45:31.238979+00:00
audit_failure
Audit log compromised - missing: audit/operations.jsonl


**Status**: [x] Pass  [ ] Fail

---

### AUD-02: Full Audit Directory Deletion

**Purpose**: Verify comprehensive missing file report when entire audit directory is deleted

**Precondition**: Proxy running, note PID

**Steps**:
1. Start proxy and connect via MCP Inspector
2. Note the proxy PID
3. In a terminal, delete the entire audit directory:
   ```bash
   rm -rf ~/.mcp-acp-core/mcp_acp_core_logs/audit/
   ```
4. In MCP Inspector, call any tool

**Expected Result**:
- Proxy exits with exit code 10
- `.last_crash` reports ALL missing files (not just one)

**Verification**:
```bash
cat ~/.mcp-acp-core/mcp_acp_core_logs/.last_crash
```

**Expected .last_crash Content** (should list all missing audit files):
```
<timestamp>
failure_type: audit_failure
exit_code: 10
reason: Audit log compromised - missing: audit/, audit/operations.jsonl, audit/decisions.jsonl
```

**Status**: [x] Pass  [ ] Fail

---

### AUD-03: Full Log Directory Deletion (Fallback Chain)

**Purpose**: Verify emergency_audit.jsonl fallback when both audit/ and system/ are deleted

**Precondition**:
- Proxy running
- Note PID
- Clear any existing emergency audit: `rm -f ~/Library/Application\ Support/mcp-acp-core/emergency_audit.jsonl`

**Steps**:
1. Start proxy and connect via MCP Inspector
2. In a terminal, delete both directories:
   ```bash
   rm -rf ~/.mcp-acp-core/mcp_acp_core_logs/audit/
   rm -rf ~/.mcp-acp-core/mcp_acp_core_logs/system/
   ```
3. In MCP Inspector, call any tool

**Expected Result**:
- Proxy exits
- Emergency audit file created in config directory

**Verification**:
```bash
# Check emergency audit file exists and has content
cat ~/Library/Application\ Support/mcp-acp-core/emergency_audit.jsonl | jq '.'
```

**Expected emergency_audit.jsonl Entry**

2025-12-23T18:47:22.446233+00:00
audit_failure
Audit log compromised - missing: audit/, system/

**Status**: [x] Pass  [ ] Fail

---

### AUD-05: Log Rotation Attack Detection

**Purpose**: Verify proxy detects simulated log rotation attack (file replaced with new empty file)

**Background**: An attacker could try to hide their activity by replacing the audit log
with a new empty file while keeping the same filename. The proxy detects this via inode
verification - if the file's device ID or inode changes, it means the original file was
replaced even if a file with the same name exists.

**Precondition**: Proxy running, note original inode

**Steps**:
1. Start proxy and perform an operation to create log entries
2. Note the inode:
   ```bash
   ls -i ~/.mcp-acp-core/mcp_acp_core_logs/audit/operations.jsonl
   ```
3. Replace the file (delete + create new):
   ```bash
   rm ~/.mcp-acp-core/mcp_acp_core_logs/audit/operations.jsonl
   touch ~/.mcp-acp-core/mcp_acp_core_logs/audit/operations.jsonl
   ```
4. Verify inode changed:
   ```bash
   ls -i ~/.mcp-acp-core/mcp_acp_core_logs/audit/operations.jsonl
   # Should be different from step 2
   ```
5. In MCP Inspector, call any tool

**Expected Result**:
- Proxy detects file was replaced (different inode)
- Proxy shuts down with audit failure
- `.last_crash` mentions file replacement

**Expected .last_crash Content**:
```
<timestamp>
failure_type: audit_failure
exit_code: 10
reason: Audit log file replaced: <path>
```
- Original inode: 17249644
- New inode: 17249922

2025-12-23T18:50:10.425475+00:00
audit_failure
Audit log file replaced or moved: $HOME/.mcp-acp-core/mcp_acp_core_logs/audit/operations.jsonl

**Status**: [x] Pass  [ ] Fail

---

## Cleanup

cleanup tmp-dir, config and logs

---

## Notes

_Space for tester notes, issues found, observations:_

### Session 2025-12-23

**Coverage:** All CLI commands and options were manually tested, not only the ones listed in this document. Additional exploratory testing was performed beyond the documented test cases.

**Issues Found:**

- **policy_version validation error** - MCP Inspector can't connect. `DecisionEvent.policy_version` required string but gets `None`. 

- **init overwrite prompt bug** - When config is deleted but policy existed, `init` still asks "Files already exist. Overwrite?" - confusing since config doesn't exist. 

- **HTTP health check crash** - When HTTP backend is unreachable during interactive init, shows full Python traceback and aborted instead of handling gracefully. Wrong exception caught (only `TimeoutError`/`ConnectionError`, but fastmcp wraps in `RuntimeError`). Limited recovery options (only yes/no).

- **Missing CLI help example** - Root help only shows stdio example, not how to configure both transports.

- **HITL queue indicators never shown** - Claude Desktop and Claude Code both serialize
  MCP requests, waiting for each to complete before sending the next. This means true
  concurrent HITL requests never occur during normal usage, so queue indicators ("Queue:
  #2 pending") are never displayed. Programmatic testing (HITL-13) revealed the queue
  logic is also ineffective due to synchronous subprocess blocking. See Additional Tests.

---

## Additional Tests

Tests added during investigation of specific behaviors.

---

### HITL-13: Concurrent HITL Queue Test (Programmatic)

**Purpose**: Test whether HITL dialogs queue correctly when multiple requests arrive simultaneously

**Background**: HITL-10 showed dialogs appear sequentially with Claude, but we couldn't
tell if this was due to Claude serializing requests or the queue logic not working.
This programmatic test fires truly concurrent requests to isolate the behavior.

**Test File**: `tests/test_hitl_queue.py`

**Setup**:
1. Create a test file:
   ```bash
   touch<test-workspace>/tmp-dir/hitl-test.txt
   ```

2. Add an HITL rule to policy.json:
   ```json
   {
     "id": "hitl-test",
     "effect": "hitl",
     "conditions": {
       "path_pattern": "<test-workspace>/hitl-test.txt"
     }
   }
   ```

3. Optionally reduce timeout for faster testing:
   ```json
   "hitl": { "timeout_seconds": 10 }
   ```

**Steps**:
```bash
uv run python tests/test_hitl_queue.py --count 5
```

**Expected Result** (if queuing worked):
- First dialog plays sound, shows no queue indicator
- Subsequent dialogs show "Queue: #2 pending", "#3 pending", etc.
- No sound for queued dialogs

**Actual Result**:
- Dialogs appear one after another (sequentially, not concurrently)
- Each dialog plays sound
- No queue indicators shown
- All requests complete, but serially

**Root Cause**:
The queuing logic in `HITLHandler` (tracking `_pending_count` and `queue_position`) is
currently ineffective because `_show_macos_dialog` uses synchronous `subprocess.run()`
which blocks the entire async event loop. This means:
1. Request 0 increments `_pending_count` to 1, shows dialog (BLOCKS event loop)
2. Requests 1-4 are queued in the event loop, waiting
3. Request 0's dialog finishes, decrements `_pending_count` to 0
4. Request 1 runs, increments `_pending_count` to 1 again (never > 1)

**Resolution**:
The queuing logic is preserved for future async HITL backends (web UI, notification
systems, non-blocking platform APIs). A code comment was added to `hitl.py:92-100`
documenting this limitation and how to fix it if needed (use `run_in_executor`).

**Status**: [x] Pass (documents known limitation)  [ ] Fail

**Note**: This is not a bug - it's a design tradeoff. The synchronous blocking is
intentional for security (prevents race conditions). The queuing logic will work
correctly when/if an async HITL backend is implemented.

---

## Test Session Log

Append your configuration and logs after each test session. This creates a complete
record of what was tested.