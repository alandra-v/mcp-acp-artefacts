# MCP-ACP Artefacts Repository

This repository contains non-code artefacts (test evidence, logs, reports, and supporting documentation) for the **mcp-acp** project.

**Source repositories:**
- Stage 1: https://github.com/alandra-v/mcp-acp-core
- Stage 2: https://github.com/alandra-v/mcp-acp-extended
- Stage 3: https://github.com/alandra-v/mcp-acp-nexus

---

## Repository Purpose

This repository serves as a permanent record of testing and validation activities performed at each project stage.
It is intentionally separated from the codebase to preserve test evidence, auditability, and historical traceability.

---

## Artefacts Folder Structure

```text
mcp-acp-core/                          # Stage 1 artefacts
├─ diagrams/
└─ testing/
   ├─ unit/
   │  └─ htmlcov/
   └─ e2e-manual/
      ├─ configs/
      ├─ logs/
      └─ manual-e2e-test-record.md

mcp-acp-extended/                      # Stage 2 artefacts
├─ diagrams/
├─ operator-interface/
│  ├─ cli/
│  └─ web-ui/
│     ├─ demo-assets/
│     └─ demo-screenshots/
└─ testing/
   ├─ unit/
   │  └─ htmlcov/
   └─ e2e-manual/
      ├─ 00-e2e-manual/
      ├─ 01-e2e-manual/
      ├─ resilience-testing/
      └─ binary-attestation-test-record.md

mcp-acp-(nexus)/                       # Stage 3 artefacts
├─ assessments/
├─ demo-testing-guide/
├─ diagrams/
├─ operator-interface/
│  ├─ cli/
│  └─ web-ui/demo-screenshots
├─ performance/
│  ├─ documentation/
│  ├─ results/
│  │  └─ raw-logs/
│  └─ scripts/
└─ testing/
   ├─ e2e-manual/
   ├─ security/
   └─ unit-and-integration/
      ├─ htmlcov/
      └─ web-coverage/

log-schema-evolution/                  # Logging specification history
├─ 00-planned-log-schemas/
├─ 01-logging-specs-mcp-acp-core/
├─ 02-logging-specs-mcp-acp-extended/
├─ 03-logging-specs-mcp-acp/
└─ log-schema-changelog.md
```

---

## Folder Descriptions

### Stage 1: mcp-acp-core/

- **diagrams/** — Architecture, workflow, and sequence diagrams.
- **testing/unit/** — Unit test coverage reports.
- **testing/e2e-manual/** — Manual end-to-end testing artefacts including configs, logs, and test records.

### Stage 2: mcp-acp-extended/

- **diagrams/** — Architecture, UI, and request flow diagrams.
- **operator-interface/** — Demo assets and screenshots for the CLI and web UI operator interfaces.
- **testing/unit/** — Unit test coverage reports.
- **testing/e2e-manual/** — Multiple rounds of manual e2e testing, resilience testing, and binary attestation test records.

### Stage 3: mcp-acp-(nexus)/

- **assessments/** — Zero-trust compliance evaluation and future directions roadmap.
- **demo-testing-guide/** — Demo workspace setup, policy configuration, and screenrecording scenarios.
- **diagrams/** — Architecture and request flow diagrams.
- **operator-interface/** — Demo assets for the CLI and web UI operator interfaces.
- **performance/** — Proxy overhead benchmarks, measurement scripts, raw audit logs, and results documentation.
- **testing/e2e-manual/** — Manual end-to-end testing checklist.
- **testing/security/** — Security testing artefacts.
- **testing/unit-and-integration/** — Unit and integration test coverage reports (Python and web).

### log-schema-evolution/

Documents the evolution of logging specifications across project stages:
- **00-planned-log-schemas/** — Initial planned schemas for system, audit, and debug logs.
- **01-logging-specs-mcp-acp-core/** — Logging specs as implemented in Stage 1.
- **02-logging-specs-mcp-acp-extended/** — Logging specs as implemented in Stage 2.
- **03-logging-specs-mcp-acp/** — Logging specs as implemented in Stage 3.
- **log-schema-changelog.md** — Changelog documenting schema evolution across stages.

---

## Notes

Local usernames, machine-specific paths, and other environment-identifying details have been redacted or replaced with placeholders.