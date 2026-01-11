# Manual E2E Testing Guide

Manual acceptance testing for mcp-acp-extended. Run these tests before releases to verify all functionality works correctly.

> **Note**: Most of these scenarios have been tested extensively throughout development. This document serves as a final verification checklist to systematically confirm expected behavior and catch any regressions.

---

## Test Execution Record

| Field | Value |
|-------|-------|
| **Date** |04.01.2026|
| **Version** |1|
| **Platform** | macOS-15.7.2-arm64-arm-64bit-Mach-O |
| **FastMCP version** |2.14.1|
| **MCP version** |1.25.0|
| **Python version** |3.13.5|

---

## Test Summary

| Category | Total | Pass | Fail | Skip | N/A |
|----------|-------|------|------|------|-----|
| Policy Enforcement (POLICY) | 2 | 1 | | | 1 |
| mTLS Transport (MTLS) | 7 | 6 | 1 | | |
| HITL Approval Caching (HITL-CACHE) | 12 | 10 | | | 2 |
| Rate Limiting (RATE) | 5 | 5 | | | |
| **Total** | **26** | **22** | **1** | | **3** |

**Legend**: Pass = Test passed, Fail = Test failed, Skip = Skipped (preconditions not met), N/A = Not Implemented


## Policy Enforcement Tests

### Test Directory Setup

These tests require a test directory at `<test-workspace>/tmp-dir` with the following structure:

```
tmp-dir/
├── hello-world.md          # "hellllooooo"
├── potatoes.md             # "# potatos, potats, potatooeeeess alias truffls"
├── secrets/                # DENY access (sensitive data)
│   ├── credentials.txt     # "PASSWORD=hunter2"
│   └── token.txt           # "API_KEY=secret123"
├── private/                # DENY access (private config)
│   └── config.env          # "USER=admin"
└── projects/               # ALLOW/HITL access (working area)
    ├── hello_world.py      # "print("Hello, World!")"
    └── example-project/
        ├── README.md       # "# Example Project"
        ├── app.py          # "print('hello world')"
        └── test-file       # "This is a test file!"
```


### Test Policy

These tests use the following policy:
```json
{
  "version": "1",
  "default_action": "deny",
  "rules": [
    {
      "id": "allow-read-tmp-dir",
      "effect": "allow",
      "description": "Allow reading from tmp-dir",
      "conditions": {
        "tool_name": "read*",
        "path_pattern": "<test-workspace>/tmp-dir/**"
      }
    },
    {
      "id": "hitl-read-py-files",
      "effect": "hitl",
      "description": "HITL for Python files",
      "conditions": {
        "tool_name": "read*",
        "extension": ".py"
      }
    },
    {
      "id": "hitl-write-project",
      "effect": "hitl",
      "description": "HITL for writes in Projects",
      "conditions": {
        "tool_name": "write*",
        "path_pattern": "<test-workspace>/**"
      }
    },
    {
      "id": "allow-write-tmp-files",
      "effect": "allow",
      "description": "Allow writing .tmp files",
      "conditions": {
        "tool_name": "write*",
        "extension": ".tmp"
      }
    },
    {
      "id": "hitl-delete-project",
      "effect": "hitl",
      "description": "HITL for deletes in Projects",
      "conditions": {
        "tool_name": ["delete*", "remove*"],
        "path_pattern": "<test-workspace>/**"
      }
    },
    {
      "id": "deny-delete-py-files",
      "effect": "deny",
      "description": "Never delete Python files",
      "conditions": {
        "tool_name": ["delete*", "remove*"],
        "extension": ".py"
      }
    },
    {
      "id": "deny-sensitive-dirs",
      "effect": "deny",
      "description": "Deny secrets and private dirs",
      "conditions": {
        "path_pattern": ["**/secrets/**", "**/private/**"]
      }
    },
    {
      "id": "allow-copy-within-projects",
      "effect": "allow",
      "conditions": {
        "tool_name": "copy*",
        "source_path": "<test-workspace>/tmp-dir/projects/**",
        "dest_path": "<test-workspace>/tmp-dir/projects/**"
      }
    },
    {
      "id": "deny-copy-sensitive",
      "effect": "deny",
      "description": "Deny copy/move to sensitive dirs",
      "conditions": {
        "tool_name": ["copy*", "move*"],
        "dest_path": ["**/secrets/**", "**/private/**"]
      }
    },
    {
      "id": "hitl-move-within-projects",
      "effect": "hitl",
      "conditions": {
        "tool_name": "move*",
        "source_path": "<test-workspace>/tmp-dir/projects/**",
        "dest_path": "<test-workspace>/tmp-dir/projects/**"
      }
    }
  ],
  "hitl": {
    "timeout_seconds": 30,
    "default_on_timeout": "deny"
  }
}

```

