### API Activity [6003] Class 
Application Activity Category

The schema follows the same conceptual structure as OCSF API Activity (actor, action, resource, outcome, time, latency) but uses a project-specific field naming.

## Core
time – ISO 8601 timestamp
session_id – ID of the MCP session
request_id – per-MCP operation ID (use the JSON-RPC id)
method – MCP method, e.g. "tools/call", "tools/list", "resources/read", etc.
status – "Success" | "Failure" | "Denied"
message – short human-readable description (optional)

## Identity (from OIDC)
subject_id – the OIDC sub claim (required)
subject_claims – optional dict of selected safe claims (e.g. preferred_username, email)

## Backend
backend_id – internal ID of the MCP backend / server
(full server info lives in the initialize logs, not here)

## MCP operation details
tool_name – optional, only set if method == "tools/call"
(e.g. "prod_log_reader")
arguments_summary – optional object:
redacted – bool (true if you didn’t log full args)
body_hash – optional hash of the args (e.g. SHA-256 over the JSON)
payload_length – optional, size in bytes of the request payload
(You can add response_summary later if you want, but we can omit it for now.)

## Config
config_version – version string from your loaded config
(so you can tie each operation back to the config in effect)

## Latency
latency_ms_total – total end-to-end latency in ms (required)
latency_ms_client_to_proxy – optional
latency_ms_proxy_to_backend – optional
latency_ms_backend_processing – optional