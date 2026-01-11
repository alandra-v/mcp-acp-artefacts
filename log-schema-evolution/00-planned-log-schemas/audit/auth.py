from __future__ import annotations
from typing import Optional, Dict, Any, List, Literal
from datetime import datetime
from pydantic import BaseModel


class SubjectIdentity(BaseModel):
    """
    Identity of the human user, derived from the OIDC token.
    """
    subject_id: str                                  # OIDC 'sub'
    subject_claims: Optional[Dict[str, str]] = None  # selected safe claims


class OIDCInfo(BaseModel):
    """
    Details about the OIDC/OAuth token and provider, for authentication logs.
    """
    issuer: str                                      # OIDC 'iss'
    provider: Optional[str] = None                   # friendly name, e.g. "google", "auth0"
    client_id: Optional[str] = None                  # upstream client_id (if you want to log it)

    audience: Optional[List[str]] = None             # normalized 'aud' as list
    scopes: Optional[List[str]] = None               # token scopes, if available

    token_type: Optional[str] = None                 # "access", "id", "proxy", etc.
    token_exp: Optional[datetime] = None             # 'exp' as datetime
    token_iat: Optional[datetime] = None             # 'iat' as datetime
    token_expired: Optional[bool] = None             # whether it was expired at validation time


class AuthEvent(BaseModel):
    """
    One authentication/authorization log entry (logs/audit/auth.jsonl).

    Inspired by:
      - OCSF Authentication (3002): token validation outcome, identity, IdP context
      - OCSF Authorize Session (3003): session lifecycle (start/stop) tied to identity
    """

    # --- core ---
    time: datetime
    session_id: str

    # For per-request auth checks, this is the MCP JSON-RPC id; may be omitted for pure session events.
    request_id: Optional[str] = None

    event_type: Literal["token_validated", "token_invalid", "session_started", "session_ended"]
    status: Literal["Success", "Failure"]
    message: Optional[str] = None

    # Optional MCP method (useful when event_type is per-request token validation).
    method: Optional[str] = None                     # "tools/call", "tools/list", etc.

    # --- identity ---
    # May be None if token could not be parsed at all (e.g. totally invalid or missing)
    subject: Optional[SubjectIdentity] = None

    # --- OIDC/OAuth details ---
    oidc: Optional[OIDCInfo] = None

    # --- errors / extra details ---
    error_type: Optional[str] = None                 # e.g. "TokenExpiredError"
    error_message: Optional[str] = None              # human-readable error
    details: Optional[Dict[str, Any]] = None         # any extra structured data

    class Config:
        extra = "forbid"
