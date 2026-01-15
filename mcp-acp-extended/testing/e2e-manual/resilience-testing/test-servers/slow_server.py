"""Slow MCP server for resilience testing (BACKEND-01).

This server has a tool that takes 35 seconds to respond,
used to test proxy timeout handling.
"""

import time

from fastmcp import FastMCP

mcp = FastMCP("slow-server")


@mcp.tool()
def slow_operation() -> str:
    """A tool that takes 35 seconds to respond."""
    time.sleep(35)
    return "finally done"


@mcp.tool()
def quick_ping() -> str:
    """A quick tool to verify server is working."""
    return "pong"


if __name__ == "__main__":
    mcp.run(transport="streamable-http", host="127.0.0.1", port=3011)
