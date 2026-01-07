#!/usr/bin/env python3
"""Test HITL dialog queuing with concurrent requests.

This script fires multiple MCP requests simultaneously to trigger
HITL approval dialogs and verify the queuing behavior:
- Queue position indicator shows correctly ("Queue: #2 pending", etc.)
- Sound only plays for first dialog (queue_position == 1)
- All dialogs eventually appear and can be approved/denied

SETUP:
1. Create a test file:
   touch<test-workspace>/tmp-dir/hitl-test.txt

2. Add an HITL rule to your policy.json:
   {
     "id": "hitl-test",
     "effect": "hitl",
     "conditions": {
       "paths": ["<test-workspace>/hitl-test.txt"]
     }
   }

3. Optionally reduce timeout for faster testing:
   "hitl": { "timeout_seconds": 10 }

USAGE:
    python tests/test_hitl_queue.py              # Default: 3 concurrent requests
    python tests/test_hitl_queue.py --count 5   # 5 concurrent requests
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

try:
    from mcp import ClientSession
    from mcp.client.stdio import StdioServerParameters, stdio_client
except ImportError:
    print("Error: mcp package not installed. Install with: pip install mcp")
    sys.exit(1)


async def test_hitl_queue(count: int, test_path: str) -> None:
    """Fire concurrent requests to test HITL dialog queuing."""
    print(f"\nHITL Queue Test")
    print("=" * 50)
    print(f"Concurrent requests: {count}")
    print(f"Target path: {test_path}")
    print()

    server_params = StdioServerParameters(
        command="mcp-acp-core",
        args=["start"],
    )

    async def single_request(i: int, session: ClientSession) -> str:
        """Send a single request and return outcome."""
        try:
            result = await session.call_tool("read_file", {"path": test_path})
            if result.isError:
                return f"Request {i}: DENIED/TIMEOUT"
            return f"Request {i}: ALLOWED"
        except Exception as e:
            return f"Request {i}: ERROR - {e}"

    try:
        async with stdio_client(server_params) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()

                print(f"Firing {count} concurrent requests...")
                print("Watch for dialog queue indicators!\n")

                # Fire all requests simultaneously
                results = await asyncio.gather(
                    *[single_request(i, session) for i in range(count)],
                    return_exceptions=True,
                )

                print("\nResults:")
                print("-" * 30)
                for r in results:
                    if isinstance(r, Exception):
                        print(f"  EXCEPTION: {r}")
                    else:
                        print(f"  {r}")

    except Exception as e:
        print(f"Connection error: {e}")
        sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(description="Test HITL dialog queuing")
    parser.add_argument(
        "--count",
        type=int,
        default=3,
        help="Number of concurrent requests (default: 3)",
    )
    parser.add_argument(
        "--path",
        type=str,
        default="<test-workspace>/hitl-test.txt",
        help="Path to file with HITL rule",
    )
    args = parser.parse_args()

    asyncio.run(test_hitl_queue(args.count, args.path))


if __name__ == "__main__":
    main()
