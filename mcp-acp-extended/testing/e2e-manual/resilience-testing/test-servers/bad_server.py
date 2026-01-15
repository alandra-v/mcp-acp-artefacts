"""Bad MCP server for resilience testing (BACKEND-02).

This server returns invalid JSON to test proxy error handling.
"""

from fastapi import FastAPI, Request
from fastapi.responses import PlainTextResponse
import uvicorn

app = FastAPI()


@app.post("/mcp")
async def mcp_endpoint(request: Request):
    """Return invalid JSON for any MCP request."""
    # Log what we received for debugging
    body = await request.body()
    print(f"Received: {body.decode()[:100]}...")

    # Return invalid JSON
    return PlainTextResponse(
        "this is not valid json {{{",
        media_type="application/json"  # Lie about content type
    )


@app.get("/mcp")
async def mcp_sse_endpoint():
    """Handle SSE endpoint with invalid response."""
    return PlainTextResponse(
        "this is not valid json {{{",
        media_type="text/event-stream"
    )


if __name__ == "__main__":
    print("Starting bad server on http://127.0.0.1:3012/mcp")
    uvicorn.run(app, host="127.0.0.1", port=3012)