#### POLICY-01: Subject ID Binding

**Purpose**: Verify policy rules can be bound to specific user IDs

**Status**: [ ] Pass  [ ] Fail  [x] N/A

**Reason**: Single-user scope - subject_id policy conditions not applicable. Session binding validation (SESSIONS-04 in testing-0.md) already covers identity security. The subject_id is logged in decisions.jsonl for audit purposes.

---

#### POLICY-02: Decision Trace in Logs

**Purpose**: Verify decisions.jsonl includes explanation/trace of rule matching

**Status**: [x] Pass  [ ] Fail 

**Actual Result**:
{"time": "2026-01-04T07:38:22.762Z", "event": "policy_decision", "decision": "hitl", "hitl_outcome": "user_allowed", "hitl_cache_hit": false, "matched_rules": [{"id": "allow-read-tmp-dir", "effect": "allow", "description": "Allow reading from tmp-dir"}, {"id": "hitl-read-py-files", "effect": "hitl", "description": "HITL for Python files"}], "final_rule": "hitl-read-py-files", "mcp_method": "tools/call", "tool_name": "read_file", "path": "<test-workspace>/tmp-dir/projects/hello_world.py", "subject_id": "<user-2-subject-id>", "backend_id": "cyanheads", "side_effects": ["fs_read"], "policy_version": "v2", "policy_eval_ms": 0.47, "policy_hitl_ms": 5191.47, "policy_total_ms": 5191.94, "request_id": "4", "session_id": "55a62561-9bfe-4299-9c47-460131edb7bf"}
{"time": "2026-01-04T07:38:49.939Z", "event": "policy_decision", "decision": "deny", "matched_rules": [{"id": "allow-read-tmp-dir", "effect": "allow", "description": "Allow reading from tmp-dir"}, {"id": "deny-sensitive-dirs", "effect": "deny", "description": "Deny secrets and private dirs"}], "final_rule": "deny-sensitive-dirs", "mcp_method": "tools/call", "tool_name": "read_file", "path": "<test-workspace>/tmp-dir/secrets/credentials.txt", "subject_id": "<user-2-subject-id>", "backend_id": "cyanheads", "side_effects": ["fs_read"], "policy_version": "v2", "policy_eval_ms": 0.12, "policy_total_ms": 0.12, "request_id": "5", "session_id": "55a62561-9bfe-4299-9c47-460131edb7bf"}


---

## mTLS Transport Tests

These tests verify mutual TLS authentication for HTTP backends.

### Setup: Generate Test Certificates

```bash
# Define certs location (used throughout mTLS tests)
export CERTS=/tmp/mtls-test-certs

# Create certs directory
mkdir -p $CERTS
cd $CERTS

# Generate CA
openssl genrsa -out ca-key.pem 4096
openssl req -new -x509 -days 365 -key ca-key.pem -out ca-cert.pem \
  -subj "/CN=Test CA/O=MCP Test" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

# Generate server cert
openssl genrsa -out server-key.pem 4096
openssl req -new -key server-key.pem -out server.csr \
  -subj "/CN=localhost/O=MCP Test"
openssl x509 -req -days 365 -in server.csr -CA ca-cert.pem -CAkey ca-key.pem \
  -CAcreateserial -out server-cert.pem \
  -extfile <(echo "subjectAltName=DNS:localhost,IP:127.0.0.1
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth")

# Generate client cert (for proxy)
openssl genrsa -out client-key.pem 4096
openssl req -new -key client-key.pem -out client.csr \
  -subj "/CN=mcp-proxy/O=MCP Test"
openssl x509 -req -days 365 -in client.csr -CA ca-cert.pem -CAkey ca-key.pem \
  -CAcreateserial -out client-cert.pem \
  -extfile <(echo "keyUsage=digitalSignature
extendedKeyUsage=clientAuth")

# Verify
openssl verify -CAfile ca-cert.pem server-cert.pem
openssl verify -CAfile ca-cert.pem client-cert.pem
```

