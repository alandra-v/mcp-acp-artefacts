# Resilience & Edge Case Testing

Manual tests for security edge cases, error handling, and system resilience. These scenarios test behavior under adverse conditions that are difficult to cover with automated tests.

> **Note**: These tests verify the system behaves safely and predictably when faced with unusual inputs, timing issues, or adversarial conditions.

---

## Test Execution Record

| Field | Value |
|-------|-------|
| **Date** |14.01.2026|
| **Version** |1|
| **Platform** | macOS-15.7.2-arm64-arm-64bit-Mach-O |

---

## Test Summary

| Category | Total | Pass | Fail | Skip | N/A |
|----------|-------|------|------|------|-----|
| Policy Engine (POLICY) | 3 | | | | |
| Security (SEC) | 2 | | | | |
| Backend Resilience (BACKEND) | 3 | | | | |
| Frontend Resilience (UI) | 1 | | | | |
| **Total** | **9** | | | | |

**Legend**: Pass = Test passed, Fail = Test failed, Skip = Skipped (preconditions not met), N/A = Not applicable

---

## Policy Engine Tests

### POLICY-01: Policy Reload During Active Request

**Purpose**: Verify request completes safely when policy reloads mid-processing

**Precondition**: Proxy running with HITL policy

**Steps**:
1. Trigger a HITL dialog (request that matches HITL rule)
2. While dialog is pending, reload policy via API:
   ```bash
   curl -X POST http://127.0.0.1:8765/api/control/reload
   ```
3. Approve the pending HITL dialog
4. Observe request completion

**Expected Result**:
- Request completes with the policy that was active when request started
- Policy is evaluated once at decision time, not re-evaluated after HITL approval
- Approval cache is cleared on reload, but pending HITL dialogs are NOT cancelled
- No crash, no undefined behavior
- Logs show clear sequence of events

**Status**: [x] Pass  [ ] Fail  [ ] N/A

**Actual Result**:
Request completes with the policy that was active when request started. This matches standard PDP/PEP behavior where policy is evaluated once at decision time.

---

### POLICY-02: Conflicting Rules (HITL vs DENY vs ALLOW)

**Purpose**: Verify correct precedence when multiple rules match the same request

**Precondition**: Proxy running

**Steps**:
1. Create policy with overlapping rules:
   ```json
   {
     "rules": [
       {"id": "allow-tmp", "effect": "allow", "conditions": {"path_pattern": "/tmp/**"}},
       {"id": "hitl-txt", "effect": "hitl", "conditions": {"extension": ".txt"}},
       {"id": "deny-secrets", "effect": "deny", "conditions": {"path_pattern": "**/secret*"}}
     ]
   }
   ```
2. Request: `read_file /tmp/secret.txt`
3. Observe which rule wins

**Expected Result**:
- All three rules match
- Effect priority: HITL > DENY > ALLOW (hitl wins, human decides)
- `decisions.jsonl` shows all `matched_rules` and `final_rule`

**Status**: [x] Pass  [ ] Fail  [ ] N/A

**Actual Result**:
- All three rules matched
- HITL won (correct - human-in-the-loop takes precedence)

---

### POLICY-03: Empty vs Null Conditions

**Purpose**: Verify correct handling of edge-case condition values

**Precondition**: Proxy running

**Steps**:
1. Test each condition format via policy API:
   - `{"tool_name": []}` (empty array)
   - `{}` (empty conditions object)
   - Missing `conditions` key entirely
2. Reload policy after each change
3. Observe behavior

**Expected Result**:
- Empty array `[]`: Should match nothing (no tools in list)
- Empty object `{}`: Should match everything (no constraints)
- Missing key: Should match everything (no constraints)
- Each case is handled consistently without errors
- System prevents accidental "match everything" rules

**Status**: [x] Pass  [ ] Fail  [ ] N/A

**Actual Result**:
- Empty array `[]`: Policy denied
- Empty object `{}`:
   ✗ Reload failed: Invalid policy configuration in ~/Library/Application Support/mcp-acp-extended/policy.json:
   - rules.7.conditions: Value error, At least one condition must be specified. Empty conditions would match everything.
- Missing key: 
   ✗ Reload failed: Invalid policy configuration in ~/Library/Application Support/mcp-acp-extended/policy.json:
   - : Value error, At least one condition must be specified. Empty conditions would match everything.

---

## Security Tests

### SEC-01: Symlink Attack Prevention

**Purpose**: Verify path normalization prevents symlink-based bypasses

**Precondition**: Proxy running with HITL for `/safe/**` and DENY for `/secrets/**`

**Steps**:
1. Create symlink:
   ```bash
   mkdir -p /tmp/test-symlink/safe /tmp/test-symlink/secrets
   echo "secret data" > /tmp/test-symlink/secrets/password.txt
   ln -s /tmp/test-symlink/secrets/password.txt /tmp/test-symlink/safe/link.txt
   ```
