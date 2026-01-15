# Binary Attestation E2E Testing

Manual testing for STDIO backend binary attestation feature.

---

## Test Execution Record

| Field | Value |
|-------|-------|
| **Date** | 12.01.2026 |
| **Tester** | User |
| **Platform** | macOS-15.7.2-arm64-arm-64bit-Mach-O |

---

## Test Summary

| Test ID | Description | Result |
|---------|-------------|--------|
| ATT-01 | Hash verification (correct) | Pass |
| ATT-02 | Hash verification (wrong) | Pass |
| ATT-03 | macOS codesign (signed binary) | Pass |
| ATT-04 | macOS codesign (unsigned binary) | Pass |
| ATT-05 | SLSA verification (correct owner) | Pass |
| ATT-06 | SLSA verification (wrong owner) | Pass |
| ATT-07 | Transport integration | Pass |

---

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth login`)
- Python environment with `mcp_acp_extended` installed

---

## Tests

### ATT-01: Hash Verification (Correct Hash)

**Purpose**: Verify binary passes when hash matches

**Steps**:
```bash
# Get hash
shasum -a 256 /bin/ls
# Example output: 3be943172b502b245545fbfd57706c210fabb9ee058829c5bf00c3f67c8fb474

# Test (replace hash with your output)
python3 -c "from mcp_acp_extended.security.binary_attestation import *; result = verify_backend_binary('ls', BinaryAttestationConfig(expected_sha256='3be943172b502b245545fbfd57706c210fabb9ee058829c5bf00c3f67c8fb474', require_signature=False)); print(f'Verified: {result.verified}')"
```

**Expected**: `Verified: True`

---

### ATT-02: Hash Verification (Wrong Hash)

**Purpose**: Verify binary fails when hash doesn't match

**Steps**:
```bash
python3 -c "from mcp_acp_extended.security.binary_attestation import *; result = verify_backend_binary('ls', BinaryAttestationConfig(expected_sha256='0000000000000000000000000000000000000000000000000000000000000000', require_signature=False)); print(f'Verified: {result.verified}, Error: {result.error}')"
```

**Expected**: `Verified: False, Error: Hash mismatch: expected 0000..., got <actual_hash>`

---

### ATT-03: macOS Codesign (Signed Binary)

**Purpose**: Verify signed system binaries pass codesign check

**Steps**:
```bash
python3 -c "from mcp_acp_extended.security.binary_attestation import *; result = verify_backend_binary('ls', BinaryAttestationConfig(require_signature=True)); print(f'Verified: {result.verified}, Signature: {result.signature_valid}')"
```

**Expected**: `Verified: True, Signature: True`

---

### ATT-04: macOS Codesign (Unsigned Binary)

**Purpose**: Verify unsigned binaries fail codesign check

**Steps**:
```bash
# Create unsigned script
echo '#!/bin/bash' > /tmp/test-unsigned.sh
chmod +x /tmp/test-unsigned.sh

# Test
python3 -c "from mcp_acp_extended.security.binary_attestation import *; result = verify_backend_binary('/tmp/test-unsigned.sh', BinaryAttestationConfig(require_signature=True)); print(f'Verified: {result.verified}, Error: {result.error}')"

# Cleanup
rm /tmp/test-unsigned.sh
```

**Expected**: `Verified: False, Error: ... code object is not signed at all`

---

### ATT-05: SLSA Verification (Correct Owner)

**Purpose**: Verify SLSA attestation passes with correct GitHub owner

**Test binary**: [obsidian-mcp-tools](https://github.com/jacksteamdev/obsidian-mcp-tools) - an MCP server for Obsidian with SLSA provenance attestations via GitHub Actions. Used here because it's a standalone compiled binary (not npm), making it ideal for SLSA testing.

**Steps**:
```bash
# Download binary with SLSA attestation
cd /tmp
gh release download --repo jacksteamdev/obsidian-mcp-tools --pattern "mcp-server-macos-arm64"
chmod +x mcp-server-macos-arm64