### Setup: Create mTLS Test Server

```bash
cat > /tmp/test_mtls_server.py << 'EOF'
"""FastMCP HTTPS server with mTLS (requires client certificate)."""
import ssl
from pathlib import Path

import uvicorn
from fastmcp import FastMCP

CERT_DIR = Path("/tmp/mtls-test-certs")

mcp = FastMCP("mtls-test-server")

@mcp.tool()
def secure_ping() -> str:
    """Return pong from mTLS-protected server."""
    return "secure pong - mTLS verified!"

@mcp.tool()
def echo(message: str) -> str:
    """Echo the message back."""
    return f"Echo from mTLS server: {message}"

if __name__ == "__main__":
    app = mcp.http_app()
    uvicorn.run(
        app,
        host="127.0.0.1",
        port=9443,
        ssl_keyfile=str(CERT_DIR / "server-key.pem"),
        ssl_certfile=str(CERT_DIR / "server-cert.pem"),
        ssl_ca_certs=str(CERT_DIR / "ca-cert.pem"),
        ssl_cert_reqs=ssl.CERT_REQUIRED,
    )
EOF
```

**Start the mTLS backend:**
```bash
# Terminal 1: Start the mTLS server (requires fastmcp in environment)
python3 /tmp/test_mtls_server.py
```

**Verify mTLS is working:**
```bash
# This should work (with client cert) - returns "Not Found" which is OK:
curl --cacert $CERTS/ca-cert.pem \
     --cert $CERTS/client-cert.pem \
     --key $CERTS/client-key.pem \
     https://127.0.0.1:9443/
# Expected: "Not Found" (proves SSL works, / is not a valid endpoint)

# This should FAIL (no client cert) - connection reset:
curl --cacert $CERTS/ca-cert.pem https://127.0.0.1:9443/
# Expected: "Connection reset by peer" (server requires client cert)
```

**Note:** The mTLS test server is for verifying SSL/TLS certificate exchange only.
For full MCP protocol testing, use a real MCP backend that supports mTLS.

### Setup: Configure Proxy for mTLS Backend

**Add mTLS to existing config**
```bash
mcp-acp-extended config edit

# Add/update the auth.mtls section:
# {
#   "auth": {
#     "oidc": { ... },
#     "mtls": {
#       "client_cert_path": "/tmp/mtls-test-certs/client-cert.pem",
#       "client_key_path": "/tmp/mtls-test-certs/client-key.pem",
#       "ca_bundle_path": "/tmp/mtls-test-certs/ca-cert.pem"
#     }
#   },
#   "backend": {
#     "http": {
#       "url": "https://127.0.0.1:9443/mcp"
#     }
#   }
# }
```

---

### MTLS-01: HTTPS Backend WITH mTLS

**Purpose**: Verify proxy connects to mTLS-required backend

**Steps**:
1. Start mTLS server:
   ```bash
   python3 /tmp/test_mtls_server.py &
   ```
2. Add mTLS config:
   ```bash
   mcp-acp-extended config edit
   ```
   Add to config:
   ```json
   {
     "auth": {
       "mtls": {
         "client_cert_path": "/tmp/mtls-test-certs/client-cert.pem",
         "client_key_path": "/tmp/mtls-test-certs/client-key.pem",
         "ca_bundle_path": "/tmp/mtls-test-certs/ca-cert.pem"
       }
     },
     "backend": {
       "http": {
         "url": "https://127.0.0.1:9443/mcp"
       }
     }
   }
   ```
3. Check status: `mcp-acp-extended auth status`
4. Start proxy: `mcp-acp-extended start`

**Expected Result**:
- `auth status` shows mTLS cert status
- Proxy connects successfully with mTLS
- Health check passes

**Status**: [x] Pass  [ ] Fail
mTLS Certificate
  Client cert: /tmp/mtls-test-certs/client-cert.pem
  Client key: /tmp/mtls-test-certs/client-key.pem
  CA bundle: /tmp/mtls-test-certs/ca-cert.pem
  Status: Valid
  Expires in: 364 days
Backend transport: streamablehttp with mTLS

---

### MTLS-02: mTLS Without Client Cert (Should Fail)

