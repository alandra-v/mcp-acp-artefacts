# MCP-ACP Artifacts Repository

This repository contains non-code artifacts (test evidence, logs, reports, and supporting documentation) for the **mcp-acp** project.

**Main source repository (Stage 1):**  
https://github.com/alandra-v/mcp-acp-core

---

## Repository Purpose

This repository serves as a permanent record of testing and validation activities performed at each project stage.  
It is intentionally separated from the codebase to preserve test evidence, auditability, and historical traceability.

---

## Stage 1 Artifacts

All Stage 1 artifacts are located under the following structure:

---

## Artifacts Folder Structure

```text
mcp-acp-core/
├─ diagrams/
└─ testing/
   ├─ e2e-manual/
   │  ├─ configs/
   │  ├─ logs/
   │  └─ manual-e2e-test-record.md
   └─ unit/


### Folder descriptions

- **diagrams/**  
  Architecture, workflow, and sequence diagrams for the project.

- **testing/unit/**  
  Artifacts produced by automated unit testing (e.g. coverage reports).

- **testing/e2e-manual/**  
  Manual end-to-end and acceptance testing artifacts.

  - **configs/**  
    Configuration and policy files used during manual testing.

  - **logs/**  
    System, audit, and debug logs captured during test execution.

  - **manual-e2e-test-record\_*.md**  
    Authoritative record of manual test execution, including test cases, results, environment details, and tester notes.


Local usernames, machine-specific paths, and other environment-identifying details have been redacted or replaced with placeholders.