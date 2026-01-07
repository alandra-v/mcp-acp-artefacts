# Implementation Diagrams

## 1. Request Flow (Middleware Stack)

```
┌─────────────────────────────────────────────────────────────────┐
│                        MCP Client                               │
│                   (Claude Desktop / Inspector)                  │
└─────────────────────────────┬───────────────────────────────────┘
                              │ STDIO
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      mcp-acp-core Proxy                         │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ ContextMiddleware                                         │  │
│  │  • Sets request_id, session_id                            │  │
│  │  • Extracts tool_context for tools/call                   │  │
│  │  • Clears all context in finally block                    │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │ AuditLoggingMiddleware                              │  │  │
│  │  │  • Logs to operations.jsonl                         │  │  │
│  │  │  • Captures: method, status, duration, tool_name    │  │  │
│  │  │  • Sees ALL requests (including denied)             │  │  │
│  │  │  ┌───────────────────────────────────────────────┐  │  │  │
│  │  │  │ ClientLoggingMiddleware                       │  │  │  │
│  │  │  │  • Debug wire logs (client_wire.jsonl)        │  │  │  │
│  │  │  │  • Only when log_level=DEBUG                  │  │  │  │
│  │  │  │  ┌─────────────────────────────────────────┐  │  │  │  │
│  │  │  │  │ PolicyEnforcementMiddleware             │  │  │  │  │
│  │  │  │  │  • Builds DecisionContext               │  │  │  │  │
│  │  │  │  │  • Calls PolicyEngine.evaluate()        │  │  │  │  │
│  │  │  │  │  • ALLOW → forward to backend           │  │  │  │  │
│  │  │  │  │  • DENY → return error                  │  │  │  │  │
│  │  │  │  │  • HITL → show dialog, then decide      │  │  │  │  │
│  │  │  │  │  • Logs to decisions.jsonl              │  │  │  │  │
│  │  │  │  └────────────────┬────────────────────────┘  │  │  │  │
│  │  │  └───────────────────┼───────────────────────────┘  │  │  │
│  │  └──────────────────────┼──────────────────────────────┘  │  │
│  └─────────────────────────┼─────────────────────────────────┘  │
└────────────────────────────┼────────────────────────────────────┘
                             │ STDIO or HTTP
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Backend MCP Server                         │
│                    (filesystem-mcp-server)                      │
└─────────────────────────────────────────────────────────────────┘
```

## 2. Policy Evaluation Flow (PDP)

```
                    ┌──────────────────┐
                    │  MCP Request     │
                    │  (tools/call)    │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │ Build Decision   │
                    │ Context (ABAC)   │
                    │ • Subject (user) │
                    │ • Action (method)│
                    │ • Resource (path)│
                    │ • Environment    │
                    └────────┬─────────┘
                             │
                             ▼
               ┌─────────────────────────────┐
               │  Is discovery method?       │
               │  (tools/list, prompts/list) │
               └─────────────┬───────────────┘
                             │
              ┌──────────────┴──────────────┐
              │ YES                         │ NO
              ▼                             ▼
     ┌─────────────┐              ┌──────────────────┐
     │   ALLOW     │              │ Collect ALL      │
     │  (bypass)   │              │ matching rules   │
     └─────────────┘              └────────┬─────────┘
                                           │
                                           ▼
                                  ┌──────────────────┐
                                  │ Apply combining  │
                                  │ algorithm        │
                                  └────────┬─────────┘
                                           │
              ┌────────────────────────────┼────────────────────────────┐
              │                            │                            │
              ▼                            ▼                            ▼
     ┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
     │ Any HITL match? │   NO    │ Any DENY match? │   NO    │ Any ALLOW match?│
     │                 │────────▶│                 │────────▶│                 │
     └────────┬────────┘         └────────┬────────┘         └────────┬────────┘
              │ YES                       │ YES                       │
              ▼                           ▼                           ▼
     ┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
     │     HITL        │         │     DENY        │         │ YES: ALLOW      │
     │ (human decides) │         │                 │         │ NO: default_deny│
     └─────────────────┘         └─────────────────┘         └─────────────────┘

                         Priority: HITL > DENY > ALLOW
```

## 3. Audit Fallback Chain

```
┌─────────────────────────────────────────────────────────────────┐
│                    Audit Event to Log                           │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │ Primary Handler  │
                    │ (operations.jsonl│
                    │  or decisions.   │
                    │  jsonl)          │
                    └────────┬─────────┘
                             │
                    ┌────────┴────────┐
                    │ Write succeeds? │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │ YES                         │ NO (file deleted/replaced)
              ▼                             ▼
     ┌─────────────────┐         ┌──────────────────────┐
     │    Success      │         │ Check inode/device   │
     │                 │         │ Detect: deletion,    │
     └─────────────────┘         │ replacement, moved   │
                                 └──────────┬───────────┘
                                            │
                                            ▼
                                 ┌──────────────────────┐
                                 │ Fallback 1:          │
                                 │ system.jsonl         │
                                 └──────────┬───────────┘
                                            │
                                 ┌──────────┴───────────┐
                                 │ Write succeeds?      │
                                 └──────────┬───────────┘
                                            │
                          ┌─────────────────┴─────────────────┐
                          │ YES                               │ NO
                          ▼                                   ▼
                 ┌─────────────────┐              ┌──────────────────────┐
                 │ Log warning,    │              │ Fallback 2:          │
                 │ continue to     │              │ emergency_audit.jsonl│
                 │ shutdown        │              │ (config directory)   │
                 └────────┬────────┘              └──────────┬───────────┘
                          │                                  │
                          ▼                                  ▼
                 ┌─────────────────────────────────────────────────────┐
                 │                  SHUTDOWN                           │
                 │  • Write .last_crash breadcrumb (all missing files) │
                 │  • Spawn background thread (500ms delay)            │
                 │  • Return error to client (-32603)                  │
                 │  • os._exit(10)                                     │
                 └─────────────────────────────────────────────────────┘
```