**Purpose**: Verify connection fails when mTLS required but not configured

**Steps**:
1. Start mTLS server (requires client cert)
2. Configure proxy WITHOUT mTLS section
3. Try to start: `mcp-acp-extended start`

**Expected Result**:
- Connection fails with SSL error
- Popup shows "SSL/TLS error"
- Error message indicates client certificate required

**Status**: [ ] Pass  [x] Fail
Backend connection timed out.

Backend not reachable after 3 attempts: https://127.0.0.1:9443/mcp  Check that the backend server is running and responsive.

---

### MTLS-03: Certificate Expiry Warning

**Purpose**: Verify warning when cert expires within 14 days

**Steps**:
1. Generate cert expiring in 10 days:
   ```bash
   cd $CERTS
   openssl genrsa -out client-expiring-key.pem 4096
   openssl req -new -key client-expiring-key.pem -out client-expiring.csr \
     -subj "/CN=expiring/O=Test"
   openssl x509 -req -days 10 -in client-expiring.csr -CA ca-cert.pem \
     -CAkey ca-key.pem -out client-expiring-cert.pem
   ```
2. Update config to use expiring cert
3. Run: `mcp-acp-extended auth status`

**Expected Result**:
- Status shows "Warning" for certificate
- Shows "Expires in: X days"
- Message: "Consider renewing soon"

**Status**: [x] Pass  [ ] Fail
mTLS Certificate
  Client cert: /tmp/mtls-test-certs/client-expiring-cert.pem
  Client key: /tmp/mtls-test-certs/client-expiring-key.pem
  CA bundle: /tmp/mtls-test-certs/ca-cert.pem
  Status: Warning
  Expires in: 9 days
  Consider renewing soon.

---

### MTLS-04: Certificate Expiry Critical

**Purpose**: Verify critical warning when cert expires within 7 days

**Steps**:
1. Generate cert expiring in 3 days:
   ```bash
   cd $CERTS
   openssl x509 -req -days 3 -in client-expiring.csr -CA ca-cert.pem \
     -CAkey ca-key.pem -out client-critical-cert.pem
   ```
2. Update config
3. Run: `mcp-acp-extended auth status`

**Expected Result**:
- Status shows "CRITICAL" (red)
- Message: "Renew immediately!"

**Status**: [x] Pass  [ ] Fail
mTLS Certificate
  Client cert: /tmp/mtls-test-certs/client-critical-cert.pem
  Client key: /tmp/mtls-test-certs/client-critical-key.pem
  CA bundle: /tmp/mtls-test-certs/ca-cert.pem
  Status: CRITICAL
  Expires in: 2 days
  Renew immediately!

---

### MTLS-05: Expired Certificate Blocks Startup

**Purpose**: Verify expired cert prevents proxy startup

**Steps**:
1. Generate already-expired cert (requires openssl tricks or wait for test cert to expire)
2. Update config to use expired cert
3. Try to start: `mcp-acp-extended start`

**Expected Result**:
- Proxy refuses to start
- Error: "mTLS client certificate has expired"

**Status**: [x] Pass  [ ] Fail
Invalid configuration.

mTLS client certificate has expired (expired 2 days ago). Certificate: /private/tmp/mtls-test-certs/client-expired-cert.pem  Fix config file or run:   mcp-acp-extended init

---

### MTLS-06: HTTP Backend Without mTLS

**Purpose**: Verify HTTP backends work without mTLS

**Steps**:
1. Start a simple HTTP MCP server (no SSL):
2. Initialize
3. Check connection works: `mcp-acp-extended start`

**Expected Result**:
- Connection succeeds without mTLS
- No SSL errors

**Status**: [x] Pass  [ ] Fail

---

### MTLS-07: STDIO Backend (No mTLS)

**Purpose**: Verify STDIO backends work without mTLS (mTLS config is ignored)

**Steps**:
1. Initialize with STDIO backend
2. Check config has no mTLS section
3. Run `mcp-acp-extended config show`

**Expected Result**:
- Config created successfully
- No mTLS section (not applicable to STDIO)

**Status**: [x] Pass  [ ] Fail

---

### Cleanup

```bash
# Stop test servers
pkill -f test_mtls_server
pkill -f simple_server

# Remove test files
rm -rf $CERTS
rm -f /tmp/test_mtls_server.py /tmp/simple_server.py
```