# Test
python3 -c "from mcp_acp_extended.security.binary_attestation import *; result = verify_backend_binary('/tmp/mcp-server-macos-arm64', BinaryAttestationConfig(slsa_owner='jacksteamdev', require_signature=False)); print(f'Verified: {result.verified}, SLSA: {result.slsa_verified}')"
```

**Expected**: `Verified: True, SLSA: True`

---

### ATT-06: SLSA Verification (Wrong Owner)

**Purpose**: Verify SLSA attestation fails with wrong GitHub owner

**Steps**:
```bash
python3 -c "from mcp_acp_extended.security.binary_attestation import *; result = verify_backend_binary('/tmp/mcp-server-macos-arm64', BinaryAttestationConfig(slsa_owner='wrong-owner', require_signature=False)); print(f'Verified: {result.verified}, Error: {result.error}')"

# Cleanup
rm /tmp/mcp-server-macos-arm64
```

**Expected**: `Verified: False, Error: ... HTTP 404 ...`

---

### ATT-07: Transport Integration

**Purpose**: Verify attestation integrates with transport layer

**Steps**:
```bash
# Get hash of node (or any binary you have)
HASH=$(shasum -a 256 $(which node) | cut -d' ' -f1)
echo "Hash: $HASH"

# Test transport creation (replace HASH)
python3 -c "
from mcp_acp_extended.config import BackendConfig, StdioTransportConfig, StdioAttestationConfig
from mcp_acp_extended.utils.transport import create_backend_transport
config = BackendConfig(server_name='test', transport='stdio', stdio=StdioTransportConfig(command='node', args=['--version'], attestation=StdioAttestationConfig(expected_sha256='PASTE_HASH_HERE')))
transport, ttype = create_backend_transport(config)
print(f'Transport: {ttype}')
"
```

**Expected**: `Transport: stdio` (no error)

---

## Known Limitations

1. **macOS stub binaries**: Python framework uses stub binaries that exec the real binary. Post-spawn verification may fail for these.

2. **Script wrappers**: Commands like `npx` are symlinks to scripts that run via `node`. The actual process will be `node`, not `npx`.

3. **SLSA requires gh CLI**: The `gh` CLI must be installed and authenticated for SLSA verification.

---

## Test Attribution

All tests (ATT-01 to ATT-07) were executed manually by the user. Claude Code supported test instructions and evaluating expected outputs.

---

## Practical Applicability

Binary attestation is **opt-in** - if you don't configure `attestation` in your stdio config, nothing changes.

### When Each Feature Applies

| Feature | Applicability | Example Use Case |
|---------|---------------|------------------|
| **Hash verification** | Any binary | Pin `node` to a known-good version. Detect if binary changes (update, compromise). |
| **Codesign (macOS)** | Signed binaries | System tools (`/bin/ls`), official installers. Node from Homebrew is signed. |
| **SLSA provenance** | GitHub releases with attestation | Standalone binaries like `obsidian-mcp-tools`. Growing adoption. |

### npm/Node.js MCP Servers

Most MCP servers (like `@modelcontextprotocol/server-filesystem` or `@cyanheads/filesystem-mcp-server`) are **npm packages**, not standalone binaries. For these:

- **SLSA doesn't apply** - SLSA is for GitHub release binaries, not npm packages
- **The actual binary is `node`** - attestation verifies `node`, not the JS package
- **npm has its own integrity model** - package-lock.json contains SHA-512 checksums that npm verifies on install

#### npm Package Integrity (Reference)

npm uses SHA-512 checksums in `package-lock.json` to verify packages haven't been tampered with:
- First install: npm generates and stores checksums
- Subsequent installs: npm recalculates hash and compares to lockfile
- Mismatch: installation halts with `EINTEGRITY` error

See: [Lockfile poisoning and how hashes verify integrity](https://medium.com/node-js-cybersecurity/lockfile-poisoning-and-how-hashes-verify-integrity-in-node-js-lockfiles-0f105a6a18cd)

### When Binary Attestation Is Most Valuable

1. **Standalone compiled binaries** - Go, Rust, or compiled tools distributed as binaries
2. **High-security environments** - Where you want to pin exact binary versions
3. **SLSA-enabled projects** - GitHub releases with build provenance (growing ecosystem)
4. **Defense-in-depth** - Additional layer alongside npm integrity checks
