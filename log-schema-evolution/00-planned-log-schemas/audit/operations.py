from __future__ import annotations
from typing import Optional, Dict
from datetime import datetime
from pydantic import BaseModel, Field


class SubjectIdentity(BaseModel):
    """
    Identity of the human user, derived from the OIDC token.
    """
    subject_id: str                                  # OIDC 'sub'
    subject_claims: Optional[Dict[str, str]] = None  # selected safe claims


class ArgumentsSummary(BaseModel):
    """
    Summary of MCP request arguments (without logging full sensitive payloads).
    """
    redacted: bool = True
    body_hash: Optional[str] = None                  # e.g. sha256 hex string
    payload_length: Optional[int] = None             # request size in bytes


class LatencyInfo(BaseModel):
    """
    Latency measurements for this MCP operation.
    """
    latency_ms_total: float = Field(..., description="Total end-to-end latency in ms")
    latency_ms_client_to_proxy: Optional[float] = None
    latency_ms_proxy_to_backend: Optional[float] = None
    latency_ms_backend_processing: Optional[float] = None


class OperationEvent(BaseModel):
    """
    One MCP operation log entry (audit/operations.jsonl).
    """

    # --- core ---
    time: datetime
    session_id: str
    request_id: str
    method: str                                       # MCP method ("tools/call", ...)

    status: str                                       # "Success", "Failure", "Denied"
    message: Optional[str] = None

    # --- identity ---
    subject: SubjectIdentity

    # --- backend info ---
    backend_id: str                                   # internal MCP backend identifier

    # --- MCP details ---
    tool_name: Optional[str] = None                   # only for tools/call
    arguments_summary: Optional[ArgumentsSummary] = None

    # --- config ---
    config_version: Optional[str] = None

    # --- latency ---
    latency: LatencyInfo

    class Config:
        extra = "forbid"
