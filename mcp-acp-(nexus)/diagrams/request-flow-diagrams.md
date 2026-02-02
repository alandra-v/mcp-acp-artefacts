# MCP ACP Lifecycle

```mermaid
sequenceDiagram
    participant Client as Client (Claude Desktop)
    participant Proxy as Proxy
    participant Backend as Backend MCP Server
    participant Logs as Telemetry
    participant Keychain as OS Keychain

    rect rgb(200, 220, 255)
    note over Client,Keychain: Startup Validation

    Proxy->>Proxy: Load AppConfig & PolicyConfig
    Proxy->>Logs: Verify all audit logs writable<br/>(operations, decisions, auth, system, config_history, policy_history)
    alt Any log not writable
        Proxy->>Proxy: Raise AuditFailure (exit 10)
    end

    Proxy->>Proxy: Create IntegrityStateManager (hash chains)
    Proxy->>Logs: Verify hash chain integrity on startup
    alt Hash chain verification failed
        Proxy->>Proxy: Raise AuditFailure (exit 10)
    end

    Proxy->>Proxy: Device health check (FileVault, SIP)
    alt Device unhealthy
        Proxy->>Proxy: Raise DeviceHealthError (exit 14)
    end

    note right of Proxy: All startup failures are logged to<br/>bootstrap.jsonl by the CLI layer (start.py)
    end

    rect rgb(210, 230, 255)
    note over Client,Keychain: Security Infrastructure

    Proxy->>Proxy: Create ShutdownCoordinator
    Proxy->>Proxy: Create AuditHealthMonitor (30s interval)
    Proxy->>Proxy: Create DeviceHealthMonitor (5min interval)
    Proxy->>Logs: Create AuthLogger (auth.jsonl with hash chain)
    Proxy->>Proxy: Wire AuthLogger to ShutdownCoordinator
    end

    rect rgb(220, 235, 255)
    note over Proxy,Backend: Backend Connection

    Proxy->>Backend: Create backend transport (STDIO or Streamable HTTP)
    Proxy->>Proxy: Create FastMCP.as_proxy(backend_client)
    Proxy->>Proxy: Create SessionManager
    Proxy->>Proxy: Create SessionRateTracker (30 calls/tool/60s)
    end

    rect rgb(230, 240, 255)
    note over Proxy,Keychain: Identity Provider

    Proxy->>Proxy: Create OIDCIdentityProvider (config check only)
    note right of Proxy: Zero Trust: raises AuthenticationError<br/>if auth not configured (no fallback).<br/>Token loaded later in lifespan.
    end

    rect rgb(235, 245, 255)
    note over Client,Keychain: Middleware Chain

    Proxy->>Proxy: Register DoS RateLimitingMiddleware (outermost, 10 req/s, 50 burst)
    Proxy->>Proxy: Register ContextMiddleware (request_id, session_id, tool_context)
    Proxy->>Proxy: Register AuditLoggingMiddleware (operations.jsonl)
    Proxy->>Proxy: Register PolicyEnforcementMiddleware (innermost)

    Proxy->>Proxy: Create ProxyState (aggregates all state for UI)
    Proxy->>Proxy: Wire ProxyState to HITL handler, ShutdownCoordinator, IdentityProvider
    end

    rect rgb(210, 235, 255)
    note over Client,Logs: Lifespan Start (proxy_lifespan)

    Proxy->>Proxy: Start AuditHealthMonitor
    Proxy->>Proxy: Start DeviceHealthMonitor

    rect rgb(220, 240, 255)
    note over Proxy,Keychain: Identity Validation
    Proxy->>Keychain: get_identity() loads token
    Keychain-->>Proxy: JWT (access + refresh token)
    Proxy->>Proxy: Validate token (signature, expiry, claims)
    alt Token expired
        Proxy->>Keychain: Refresh token automatically
        alt Refresh failed
            Proxy->>Logs: Log session_ended (auth_expired)
            Proxy->>Proxy: Raise AuthenticationError (exit 13)
        end
    end
    alt No token found
        Proxy->>Logs: Log session_ended (auth_expired)
        Proxy->>Proxy: Raise AuthenticationError (exit 13)
    end
    end

    Proxy->>Proxy: Create user-bound session (<user_id>:<uuid>)
    Proxy->>Logs: Log session_started (auth.jsonl)
    Proxy->>Proxy: Store bound_user_id for session binding validation

    rect rgb(225, 240, 250)
    note over Proxy: Server Setup
    Proxy->>Proxy: Start UDS server (proxy_{name}.sock, permissions 0600, always)

    alt enable_ui = true
        Proxy->>Proxy: ensure_manager_running()
        alt Manager already running
            Proxy->>Proxy: Skip HTTP server (manager serves UI on :8765)
        else Manager not running
            Proxy->>Proxy: Generate API token (32 bytes hex)
            Proxy->>Proxy: Start HTTP server on :8765 with SecurityMiddleware
        end
    end

    Proxy->>Proxy: Wire shared state to API apps
    end

    alt enable_ui = true
        Proxy->>Proxy: Register with manager (event forwarding, token updates, HITL disconnect fallback)
    end

    Proxy->>Proxy: Setup SIGHUP handler (policy hot reload)

    par Background Monitors Running
        Note over Proxy: AuditHealthMonitor checks every 30s
        Note over Proxy: DeviceHealthMonitor checks every 5min
    end
    end

    rect rgb(200, 240, 220)
    note over Client,Logs: MCP Session Handshake

    Client->>Proxy: initialize (stdio)
    Proxy->>Backend: initialize (selected transport)
    Backend-->>Proxy: InitializeResult (serverInfo, capabilities)
    Proxy->>Proxy: Cache client name for session
    Proxy-->>Client: InitializeResult (serverInfo, capabilities)
    Proxy->>Logs: Log initialization metadata

    Client->>Proxy: notifications/initialized
    Proxy->>Backend: notifications/initialized
    end

    rect rgb(200, 255, 220)
    note over Client,Logs: Operation Phase

    Client->>Proxy: MCP Request (stdio)
    Proxy->>Proxy: Middleware chain (see Operation Phase diagram)
    Proxy->>Backend: MCP Request (if allowed)
    Backend-->>Proxy: MCP Response
    Proxy->>Logs: Log operation & decision
    Proxy-->>Client: MCP Response (stdio)
    end

    rect rgb(255, 220, 200)
    note over Client,Keychain: Shutdown Phase

    alt Normal Shutdown
        Client->>Proxy: close connection
        Proxy->>Proxy: Remove SIGHUP handler
        Proxy->>Proxy: Stop UDS + HTTP servers
        Proxy->>Proxy: Disconnect from manager
        Proxy->>Proxy: Stop DeviceHealthMonitor
        Proxy->>Proxy: Stop AuditHealthMonitor
        Proxy->>Logs: Log session_ended (end_reason: normal)
        Proxy->>Proxy: Invalidate bound session
        Proxy->>Proxy: Clear rate tracking data
    else Audit Integrity Failure
        Proxy->>Proxy: Set _shutdown_in_progress (reject new requests)
        Proxy->>Logs: Write shutdowns.jsonl, system.jsonl (best effort)
        Proxy->>Proxy: Write .last_crash breadcrumb
        Proxy->>Logs: Log session_ended (best effort)
        Proxy->>Proxy: Show popup OR emit SSE critical_shutdown event
        Proxy-->>Client: MCP Error (100ms flush delay)
        Proxy->>Proxy: os._exit(10)
    else Device Health Failure
        Proxy->>Logs: Log device_health_failed
        Proxy->>Logs: Log session_ended (device_posture)
        Proxy->>Proxy: Trigger graceful shutdown via ShutdownCoordinator
    else Session Binding Violation
        Proxy->>Logs: Log session_ended (session_binding_violation)
        Proxy->>Proxy: Write .last_crash breadcrumb
        Proxy->>Proxy: os._exit(15)
    else Authentication Failure During Session
        Proxy->>Logs: Log session_ended (auth_expired)
        Proxy->>Proxy: Raise AuthenticationError (exit 13)
    end
    end
```

