# Manual E2E Testing Checklist

> **This checklist documents manual testing performed during development but is not
> an exhaustive record of every scenario tested. Automated unit and integration tests
> (pytest + vitest) provide additional coverage — see `unit-and-integration/web/coverage/` and `unit-and-integration/htmlcov/`
> for reports.**

Last updated: 01.02.2026

---

## CLI Commands

All commands tested with `--help`, valid input, and invalid input unless noted.

### `mcp-acp start`
- [x] Start proxy in foreground (`--proxy`)
- [x] Stdio backend connects and proxies requests
- [x] HTTP backend connects and proxies requests
- [x] Error on missing/invalid proxy name

### `mcp-acp status`
- [x] Show all proxy statuses (no flags)
- [x] Show specific proxy (`--proxy`)
- [x] JSON output (`--json`)
- [x] Handles no proxies configured

### `mcp-acp proxy add`
- [x] Interactive mode (no flags, prompts for values)
- [x] Non-interactive stdio (`--name`, `--server-name`, `--connection-type stdio`, `--command`, `--args`)
- [x] Non-interactive HTTP (`--connection-type http`, `--url`)
- [x] With API key (`--api-key`) — credential stored in keychain
- [x] With mTLS (`--mtls-cert`, `--mtls-key`, `--mtls-ca`)
- [x] With attestation (`--attestation-sha256`, `--attestation-slsa-owner`, `--attestation-require-signature`)
- [x] Skip confirmation (`--yes`)
- [x] Duplicate name rejected

### `mcp-acp proxy list`
- [x] List active proxies
- [x] List deleted/archived proxies (`--deleted`)
- [x] Empty state (no proxies)

### `mcp-acp proxy delete`
- [x] Soft delete (archive) with confirmation
- [x] Permanent delete (`--purge`)
- [x] Skip confirmation (`--yes`)
- [x] Error on nonexistent proxy
- [x] Full lifecycle: delete -> verify in `proxy list --deleted` -> purge -> verify gone

### `mcp-acp proxy auth`
- [x] `set-key` — set API key for proxy (`--proxy`, `--api-key`)
- [x] `set-key` — secure prompt when `--api-key` omitted
- [x] `delete-key` — remove API key from keychain

### `mcp-acp proxy purge`
- [x] Purge specific archived proxy (`--proxy`)
- [x] Purge all archived proxies
- [x] Skip confirmation (`--yes`)

### `mcp-acp manager start`
- [x] Start daemon (background)
- [x] Start in foreground (`--foreground`)
- [x] Custom port (`--port`)
- [x] Error when already running

### `mcp-acp manager stop`
- [x] Stop running daemon
- [x] Error when not running

### `mcp-acp manager status`
- [x] Show manager and proxy registration status
- [x] JSON output (`--json`)

### `mcp-acp auth login`
- [x] Device flow with browser open
- [x] Device flow without browser (`--no-browser`)
- [x] Token stored in keychain after success

### `mcp-acp auth logout`
- [x] Local logout (clear stored token)
- [x] Federated logout (`--federated`) — opens browser to Auth0

### `mcp-acp auth status`
- [x] Show auth state (authenticated / not authenticated / expired)
- [x] JSON output (`--json`)

### `mcp-acp auth sessions list`
- [x] List active OIDC sessions (`--proxy`)
- [x] JSON output (`--json`)

### `mcp-acp config show`
- [x] Show manager config (`--manager`)
- [x] Show proxy config (`--proxy`)
- [x] JSON output (`--json`)

### `mcp-acp config path`
- [x] Show all config paths (no flags)
- [x] Show manager path (`--manager`)
- [x] Show proxy path (`--proxy`)

### `mcp-acp config edit`
- [x] Edit manager config in $EDITOR (`--manager`)
- [x] Edit proxy config in $EDITOR (`--proxy`)

### `mcp-acp config validate`
- [x] Validate all configs (no flags)
- [x] Validate manager only (`--manager`)
- [x] Validate specific proxy (`--proxy`)
- [x] Exit code 0 on valid, 1 on invalid
- [x] Malformed config detected (invalid JSON, missing required fields, wrong types)