## 4. Log File Structure

```
~/.mcp-acp-core/
└── mcp_acp_core_logs/
    ├── audit/                          # Security audit (always enabled)
    │   ├── operations.jsonl            # One event per MCP operation
    │   └── decisions.jsonl             # Policy evaluation results
    │
    ├── debug/                          # Wire-level logs (log_level=DEBUG)
    │   ├── client_wire.jsonl           # Client ↔ Proxy (request+response)
    │   └── backend_wire.jsonl          # Proxy ↔ Backend (request+response)
    │
    ├── system/                         # Operational events
    │   ├── system.jsonl                # Startup, errors, disconnects
    │   ├── config_history.jsonl        # Config changes with versions
    │   └── policy_history.jsonl        # Policy changes with versions
    │
    └── .last_crash                     # Breadcrumb after audit failure

~/Library/Application Support/mcp-acp-core/   # Config directory
    ├── mcp_acp_core_config.json        # Operational configuration
    ├── policy.json                     # Security policies
    └── emergency_audit.jsonl           # Last-resort audit fallback
```

## 5. Implementation Timeline

```
Phase 1                Phase 2                Phase 3                Phase 4
Foundation             Logging                Config & CLI           Audit & HTTP
─────────────────────────────────────────────────────────────────────────────────▶
Commits 1-5            Commits 6-14           Commits 15-26          Commits 27-41

• pyproject.toml       • client_wire.jsonl    • Pydantic models      • operations.jsonl
• FastMCP proxy        • backend_wire.jsonl   • Click CLI            • HTTP transport
• STDIO transport      • correlation IDs      • init/start/config    • First unit tests
                       • system logger        • config history

     ╔════════════════════════════════════════════════════════════════════╗
     ║  PIVOT: Telemetry expanded from 2 files to full audit structure   ║
     ╚════════════════════════════════════════════════════════════════════╝

Phase 5                Phase 6                Phase 7
Identity & Policy      PEP & HITL             Hardening
─────────────────────────────────────────────────────────────────────────────────▶
Commits 42-52          Commits 53-59          Commits 60-81

• ABAC context         • Enforcement MW       • Fail-closed audit
• Policy engine        • macOS dialogs        • Inode verification
• HITL>DENY>ALLOW      • decisions.jsonl      • Documentation

     ╔═══════════════════════════╗    ╔═══════════════════════════════════╗
     ║ PIVOT: First-match-wins   ║    ║ PIVOT: stdin → osascript dialogs ║
     ║ → combining algorithm     ║    ║ (no terminal from Claude Desktop)║
     ╚═══════════════════════════╝    ╚═══════════════════════════════════╝
```

## 6. ABAC Decision Context Structure

```
DecisionContext
├── subject: Subject
│   ├── id: "<username>"                    # From getpass.getuser()
│   └── provenance: PROXY_CONFIG         # Trust source
│
├── action: Action
│   ├── mcp_method: "tools/call"
│   ├── name: "write_file"
│   └── is_mutating: true                # All tools/call = mutating
│
├── resource: Resource
│   ├── type: "tool"
│   ├── tool: ToolInfo
│   │   ├── name: "write_file"
│   │   ├── path: "<path-to-file>/file.txt"
│   │   ├── extension: ".txt"
│   │   └── side_effects: ["filesystem_write"]
│   └── server: ServerInfo
│       └── backend_id: "filesystem-server"
│
└── environment: Environment
    ├── timestamp: "2025-12-23T19:20:22Z"
    ├── request_id: "abc123"
    ├── session_id: "sess456"
    └── mcp_client_name: "claude-desktop"
```

## 7. HITL Dialog (macOS)

```
┌─────────────────────────────────────────────────────────────┐
│  ⚠️  MCP-ACP-Core: Approval Required                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Tool: write_file                                           │
│  Path:<test-workspace>/tmp-dir/test.txt             │
│  Rule: hitl-write-project                                   │
│  Effects: filesystem_write                                  │
│  User: <username>                                              │
│                                                             │
│  Auto-deny in 30s                                           │
│  [Return] Allow  •  [Esc] Deny                              │
│                                                             │
│                              ┌─────────┐    ┌─────────┐     │
│                              │  Deny   │    │  Allow  │     │
│                              └─────────┘    └─────────┘     │
└─────────────────────────────────────────────────────────────┘
```