To regenerate certs, re-run the "Setup: Generate Test Certificates" section above.

---

## HITL Approval Caching Tests

These tests verify the approval caching feature that reduces HITL dialog fatigue.

### Setup: Policy for Caching Tests

```json
{
  "version": "1",
  "default_action": "deny",
  "rules": [
        {
      "id": "hitl-read-files",
      "effect": "hitl",
      "conditions": {"tool_name": "read_*"}
    },
    {
      "id": "hitl-write-project",
      "effect": "hitl",
      "conditions": {
        "tool_name": "write*",
        "path_pattern": "<test-workspace>/**"
      }
    },
    {
    "id": "hitl-delete-files",
    "effect": "hitl",
    "conditions": {"tool_name": "delete*"}
    }
  ],
  "hitl": {
    "timeout_seconds": 30,
    "default_on_timeout": "deny",
    "approval_ttl_seconds": 600,
    "cache_side_effects": ["fs_write", "fs_read"]
  }
}
```

**Note:** CODE_EXEC tools (bash, python, etc.) are NEVER cached regardless of `cache_side_effects`.

### Setup: Cache Monitoring

Open a terminal to monitor the cache:
```bash
# Poll every 2 seconds
while true; do clear; curl -s http://127.0.0.1:8080/api/approvals; sleep 2; done
```

Or check manually:
```bash
curl -s http://127.0.0.1:8080/api/approvals | python3 -m json.tool
```

---

### HITL-CACHE-01: Three-Button Dialog (Cacheable Tool)

**Purpose**: Verify 3-button dialog appears for cacheable tools

**Precondition**: Policy with read-only HITL rule (Option 1), proxy running

**Steps**:
1. Restart Client
2. Ask client to read a file
3. Observe HITL dialog

**Expected Result**:
- Dialog shows 3 buttons: `Deny`, `Allow (10m)`, `Allow once`
- Legend shows: `[Esc] Deny | Allow (10m) | [Return] Allow once`
- Default button (Return) is "Allow once"

**Status**: [x] Pass  [ ] Fail

---

### HITL-CACHE-02: Allow with Caching

**Purpose**: Verify clicking "Allow (10m)" caches the approval

**Steps**:
1. Trigger HITL dialog (read a file)
2. Click "Allow (10m)"
3. Check cache: `curl -s http://127.0.0.1:8080/api/approvals`

**Expected Result**:
- Operation succeeds
- Cache shows 1 approval with:
  - `tool_name`: the tool that was approved
  - `path`: the path that was approved
  - `ttl_seconds`: 600
  - `expires_in_seconds`: ~600 (counting down)

**Status**: [x] Pass  [ ] Fail

{"count":1,"ttl_seconds":600,"approvals":[{"subject_id":"<user-2-subject-id>","tool_name":"read_file","path":"<test-workspace>/tmp-dir/potatoes.md","request_id":"5","age_seconds":67.3,"ttl_seconds":600,"expires_in_seconds":532.7}]}

---

### HITL-CACHE-03: Cached Approval Skips Dialog

**Purpose**: Verify cached approval bypasses HITL dialog

**Precondition**: Approval cached from HITL-CACHE-02

**Steps**:
1. Request the SAME tool + path again (e.g., "Read /tmp/test.txt")
2. Observe no HITL dialog appears

**Expected Result**:
- Operation succeeds immediately (no dialog)
- Cache still shows the approval
- decisions.jsonl shows `hitl_cache_hit: true`

**Status**: [x] Pass  [ ] Fail

---

### HITL-CACHE-04: Allow Once (No Caching)

**Purpose**: Verify "Allow once" does NOT cache the approval

**Steps**:
1. Trigger HITL dialog for a NEW path (e.g., "Read /tmp/other.txt")
2. Click "Allow once" (or press Return)
3. Check cache
4. Request same path again

**Expected Result**:
- First operation succeeds
- Cache does NOT show this approval
- Second request triggers HITL dialog again

**Status**: [x] Pass  [ ] Fail

---

### HITL-CACHE-05: Deny Button

**Purpose**: Verify "Deny" blocks operation and doesn't cache

**Steps**:
1. Trigger HITL dialog
2. Click "Deny" (or press Escape)
3. Check cache