### `mcp-acp init`
- [x] Interactive mode (prompts for OIDC settings)
- [x] Non-interactive (`--non-interactive`, `--oidc-issuer`, `--oidc-client-id`, `--oidc-audience`, `--ui-port`)
- [x] Re-init on already-initialized config (overwrite/merge behavior)

### `mcp-acp policy show`
- [x] Display policy rules (`--proxy`)
- [x] JSON output (`--json`)

### `mcp-acp policy path`
- [x] Show policy file path (`--proxy`)

### `mcp-acp policy edit`
- [x] Edit in $EDITOR (`--proxy`)

### `mcp-acp policy add`
- [x] Interactive rule creation (`--proxy`)

### `mcp-acp policy validate`
- [x] Validate all policies (no flags)
- [x] Validate specific proxy (`--proxy`)

### `mcp-acp policy reload`
- [x] Hot reload with running proxy (`--proxy`)
- [x] Error when proxy not running

### `mcp-acp logs list`
- [x] List all log files (no flags)
- [x] List for specific proxy (`--proxy`)

### `mcp-acp logs show`
- [x] View log file (`--proxy`, `--file`)
- [x] Filtering and pagination

### `mcp-acp logs tail`
- [x] Real-time log streaming (`--proxy`, `--file`)

### `mcp-acp audit verify`
- [x] Verify all files for all proxies (no flags)
- [x] Verify specific proxy (`--proxy`)
- [x] Verify specific file type (`--file`)
- [x] Exit codes: 0 (passed), 1 (tampering), 2 (unable to verify)

### `mcp-acp audit repair`
- [x] Repair integrity state (`--proxy`, `--file`)
- [x] Skip confirmation (`--yes`)

### `mcp-acp approvals cache`
- [x] Show cached approvals (`--proxy`)
- [x] JSON output (`--json`)

### `mcp-acp approvals clear`
- [x] Clear all (`--proxy`, `--all`)
- [x] Clear specific entry (`--proxy`, `--entry`)

### `mcp-acp install mcp-json`
- [x] Generate JSON for all proxies
- [x] Generate for specific proxy (`--proxy`)
- [x] Copy to clipboard (`--copy`)
- [x] Generated JSON used in Claude Desktop — proxy connects successfully

---

## Web UI

### Proxy List Page (Dashboard)
- [x] Proxy cards display with correct status (running/inactive)
- [x] Filter chips: All, Running, Inactive
- [x] Add Proxy button opens modal
- [x] Export All copies Claude Desktop JSON to clipboard
- [x] Empty state when no proxies configured
- [x] Real-time stats update on cards

### Add Proxy Modal
- [x] Stdio proxy creation with all fields
- [x] HTTP proxy creation with URL
- [x] API key field (stored securely)
- [x] mTLS certificate fields
- [x] Attestation fields (SHA-256, SLSA, code signature)
- [x] Field validation (name format, URL format, etc.)
- [x] Advanced section toggle
- [x] Submit and cancel
- [x] Error handling (backend unreachable, invalid URL, duplicate name)

### Proxy Detail Page — Overview Tab
- [x] Transport flow diagram displays correctly
- [x] Stats section shows real-time metrics
- [x] Pending approvals section with approve/deny
- [x] Cached approvals section
- [x] Activity/recent requests section

### Proxy Detail Page — Audit Tab
- [x] Hash chain integrity status per file
- [x] Entry counts and sequence numbers
- [x] Backup file information

### Proxy Detail Page — Policy Tab
- [x] Visual editor: rule list display
- [x] Visual editor: add/edit/delete rules via form dialog
- [x] Visual editor: rule ordering and priority
- [x] Visual editor: validation error feedback
- [x] JSON editor: raw policy editing
- [x] Tab switching between visual and JSON modes

### Proxy Detail Page — Config Tab
- [x] Backend config display (transport, URL/command, timeout)
- [x] HITL settings display
- [x] Logging settings display
- [x] API key management (set/delete)
- [x] mTLS settings display (when configured)

