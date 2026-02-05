# Goal Traceability Matrix

This document traces every project goal to its implementation status, the key source files that realise it, and an assessment of coverage gaps where applicable.

---

## Must Goals

### M1: Core Proxy — MET

> The project must deliver a working MCP Access Control Proxy that mediates all MCP interactions between at least one MCP client (Claude Desktop or MCP Inspector) and the two targeted file system servers (the official reference MCP file system server provided in the modelcontextprotocol/servers GitHub repository and an independent third-party MCP file system server maintained by Cyanheads). The client connects to the proxy via standard input/output (stdio) and the proxy communicates with the file system servers via stdio and/or streamable hypertext transport protocol (HTTP) in a single–tenant, single–user, single–host environment. This goal is considered achieved when representative read and write workflows run end–to–end (E2E) only through the proxy without any direct client–server connections or code changes to the clients or file system servers.


**How it is met:**

The proxy mediates all MCP communication through a full middleware chain (DoS Limiter, Context, Audit, ClientLogger, Enforcement). Clients are explicitly configured to connect to the proxy via stdio; the proxy communicates with backends via stdio and/or streamable HTTP.

Both targeted filesystem servers are supported:

- Official reference server (`@modelcontextprotocol/server-filesystem`) via stdio.
- Cyanheads third-party server (`@cyanheads/filesystem-mcp-server`) via stdio and HTTP.

The system is single-tenant, single-user, and single-host. Representative read and write workflows run end-to-end through the proxy without direct client-server connections or code changes to clients or servers.

| Aspect | Detail |
|--------|--------|
| Client transport | stdio (JSON-RPC 2.0 over stdin/stdout) |
| Backend transports | stdio (`StdioTransport`), streamable HTTP (`StreamableHttpTransport`); configurable per proxy with optional auto-selection (tries HTTP first, falls back to stdio) |
| Architecture | Single backend per proxy instance; manager daemon coordinates multiple proxies |
| E2E evidence | `tests/integration/test_proxy_e2e.py` (10 scenarios), `docs/demo-testing-guide/` (22 scenarios) |

**Key files:**

| File | Purpose |
|------|---------|
| `src/mcp_acp/proxy.py` | Main proxy orchestration |
| `src/mcp_acp/utils/transport.py` | Backend transport creation and auto-detection |
| `src/mcp_acp/telemetry/debug/logging_proxy_client.py` | Wire-logging wrapper around backend transport |
| `src/mcp_acp/telemetry/debug/client_logger.py` | Client-side wire logging middleware |
| `tests/integration/test_proxy_e2e.py` | End-to-end integration tests |
| `tests/integration/conftest.py` | Test fixtures with production middleware chain |

---

### M2: Zero Trust-Oriented Policy Engine — PARTIALLY MET

