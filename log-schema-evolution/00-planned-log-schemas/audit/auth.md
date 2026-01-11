### Authentication [3002] Class and Authorize Session [3003] Class
Identity & Access Management Category

The authentication log schema is based on the OCSF Identity & Access Management domain, drawing primarily from the Authentication (3002) and Authorize Session (3003) classes. From Authentication, the schema adopts the structured representation of token validation events, including the identity provider context, token metadata (issuer, audience, scopes, expiration), and the success or failure of each validation attempt. From Authorize Session, it inherits the conceptual model for session lifecycle management, capturing when an MCP session is established, validated on a per-request basis, or terminated. These OCSF concepts are simplified and adapted to the Model Context Protocol environment, where authentication happens through an OIDC/OAuth proxy and tokens are re-verified for each MCP request, enabling precise correlation between authentication events, MCP sessions, and operation-level audit logs.

## Core
time – ISO 8601 timestamp
session_id – ID of the MCP session (same as in operations.jsonl)
request_id – optional, per-MCP operation ID (use JSON-RPC id when this event is tied to a specific request)
event_type – one of:
"token_validated" – token checked and valid for this request
"token_invalid" – token missing/expired/invalid for this request
"session_started" – MCP session established + auth ok (e.g. on initialize)
"session_ended" – MCP session terminated / cleaned up
status – "Success" or "Failure"
token_validated usually → "Success"
token_invalid usually → "Failure"
message – short human-readable summary (optional), e.g.
    "Token validated for subject auth0|user_123"
    "Token expired for subject auth0|user_123"
Optionally (nice to have):
method – optional MCP method ("tools/call", "tools/list", etc.)
    Set for per-request token validations (event_type="token_validated" / "token_invalid").

## Identity (from OIDC)
subject_id – OIDC sub claim (when token is parseable)
subject_claims – optional dict of selected safe claims:
    e.g.
    {
    "preferred_username": "alice",
    "email": "alice@example.com"
    }
For totally invalid tokens where you can’t even decode, subject can be omitted (or None).

## OIDC / OAuth token details
These align with OCSF Authentication (3002) concepts: identity provider, token, and outcome.
issuer – OIDC iss (e.g. "https://accounts.google.com", "https://your-tenant.auth0.com")
provider – optional friendly name, e.g. "google", "auth0", "azure"
client_id – client ID your FastMCP OIDC/OAuth proxy uses upstream (optional)
audience – list of audiences (from aud, normalized to List[str])
scopes – list of scopes (if you have them)
token_type – optional ("access", "id", "proxy", etc. – depending on what FastMCP gives you)
token_exp – token expiration (as datetime)
token_iat – token issued-at (as datetime, optional)
token_expired – bool, did you consider this token expired at validation time?
You can fill only what you actually have; others can be omitted.

## Error details (for failed auth)
Inspired by Application Error style, but scoped to auth:
error_type – e.g. "TokenExpiredError", "InvalidSignatureError", "MissingToken"
error_message – short human-readable error, e.g. "Token expired at 2025-12-10T09:00:00Z"
Optional extra:
details – optional dict for any extra structured bits:
{"missing_claims": ["aud"], "raw_reason": "aud mismatch"}