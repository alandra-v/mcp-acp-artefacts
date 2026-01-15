"""FastMCP HTTPS server with mTLS for resilience testing (BACKEND-03).

This server requires client certificate authentication.
Used to test mTLS certificate rotation during session.

Setup: Generate certificates first:
    export CERTS=/tmp/mtls-test-certs
    mkdir -p $CERTS && cd $CERTS

    # CA
    openssl genrsa -out ca-key.pem 4096
    openssl req -new -x509 -days 365 -key ca-key.pem -out ca-cert.pem \
      -subj "/CN=Test CA/O=mcp-acp-extended-test" \
      -addext "basicConstraints=critical,CA:TRUE" \
      -addext "keyUsage=critical,keyCertSign,cRLSign"

    # Server cert
    openssl genrsa -out server-key.pem 2048
    openssl req -new -key server-key.pem -out server.csr -subj "/CN=localhost"
    openssl x509 -req -days 365 -in server.csr -CA ca-cert.pem -CAkey ca-key.pem \
      -CAcreateserial -out server-cert.pem \
      -extfile <(echo "subjectAltName=DNS:localhost,IP:127.0.0.1")

    # Client cert (for proxy)
    openssl genrsa -out client-key.pem 2048
    openssl req -new -key client-key.pem -out client.csr -subj "/CN=mcp-acp-extended-proxy"
    openssl x509 -req -days 365 -in client.csr -CA ca-cert.pem -CAkey ca-key.pem \
      -CAcreateserial -out client-cert.pem \
      -extfile <(echo "extendedKeyUsage=clientAuth")
"""

import ssl
from pathlib import Path

import uvicorn
from fastmcp import FastMCP

CERT_DIR = Path("/tmp/mtls-test-certs")

mcp = FastMCP("mtls-test-server")


@mcp.tool()
def secure_ping() -> str:
    """Return pong from mTLS-protected server."""
    return "secure pong - mTLS verified!"


@mcp.tool()
def secure_echo(message: str) -> str:
    """Echo a message back from the mTLS server."""
    return f"Echo from mTLS server: {message}"


if __name__ == "__main__":
    # Create SSL context requiring client certificates
    ssl_context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    ssl_context.load_cert_chain(
        certfile=str(CERT_DIR / "server-cert.pem"),
        keyfile=str(CERT_DIR / "server-key.pem"),
    )
    ssl_context.load_verify_locations(cafile=str(CERT_DIR / "ca-cert.pem"))
    ssl_context.verify_mode = ssl.CERT_REQUIRED

    # Get the ASGI app from FastMCP
    app = mcp.http_app()

    print(f"Starting mTLS server on https://127.0.0.1:9443/mcp")
    uvicorn.run(
        app,
        host="127.0.0.1",
        port=9443,
        ssl_keyfile=str(CERT_DIR / "server-key.pem"),
        ssl_certfile=str(CERT_DIR / "server-cert.pem"),
        ssl_ca_certs=str(CERT_DIR / "ca-cert.pem"),
        ssl_cert_reqs=ssl.CERT_REQUIRED,
    )