2. Configure policy:
   - ALLOW: `/tmp/test-symlink/safe/**`
   - DENY: `/tmp/test-symlink/secrets/**`
3. Request: `read_file /tmp/test-symlink/safe/link.txt`
4. Observe decision

**Expected Result**:
- Path is NOT resolved (by design - see Known Limitation below)
- Request falls through to default action (DENY) since no rules match the original path
- This is a **known limitation**, not a bug

**Status**: [ ] Pass  [ ] Fail  [x] N/A (Known Limitation)

**Actual Result**:
```json
{
  "decision": "deny",
  "matched_rules": [],
  "final_rule": "default",
  "path": "/tmp/test-symlink/safe/link.txt"
}
```

- Request DENIED by default action (no rules matched original path)
- Symlink was NOT resolved - this is intentional

**Known Limitation - Symlink Bypass**:
Policy evaluation intentionally does NOT resolve symlinks. This is a design trade-off:

| Approach | Pros | Cons |
|----------|------|------|
| No resolution (current) | macOS `/tmp` works, user symlinks work, predictable | Symlink bypass possible |
| With resolution | Prevents symlink bypass | Breaks `/tmp/**` on macOS, breaks user symlinks |

**Why this trade-off was chosen**:
1. macOS maps `/tmp` → `/private/tmp`, breaking all `/tmp/**` policies if resolved
2. User symlinks (e.g., `/data/project` → `/home/user/work/project`) are common workflows
3. Resolving would be a breaking change for existing policies
4. Protected paths (config dir, log dir) ARE symlink-safe via `realpath()` at startup

**Mitigation Guidance**: See `docs/security.md` "Symlink Considerations" section for
secure policy writing practices when this limitation applies.

---

### SEC-02: Corrupted Token in Keychain

**Purpose**: Verify graceful handling of corrupted stored credentials

**Precondition**: User previously logged in (tokens stored in keychain)

**Steps**:
1. Corrupt the stored token:
   ```bash
   # View current token (stored as JSON blob)
   keyring get mcp-acp-extended oauth_tokens

   # Set corrupted value (enter "corrupted-not-a-real-token" at prompt)
   keyring set mcp-acp-extended oauth_tokens
   ```
2. Start proxy: `mcp-acp-extended start`
3. Observe behavior

**Expected Result**:
- Proxy detects invalid token
- User is prompted to re-authenticate (device flow)
- No crash, clear error message
- After re-auth, new valid token is stored

**Cleanup**:
```bash
# Clear stored tokens
keyring del mcp-acp-extended oauth_tokens
```

**Status**: [x] Pass  [ ] Fail  [ ] N/A

**Actual Result**:
- macOS dialog displayed: "Authentication error. Failed to parse stored token (may be corrupted): 1 validation error for StoredToken Invalid JSON: expected value at line 1 column 1"
- Clear instruction provided: "Run 'mcp-acp-extended auth login' to re-authenticate."
- No crash, graceful handling confirmed

---

## Backend Resilience Tests

### BACKEND-01: Slow Backend Response (30+ seconds)

**Purpose**: Verify proxy handles slow backends gracefully

**Precondition**: Backend configured with artificial delay

**Steps**:
1. Create slow test server (see `tests/manual/slow_server.py`):
   ```python
   import time
   from fastmcp import FastMCP

   mcp = FastMCP("slow-server")

   @mcp.tool()
   def slow_operation() -> str:
       time.sleep(35)  # 35 second delay
       return "finally done"

   if __name__ == "__main__":
       mcp.run(transport="streamable-http", host="127.0.0.1", port=3011)
   ```
2. Configure proxy to use slow backend (update `http.url` to `http://127.0.0.1:3011/mcp`)
3. Add policy rule to allow test tools: `{"tool_name": ["slow_operation", "quick_ping"]}`
4. Call `slow_operation` tool
5. Observe timeout behavior

**Expected Result**:
- Request either completes after delay, or times out gracefully
- No proxy crash
- Timeout logged with clear message
- Client receives appropriate error response

**Status**: [x] Pass  [ ] Fail  [ ] N/A

**Actual Result**:
- Request completed successfully after 35 seconds with result: `{"result": "finally done"}`
- No timeout occurred despite `http.timeout: 30` config setting
- No proxy crash

**Analysis - Timeout Behavior**:

| Config | Purpose | Value |
|--------|---------|-------|
| `http.timeout` | Startup health check only | 30s (capped to 10s internally) |
| `sse_read_timeout` | Tool request duration | **Not set** (infinite) |

