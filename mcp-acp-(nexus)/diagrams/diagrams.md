# Diagrams

Focused diagrams for subsystems that benefit from visual explanation. For the full proxy lifecycle and request flow sequence diagrams, see [Request Flow Diagrams](request_flow_diagrams.md).

---

## Policy Evaluation Flowchart

How the Policy Engine (`pdp/engine.py`) evaluates a request. This is the decision algorithm executed on every non-discovery MCP request.

```
┌──────────────────────────────────────────────────────────────────────────┐
│                       POLICY EVALUATION FLOW                             │
│                                                                          │
│  MCP Request arrives                                                     │
│           │                                                              │
│           ▼                                                              │
│  1. Protected path? ─── Yes ──► DENY (built-in, cannot be overridden)   │
│     Checks `path` field only (not source_path / dest_path)               │
│           │                                                              │
│           No                                                             │
│           ▼                                                              │
│  2. Discovery action? ── Yes ──► ALLOW (discovery bypass)               │
│     (tools/list, resources/list, initialize, ping, ...)                  │
│           │                                                              │
│           No                                                             │
│           ▼                                                              │
│  3. Collect all matching rules                                           │
│     Each rule: all conditions must match (AND logic)                     │
│     None condition = no constraint (matches anything)                    │
│           │                                                              │
│           ├── Exception ──► PolicyEnforcementFailure propagates          │
│           │                 to FastMCP — request fails, proxy running     │
│           ▼                                                              │
│  4. Any rules matched? ── No ──► DENY (default, Zero Trust)             │
│           │                                                              │
│           Yes                                                            │
│           ▼                                                              │
│  5. Combining algorithm (most restrictive wins):                         │
│     ├── Any effect = hitl? ──► HITL (human decides)                     │
│     ├── Any effect = deny? ──► DENY                                     │
│     └── Otherwise ───────────► ALLOW                                    │
│           │                                                              │
│           ▼                                                              │
│  6. Select most specific rule within winning effect (logging only)       │
│     score = (condition_count × 100)                                      │
│           + exactness_bonus (+10 per exact pattern)                       │
│           + path_depth_bonus (+1 per segment before wildcard)             │
│     Tie-breaker: first rule in policy file wins                          │
│           │                                                              │
│           ▼                                                              │
│  7. Log decision to decisions.jsonl                                      │
│     (matched rules, final rule, eval timing)                             │
└──────────────────────────────────────────────────────────────────────────┘
```

**Combining algorithm priority:** HITL > DENY > ALLOW (most restrictive wins).

**Key properties:**
- Protected path check runs first and cannot be overridden by policy rules
- Discovery methods bypass policy entirely (MCP clients cannot function without discovery)
- If no rules match, the default action is DENY (Zero Trust)
- Any exception during evaluation raises `PolicyEnforcementFailure` which propagates to FastMCP — the individual request fails but the proxy keeps running (the middleware does not catch this exception or trigger shutdown)
- Specificity scoring only affects which rule is logged as `final_rule` — the decision is already determined by the combining algorithm

---

## Authentication Lifecycle

End-to-end authentication flow from first login through per-request validation, token refresh, and session binding enforcement. Combines the flows from `pips/auth/oidc_provider.py`, `pips/auth/session.py`, and `context/context.py`.