**Expected Result**:
- Operation fails (access denied)
- Cache does NOT show any approval for this tool+path
- decisions.jsonl shows `effect: Deny`

**Status**: [x] Pass  [ ] Fail

---

### HITL-CACHE-06: Different Path Requires New Approval

**Purpose**: Verify cache is path-specific

**Precondition**: Approval cached for `/tmp/test.txt`

**Steps**:
1. Request same tool but DIFFERENT path (e.g., "Read /tmp/other.txt")
2. Observe HITL dialog

**Expected Result**:
- HITL dialog appears (different path = different cache key)
- Cache shows both approvals after allowing

**Status**: [x] Pass  [ ] Fail

---

### HITL-CACHE-07: Two-Button Dialog (Non-Cacheable Tool)

**Purpose**: Verify 2-button dialog for tools with side effects (without cache_side_effects config)

**Precondition**: Policy WITHOUT `cache_side_effects` for write tools

**Steps**:
1. Trigger HITL for a write tool
2. Observe dialog

**Expected Result**:
- Dialog shows 2 buttons: `Deny`, `Allow`
- Legend shows: `[Esc] Deny | [Return] Allow`
- No caching option available

**Status**: [x] Pass  [ ] Fail

---

### HITL-CACHE-08: Write Tool Caching (with cache_side_effects)

**Purpose**: Verify write tools can be cached when `cache_side_effects` includes `fs_write`

**Precondition**: Policy with Option 2 (`cache_side_effects: ["fs_write"]`)

**Steps**:
1. Restart Claude Desktop with new policy
2. Trigger HITL for a write tool
3. Observe 3-button dialog
4. Click "Allow (10m)"
5. Check cache

**Expected Result**:
- 3-button dialog appears
- Cache shows the write approval
- Subsequent writes to same path skip dialog

**Status**: [x] Pass  [ ] Fail

---

### HITL-CACHE-09: CODE_EXEC Never Cached

**Purpose**: Verify bash/python tools are NEVER cached (security)

**Precondition**: Policy with `cache_side_effects: ["code_exec"]` (should be ignored)

**Steps**:
1. Add bash to HITL rule
2. Trigger HITL for bash tool
3. Observe dialog

**Expected Result**:
- Only 2-button dialog (no caching option)
- Even with `cache_side_effects` including `code_exec`, bash is not cacheable
- This prevents approving `bash cat file` from auto-approving `bash rm file`

**Status**: [ ] Pass  [ ] Fail  [x] N/A

---

### HITL-CACHE-10: Clear Cache via API

**Purpose**: Verify cache can be cleared via DELETE endpoint

**Precondition**: Cache has some approvals

**Steps**:
1. Verify cache has approvals: `curl http://127.0.0.1:8080/api/approvals`
2. Clear cache: `curl -X DELETE http://127.0.0.1:8080/api/approvals`
3. Check cache again

**Expected Result**:
- DELETE returns `{"cleared": N, "status": "ok"}`
- Cache is now empty
- All subsequent requests require fresh HITL approval

**Status**: [x] Pass  [ ] Fail

---

### HITL-CACHE-11: Cache Expiry (10 minutes)

**Purpose**: Verify cached approval expires after TTL

**Precondition**: Approval cached from HITL-CACHE-02

**Steps**:
1. Note cache shows approval with `expires_in_seconds`
2. Wait 10 minutes (or until `expires_in_seconds` reaches 0)
3. Check cache
4. Request same tool+path again

**Expected Result**:
- Cache shows approval disappears after expiry
- New request triggers HITL dialog again

**Status**: [x] Pass  [ ] Fail

---

### HITL-CACHE-12: Cache Survives Across Requests

**Purpose**: Verify cache persists during session (in-memory)

**Steps**:
1. Cache an approval
2. Make multiple unrelated requests
3. Check cache is still present

**Expected Result**:
- Cache persists until TTL expiry or proxy restart
- Cache is NOT persisted across proxy restarts (in-memory only)

**Status**: [x] Pass  [ ] Fail

---

## Rate Limiting Tests

These tests verify per-session rate limiting that detects runaway LLM loops and potential abuse.

**Background**: The proxy tracks tool call frequency per session (`src/mcp_acp_extended/security/rate_limiter.py`). When a tool is called more than 30 times per minute, HITL is triggered to let the user confirm the activity is legitimate.