# MCP ACP Operation Phase

```mermaid
sequenceDiagram
    participant Client as Client
    participant DOS as DoS Rate Limiter
    participant CTX as Context
    participant AUD as Audit
    participant PEP as Enforcement
    participant PDP as Policy Engine
    participant HITL as HITL Handler
    participant Backend as Backend
    participant Logs as Telemetry

    Client->>DOS: MCP Request

    rect rgb(255, 240, 240)
    note over DOS: DoS Protection (outermost)
    DOS->>DOS: Token bucket check (10 req/s, 50 burst)
    alt Rate exceeded
        DOS-->>Client: MCP Error (rate limited)
    else OK
        DOS->>CTX: Forward request
    end
    end

    rect rgb(230, 240, 255)
    note over CTX: Context Setup
    CTX->>CTX: Set request_id, session_id from FastMCP context
    CTX->>CTX: Extract tool_name, arguments (if tools/call)
    CTX->>AUD: Forward request
    end

    rect rgb(240, 248, 255)
    note over AUD: Audit Middleware
    AUD->>AUD: Check shutdown_coordinator (reject if shutting down)
    AUD->>AUD: Get identity from provider
    AUD->>AUD: Extract client_id from initialize (cached)
    AUD->>PEP: Forward request
    end

    rect rgb(255, 245, 220)
    note over PEP,PDP: Policy Enforcement (innermost)

    PEP->>PEP: Extract client info from initialize (cached)

    rect rgb(255, 240, 230)
    note over PEP: Session Rate Check (tools/call only, before policy)
    alt method == tools/call AND rate exceeded (30 calls/tool/60s)
        PEP->>HITL: Trigger rate breach HITL (will_cache=false, never cached)
        alt User approves
            HITL-->>PEP: Approved
            PEP->>PEP: Reset rate counter for tool
            PEP->>Logs: Log rate override (decisions.jsonl)
            note right of PEP: Continues to policy evaluation below
        else User denies or timeout
            HITL-->>PEP: Denied / Timeout
            PEP-->>Client: MCP Error (-32001 PermissionDenied)
        end
    end
    end

    PEP->>PEP: Build DecisionContext (Subject, Action, Resource, Environment)
    note right of PEP: Includes session binding validation
    alt Session binding violation
        PEP->>PEP: Trigger shutdown via on_critical_failure
        PEP-->>Client: SessionBindingViolationError (exit 15)
    else Authentication failed
        PEP-->>Client: MCP Error (-32001 PermissionDenied)
    end

    PEP->>PDP: Evaluate policy
    PDP->>PDP: Check protected paths (config/log dirs)
    PDP->>PDP: Check discovery bypass (tools/list, resources/list, etc.)
    PDP->>PDP: Match rules by specificity scoring
    PDP->>PDP: Combine decisions: HITL > DENY > ALLOW
    PDP-->>PEP: Decision (ALLOW / DENY / HITL)
    PEP->>PEP: Get matched_rules + final_rule (for logging)
    end

    rect rgb(220, 255, 220)
    note over PEP,Backend: Decision Execution

    alt ALLOW
        PEP->>Logs: Log decision (decisions.jsonl)
        PEP->>Backend: Forward request
        alt Backend error
            Backend-->>PEP: Error (timeout/refused/TLS/disconnected)
            PEP->>PEP: Emit SSE backend error event
            PEP-->>Client: MCP Error (backend error)
        else Backend success
            Backend-->>PEP: MCP Response
            alt method == tools/list
                PEP->>PEP: Sanitize tool descriptions (prompt injection protection)
            end
        end
    else DENY
        PEP->>Logs: Log decision (decisions.jsonl)
        PEP-->>Client: MCP Error (-32001 PermissionDenied)
    else HITL
        rect rgb(255, 230, 230)
        note over PEP,HITL: Human-in-the-Loop Approval
        PEP->>PEP: Determine will_cache (per-rule cache_side_effects)
        PEP->>PEP: Check approval cache
        alt Cached approval exists
            PEP->>Logs: Log decision (cache_hit, hitl_ms=0)
            PEP->>Backend: Forward request
        else No cached approval
            PEP->>HITL: Request approval
            note right of HITL: Routing (fallback chain):<br/>1. Web UI if SSE subscriber connected<br/>2. osascript dialog if macOS<br/>3. Auto-deny otherwise
            alt USER_ALLOWED
                HITL-->>PEP: USER_ALLOWED
                PEP->>PEP: Cache approval (keyed by subject_id, tool, path)
                PEP->>Logs: Log decision (decisions.jsonl)
                PEP->>Backend: Forward request
                Backend-->>PEP: MCP Response
            else USER_ALLOWED_ONCE
                HITL-->>PEP: USER_ALLOWED_ONCE
                PEP->>Logs: Log decision (decisions.jsonl)
                PEP->>Backend: Forward request
                Backend-->>PEP: MCP Response
            else USER_DENIED or TIMEOUT (60s default)
                HITL-->>PEP: USER_DENIED / TIMEOUT
                PEP->>Logs: Log decision (decisions.jsonl)
                PEP-->>Client: MCP Error (-32001 PermissionDenied)
            end
        end
        end
    end
    end

    rect rgb(235, 245, 255)
    note over AUD,Logs: Audit Logging (finally block)
    AUD->>AUD: Create OperationEvent
    AUD->>Logs: Log operation (operations.jsonl)
    note right of Logs: Fallback chain if primary log fails:<br/>operations.jsonl → system.jsonl → emergency_audit.jsonl<br/>Then triggers fail-closed shutdown
    AUD-->>CTX: Forward response
    end

    rect rgb(230, 240, 255)
    note over CTX: Context Cleanup (finally block)
    CTX->>CTX: clear_all_context(request_id)
    CTX-->>DOS: Forward response
    end

    DOS-->>Client: MCP Response
```