```
┌──────────────────────────────────────────────────────────────────────────┐
│              ONE-TIME SETUP  (mcp-acp auth login)                        │
│                                                                          │
│  1. CLI → IdP: POST /oauth/device/code                                  │
│     (Device Authorization Grant, RFC 8628)                               │
│                    │                                                     │
│                    ▼                                                     │
│  2. IdP returns: device_code + user_code + verification_uri              │
│                    │                                                     │
│                    ▼                                                     │
│  3. CLI opens browser, displays: "Enter code: {user_code}"              │
│                    │                                                     │
│                    ▼                                                     │
│  4. Poll IdP for tokens  (5 min timeout)                                │
│     POST /oauth/token (device_code) until user completes auth            │
│                    │                                                     │
│                    ▼                                                     │
│  5. Store tokens in OS Keychain (machine-bound)                          │
│  6. Notify running manager → broadcast to proxies                        │
└──────────────────────────────────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────────────────────┐
│              PROXY STARTUP  (every session)                               │
│                                                                          │
│  1. Load token from Keychain                                             │
│     (prefers manager-distributed token over local keychain)              │
│                    │                                                     │
│                    ▼                                                     │
│  2. JWTValidator.validate()                                              │
│     Verify: signature (JWKS), issuer, audience, expiry                   │
│                    │                                                     │
│                    ├── Expired? → refresh via POST /oauth/token           │
│                    │              (runs in thread pool)                   │
│                    │              Save new token → re-validate            │
│                    │                                                     │
│                    ├── Validation fails? → AuthenticationError → exit 13  │
│                    │                                                     │
│                    ▼                                                     │
│  3. Create session: {user_id}:{session_uuid}                             │
│     256-bit random, 8-hour TTL                                           │
│                    │                                                     │
│                    ▼                                                     │
│  4. set_bound_user_id(identity.subject_id)                               │
│     Stored in ContextVar for per-request binding checks                  │
└──────────────────────────────────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────────────────────┐
│              PER-REQUEST VALIDATION  (every MCP request)                  │
│                                                                          │
│  1. OIDCIdentityProvider.get_identity()                                  │
│     Load token from Keychain (no caching — true Zero Trust)              │
│                    │                                                     │
│                    ├── Expired? → refresh via POST /oauth/token           │
│                    │              Save new token to Keychain              │
│                    │                                                     │
│                    ▼                                                     │
│  2. ensure_jwks_available()  (async pre-flight)                          │
│                    │                                                     │
│                    ├── Unreachable? → AuthenticationError (fail-closed)   │
│                    │                                                     │
│                    ▼                                                     │
│  3. JWTValidator.validate()                                              │
│     Verify: signature, issuer, audience, expiry                          │
│     Returns: SubjectIdentity (subject_id, claims)                        │
│                    │                                                     │
│                    ▼                                                     │
│  4. build_decision_context()                                             │
│     Compare identity.subject_id vs get_bound_user_id()                   │
│                    │                                                     │
│                    ├── Match → DecisionContext (proceed to policy eval)   │
│                    │                                                     │
│                    └── Mismatch → SESSION BINDING VIOLATION               │
│                         SessionBindingViolationError                      │
│                         → shutdown_callback(reason)                       │
│                         → Log: system.jsonl, auth.jsonl,                  │
│                           shutdowns.jsonl, .last_crash                    │
│                         → os._exit(15) after 100ms                       │
└──────────────────────────────────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────────────────────┐
│              LOGOUT  (mcp-acp auth logout)                               │
│                                                                          │
│  1. Delete tokens from OS Keychain                                       │
│  2. Notify proxy via manager                                             │
│  3. Proxy clears: identity cache, HITL approval cache                    │
│                                                                          │
│  Effect: next request → PermissionDeniedError                            │
│  (proxy keeps running, all requests denied until re-auth)                │
│                                                                          │
│  Use --federated to also log out of IdP in browser                       │
└──────────────────────────────────────────────────────────────────────────┘
```

**Key security properties:**
- **No token caching**: Every request loads from keychain and validates JWT — logout takes effect immediately
- **Session binding**: If the identity behind the token changes mid-session, the proxy shuts down (exit 15)
- **Fail-closed**: Any auth failure → proxy exits, no fallback to unauthenticated access
- **Manager token distribution**: In multi-proxy mode, the manager refreshes tokens and distributes to proxies; individual proxies skip local refresh

---

## Audit Integrity Pipeline

The fail-closed audit system with hash chain tamper detection. Shows both the write path (normal operation) and the verification path (startup + background monitoring). Based on `security/integrity/` modules.

### Write Path

How each audit log entry is written with hash chain protection.

