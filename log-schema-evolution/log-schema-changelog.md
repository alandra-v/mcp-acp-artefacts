# Log Schema Evolution Changelog

How the MCP-ACP logging schemas evolved across four development stages, from initial design through Zero Trust hardening and cryptographic integrity.

All schemas use JSONL format and draw from the [OCSF](https://schema.ocsf.io/) framework where applicable.

---

## Stage 0 — Planned Schemas

> `00-planned-log-schemas/`

The initial design laid out the foundational log types and established the OCSF-aligned field conventions used throughout the project.

### Log types

| Log | File | OCSF basis |
|-----|------|------------|
| Authentication | `audit/auth.jsonl` | Authentication [3002] + Authorize Session [3003] |
| Operations | `audit/operations.jsonl` | API Activity [6003] |
| System errors | `system/system.jsonl` | Process Activity [1007] + Application Error [6008] |
| Config history | `system/config_history.jsonl` | OWASP / NIST SP 800-92 & 800-128 / CIS Control 8 |
| Debug wire logs | `debug/backend_wire.jsonl`, `debug/client_wire.jsonl` | — |

### Key design decisions

- **Auth log** tracked token validation (per-request) and session lifecycle. Identity was captured as flat fields (`subject_id`, `subject_claims`). OIDC token details (issuer, audience, scopes, expiration) were also flat.
- **Operations log** captured who-did-what-when with a granular **latency breakdown**: `latency_ms_total`, `latency_ms_client_to_proxy`, `latency_ms_proxy_to_backend`, `latency_ms_backend_processing`. Request bodies were redacted via `arguments_summary` with a body hash.
- **System log** captured WARNING/ERROR/CRITICAL events with component context and optional stack traces.
- **Config history** recorded every config load/update with a full snapshot for point-in-time reconstruction.
- **No policy decision log yet** — authorization logging hadn't been scoped. An empty `decisions.jsonl` placeholder existed but had no schema.
- `time` was listed as a plain required field in auth and operations. The system log already noted "(your formatter does this already)", so formatter injection was partially in use but not yet a consistent convention.

> **Commentary:** This was a reasonable starting point — the classic "auth + ops + errors + config" quartet. The granular latency breakdown in operations was ambitious but reflected the proxy's multi-hop architecture (client → proxy → backend). The absence of authorization logging is the most notable gap: at this stage the focus was on *identity* ("who are you?") rather than *authorization* ("are you allowed to do this?").

---

## Stage 0 → Stage 1 — Core Implementation

> `01-logging-specs-mcp-acp-core/`

The first implementation stage made the most structurally significant changes. The auth log was dropped entirely, replaced by a dedicated policy decisions log that became the centerpiece of the audit trail.

### Added

- **`audit/decisions.jsonl`** — New ABAC policy decision log. Records every authorization evaluation: which rules matched, which rule was final, whether the request was allowed/denied/escalated to human-in-the-loop (HITL). Captures resource context (`tool_name`, `path`, `uri`, `scheme`), side-effect tags (`fs_read`, `fs_write`), and performance metrics (`policy_eval_ms`, `policy_hitl_ms`, `policy_total_ms`). For HITL decisions, logs the human outcome (`user_allowed`, `user_denied`, `timeout`).
- **`system/policy_history.jsonl`** — Policy lifecycle tracking, mirroring `config_history` in structure. Records policy creation, loads, updates, manual edits, and validation failures. Includes rule-level detail (`rule_id`, `rule_effect`, `rule_conditions`) for granular change tracking.

### Removed

- **`audit/auth.jsonl`** — Dropped entirely. Authentication wasn't yet implemented in the core proxy, so the schema was removed rather than kept as dead weight.
- **`debug/` directory** — Wire log placeholders removed.

### Changed

**Operations (`audit/operations.jsonl`):**
- `time` explicitly marked as **formatter-injected** across all log types (added during serialization, not by the caller). Stage 0's system log already used a formatter, but Stage 1 made this the consistent convention.
- Latency **simplified**: the 4-field breakdown (`latency_ms_total`, `latency_ms_client_to_proxy`, etc.) was replaced with a single `duration` object containing `duration_ms`. The granular breakdown turned out to be impractical to measure accurately at the proxy layer.
- Added `error_code` for JSON-RPC/MCP error codes on failure.
- Added `client_id` (MCP client app name), `transport` (`stdio` | `streamablehttp`).
- Added `file_path`, `file_extension` — extracted from request arguments for easier querying. (`tool_name` already existed in Stage 0.)
- Added `response_summary` (`size_bytes`, `body_hash`) — request bodies were already hashed, now responses got the same treatment.

**Config history (`system/config_history.jsonl`):**
- New events: `config_loaded`, `manual_change_detected`, `config_validation_failed`.
- Change types reworked: `manual_update` and `reload` removed; `cli_update`, `manual_edit`, `startup_load`, `validation_error` added. `initial_load` retained.
- Added `source` field (e.g. "cli_init", "cli_update", "proxy_startup").
- Added `changes` dict for diffing updates (`{"path": {"old": x, "new": y}}`).
- Added `error_type` and `error_message` for validation failure events.
- `snapshot_format` expanded to `"yaml" | "json"`.

**System (`system/system.jsonl`):**
- `time` wording updated to match the new formatter-injected convention (was already formatter-based in Stage 0).
- Explicitly noted as extensible (`extra = "allow"`).

> **Commentary:** This is where the logging philosophy shifted. Dropping the auth log in favor of a decisions log was a deliberate reorientation: the system's primary audit concern wasn't "did the token validate?" but "why was this request allowed or denied?" The decisions log provides full transparency into ABAC evaluation — which rules matched, which one won, and whether a human was involved. This is the log you'd use in an incident to answer "how did that request get through?"
>
> The latency simplification is also telling. The original 4-field breakdown was theoretically useful but hard to populate accurately in practice. Collapsing it to a single `duration_ms` reflects a pragmatic adjustment: measure what you can measure reliably.
>
> The addition of `policy_history` alongside `config_history` established a pattern: every mutable configuration surface gets its own lifecycle log.

---

## Stage 1 → Stage 2 — Zero Trust Extension

> `02-logging-specs-mcp-acp-extended/`

The extended implementation reintroduced authentication logging, but in a fundamentally different form — rebuilt around Zero Trust principles with device posture checking and session binding.

### Added

- **`audit/auth.jsonl`** — Reintroduced, now as a Zero Trust authentication log. Key additions:
  - **Device health checks** (`device_checks`): verifies `disk_encryption` (FileVault) and `device_integrity` (SIP) on macOS, each reporting `pass` | `fail` | `unknown`. Unknown is treated as unhealthy.
  - **Dual session IDs**: `bound_session_id` (format `<user_id>:<session_uuid>`, structurally binds the session to the authenticated identity) and `mcp_session_id` (plain UUID for correlation with operations/decisions logs).
  - **New event types**: `token_refreshed`, `token_refresh_failed`, `device_health_failed`.
  - **Session termination reasons**: `end_reason` with values including `session_binding_violation` (session-identity mismatch detected) and `auth_expired`.
  - **Failure-only logging**: success events for per-request token validation and periodic device checks are not logged. Only failures and session lifecycle events are recorded.

### Changed

**Operations (`audit/operations.jsonl`):**
- `subject` restructured from flat fields (`subject_id`, `subject_claims`) into a **`SubjectIdentity` object** (`subject.subject_id`, `subject.subject_claims`). This nesting pattern was applied consistently across all logs that carry identity.
- Added `source_path` and `dest_path` for file copy/move operations.
- `arguments_summary`, `response_summary`, and `duration` formalized as typed objects (`ArgumentsSummary`, `ResponseSummary`, `DurationInfo`).

**Decisions (`audit/decisions.jsonl`):**
- `matched_rules` changed from a flat list of rule IDs to a **list of objects** with `{id, effect, description}` — richer trace information for each matching rule.
- Added `hitl_cache_hit` (boolean: was the HITL approval served from cache or did the user get prompted?).
- Added `source_path`, `dest_path` for move/copy context.
- Removed `is_mutating` field (mutation semantics now inferred from `side_effects`).
- `side_effects` values uppercased (`"FS_WRITE"`, `"CODE_EXEC"` instead of `"fs_read"`, `"fs_write"`).

**Auth OIDC details** restructured from flat fields into an **`OIDCInfo` object** (`oidc.issuer`, `oidc.audience`, etc.).

> **Commentary:** The reintroduction of the auth log is the headline change, but it's a completely different log than the Stage 0 version. The original was a token validation record. This one is a Zero Trust posture assessment: it checks not just "is your token valid?" but "is your device compliant?" and "does your session still match your identity?"
>
> The failure-only logging philosophy is worth noting. Stage 0 would have logged every successful token validation (one per MCP request). Stage 2 deliberately avoids that noise — the interesting events are failures, session boundaries, and device health violations. This is a maturity signal: log what you'd actually investigate, not everything that happens.
>
> The `bound_session_id` format (`<user_id>:<session_uuid>`) creates a structural link between an authenticated identity and a session. If the identity changes mid-session (token swap, session hijacking attempt), the `session_binding_violation` end reason fires. This wouldn't have been possible with Stage 0's single `session_id`.
>
> The structural refactoring (flat fields → typed objects like `SubjectIdentity`, `OIDCInfo`, `DurationInfo`) reflects the codebase maturing from spec-stage field lists into implemented Pydantic models. These aren't semantic changes, but they make the schemas more composable and consistent across log types.

---

## Stage 2 → Stage 3 — Cryptographic Integrity & Manager Observability

> `03-logging-specs-mcp-acp/`

The final stage added two things: tamper-evident hash chains across all proxy logs, and a new log type for the manager daemon.

### Added

- **Hash chain fields on all proxy logs** — Three new fields added to `auth`, `operations`, `decisions`, `system`, `config_history`, and `policy_history`:
  - `sequence` — Monotonically increasing entry number, added by `HashChainFormatter`.
  - `prev_hash` — SHA-256 hash of the previous log entry, or `"GENESIS"` for the first entry.
  - `entry_hash` — SHA-256 hash of the current entry.

  Together these form a hash chain: any modification, deletion, or reordering of log entries breaks the chain and is detectable during verification.

- **`manager/system.jsonl`** — New log type for the manager daemon (the process that supervises proxy instances). Based on OCSF Application Lifecycle [6002] and API Activity [6003]. Captures:
  - Daemon lifecycle: `manager_started`, `manager_stopped`, `idle_shutdown_triggered`.
  - Proxy management: `proxy_connection_error`, `registration_timeout`, with `proxy_name`, `instance_id`, `socket_path`.
  - API routing: `path`, `status_code`, `duration_ms`.
  - SSE subscriber tracking: `subscriber_count`.
  - Idle shutdown context: `proxy_count`, `sse_count`, `seconds_idle`.
  - Uses standard Python logging — **no hash chains** (manager logs are operational, not audit-grade).

### Changed

**Decisions (`audit/decisions.jsonl`):**
- Added `hitl_approver_id` — OIDC subject ID of the user who approved or denied a HITL request. Null on timeout or cache hit. Closes an accountability gap: previously you could see that a human approved something, but not *which* human.

> **Commentary:** The hash chain is the most significant security addition in the entire evolution. Up to Stage 2, log integrity depended entirely on filesystem permissions and trust in the logging infrastructure. Stage 3 makes tampering *detectable*: if someone modifies a log entry, deletes one, or reorders them, the chain breaks. This is the kind of property that compliance frameworks (SOC 2, ISO 27001) care about — it moves logs from "we wrote them down" to "we can prove they haven't been altered."
>
> The implementation is clean: the `HashChainFormatter` handles it transparently during serialization, so log-emitting code doesn't need to know about chaining. The `"GENESIS"` sentinel for the first entry is a nice touch — it makes chain verification unambiguous without needing a separate bootstrap mechanism.
>
> The manager log fills the last observability gap. The proxy was thoroughly instrumented from Stage 1, but the daemon that manages proxy lifecycle, handles SSE fan-out, and makes idle shutdown decisions was a black box. This matters operationally: if a proxy fails to register or an idle shutdown fires unexpectedly, you need the manager's perspective to debug it.
>
> Note that the manager log intentionally skips hash chains. This is a sensible boundary: manager logs are operational diagnostics, not security audit records. Applying hash chains everywhere would add overhead without a clear compliance benefit.
>
> The addition of `hitl_approver_id` is a small but important detail. In a HITL workflow, knowing that "a human approved this" is insufficient for a real audit — you need to know *who*. This closes the accountability loop.

---

## Summary of Log Types Across Stages

| Log type | Stage 0 | Stage 1 | Stage 2 | Stage 3 |
|----------|---------|---------|---------|---------|
| `audit/auth.jsonl` | Token validation + session lifecycle | *Removed* | Zero Trust: device checks, session binding, failure-only | + Hash chain |
| `audit/operations.jsonl` | API activity, granular latency | Simplified duration, added response hash | + SubjectIdentity objects, copy/move paths | + Hash chain |
| `audit/decisions.jsonl` | *Placeholder only* | ABAC decisions with HITL | + Rich matched_rules, HITL cache | + Hash chain, approver ID |
| `system/system.jsonl` | Errors/warnings | Formatter-injected time | `message`, `component` explicitly optional | + Hash chain |
| `system/config_history.jsonl` | Config snapshots | + Expanded events, change diffs, YAML support | YAML dropped (`snapshot_format` → JSON only) | + Hash chain |
| `system/policy_history.jsonl` | *Did not exist* | Policy lifecycle | *(unchanged)* | + Hash chain |
| `manager/system.jsonl` | *Did not exist* | *Did not exist* | *Did not exist* | Daemon ops (no hash chain) |

## Cross-Cutting Themes

**From identity to authorization.** The most important conceptual shift happens between Stage 0 and Stage 1. The original design centered on authentication ("who are you?"). The core implementation recentered on authorization ("what are you allowed to do, and why?"). The decisions log — not the auth log — became the primary audit artifact.

**Failure-only logging.** Stage 2 introduced the principle of logging failures and lifecycle events, not successes. A token that validates correctly on every request isn't interesting. A token that *fails* or a device that *fails* a health check is. This reduces log volume without losing investigative value.

**Progressive trust hardening.** Each stage added a layer of trust verification: Stage 0 trusted tokens, Stage 1 evaluated policies, Stage 2 checked device posture, Stage 3 made the logs themselves tamper-evident. The arc is from "trust the client" toward "verify everything, trust nothing, and prove you haven't been lied to."

**Structural maturation.** Fields evolved from flat key-value pairs (Stage 0) to typed, nested objects (Stage 2+). This reflects the transition from design specs to implemented Pydantic models, and makes the schemas more composable and self-documenting.

**OCSF as vocabulary, not constraint.** The schemas consistently reference OCSF classes (Authentication 3002, API Activity 6003, Process Activity 1007, etc.) for conceptual grounding, but never rigidly follow the OCSF field schema. The project uses OCSF as a shared vocabulary and design influence, adapting it to MCP-specific needs rather than conforming to it.