### Proxy Detail Page — Other
- [x] Delete proxy (trash icon, confirmation dialog)
- [x] Copy MCP JSON config
- [x] Back button navigation

### Auth Page
- [x] Authentication status display (authenticated/expired/none)
- [x] Login via device flow
- [x] Logout (local)
- [x] Logout federated (Auth0)
- [x] Token info (expiration, refresh token)
- [x] User info (email, name)
- [x] OIDC config display
- [x] Manual token refresh

### Incidents Page
- [x] Timeline view of incidents
- [x] Type filter: All, Shutdowns, Startup, Emergency Audit
- [x] Proxy filter dropdown
- [x] Incident cards with severity, timestamp, details
- [x] Mark as read / unread count badge
- [x] Load more pagination

### Log Viewer (UI)
- [x] Log display with filtering
- [x] Pagination
- [x] Real-time streaming updates

### Layout / Global
- [x] Header: pending approvals button with count badge
- [x] Header: incidents link with unread badge
- [x] Connection status banner on disconnect
- [ ] Error boundary fallback UI (not manually triggered)
- [x] Toast notifications
- [x] Notification sounds (approval requests, incidents)
- [x] SSE real-time event streaming from manager to UI

---

## Cross-Cutting (CLI + UI)

### Manager-UI Coupling (from manager-ui-coupling-tests.md)
- [x] Start manager, no browser — proxy starts, no browser status logged
- [x] Open browser — `browser_status_changed` logged, UI shows proxy
- [x] Close browser tab — disconnect logged
- [x] HITL with browser open — approval dialog in web UI
- [x] HITL without browser — osascript fallback on macOS
- [x] HITL with browser closed mid-wait — times out with error
- [x] Manager disconnect during HITL — immediate osascript fallback
- [x] Manager crash recovery — proxy reconnects within ~10s
- [x] Proxy reconnects after manager restart — browser status restored

### Transport (from backend-api-key-auth-e2e-test.md)
- [x] Stdio transport — proxy spawns and communicates with backend process
- [x] HTTP transport — proxy connects to HTTP backend
- [x] API key injection — `Authorization: Bearer <token>` sent to backend
- [x] Credential stored in keychain, only `credential_key` in config
- [x] Missing credential at startup fails securely (proxy refuses to start)
- [x] mTLS — client certificates used for backend connection
- [x] Attestation — SHA-256 hash verification of backend binary
- [x] Attestation — code signature verification (macOS)

### Multi-Client
- [x] MCP Inspector and Claude Desktop connected to different proxies simultaneously

### Policy Enforcement
- [x] Policy deny blocks tool calls end-to-end
- [x] Policy allow permits tool calls
- [x] Policy hot reload takes effect without proxy restart
- [x] HITL approval flow: request pending -> approve in UI -> request proceeds
- [x] HITL denial flow: request pending -> deny in UI -> request blocked
- [x] HITL timeout: approval expires, request blocked with timeout error
- [x] Approval caching: approved request cached, subsequent identical requests auto-approved
- [x] Approval cache expiry (TTL): cached approval expires, next request triggers HITL again
- [x] Approval cache management via CLI (`approvals cache`, `approvals clear`) and UI

### Rate Limiting
- [x] Session rate tracker — rapid repeated tool calls trigger HITL approval

### Security Enforcement
- [x] Session binding violation triggers incident and shutdown
- [x] Audit integrity failure detected and reported
- [x] Emergency shutdown on security violation
- [x] Incidents page displays shutdown/audit/startup events correctly

### Audit Integrity
- [x] Clean log verification passes (exit code 0)
- [x] Full tamper cycle: tamper with log file -> `audit verify` detects it -> `audit repair` fixes it

### Authentication Flow
- [x] CLI login -> token stored -> UI shows authenticated
- [x] CLI logout -> token cleared -> UI shows not authenticated
- [x] Token expiry -> UI shows expired state
- [x] Token refresh from UI
- [x] Expired tokens rejected
- [x] Invalid tokens rejected
- [x] Revoked sessions blocked