# CLI / Web UI / API Communication

```mermaid
sequenceDiagram
    participant CLI as CLI
    participant ProxyUDS as Proxy UDS<br/>(per-proxy .sock)
    participant Manager as Manager<br/>(:8765 HTTP + manager.sock NDJSON)
    participant Browser as Browser

    rect rgb(220, 240, 255)
    note over CLI,ProxyUDS: CLI Communication (always direct to Proxy UDS)

    CLI->>CLI: Check per-proxy socket exists
    alt Socket missing
        CLI-->>CLI: "Proxy not running" error
    else Socket exists
        CLI->>ProxyUDS: HTTP-over-UDS request
        note right of ProxyUDS: Auth: OS file permissions (socket 0600)<br/>No token/host/origin validation<br/>Request size limit only (1MB)
        ProxyUDS-->>CLI: JSON response
    end
    note over CLI,ProxyUDS: CLI never goes through manager.
    end

    rect rgb(230, 245, 230)
    note over Manager,Browser: Web UI (Manager serves all UI on :8765)

    note over Manager: Manager auto-starts on first proxy startup.<br/>Headless mode (--headless): no manager, no UI, HITL via osascript only.

    Browser->>Manager: GET / (initial page load)
    Manager-->>Browser: HTML + API token
    note right of Browser: Production: HttpOnly cookie<br/>Dev mode: window.__API_TOKEN__

    Browser->>Manager: API request + token
    Manager->>Manager: SecurityMiddleware<br/>(size, host, origin, token, security headers)

    alt Manager-level routes (handled directly)
        note right of Manager: /api/manager/* (status, auth, proxies,<br/>policy, config, logs, audit, incidents)<br/>/api/events (manager SSE stream)
        Manager-->>Browser: JSON response
    else Proxy-specific routes (forwarded to proxy UDS)
        note right of Manager: /api/proxy/{name}/* → proxy UDS<br/>/api/* fallback → default proxy UDS<br/>(when only one proxy exists)
        Manager->>ProxyUDS: Forward request (strips auth headers, UDS uses OS auth)
        ProxyUDS-->>Manager: JSON response
        Manager-->>Browser: JSON response
    end
    end

    rect rgb(235, 240, 255)
    note over ProxyUDS,Manager: Proxy Registration (NDJSON over manager.sock)

    note over ProxyUDS,Manager: Each proxy connects to manager.sock on startup.<br/>Raw NDJSON protocol (not HTTP).

    ProxyUDS->>Manager: Register (proxy_id, proxy_name, instance_id, socket_path, config_summary)
    Manager-->>ProxyUDS: Ack (registered)
    Manager-->>ProxyUDS: UI status (browser_connected, subscriber_count)
    Manager-->>ProxyUDS: Token update (if OIDC token exists)

    loop Ongoing
        ProxyUDS->>Manager: Forward SSE events (pending, backend, auth, etc.)
        Manager->>ProxyUDS: Token updates (auth login/logout from browser)
        Manager->>ProxyUDS: UI status updates (browser_connected, subscriber_count)
        Manager->>ProxyUDS: Heartbeat (every 30s)
    end
    end

    rect rgb(220, 255, 220)
    note over ProxyUDS: Proxy Shared State (wired to UDS app)
    note over ProxyUDS: ProxyState (SSE broadcasting, stats)<br/>ApprovalStore (HITL approval cache)<br/>PolicyReloader (SIGHUP hot reload)<br/>IdentityProvider (OIDC token management)<br/>AppConfig (proxy configuration)
    end
```

