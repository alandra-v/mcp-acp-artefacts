# Architecture Diagrams

Backend and infrastructure diagrams. For UI-specific diagrams, see [ui_diagrams.md](ui_diagrams.md).

---

## Socket Location (macOS)

```
Platform Directory Structure:

macOS:
├── Config:    ~/Library/Application Support/mcp-acp-extended/
│              └── mcp_acp_extended_config.json
├── Data:      ~/Library/Application Support/mcp-acp-extended/
│              └── logs/
├── Cache:     ~/Library/Caches/mcp-acp-extended/
└── Runtime:   ~/Library/Caches/TemporaryItems/mcp-acp-extended/
               └── api.sock  ◀── UDS socket (cleaned on reboot)

Linux (future):
├── Config:    ~/.config/mcp-acp-extended/
├── Data:      ~/.local/share/mcp-acp-extended/
├── Cache:     ~/.cache/mcp-acp-extended/
└── Runtime:   $XDG_RUNTIME_DIR/mcp-acp-extended/
               └── api.sock
```

---

## Fail-Closed Shutdown Flow

When a critical security failure occurs, the ShutdownCoordinator ensures orderly termination:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         FAILURE SOURCES                                   │
│                                                                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │
│  │AuditHealthMonitor│  │DeviceHealthMonitor│  │FailClosedHandler│          │
│  │ (30s interval)  │  │ (5min interval) │  │ (on write fail) │          │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘          │
│           │                    │                    │                    │
│           │  audit missing/    │  FileVault/SIP    │  log write         │
│           │  tampered          │  disabled          │  failed            │
│           │                    │                    │                    │
│           └────────────────────┴────────────────────┘                    │
│                                │                                          │
│                                ▼                                          │
│                    ┌───────────────────────┐                             │
│                    │  ShutdownCoordinator  │                             │
│                    │  initiate_shutdown()  │                             │
│                    └───────────┬───────────┘                             │
└────────────────────────────────┼─────────────────────────────────────────┘
                                 │
                                 ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                       SHUTDOWN SEQUENCE                                   │
│                                                                          │
│  1. Set _shutdown_in_progress = True  (reject new requests)              │
│                    │                                                      │
│                    ▼                                                      │
│  2. Write to shutdowns.jsonl  (for incidents page)                       │
│                    │                                                      │
│                    ▼                                                      │
│  3. Write to system.jsonl  (system event log)                            │
│                    │                                                      │
│                    ▼                                                      │
│  4. Write .last_crash breadcrumb  (for operator)                         │
│                    │                                                      │
│                    ▼                                                      │
│  5. Log session_ended to auth.jsonl  (audit trail)                       │
│                    │                                                      │
│                    ▼                                                      │
│  6. Print to stderr  (process output)                                    │
│                    │                                                      │
│                    ▼                                                      │
│  7. Show popup to user  (macOS osascript)                                │
│                    │                                                      │
│                    ▼                                                      │
│  8. Emit critical_shutdown SSE event  (notify UI)                        │
│                    │                                                      │
│                    ▼                                                      │
│  9. Schedule os._exit() after 100ms  (flush response to client)          │
│                    │                                                      │
│                    ▼                                                      │
│  10. Return control to caller  (raises MCP error)                        │
│                    │                                                      │
│                    ▼                                                      │
│  11. os._exit(exit_code)  (terminates process)                           │
│                                                                          │
│      Exit codes: 10=audit, 11=policy (reserved), 12=identity (reserved), │
│                  13=auth, 14=device_health, 15=session_binding           │
└──────────────────────────────────────────────────────────────────────────┘
```
