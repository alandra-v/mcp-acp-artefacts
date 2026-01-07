# **MCP ACP Lifecycle**

```mermaid
sequenceDiagram
participant Client as Client (e.g., Claude Desktop)
participant Proxy as Proxy
participant Backend as Backend MCP Server
participant Logs as Telemetry

rect rgb(200, 220, 255)
note over Client,Logs: Initialization Phase

Proxy->>Proxy: Load AppConfig & PolicyConfig
Proxy->>Logs: Validate logs writable (fail if not)

alt transport = None (auto-detect)
alt Both HTTP and STDIO configured
Proxy->>Backend: HTTP health check
alt HTTP reachable
Proxy->>Proxy: Select HTTP transport
else HTTP unreachable
Proxy->>Proxy: Fall back to STDIO transport
end
else HTTP only configured
Proxy->>Backend: HTTP health check (must succeed)
Proxy->>Proxy: Select HTTP transport
else STDIO only configured
Proxy->>Proxy: Select STDIO transport
end
end

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
Proxy->>Proxy: Policy enforcement & HITL (see Operation Phase diagram)
Proxy->>Backend: MCP Request (if allowed)
Backend-->>Proxy: MCP Response
Proxy->>Logs: Log operation & decision
Proxy-->>Client: MCP Response (stdio)
end

rect rgb(255, 220, 200)
note over Client,Logs: Shutdown Phase

alt Normal Shutdown
Client->>Proxy: close connection
Proxy->>Backend: close connection
Backend-->>Proxy: exit
Proxy-->>Client: exit
else Audit Integrity Failure
Proxy->>Logs: Log critical event (best effort)
Proxy->>Proxy: Write .last_crash breadcrumb
Proxy-->>Client: MCP Error
Proxy->>Proxy: os._exit(10) - fail-closed
end
end
```

# **MCP ACP Operation Phase**

```mermaid
sequenceDiagram
participant Client as Client
participant CTX as ContextMiddleware
participant AUD as AuditMiddleware
participant PEP as PolicyEnforcementMiddleware
participant PDP as Policy Engine
participant HITL as HITL Dialog
participant Backend as Backend
participant Logs as Telemetry

Client->>CTX: MCP Request

rect rgb(230, 240, 255)
note over CTX,AUD: Context Setup
CTX->>CTX: Set request_id, session_id
CTX->>CTX: Extract tool_name, arguments (if tools/call)
CTX->>AUD: Forward request
AUD->>AUD: Extract client ID
end

AUD->>PEP: Forward request

rect rgb(255, 245, 220)
note over PEP,PDP: Policy Evaluation

PEP->>PDP: Build DecisionContext (subject, action, resource, environment)

alt Built-in Protected Path (config/logs dir)
PDP-->>PEP: DENY (cannot override)
PEP->>Logs: Log decision
PEP-->>Client: MCP Error (-32001 PermissionDenied)
else Discovery Method (initialize, tools/list, resources/list, etc.)
PDP-->>PEP: ALLOW (bypass policy)
PEP->>Backend: Forward request
else Policy Rule Evaluation
PDP->>PDP: Match rules (AND logic), Combine (HITL > DENY > ALLOW)
PDP-->>PEP: Decision (ALLOW/DENY/HITL)
end
end

rect rgb(220, 255, 220)
note over PEP,Backend: Decision Execution

alt ALLOW
PEP->>Logs: Log decision
PEP->>Backend: Forward request
Backend-->>PEP: MCP Response
else DENY
PEP->>Logs: Log decision
PEP-->>Client: MCP Error (-32001 PermissionDenied)
else HITL
rect rgb(255, 230, 230)
note over PEP,HITL: Human-in-the-Loop Approval
PEP->>HITL: Show approval dialog (tool, path, rule, effects, user)

alt User clicks Allow
HITL-->>PEP: USER_ALLOWED
PEP->>Logs: Log decision (HITL + USER_ALLOWED)
PEP->>Backend: Forward request
Backend-->>PEP: MCP Response
else User clicks Deny
HITL-->>PEP: USER_DENIED
PEP->>Logs: Log decision (HITL + USER_DENIED)
PEP-->>Client: MCP Error (-32001 PermissionDenied)
else Timeout (configurable, default 30s)
HITL-->>PEP: TIMEOUT
PEP->>Logs: Log decision (HITL + TIMEOUT)
PEP-->>Client: MCP Error (-32001 PermissionDenied)
end
end
end
end

rect rgb(240, 240, 255)
note over AUD,Logs: Response & Cleanup

PEP-->>AUD: MCP Response
AUD->>Logs: Log operation (operations.jsonl)
AUD-->>CTX: Forward response
CTX->>CTX: Clear request_id, session_id, tool_context
CTX-->>Client: MCP Response
end

```
