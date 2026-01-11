from __future__ import annotations
from typing import Optional, Literal
from datetime import datetime
from pydantic import BaseModel


class ConfigHistoryEvent(BaseModel):
    """
    One configuration history log entry (logs/system/config_history.jsonl).

    Captures the lifecycle of successful configuration versions:
    - initial load at startup
    - subsequent successful updates or reloads

    The design follows general security logging and configuration
    management guidance (e.g., OWASP logging recommendations,
    NIST SP 800-128 for security-focused configuration management,
    and NIST SP 800-92 / CIS Control 8 for audit log management),
    by recording when configuration changes occur, which version
    is active, and a snapshot sufficient to reconstruct the effective
    configuration during later analysis.
    """

    # --- core ---
    time: datetime
    event: Literal["config_created", "config_updated"]
    message: Optional[str] = None  # human-readable description

    # --- versioning ---
    config_version: str                  # new/active version ID
    previous_version: Optional[str] = None
    change_type: Literal["initial_load", "manual_update", "reload"]

    # --- source / component ---
    component: Optional[str] = None      # e.g. "proxy", "policy_engine"
    config_path: Optional[str] = None    # path to the config file on disk

    # --- integrity ---
    checksum: str                        # e.g. "sha256:abcd1234..."

    # --- snapshot ---
    snapshot_format: Literal["yaml", "json"] = "yaml"
    snapshot: str                        # full config content as text

    class Config:
        extra = "forbid"