# SSE Event Flow

```mermaid
sequenceDiagram
    participant Browser as Browser
    participant MgrHTTP as Manager HTTP<br/>(:8765)
    participant Registry as Manager Registry
    participant MgrClient as ManagerClient<br/>(in proxy)
    participant State as ProxyState
    participant PEP as Event Sources<br/>(PEP, HITL, backend)

    rect rgb(230, 245, 255)
    note over Browser,Registry: Browser Connection (via Manager)

    Browser->>MgrHTTP: GET /api/events
    MgrHTTP-->>Browser: EventSourceResponse (text/event-stream)

    note over MgrHTTP,Browser: Wire format: data: {"type": "...", ...}\n\n<br/>Type inside JSON, no event: line

    loop Initial snapshots (per registered proxy)
        MgrHTTP->>State: Fetch via proxy UDS (HTTP-over-UDS)
        State-->>MgrHTTP: pending, cached, stats
        MgrHTTP->>Browser: snapshot (approvals, proxy_name, proxy_id)
        MgrHTTP->>Browser: cached_snapshot (approvals, ttl_seconds, count, proxy_name, proxy_id)
        MgrHTTP->>Browser: stats_updated (stats, proxy_id)
    end

    MgrHTTP->>Registry: subscribe_sse()
    Registry->>Registry: Create asyncio.Queue (unbounded)
    Registry->>Registry: broadcast_ui_status() to all proxies
    end

    rect rgb(255, 245, 220)
    note over PEP,Browser: Event Broadcasting

    PEP->>State: emit_system_event() / create_pending()
    State->>State: _broadcast_event()

    note right of State: Proxy-local subscribers:<br/>put_nowait (maxsize=100).<br/>If full, new event skipped.

    State->>MgrClient: push_event() (fire-and-forget)
    MgrClient->>Registry: NDJSON: {type: event, event_type, data}
    Registry->>Registry: Enrich with proxy_name, proxy_id
    Registry->>Registry: Put in all subscriber queues
    Registry-->>MgrHTTP: Yield from queue
    MgrHTTP-->>Browser: data: {type, proxy_name, ...}

    note over State,MgrClient: Event domains (see events.py for full list):<br/>Pending (5): created, resolved, timeout, ...<br/>Backend (5): connected, disconnected, timeout, ...<br/>TLS (3): tls_error, mtls_failed, cert_validation_failed<br/>Auth (6): login, logout, token_refresh_failed, ...<br/>Policy (5): reloaded, rollback, config_change_detected, ...<br/>Rate (3): triggered, approved, denied<br/>Cache (3): cleared, entry_deleted, cached_snapshot<br/>Request (3): error, hitl_parse_failed, tool_sanitization_failed<br/>Lifecycle (1): proxy_deleted<br/>Stats (3): stats_updated, new_log_entries, incidents_updated<br/>Critical (9): shutdown, audit_*, session_hijacking, ...

    par Keep-alive
        loop Every 30 seconds
            MgrHTTP-->>Browser: : keepalive
            note right of Browser: SSE comment (colon prefix)
        end
    end
    end

    rect rgb(230, 245, 230)
    note over State,MgrClient: UI Connectivity (drives HITL routing)

    note over State: is_ui_connected =<br/>local subscribers > 0<br/>OR MgrClient.browser_connected

    note over MgrClient,Registry: Manager sends ui_status on<br/>every subscribe/unsubscribe

    note over State: When is_ui_connected = False:<br/>HITL falls back to osascript (macOS)
    end

    rect rgb(255, 230, 230)
    note over Browser,Registry: Browser Disconnect

    Browser->>MgrHTTP: Connection closed
    MgrHTTP->>Registry: unsubscribe_sse(queue)
    Registry->>Registry: Remove queue, broadcast_ui_status()
    end
```