**Constants** (from `rate_limiter.py`):
- `DEFAULT_RATE_WINDOW_SECONDS = 60` (sliding window)
- `DEFAULT_RATE_THRESHOLD = 30` (calls per tool per window)

---

### RATE-01: Normal Usage Below Threshold

**Purpose**: Verify normal usage (< 30 calls/min) doesn't trigger rate limiting

**Precondition**: Proxy running, user logged in

**Steps**:
1. Connect via MCP Inspector
2. Make 10 rapid calls to the same tool (e.g., `Read` 10 different files)
3. Observe no rate limit dialog appears

**Expected Result**:
- All 10 requests succeed without HITL dialog
- No rate limit warnings in logs

**Status**: [x] Pass  [ ] Fail

**Actual Result**:

---

### RATE-02: Threshold Exceeded Triggers HITL

**Purpose**: Verify exceeding 30 calls/minute triggers HITL dialog

**Precondition**: Proxy running

**Steps**:
1. Connect via MCP Inspector
2. Make 31+ rapid calls to the same tool within 60 seconds
3. Observe behavior on the 31st call

**Expected Result**:
- First 30 calls succeed
- 31st call triggers HITL dialog with message about rate limit
- Dialog shows current count and threshold
- Clicking "Allow" permits the request

**Status**: [x] Pass  [ ] Fail

**Actual Result**:

---

### RATE-03: Rate Counter Resets After HITL Approval

**Purpose**: Verify approving rate limit HITL resets the counter

**Precondition**: Rate limit triggered (from RATE-02)

**Steps**:
1. When rate limit HITL appears, click "Allow"
2. Continue making rapid requests
3. Observe when next HITL triggers

**Expected Result**:
- After HITL approval, counter resets
- Can make another 30 calls before next trigger
- Prevents immediate re-triggering after approval

**Implementation Reference**: `reset_tool()` in `src/mcp_acp_extended/security/rate_limiter.py:168`

**Status**: [x] Pass  [ ] Fail

**Actual Result**:

---

### RATE-04: Rate Limiting is Per-Tool

**Purpose**: Verify rate limits are tracked independently per tool

**Precondition**: Proxy running

**Steps**:
1. Make 25 calls to tool A (e.g., `Read`)
2. Make 25 calls to tool B (e.g., `Write`)
3. Make 6 more calls to tool A (total: 31)

**Expected Result**:
- First 25 calls to A succeed
- 25 calls to B succeed (separate counter)
- 31st call to tool A triggers HITL (exceeded threshold)
- Tool B count (25) doesn't affect tool A's limit

**Status**: [x] Pass  [ ] Fail

**Actual Result**:

---

## Notes

_Space for tester notes, issues found, observations:_

### Session 2026-01-04

**Coverage:** Additional exploratory testing was performed beyond the documented test cases.


**POLICY-02: Observation** 
The `final_rule` is currently determined by:
1. Effect priority: HITL > DENY > ALLOW
2. Rule order: First matching rule of the winning effect type

- **Issue:** This behavior feels unintuitive. Would prefer "most specific rule wins" semantics.
Current behavior:
  - Two HITL rules match → first one in policy file wins
Desired behavior:
  - Two HITL rules match → most specific one wins

- **Proposed specificity criteria (in order):**
  1. Number of conditions - more conditions = more targeted
  2. Path pattern depth - `/a/b/c/**` beats `/a/**`
  3. Wildcard count - fewer wildcards = more specific
  4. Exact vs glob match - `tool_name: "read_file"` beats `tool_name: "read*"`


**MTLS-02: Incorrect error msg**

- **Issue:** Incorrect error message shown when mTLS is required but not configured.
- **Action needed:** Fix error message to clearly indicate client certificate is required.
- **Solution:**
  1. SSL-specific errors (SSLCertificateError, SSLHandshakeError) now fail immediately without retrying
  2. When HTTPS connection fails and no mTLS is configured, error now says: SSL/TLS connection failed: <url>. The server may require mTLS (client certificate authentication).

  test successfully passed after.


**HITL-CACHE-09:**
**N/A** Test backend (cyanheads/filesystem-mcp-server) does not expose any CODE_EXEC tools (bash/python). Security behavior is enforced in proxy code regardless.