> The system must provide a ZT-oriented policy engine  that enforces a default-deny stance and least-privilege access to file system resources based on attributes such as user identity, server, action type and simple data labels. It supports both (1) single-server rules (such as allow reads on /project/**, deny access to /secrets/**, human-in-the-loop (HITL)  for writes to /project/examplefile) and (2) basic cross-server data-flow restrictions (such as preventing data read from server A from being written to server B). This goal is met when policies such as allow reads under /project/** etc. can be configured and reliably enforced in the implemented prototype.

**What is met:**

The policy engine implements Attribute-Based Access Control (ABAC) with a hardcoded default-deny stance (`PolicyConfig.default_action = "deny"`, not configurable).

When a request is evaluated, the engine collects all rules whose conditions match the request context. The decision is then determined by a fixed effect precedence: HITL > DENY > ALLOW (most restrictive wins). If any matching rule has effect `hitl`, the decision is HITL regardless of other matches. Otherwise, if any matching rule has effect `deny`, the decision is DENY. The decision is ALLOW only when all matching rules agree on `allow`. If no rule matches at all, the default action (deny) applies. This means a broad deny rule (e.g., `deny on /secrets/**`) will always override a more specific allow rule (e.g., `allow on /secrets/readme.txt`), which is intentional for a zero-trust posture. Specificity scoring exists but is used only to select the representative "final rule" recorded in audit logs; it does not influence the access decision itself.

Single-server rules work exactly as specified:

- `allow reads on /project/**` via `path_pattern` with glob matching.
- `deny access to /secrets/**` via deny rules with path patterns.
- `HITL for writes to /project/examplefile` via hitl effect with path conditions.
- Protected paths (config and log directories) are hardcoded and cannot be overridden.

Policy attributes span four ABAC categories:

| Category | Attributes |
|----------|-----------|
| Subject | `id` (OIDC sub), `issuer`, `audience`, `client_id`, `scopes`, `token_age_s`, `auth_time` |
| Action | `mcp_method`, `name`, `intent` (for resources/read only; null for tools/call), `category` |
| Resource | `tool_name`, `path`, `source_path`, `dest_path`, `extension`, `scheme`, `backend_id`, `resource_type`, `side_effects` |
| Environment | `timestamp`, `request_id`, `session_id`, `mcp_client_name`, `mcp_client_version`, `proxy_instance` |

**What is partially met (cross-server data-flow restrictions):**

The project addresses cross-server data flow through architectural isolation rather than explicit flow tracking. Each proxy instance connects to exactly one backend, so data cannot flow between backends within a single proxy session. Policies can match on `backend_id` to restrict operations per-server.

However, there is no mechanism to track data provenance across proxy instances. If a client reads data from Proxy A (server A) and writes it via Proxy B (server B), nothing prevents this. The `classification` field on `ResourceInfo` is marked "Future" and is not implemented. There are no data labels (public, internal, secret) and no cross-proxy coordination for data flow.

**Key files:**

| File | Purpose |
|------|---------|
| `src/mcp_acp/pdp/engine.py` | Policy evaluation engine |
| `src/mcp_acp/pdp/matcher.py` | Rule condition matching with glob support |
| `src/mcp_acp/pdp/policy.py` | Policy rule, condition, and schema structures |
| `src/mcp_acp/pdp/decision.py` | Decision enum (ALLOW, DENY, HITL, TIMEOUT) |
| `src/mcp_acp/pdp/protocol.py` | Pluggable policy engine protocol (enables future external engines) |
| `src/mcp_acp/pep/middleware.py` | Policy enforcement middleware |
| `src/mcp_acp/context/context.py` | DecisionContext model |
| `src/mcp_acp/context/subject.py` | Subject attribute model |
| `src/mcp_acp/context/action.py` | Action attribute model |
| `src/mcp_acp/context/resource.py` | Resource attribute model (includes unimplemented `classification` field) |
| `src/mcp_acp/context/environment.py` | Environment attribute model |
| `src/mcp_acp/context/parsing.py` | Safe MCP argument extraction and resource attribute parsing |
| `src/mcp_acp/context/provenance.py` | Provenance tracking for attribute sources (fact vs. inference) |
| `src/mcp_acp/context/tool_side_effects.py` | Tool-to-side-effect mapping (~78 tools) |
| `src/mcp_acp/pep/protected_paths.py` | Built-in hardcoded path protections |
| `tests/pdp/test_policy.py` | Policy evaluation tests |
| `tests/pdp/test_policy_protocol.py` | Protocol conformance tests |
| `tests/pdp/test_specificity.py` | Rule specificity and priority tests |
| `tests/integration/test_proxy_e2e.py` | E2E enforcement tests |

---

### M3: Auth — MET

> The proxy must enforce per-invocation authentication by requiring each request from the MCP client to carry an access token issued by Auth0  that the proxy validates (including signature, issuer, audience and expiry) before evaluating any policy . This goal is achieved when unauthenticated or invalidly authenticated requests are rejected, and when the proxy consistently derives a stable user identity (and, where applicable, role information) from valid tokens and uses this identity both in access–control decisions and in its security-relevant logging.

**How it is met:**

Every MCP request triggers JWT validation through the OIDC identity provider. The validation itself — signature, issuer, audience, and expiry — is performed on every request and never cached. JWKS signing keys are cached with a 10-minute TTL for performance, but this caches the public keys used for verification, not the validation result. The validation chain checks signature (RS256/ES256 via JWKS), issuer, audience, and expiry. Required claims are `exp`, `iat`, `sub`, `iss`, and `aud`.

Unauthenticated or invalidly authenticated requests are rejected. The proxy refuses to start without valid credentials. A stable user identity (`sub` claim) is derived from valid tokens and used in both policy decisions (ABAC subject attributes) and audit logs.

Session binding validates that the authenticated identity has not changed mid-session. A mismatch triggers immediate fail-closed shutdown, preventing session hijacking.

Token storage uses the OS keychain (macOS Keychain, Linux Secret Service, Windows Credential Locker) with encrypted file fallback. Automatic token refresh via refresh tokens avoids unnecessary re-authentication.

**Key files:**

| File | Purpose |
|------|---------|
| `src/mcp_acp/security/auth/jwt_validator.py` | JWT signature, issuer, audience, expiry validation |
| `src/mcp_acp/pips/auth/oidc_provider.py` | OIDC identity provider |
| `src/mcp_acp/pips/auth/claims.py` | Claims-to-Subject mapping |
| `src/mcp_acp/pips/auth/session.py` | Session binding to authenticated identity (mid-session mismatch triggers shutdown) |
| `src/mcp_acp/security/auth/token_storage.py` | Keychain-backed token storage |
| `src/mcp_acp/security/auth/token_refresh.py` | Automatic token refresh |
| `src/mcp_acp/security/auth/token_parser.py` | Shared OAuth token response parsing |
| `src/mcp_acp/security/auth/device_flow.py` | Auth0 Device Flow (RFC 8628) |
| `src/mcp_acp/cli/commands/auth.py` | CLI auth commands (login, logout, status) |
| `tests/pips/auth/test_session.py` | Session binding tests |
| `tests/pips/auth/test_oidc_logout.py` | OIDC logout and token clearing tests |
| `tests/security/auth/test_auth.py` | JWT validation and token tests |

---

### M4: HITL — MET

> The system must implement HITL enforcement for security-sensitive actions, particularly write operations and cross-server flows that involve sensitive or secret-labelled data, so that such actions are blocked or paused until a human explicitly approves or denies them. This goal is considered fulfilled when the proxy exposes these decisions through a combination of command-line interaction and desktop notifications (for example, via osascript  on macOS) and when each approval or denial, together with the relevant context such as server and path, is recorded in the audit logs for later evaluation.

**How it is met:**

Policy rules with `effect: "hitl"` gate operations requiring human approval. The effect precedence ensures HITL takes priority over both ALLOW and DENY when matched. Per-session rate limiting also escalates to HITL when a tool exceeds 30 calls per minute.

HITL decisions are exposed through two channels:

1. **macOS osascript dialogs**: Native dialog with three buttons (Deny, Allow for TTL, Allow once) and auto-deny timeout after 30 seconds.
2. **Web UI**: When connected, approvals are routed via SSE events to a pending-approvals panel with approve, deny, and allow-once actions.

The fallback chain is: Web UI (preferred) then osascript (macOS) then auto-deny (unsupported platforms).

An approval cache reduces dialog fatigue by storing decisions keyed by (subject_id, tool_name, path) with a configurable TTL. Caching is opt-in at the policy rule level: each HITL rule can declare `cache_side_effects` to specify which side-effect categories are safe to cache for that rule. Without this declaration, only tools with no known side effects are eligible for caching. Tools with unknown side effects and code-execution tools (`CODE_EXEC`) are never cached regardless of the rule configuration. The cache is in-memory only and is cleared on policy reload.

Every HITL decision is logged to `decisions.jsonl` with `hitl_outcome` (user_allowed, user_denied, timeout), `hitl_cache_hit`, `hitl_approver_id`, `policy_hitl_ms` (wait time), and full context (server, path, tool, user).

**Key files:**

| File | Purpose |
|------|---------|
| `src/mcp_acp/pep/hitl.py` | HITL handler with dialog and web UI integration |
| `src/mcp_acp/pep/applescript.py` | macOS native dialog via osascript |
| `src/mcp_acp/pep/approval_store.py` | Approval caching with TTL and side-effect filtering |
| `src/mcp_acp/pep/middleware.py` | HITL enforcement within PEP middle585-718) |
| `src/mcp_acp/pep/rate_handler.py` | Rate-limit escalation to HITL |
| `src/mcp_acp/api/routes/pending.py` | API endpoints for pending approval actions (approve, deny, allow-once) |
| `src/mcp_acp/cli/commands/approvals.py` | CLI approval management (view, clear cache) |
| `web/src/components/approvals/PendingDrawer.tsx` | Web UI approval panel |
| `web/src/components/approvals/ApprovalItem.tsx` | Individual approval actions |
| `tests/pep/test_approval_store.py` | Approval caching tests |
| `tests/api/test_pending.py` | Pending approval API tests |
| `tests/cli/test_approvals.py` | CLI approval command tests |
| `docs/demo-testing-guide/e2e-testing/manager-ui-coupling-tests.md` | 9 manual HITL fallback scenarios |

---

### M5: Configuration — MET

> The system must handle its configuration through a validated Pydantic  schema that rejects malformed settings, supports configuration setup and modification through both configuration files and the CLI, and records every configuration change with a version or revision marker to ensure traceability. This goal is achieved when configuration errors are reliably caught at startup, CLI-based configuration changes are validated and logged, and the chronological development of the proxy’s configuration can be reconstructed from the audit logs for evaluation.

**How it is met:**

All configuration models use Pydantic with strict type validation and field constraints. Malformed settings raise `ValidationError` at parse time. Configuration is loaded and validated before the proxy starts; invalid configuration prevents startup.

Configuration is managed through both files (`manager.json`, `proxies/{name}/config.json`, `proxies/{name}/policy.json`) and CLI commands (`config show`, `config edit`, `config validate`, `config path`). Interactive prompts guide proxy creation.

Version and revision tracking is implemented via `config_history.jsonl`:

- Events recorded: `config_created`, `config_loaded`, `config_updated`, `manual_change_detected`, `config_validation_failed`.
- Each entry carries a version marker (v1, v2, v3...).
- SHA-256 checksums detect manual file changes outside the CLI.
- Deep comparison tracking records changed paths with old and new values.
- Policy history is similarly tracked in `policy_history.jsonl`.

The chronological development of configuration can be reconstructed from these audit logs.

**Key files:**

| File | Purpose |
|------|---------|
| `src/mcp_acp/config.py` | Pydantic configuration models |
| `src/mcp_acp/cli/commands/config.py` | CLI config management commands |
| `src/mcp_acp/cli/commands/init.py` | Interactive configuration initialisation |
| `src/mcp_acp/cli/prompts.py` | Interactive CLI prompts |
| `src/mcp_acp/manager/routes/config.py` | Manager API config endpoints (read, update, compare, API key management) |
| `src/mcp_acp/utils/history_logging/config_logger.py` | Configuration history logging with change detection |
| `src/mcp_acp/utils/history_logging/policy_logger.py` | Policy history logging with checksum comparison |
| `tests/test_config.py` | Pydantic config model validation tests |
| `tests/api/test_config_routes.py` | Config API endpoint tests |

---

### M6: Logging — MET

> The prototype must provide structured logs that record all client↔proxy and proxy↔server communication, HITL approvals and denials, system events and relevant metrics in clearly separated JSONL  log categories. Each communication log entry must include an ISO 8601 timestamp with milliseconds in UTC, a correlation or trace identifier, user and server identifiers where available, the requested action and the resulting policy decision, and logging must occur synchronously so that no decision is returned before its corresponding log entry is written. This goal is achieved when these logs enable a complete reconstruction of proxy–mediated actions, HITL decisions, and system behaviour in line with the ZT auditability requirements.

**How it is met:**

The logging subsystem is structured around three concerns — audit, system, and debug — each written to dedicated JSONL files so that security-critical records are separated from operational noise:

| Log File | Category | Content |
|----------|----------|---------|
| `audit/operations.jsonl` | Audit | All client-proxy and proxy-server operations |
| `audit/decisions.jsonl` | Audit | Policy decisions (allow, deny, hitl) |
| `audit/auth.jsonl` | Audit | Authentication events |
| `system/system.jsonl` | System | System events, lifecycle, errors |
| `system/config_history.jsonl` | System | Configuration change history |
| `system/policy_history.jsonl` | System | Policy version history |
| `debug/client_wire.jsonl` | Debug | Client-proxy JSON-RPC traffic (optional) |
| `debug/backend_wire.jsonl` | Debug | Proxy-server JSON-RPC traffic (optional) |

All Pydantic log models are defined in `src/mcp_acp/telemetry/models/` with `extra="forbid"` on audit models, which prevents unstructured fields from entering the audit trail.

**Correlation.** Two identifiers thread through all log categories: `request_id` (unique per JSON-RPC request, set once and propagated via async-safe `ContextVar`) and `session_id` (stable for the lifetime of a client connection). Because every audit, wire, and system log entry carries both identifiers, an analyst can reconstruct the full lifecycle of any single request across all eight log files and can group all requests belonging to a session. Correlation IDs are validated on ingestion: newline characters are rejected to prevent JSONL log injection.

**Kipling coverage.** Each logged event answers the six Kipling questions (who, what, when, where, why, how) that underpin forensic audit:

| Question | Fields | Source |
|----------|--------|--------|
| **Who** | `subject_id` (OIDC `sub`), `hitl_approver_id`, `client_id` (MCP client name) | JWT claims, HITL handler, MCP `clientInfo` |
| **What** | `mcp_method`, `tool_name`, `event` / `event_type`, `decision` | MCP protocol, policy engine |
| **When** | `time` (ISO 8601 with ms in UTC), `policy_eval_ms`, `policy_hitl_ms`, `duration_ms` | `ISO8601Formatter` (single source of truth), `time.perf_counter()` |
| **Where** | `backend_id`, `path` / `source_path` / `dest_path`, `transport`, `session_id` | Proxy config, MCP arguments, transport layer |
| **Why** | `matched_rules` (all matching rules with effect), `final_rule`, `policy_version`, `hitl_outcome` | Policy engine evaluation trace |
| **How** | `arguments_summary` (payload hash + size, content redacted), `side_effects`, wire logs (full JSON-RPC payloads in debug mode) | Audit middleware, tool side-effect registry |

Timestamps are not set by the model constructors; `ISO8601Formatter` adds them during log serialisation, providing a single source of truth and avoiding duplicate timestamp generation.

**Synchronous write guarantee.** Logging is synchronous: `FileHandler` writes directly to disk, and `FailClosedAuditHandler` checks file integrity (inode monitoring) before each write. No decision is returned to the client before its corresponding log entry is written. This ensures the audit trail cannot lag behind or silently lose entries.

**Key files:**

| File | Purpose |
|------|---------|
| `src/mcp_acp/telemetry/audit/decision_logger.py` | Policy decision audit logger (decisions.jsonl) |
| `src/mcp_acp/telemetry/audit/operation_logger.py` | MCP operation audit logger (operations.jsonl) |
| `src/mcp_acp/telemetry/audit/auth_logger.py` | Authentication event audit logger (auth.jsonl) |
| `src/mcp_acp/telemetry/system/system_logger.py` | System event logger (system.jsonl) |
| `src/mcp_acp/telemetry/debug/client_logger.py` | Client-side wire logging middleware (client_wire.jsonl) |
| `src/mcp_acp/telemetry/debug/backend_logger.py` | Backend wire logging (backend_wire.jsonl) |
| `src/mcp_acp/telemetry/debug/logging_proxy_client.py` | Wire-logging wrapper around backend transport |
| `src/mcp_acp/telemetry/models/audit.py` | Audit log entry models |
| `src/mcp_acp/telemetry/models/decision.py` | Decision event model (with timing fields) |
| `src/mcp_acp/telemetry/models/system.py` | System event model |
| `src/mcp_acp/telemetry/models/wire.py` | Wire protocol log models |
| `src/mcp_acp/utils/logging/iso_formatter.py` | ISO 8601 timestamp formatter |
| `src/mcp_acp/utils/logging/logging_helpers.py` | Logger setup with fail-closed handler |
| `src/mcp_acp/utils/logging/logging_context.py` | Correlation ID context variables |
| `tests/telemetry/audit/test_audit_logging.py` | Audit logging tests |
| `tests/api/test_logs.py` | Log viewing API tests |

---

## Should Goals

### S1: UI — PARTIALLY MET

> The system should provide a minimal, locally hosted React web UI to support transparency and operability of the proxy. The web UI focuses on inspection and basic control rather than visual design and includes core capabilities such as proxy lifecycle control, configuration, policy inspection with basic editing and validation, visibility into active sessions, HITL integration and log views. This goal is achieved when an operator can use the web UI to inspect the current proxy state, access–control situation and respond to basic approval workflows and view logs without relying exclusively on the CLI and raw log files.

**How it is met:**

A React 18.3 web UI (TypeScript, Vite, Tailwind CSS, Radix UI) is served by the manager daemon at `http://localhost:8765`. It provides most of the specified core capabilities:

| Capability | Implementation |
|-----------|----------------|
| Proxy lifecycle control | **Partially met.** The UI displays proxy status (running/inactive) via SSE and supports creating and archiving proxy configurations, but cannot start, stop, or restart proxy processes. Process lifecycle is owned by the MCP client (e.g., Claude Desktop), which spawns each proxy via stdio. The UI provides config export snippets that tell the client how to launch a proxy, but has no direct process control. |
| Configuration | Config display and editing via proxy detail page |
| Policy inspection with editing | Rule editor with drag-to-reorder, real-time validation, hot reload |
| Active session visibility | Real-time SSE streaming of request statistics and connection status |
| HITL integration | Pending approval drawer with approve/deny/allow-once, timeout countdown, cached approval visualisation |
| Log views | Log viewer with folder navigation, time range and decision filters, correlation ID lookup (session ID, request ID), cursor-based pagination, raw JSON export. No free-text keyword search. |

Additional features include an incidents page for security events and audit integrity verification display.

**Key files:**

| File | Purpose |
|------|---------|
| `web/src/App.tsx` | Application routing |
| `web/src/pages/ProxyListPage.tsx` | Proxy dashboard |
| `web/src/pages/ProxyDetailPage.tsx` | Proxy management with sidebar sections |
| `web/src/pages/IncidentsPage.tsx` | Security incident timeline with type and proxy filters |
| `web/src/pages/AuthPage.tsx` | Authentication flow UI (device flow login, token status) |
| `web/src/components/approvals/PendingDrawer.tsx` | HITL approval panel |
| `web/src/components/logs/LogViewer.tsx` | Log viewer with filtering |
| `web/src/components/policy/` | Policy editor components |
| `web/src/components/detail/TransportFlow.tsx` | Visual client → proxy → backend flow diagram |
| `web/src/components/detail/AuditIntegritySection.tsx` | Hash chain integrity verification with visual status |
| `web/src/components/detail/StatsSection.tsx` | Real-time request statistics display |
| `web/src/context/AppStateContext.tsx` | Real-time state management via SSE |
| `web/src/context/IncidentsContext.tsx` | Incident state and filtering |
| `src/mcp_acp/manager/daemon/server.py` | Manager daemon serving the web UI |

---

### S2: Client-Side Protections — MET

> The system should implement basic client-side protections that treat all server responses as untrusted input by (1) validating backend-to-proxy messages as well-formed MCP/JSON-RPC , (2) sanitising or escaping potentially dangerous output, such as embedded HTML, and (3) blocking obviously unsafe elicitation attempts that try to obtain secrets like passwords, tokens or application programming interface (API) keys from the user. This goal is achieved when malformed or malicious responses and user-elicitation attempts in representative scenarios are reliably detected, rejected or sanitised by the proxy without disrupting legitimate MCP interactions.

**How it is met:**

1. **MCP/JSON-RPC validation**: Safe argument extraction with graceful handling of malformed arguments, JSON-RPC error code mapping, and request ID validation that prevents JSONL log corruption via newline character rejection.

2. **Sanitisation of server responses**: Tool descriptions from backends are sanitised before returning to the client. The sanitisation pipeline applies:
   - Unicode normalisation (NFKC) to collapse homoglyph attacks.
   - Control character removal (preserving newline, tab, carriage return).
   - Whitespace normalisation.
   - Markdown link URL stripping (retains text, removes URLs).
   - HTML/XML tag removal.
   - Length truncation (500 characters maximum).

3. **Prompt injection detection in tool descriptions**: Suspicious patterns are detected in tool descriptions returned by backend servers. The proxy only sees tool calls and results, not the conversation, so classic conversational elicitation attacks are outside its scope. What it can detect are attempts by a compromised or malicious server to embed adversarial instructions in tool metadata:
   - Instruction overrides: "ignore all instructions", "disregard previous".
   - Role assumption: "you are", "act as", "pretend".
   - System prompt references: "system prompt", "hidden instruction".
   - Detections are logged as warnings for analyst review.

**Key files:**

| File | Purpose |
|------|---------|
| `src/mcp_acp/security/sanitizer.py` | Tool description sanitisation pipeline |
| `src/mcp_acp/security/tool_sanitizer.py` | Tool list response sanitisation with elicitation detection |
| `src/mcp_acp/context/parsing.py` | Safe MCP argument extraction |
| `tests/security/test_sanitizer.py` | Sanitisation tests (unicode, markdown, HTML, injection) |

---

### S3: Server-Side Protections — MET

> The proxy should implement protections for the backend file system servers by normalising and validating requested paths and applying simple per-session rate limiting so that misbehaving clients or models cannot overload or misuse a server. This goal is achieved when attempts to generate excessive request volumes in test scenarios are consistently blocked or throttled by the proxy while normal, expected usage remains unaffected.


**How it is met:**

1. **Path normalisation and validation**: `os.path.realpath()` resolves symlinks for protected-path checking. `os.path.normpath()` handles `../` traversal for policy context extraction. Protected directories (config and log paths) are checked before policy evaluation as a defence-in-depth layer that cannot be overridden by policy. Unit tests verify symlink bypass prevention and directory boundary enforcement.

2. **Per-session rate limiting**: A sliding-window tracker monitors per-session, per-tool call frequency (default: 30 calls per tool per 60-second window). Exceeding the threshold triggers HITL escalation rather than automatic denial, so legitimate bursts can be approved. A global DoS rate limiter (token bucket: 10 req/s, 50 burst) operates as the outermost middleware layer. Normal usage patterns (10-20 calls/tool/minute) remain unaffected.

**Key files:**

| File | Purpose |
|------|---------|
| `src/mcp_acp/pep/protected_paths.py` | Symlink-safe protected path validation |
| `src/mcp_acp/security/rate_limiter.py` | Per-session, per-tool sliding window rate limiter |
| `src/mcp_acp/pep/rate_handler.py` | Rate-limit to HITL escalation handler |
| `tests/pep/test_protected_paths.py` | Protected path tests (14 scenarios) |
| `tests/security/test_rate_limiter.py` | Rate limiter tests |

---

### S4: Testing — MET

> The project should define and execute a small but coherent test suite that covers the most important functional and security behaviours of the proxy across both stdio and HTTP-based communication, including authorised reads, denied access to protected paths, HITL-gated writes, and at least one policy-violating cross-server scenario. This goal is achieved when these tests are documented clearly enough to be repeated by another person and when their outcomes can be used directly in the evaluation chapter to support claims about correctness and security effectiveness.

**How it is met:**

The automated test suite comprises 44 backend test files with 1 196 test functions and 15 frontend test files with 265 test cases, covering policy evaluation, enforcement, authentication, integrity, sanitisation, rate limiting, approval caching, CLI commands, API routes, manager functionality, and React components and hooks.

Integration tests (`tests/integration/test_proxy_e2e.py`) exercise the full middleware chain with 10 scenarios: authorised reads, default-deny, explicit deny overriding allow, wildcard matching, path-based rules, and side-effect restrictions.

Approval caching is covered by `tests/pep/test_approval_store.py` (27 test functions) including TTL-based expiry, cache lookup by subject/tool/path, path normalisation, overwrite semantics, and side-effect filtering (CODE_EXEC tools are never cached, even if explicitly allowed).

Manual test suites are thoroughly documented:

- Adversarial server guide (`docs/security-testing/`): 8 scenarios with setup scripts.
- Demo testing guide (`docs/demo-testing-guide/`): 22 scenarios with workspace generation script and 24-rule policy.
- Manager-UI coupling tests: 9 manual HITL fallback scenarios.

Tests are documented with clear docstrings, inline policies, and expected-vs-actual templates. Automated tests can be repeated via `pytest tests/` and `npm run test:run`.

**Note on HITL test strategy:** A consequence of the multi-process architecture is that HITL approval flows could not be feasibly included in automated integration tests, as orchestrating asynchronous approval coordination across proxy and manager processes exceeded the capabilities of the in-memory test transport. HITL correctness was instead validated through systematic manual end-to-end testing covering nine documented scenarios, including approval caching, timeout behaviour, and fallback to native dialogues.

**Key files:**

| File | Purpose |
|------|---------|
| `tests/integration/test_proxy_e2e.py` | 10 E2E scenarios with production middleware |
| `tests/integration/conftest.py` | Test fixtures replicating production stack |
| `tests/pdp/test_policy.py` | Policy evaluation logic tests |
| `tests/pep/test_approval_store.py` | Approval caching with TTL, expiry, and side-effect filtering (27 tests) |
| `tests/pep/test_protected_paths.py` | Protected path enforcement (14 tests) |
| `tests/security/test_sanitizer.py` | Sanitisation pipeline tests |
| `tests/security/integrity/test_hash_chain.py` | Hash chain verification (29 tests) |
| `docs/security-testing/adversarial-server-guide.md` | 8 manual adversarial scenarios |
| `docs/demo-testing-guide/screenrecording-scenarios.md` | 22 demo scenarios |

---

### S5: Performance — MET

> The project should collect basic performance measurements that are sufficient to assess the feasibility of the proxy (such as indicative decision latency for policy evaluation and the additional overhead introduced by HITL approvals) under representative workloads, without aiming at systematic optimisation or large-scale benchmarking. This goal is achieved when the thesis can report and interpret concrete latency or overhead figures derived from the implemented prototype to support the discussion of feasibility in the evaluation chapter, while clearly distinguishing these observations from full performance tuning or stress testing, which remain out of scope.

**How it is met:**

Performance measurement spans three layers: per-request instrumentation in audit logs, standalone benchmark scripts, and a log analysis tool that produces percentile-based statistics.

**In-flight instrumentation:**

- Every policy decision logs `policy_eval_ms`, `policy_hitl_ms`, and `policy_total_ms` to `decisions.jsonl`, captured via `time.perf_counter()`.
- Operation events log `duration_ms` for total operation latency.
- Wire logs track per-request durations for both client and backend sides.
- Live request counters (total, allowed, denied, hitl) are exposed via the management API.

**Benchmark scripts:**

- `scripts/measure_overhead.py` compares direct backend latency against proxied latency using FastMCP Client with StdioTransport, matching the production deployment model. It supports both stdio and HTTP backends, configurable warmup and run counts, and outputs structured JSON results.
- `scripts/parse_latency_logs.py` parses `decisions.jsonl` and `operations.jsonl`, correlates entries by `request_id`, and produces percentile statistics (p25, p50, p75, p95, p99) with per-decision-type breakdowns and optional date filtering. It also separates HITL-excluded statistics to isolate proxy overhead from human wait time.

**Collected results** (`scripts/results/`, 8 files):

| Scenario | Transport | Notes |
|----------|-----------|-------|
| Echo server | stdio | Baseline: 100 runs, median 16.38 ms proxied tool call |
| Echo server | HTTP | Baseline: 100 runs |
| Filesystem server | stdio | Real backend, no policy rules |
| Filesystem server | stdio + policy | With active policy evaluation |
| Filesystem server | stdio + 50 rules | Policy scaling test |
| Filesystem server | HTTP | Real backend over HTTP |
| Filesystem server | HTTP + policy | With active policy evaluation |
| Filesystem server (log parse) | stdio | Percentile analysis from production audit logs (26 decisions, p95 policy eval 1.74 ms) |

These results provide the evidence needed to assess proxy feasibility: sub-millisecond policy evaluation overhead and low tens of milliseconds total proxy overhead for stdio-based deployments.

**Key files:**

| File | Purpose |
|------|---------|
| `src/mcp_acp/telemetry/models/decision.py` | Decision event model with `policy_eval_ms`, `policy_hitl_ms`, `policy_total_ms` |
| `src/mcp_acp/pep/middleware.py` | Timing capture via `time.perf_counter()` |
| `src/mcp_acp/manager/state.py` | Live request counters |
| `scripts/measure_overhead.py` | Proxy overhead benchmark (direct vs. proxied comparison) |
| `scripts/parse_latency_logs.py` | Audit log latency analysis with percentile calculations |
| `scripts/results/` | Collected benchmark results (8 scenarios) |

---

## Could Goals

### C1: Improved UI — PARTIALLY MET

> The system could be extended with additional user interface features and a more polished design to further improve usability and operator experience. Potential enhancements include (1) advanced log filtering, sorting, and search capabilities, (2) contextual visualisations of request and decision flows, (3) onboarding aids such as an application tour or inline explanations and (4) refined visual presentation to improve clarity during extended operation. These improvements are considered beneficial for long–term usability but are not required for demonstrating the core security and access–control concepts of this work.


| Enhancement | Status | Notes |
|------------|--------|-------|
| Advanced log filtering, sorting, and search | **Partially implemented** | Time range filters, decision and HITL outcome dropdowns, log level filtering, exact-match correlation lookups (session ID, request ID), version filters, and cursor-based pagination. No free-text keyword or regex search; no user-controlled sorting (entries displayed in reverse chronological order only). |
| Contextual visualisations of request and decision flows | **Partially implemented** | Transport flow diagram (`TransportFlow.tsx`), audit integrity visualisation, incident timeline; no per-request decision trace view |
| Onboarding aids (tour, inline explanations) | **Not implemented** | No application tour or contextual help |
| Refined visual presentation | **Partially implemented** | Functional design via Radix UI and Tailwind CSS; no polish pass for extended operation |

---

### C2: Improved Cross-Server Data Flows — NOT MET

> The project could further refine its cross-server data-flow controls by improving how data labels, such as public, internal or secret, are propagated across multi-step workflows and enforcing more nuanced policies when labelled data from different servers are combined or written back. This goal is achieved when at least five multi-step scenarios involving multiple reads and writes across servers demonstrate stricter or more expressive enforcement than the minimal rules, while remaining compatible with the existing policy model.

This goal is not met:

- The `classification` field on `ResourceInfo` is declared but marked "Future" and is not populated.
- No data labels (public, internal, secret) are propagated or enforced.
- No multi-step workflow tracking exists across servers or proxy instances.
- No scenarios demonstrate stricter cross-server enforcement.
- The single-backend-per-proxy architecture provides isolation but not the nuanced flow policies this goal describes.

**Relevant file:** `src/mcp_acp/context/resource.py` (unimplemented `classification` field).

---

### C3: Logging Tamper-Proofing — MET

> The prototype could incorporate a lightweight tamper-evidence mechanism for its JSONL audit logs by computing chained hashes or checksums over log entries or log segments so that post-hoc modifications or deletions become detectable. This goal is achieved when a simple verification tool or script can recompute the chain and reliably distinguish between an unmodified log and one where earlier entries have been altered, thereby strengthening audit integrity without requiring a full immutability infrastructure.

**How it is met:**

A SHA-256 hash chain is implemented. Each log entry includes `sequence`, `prev_hash` (or `GENESIS` for the first entry), and `entry_hash`. Deterministic JSON serialisation (sorted keys, no whitespace) ensures reproducibility.

Detection capabilities:

- Deleted entries (chain breaks).
- Inserted entries (hash mismatch).
- Reordered entries (sequence gap).
- Modified entries (content hash mismatch).

Runtime protection via `FailClosedAuditHandler` monitors file inodes to detect deletion or replacement. Between-run protection via `.integrity_state` files stores the last hash, sequence, inode, and device per log file; startup verification compares stored state against actual files and hard-fails (exit code 10) on mismatch.

A CLI verification tool (`mcp-acp audit verify`) recomputes the chain and reports discrepancies, fulfilling the requirement for "a simple verification tool or script."

**Key files:**

| File | Purpose |
|------|---------|
| `src/mcp_acp/security/integrity/hash_chain.py` | SHA-256 hash chain formatter and verifier |
| `src/mcp_acp/security/integrity/integrity_state.py` | Between-run state persistence and verification |
| `src/mcp_acp/security/integrity/audit_handler.py` | Fail-closed file handler with inode monitoring |
| `src/mcp_acp/security/integrity/audit_monitor.py` | Background runtime integrity monitoring (periodic re-verification) |
| `src/mcp_acp/security/integrity/emergency_audit.py` | Three-tier fallback logging chain |
| `src/mcp_acp/cli/commands/audit.py` | CLI `audit verify` command |
| `src/mcp_acp/manager/routes/audit.py` | Audit verification API endpoints |
| `tests/security/integrity/test_hash_chain.py` | Hash chain tests (48+ scenarios) |
| `tests/security/integrity/test_integrity_state.py` | State management and tampering detection tests |

---

### C4: Log Rotation — NOT MET

> The project could extend its logging subsystem with a more complete lifecycle that includes size-based log rotation, compression of rotated log files, predictable file naming with timestamps, and in-process rotation mechanisms that avoid data loss during concurrent writes. It could further support long–term retention by shipping rotated logs to external storage or security information and event management (SIEM) systems, where they can be archived under retention policies and accompanied by integrity metadata, such as per-file hashes or chained digests. This goal is achieved when rotated logs can be stored, reviewed and verified independently of the running proxy, providing a practical foundation for durability, tamper-evidence, and future operational hardening beyond the needs of the prototype.

This goal is not met:

- No `RotatingFileHandler`, `maxBytes`, or `backupCount` usage in the codebase.
- No compression of rotated files.
- No timestamp-based naming for rotated files.
- No in-process rotation mechanism.
- No SIEM shipping or external storage integration.
- Logs grow unbounded (append-only by design for audit integrity).

---

### C5: Integration Pipeline — MET

> The project could introduce a simple continuous-integration pipeline, using GitHub Actions, that automatically runs the defined test suite and basic static checks whenever changes are pushed to the repository. This goal is achieved when commits to the main development branch trigger reproducible checks without manual intervention, providing an initial foundation for future continuous integration and continuous deployment (CI/CD) practices, even though full deployment automation remains outside the scope.

**How it is met:**

A GitHub Actions workflow (`.github/workflows/ci.yml`) triggers on pushes to `main` and pull requests:

| Job | Environment | Steps |
|-----|------------|-------|
| Backend | Ubuntu, Python 3.11 and 3.13 matrix | Install via `uv`, run `pytest` |
| Frontend | Ubuntu, Node.js 20 | Install via `npm ci`, run `vitest`, run `vite build` |

Commits to the main branch trigger reproducible checks without manual intervention.

**Key file:** `.github/workflows/ci.yml`

---

### C6: Runtime Policy Refresh — MET

> The proxy could support manual policy hot reloading that replaces the in-memory policy snapshot without restarting the process. A reload is triggered via a CLI command (policy reload), which causes the proxy to reparse and validate the policy file, instantiate a new policy state, and atomically swap it in for new requests, while allowing in-flight requests to finish using the old state . Any pending HITL approvals are cleared during reload to avoid stale decisions. This goal is achieved when a policy change (e.g. switching a path from denied → allowed or modifying a data-flow constraint) becomes effective immediately after running the reload command, without requiring a proxy restart, and can be demonstrated in an E2E read/write scenario.

**How it is met:**

`PolicyReloader` (`src/mcp_acp/pep/reloader.py`) performs async, mutex-locked reloads:

1. Reads policy from disk and validates via Pydantic (last-known-good on failure).
2. Atomically swaps the in-memory policy reference for new requests.
3. In-flight requests continue with the old policy.
4. Pending HITL approvals are cleared to avoid stale decisions.
5. Policy version is incremented in `policy_history.jsonl`.
6. SSE event is emitted for UI notification.

Reload is triggered via:

- SIGHUP signal.
- `POST /api/control/reload-policy` API endpoint.
- `mcp-acp policy reload --proxy <name>` CLI command.

The effect is immediate: a path that was denied becomes allowed (or vice versa) after the reload command, without restart.

**Key files:**

| File | Purpose |
|------|---------|
| `src/mcp_acp/pep/reloader.py` | Policy reload logic with atomic swap and version tracking |
| `src/mcp_acp/pep/middleware.py` (`reload_policy()`) | Atomic policy swap within enforcement middleware |
| `src/mcp_acp/api/routes/control.py` | `POST /api/control/reload-policy` API endpoint |
| `src/mcp_acp/manager/routes/policy.py` | Manager-level policy CRUD with automatic reload forwarding |
| `src/mcp_acp/manager/events.py` | SSE events for policy reload success, failure, and rollback |
| `src/mcp_acp/cli/commands/policy.py` | CLI `policy reload` command |
| `tests/pep/test_policy_reload.py` | Reload tests (success, errors, version tracking, approval clearing) |

---

## Won't Goals

These goals are correctly out of scope and not implemented, as intended.

| Goal | Confirmation |
|------|-------------|
| **W1: Enterprise-level IAM** | No MFA, no multi-tenant identity models, no adaptive authorisation, no OPA-based PDP/PEP separation. Single-tenant Auth0 Device Flow only. |
| **W2: Advanced security analytics** | No ML-based content inspection, no anomaly detection, no DLP, no token-replay protection, no sandboxed execution. |
| **W3: Non-filesystem server types** | Only filesystem MCP servers are supported. No API gateways, databases, Slack/GitHub connectors, or search servers. |
| **W4: Distributed architecture** | Strictly single-host, single-tenant. No clustering, load balancing, distributed failover, or multi-node coordination. |
| **W5: Performance optimisation** | No systematic tuning or large-scale benchmarking. Feasibility measurements collected (see S5) but no optimisation work performed. |
| **W6: Production CI/CD** | CI runs tests only. No automated deployment workflows, rollout validation, or operational hardening. |

---

## Summary

| Priority | Goal | Status | Key Gap (if any) |
|----------|------|--------|------------------|
| Must | M1: Core proxy | **MET** | |
| Must | M2: ZT policy engine | **PARTIALLY MET** | Cross-server flows handled via isolation, not explicit flow rules or data labels |
| Must | M3: Auth | **MET** | |
| Must | M4: HITL | **MET** | |
| Must | M5: Configuration | **MET** | |
| Must | M6: Logging | **MET** | |
| Should | S1: UI | **PARTIALLY MET** | Proxy lifecycle control limited to config management and status display; process lifecycle owned by MCP client via stdio |
| Should | S2: Client-side protections | **MET** | |
| Should | S3: Server-side protections | **MET** | |
| Should | S4: Testing | **MET** | HITL validated via manual E2E testing (multi-process coordination precludes automation) |
| Should | S5: Performance | **MET** | |
| Could | C1: Improved UI | **PARTIALLY MET** | Log filtering and partial visualisations done; no onboarding aids or per-request trace view |
| Could | C2: Improved cross-server flows | **NOT MET** | No data labels, no cross-server tracking |
| Could | C3: Logging tamper-proofing | **MET** | |
| Could | C4: Log rotation | **NOT MET** | No rotation, compression, or SIEM shipping |
| Could | C5: Integration pipeline | **MET** | |
| Could | C6: Runtime policy refresh | **MET** | |
| Won't | W1-W6 | **Correctly excluded** | |