```
┌──────────────────────────────────────────────────────────────────────────┐
│                   AUDIT WRITE PATH  (every log entry)                    │
│                                                                          │
│  Middleware emits log record → FailClosedAuditHandler.emit()             │
│                    │                                                     │
│                    ▼                                                     │
│  PRE-WRITE INTEGRITY CHECKS                                             │
│  os.stat(log_file)                                                       │
│       ├── FileNotFoundError → _trigger_shutdown()                        │
│       │   "audit log compromised"   (exit 10, 500ms delay)               │
│       ├── Inode or device changed → _trigger_shutdown()                  │
│       │   "file replaced or moved"  (exit 10, 500ms delay)               │
│       └── OK → proceed                                                   │
│                    │                                                     │
│                    ▼                                                     │
│  HASH CHAIN COMPUTATION  (HashChainFormatter)                            │
│  1. Get chain state: prev_hash, next_sequence                            │
│     (first entry: prev_hash = "GENESIS", sequence = 1)                   │
│                    │                                                     │
│                    ▼                                                     │
│  2. Build entry: {time, sequence, prev_hash, ...event_data}              │
│                    │                                                     │
│                    ▼                                                     │
│  3. entry_hash = SHA-256(entry without entry_hash field)                 │
│                    │                                                     │
│                    ▼                                                     │
│  4. Persist state BEFORE writing log entry  ◀── intentional              │
│     IntegrityStateManager.save_state()                                   │
│     (temp file → json.dump → fsync → os.replace)                         │
│     If crash here → state "ahead" of log →                               │
│     detected + auto-repaired on next startup                             │
│                    │                                                     │
│                    ▼                                                     │
│  WRITE                                                                   │
│  Write JSON entry to log file + flush                                    │
│       ├── Success → done                                                 │
│       └── Failure → emergency fallback chain:                            │
│            1. Try system.jsonl                                            │
│            2. Try emergency_audit.jsonl (config dir)                      │
│            3. Shutdown after any fallback → os._exit(10)                  │
└──────────────────────────────────────────────────────────────────────────┘
```

### Verification Path

How integrity is verified at startup and continuously during operation.

```
┌──────────────────────────────────────────────────────────────────────────┐
│               STARTUP VERIFICATION                                       │
│                                                                          │
│  1. IntegrityStateManager.load_state()                                   │
│     Load .integrity_state from disk                                      │
│                    │                                                     │
│                    ▼                                                     │
│  2. verify_on_startup(all_log_paths)   auto_repair_on_crash=True         │
│                    │                                                     │
│                    ▼                                                     │
│  3. For each monitored log file:                                         │
│                                                                          │
│     a. File exists?                                                      │
│        ├── No  → crash breadcrumb (.last_crash) exists?                  │
│        │          ├── Yes → auto-repair: clear state (fresh start)       │
│        │          └── No  → AuditFailure — proxy refuses to start        │
│        └── Yes → continue                                                │
│                                                                          │
│     b. Inode + device match stored state?                                │
│        ├── No  → same crash-breadcrumb check as above                    │
│        └── Yes → continue                                                │
│                                                                          │
│     c. verify_file_integrity() — full hash chain verification            │
│        ├── Valid   → next file                                           │
│        └── Invalid → AuditFailure — proxy refuses to start               │
│                      "Entries modified or deleted"                        │
└──────────────────────────────────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────────────────────┐
│               BACKGROUND MONITORING  (every 30 seconds)                  │
│                                                                          │
│  AuditHealthMonitor._monitor_loop()                                      │
│                    │                                                     │
│                    ▼                                                     │
│  For each monitored log path:                                            │
│                                                                          │
│     a. File exists + same inode/device?                                  │
│        └── No → ShutdownCoordinator.initiate_shutdown() — exit 10        │
│                                                                          │
│     b. File writable? (empty write + fsync test)                         │
│        └── No → ShutdownCoordinator.initiate_shutdown() — exit 10        │
│                                                                          │
│     c. Hash chain valid? (verify last 10 entries only)                   │
│        └── No → ShutdownCoordinator.initiate_shutdown() — exit 10        │
│                                                                          │
│     All checks pass → next path                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**What each layer detects:**

| Attack | Write-time (Handler) | Background (Monitor) | Startup (Verify) |
|--------|---------------------|---------------------|-------------------|
| Log file deleted | FileNotFoundError | File exists check | File exists check |
| Log file replaced | Inode/device mismatch | Inode/device mismatch | Inode/device mismatch |
| Entries modified | — | Hash chain (last 10) | Full chain verification |
| Entries deleted | — | Chain break / sequence gap | Chain break / sequence gap |
| Disk full / permissions | Write failure | Write + fsync test | — |

**Known limitation:** An attacker with write access to both log files AND `.integrity_state` can truncate tail entries undetected. Mitigations: forward logs to remote syslog, use append-only filesystem attributes, or back up to immutable storage.