The `http.timeout` config only applies to the initial connection health check at startup.
Once connected, tool requests have **no timeout** - they wait indefinitely for the backend.

This is by design (SSE streams need long-lived connections), but operators should be aware
that slow backends will block indefinitely. MCP client timeouts provide the actual limit.

**Recommendation**: Consider adding optional `request_timeout` config for operators who
want to enforce server-side request limits independent of client timeouts.

---

### BACKEND-02: Backend Returns Invalid MCP Response

**Purpose**: Verify proxy handles malformed backend responses

**Precondition**: Backend that returns invalid JSON/MCP

**Steps**:
1. Create malformed response server (see `tests/manual/bad_server.py`):
   ```python
   from fastapi import FastAPI
   from fastapi.responses import PlainTextResponse
   import uvicorn

   app = FastAPI()

   @app.post("/mcp")
   async def mcp_endpoint():
       return PlainTextResponse(
           "this is not valid json {{{",
           media_type="application/json"
       )

   if __name__ == "__main__":
       uvicorn.run(app, host="127.0.0.1", port=3012)
   ```
2. Configure proxy to use bad backend (`http.url` → `http://127.0.0.1:3012/mcp`)
3. Start proxy: `mcp-acp-extended start`
4. Observe error handling

**Expected Result**:
- Proxy catches parse error
- Error logged with details
- Client receives structured error response
- Proxy remains operational for subsequent requests

**Status**: [x] Pass  [ ] Fail  [ ] N/A

**Actual Result**:
- Proxy failed at startup during health check handshake (expected - can't connect to broken backend)
- MCP library (`mcp/client/streamable_http.py`) caught the invalid JSON
- Clear pydantic validation error:
  ```
  pydantic_core._pydantic_core.ValidationError: 1 validation error for JSONRPCMessage
    Invalid JSON: expected ident at line 1 column 2
    input_value=b'this is not valid json {{{'
  ```
- No crash, graceful failure with actionable error message
- MCP library handles JSON parsing errors before they reach the proxy

---

### BACKEND-03: mTLS Certificate Rotation During Session

**Purpose**: Verify behavior when backend certificates change mid-session

**Precondition**: mTLS backend configured and working

**Steps**:
1. Generate test certs and start mTLS server (see `tests/manual/mtls_server.py`)
2. Configure proxy with mTLS (`auth.mtls` section) pointing to `https://127.0.0.1:9443/mcp`
3. Start proxy and make successful request (`secure_ping`)
4. Rotate server certificate:
   ```bash
   cd /tmp/mtls-test-certs
   openssl genrsa -out server-key-new.pem 2048
   openssl req -new -key server-key-new.pem -out server-new.csr -subj "/CN=localhost"
   openssl x509 -req -days 365 -in server-new.csr -CA ca-cert.pem -CAkey ca-key.pem \
     -CAcreateserial -out server-cert-new.pem \
     -extfile <(echo "subjectAltName=DNS:localhost,IP:127.0.0.1")
   mv server-key-new.pem server-key.pem
   mv server-cert-new.pem server-cert.pem
   ```
5. Restart backend with new cert (same CA): `pkill -f mtls_server && python mtls_server.py`
6. Make another request (`secure_ping`) without restarting proxy

**Expected Result**:
- First request after rotation may fail (expected)
- Error message indicates certificate issue
- Subsequent reconnection attempts work (if cert is valid)
- No proxy crash

**Status**: [x] Pass  [ ] Fail  [ ] N/A

**Actual Result**:
- Request after cert rotation succeeded immediately
- Proxy reconnected to backend with new certificate automatically
- No error, no crash
- MCP/httpx client handles TLS session renegotiation transparently
- Same CA = client trusts new server cert without issues

---

## Frontend Resilience Tests

### UI-01: Browser Offline During SSE Connection

**Purpose**: Verify SSE reconnection after network interruption

**Precondition**: Web UI open with active SSE connection

**Steps**:
1. Open web UI, verify SSE connected (pending approvals update in real-time)
2. Disable network (airplane mode, or `networksetup -setairportpower en0 off`)
3. Wait 30 seconds
4. Re-enable network
5. Trigger a new pending approval
6. Observe UI update

**Expected Result**:
- UI shows connection lost indicator (or toast)
- After network restored, SSE reconnects automatically
- New pending approval appears in UI
- No manual refresh required

**Status**: [x] Pass  [ ] Fail  [ ] N/A

**Actual Result**:
- No banner shown during 30s network outage (reconnect was fast, < 5 errors)
- SSE auto-reconnected seamlessly when network restored
- New pending approvals appeared without manual refresh
- Browser's `EventSource` handled reconnection automatically

**Notes**: Brief network blips handled silently (good UX). Banner only appears after
repeated failures. Page reload during outage shows "Unable to connect" + Retry button.
