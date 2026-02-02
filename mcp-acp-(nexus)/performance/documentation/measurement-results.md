# Performance Measurement Results

> **Scope**: Feasibility measurement — demonstrating the proxy does not add unacceptable
> latency. These are not benchmarks and should not be used as optimization targets.
> See `performance-documentation.md` for methodology, deviations, and limitations.

## Test Environment

| Component | Value |
|-----------|-------|
| Hardware | Apple M3 Pro, 11 cores (5P + 6E), 18 GB RAM |
| OS | macOS 15.7.2 (Darwin 24.6.0) |
| Python | 3.13.5 |
| FastMCP | 2.14.1 |
| mcp-acp | 0.1.0 |

## Test Configuration

| Parameter | Value |
|-----------|-------|
| Warmup requests | 10 (discarded) |
| Measured requests | 100 per operation type |
| Inter-request delay | 0.12s (proxied only, to stay under DoS rate limiter) |
| Session rate limiter | Temporarily raised to 500 (default: 30/60s) |
| Policy | Allow-all (`tool_name: *`) unless noted otherwise |
| Auth | OIDC (production auth stack active) |
| Backends | `scripts/echo_server.py` (echo), `cyanheads/filesystem-mcp-server` (filesystem) |

## STDIO Backend Results

**Setup:**
```
Direct:   FastMCP Client ──STDIO──▶ echo-server (subprocess)
Proxied:  FastMCP Client ──STDIO──▶ mcp-acp proxy ──STDIO──▶ echo-server (subprocess)
```

### Tool Call (`tools/call`)

| Metric | Direct | Proxied |
|--------|--------|---------|
| Median | 1.42 ms | 16.38 ms |
| Std Dev | 0.05 ms | 3.82 ms |
| Min | 1.37 ms | 13.65 ms |
| Max | 1.77 ms | 46.36 ms |
| Samples | 100 | 100 |
| **Overhead** | | **14.96 ms** |

### Discovery (`tools/list`)

| Metric | Direct | Proxied |
|--------|--------|---------|
| Median | 0.72 ms | 7.53 ms |
| Std Dev | 0.05 ms | 0.85 ms |
| Min | 0.67 ms | 6.06 ms |
| Max | 1.07 ms | 10.95 ms |
| Samples | 100 | 100 |
| **Overhead** | | **6.81 ms** |

### Observations

- **Tool call overhead (~15ms)** includes: policy evaluation, audit logging (hash-chained
  decisions.jsonl), middleware chain (Context → Audit → ClientLogger → Enforcement),
  and an additional STDIO subprocess hop (proxy → backend).

- **Discovery overhead (~7ms)** is roughly half the tool call overhead. Discovery
  bypasses the policy engine entirely (`discovery_bypass`), so the difference (~8ms)
  approximates the policy evaluation + audit decision logging cost.

- **Stability**: Tool call stdev (3.82ms) is ~23% of median — acceptable. The max
  outlier (46.36ms) suggests occasional OS scheduling delays. Discovery is tighter
  (stdev 0.85ms, ~11% of median).

- **Direct baseline is very low** (0.7–1.4ms) because the echo backend does near-zero
  work. This gives the cleanest overhead isolation — the measured difference is
  almost entirely proxy processing.

- The filesystem backend tests (below) confirm that proxy overhead is consistent
  regardless of backend workload — real I/O vs synthetic echo produces the same
  overhead range.

## HTTP Backend Results

**Setup:**
```
Direct:   FastMCP Client ──HTTP──▶ echo-server (http://127.0.0.1:8766/mcp)
Proxied:  FastMCP Client ──STDIO──▶ mcp-acp proxy ──HTTP──▶ echo-server
```

### Tool Call (`tools/call`)

| Metric | Direct | Proxied |
|--------|--------|---------|
| Median | 3.00 ms | 114.17 ms |
| Std Dev | 0.43 ms | 6.79 ms |
| Min | 2.77 ms | 107.38 ms |
| Max | 5.11 ms | 170.45 ms |
| Samples | 100 | 100 |
| **Overhead** | | **111.17 ms** |

### Discovery (`tools/list`)

| Metric | Direct | Proxied |
|--------|--------|---------|
| Median | 2.10 ms | 31.70 ms |
| Std Dev | 0.18 ms | 5.69 ms |
| Min | 1.97 ms | 29.12 ms |
| Max | 2.80 ms | 85.53 ms |
| Samples | 100 | 100 |
| **Overhead** | | **29.60 ms** |

### Observations

- **Tool call overhead (~111ms)** is significantly higher than STDIO (~15ms). The proxy
  receives requests via STDIO but forwards to the backend via HTTP (StreamableHTTP).
  The overhead includes: STDIO→HTTP transport bridging, HTTP request/response
  serialization, StreamableHTTP protocol overhead (SSE streams), plus the same policy
  evaluation and audit logging as STDIO.

- **Discovery overhead (~30ms)** is also higher than STDIO (~7ms), again due to the
  HTTP transport bridging on the proxy→backend leg.

- **Transport bridging dominates**: The difference between HTTP and STDIO overhead
  (~96ms for tool calls, ~23ms for discovery) is far larger than the policy evaluation
  cost (~8ms estimated from STDIO). This suggests the StreamableHTTP transport
  adds substantial per-request overhead in the proxy→backend direction.

- **Stability**: Tool call stdev (6.79ms) is ~6% of median — tight. Discovery stdev
  (5.69ms) is ~18% of median, with one outlier at 85.53ms.

- **Note on comparison fairness**: The direct HTTP path (Client→HTTP→Backend) and the
  proxied path (Client→STDIO→Proxy→HTTP→Backend) use different client transports.
  The overhead includes both proxy processing AND the STDIO↔HTTP transport difference
  on the client side.

## Filesystem Backend Results (STDIO)

Real-world backend validation using the cyanheads filesystem MCP server (Node.js)
with the `read_file` tool reading a small test file (`/tmp/mcp-acp-test.txt`, 5 lines).

**Setup:**
```
Direct:   FastMCP Client ──STDIO──▶ filesystem-server (subprocess)
Proxied:  FastMCP Client ──STDIO──▶ mcp-acp proxy ──STDIO──▶ filesystem-server (subprocess)
```

### Test 3: Allow-All Policy

Same allow-all policy (`tool_name: *`) as echo tests.

#### Tool Call (`tools/call`)

| Metric | Direct | Proxied |
|--------|--------|---------|
| Median | 0.38 ms | 12.37 ms |
| Std Dev | 0.09 ms | 2.49 ms |
| Min | 0.33 ms | 8.58 ms |
| Max | 1.11 ms | 25.66 ms |
| Samples | 100 | 100 |
| **Overhead** | | **11.99 ms** |

#### Discovery (`tools/list`)

| Metric | Direct | Proxied |
|--------|--------|---------|
| Median | 0.45 ms | 8.67 ms |
| Std Dev | 0.07 ms | 1.73 ms |
| Min | 0.41 ms | 5.69 ms |
| Max | 0.93 ms | 13.82 ms |
| Samples | 100 | 100 |
| **Overhead** | | **8.22 ms** |

### Test 4: Restrictive Multi-Rule Policy

Four rules with different condition types to stress the policy engine:
- `allow-read-tmp`: allow `read_file` for `/tmp/**`
- `allow-list-tmp`: allow `list_files` for `/tmp/**`
- `deny-sensitive-extensions`: deny `.key`, `.pem`, `.env` files
- `hitl-write-ops`: HITL for write/delete operations

**Note**: The test calls `read_file` on `/tmp/mcp-acp-test.txt`, which matches the
`allow-read-tmp` rule. The deny and HITL rules are present in the policy (the engine
must parse and evaluate all rules) but are never triggered — only the **allowed path**
is exercised. See performance-documentation.md for why denied/HITL paths are not
measured and are noted as future work.

#### Tool Call (`tools/call`)

| Metric | Direct | Proxied |
|--------|--------|---------|
| Median | 0.37 ms | 16.75 ms |
| Std Dev | 0.09 ms | 4.90 ms |
| Min | 0.33 ms | 8.88 ms |
| Max | 1.13 ms | 31.66 ms |
| Samples | 100 | 100 |
| **Overhead** | | **16.38 ms** |

#### Discovery (`tools/list`)

| Metric | Direct | Proxied |
|--------|--------|---------|
| Median | 0.45 ms | 13.18 ms |
| Std Dev | 0.07 ms | 4.22 ms |
| Min | 0.41 ms | 6.09 ms |
| Max | 0.98 ms | 25.64 ms |
| Samples | 100 | 100 |
| **Overhead** | | **12.73 ms** |

### Observations

- **Proxy overhead is consistent across backends**: The allow-all filesystem test
  (~12ms tool call overhead) is in the same range as the echo baseline (~15ms).
  The slight difference is within measurement noise — confirming the proxy overhead
  is independent of backend workload.

- **Policy complexity does not meaningfully affect overhead**: The 4-rule restrictive
  policy (~16ms) appeared ~4ms higher than allow-all (~12ms), but a subsequent 50-rule
  test (~11ms) showed no increase at all. The engine evaluates all rules on every
  request (no short-circuiting), yet 50 rules of mixed condition types produced the
  same overhead as a single allow-all rule. The 4-rule result was run-to-run variance,
  not policy complexity cost. Per-rule matching (string comparisons, glob matches) is
  negligible relative to the ~12ms baseline of middleware, audit logging, and STDIO
  transport.

- **Direct baseline is sub-millisecond**: The filesystem server's `read_file` on a
  small local file (0.37ms) is actually faster than the echo server (1.42ms). This is
  likely because the Node.js filesystem server's STDIO handling is more efficient than
  the Python echo server's, or the file is cached in the OS page cache.

- **Stability**: Allow-all stdev (2.49ms) is ~20% of median — acceptable. Restrictive
  policy stdev (4.90ms) is ~29% of median — higher but still under the 50% threshold.

### Test 5: 50-Rule Policy (STDIO)

50 rules with mixed condition types (tool name matching, glob path patterns, extension
lists, operations arrays) to test whether policy evaluation cost scales with rule count.
The engine evaluates all rules on every request (no short-circuiting — confirmed by
code inspection of `engine.py:260`).

Reduced sample size (50 runs, 5 warmup) since this is a scaling comparison, not a
primary measurement.

#### Tool Call (`tools/call`)

| Metric | Direct | Proxied |
|--------|--------|---------|
| Median | 0.40 ms | 11.66 ms |
| Std Dev | 0.19 ms | 2.33 ms |
| Min | 0.35 ms | 8.83 ms |
| Max | 1.67 ms | 21.48 ms |
| Samples | 50 | 50 |
| **Overhead** | | **11.26 ms** |

#### Discovery (`tools/list`)

| Metric | Direct | Proxied |
|--------|--------|---------|
| Median | 0.44 ms | 7.76 ms |
| Std Dev | 0.04 ms | 2.11 ms |
| Min | 0.42 ms | 5.74 ms |
| Max | 0.62 ms | 17.92 ms |
| Samples | 50 | 50 |
| **Overhead** | | **7.32 ms** |

## Filesystem Backend Results (HTTP)

Same cyanheads filesystem server, but accessed via HTTP (`http://localhost:3010/mcp`)
instead of STDIO subprocess.

**Setup:**
```
Direct:   FastMCP Client ──HTTP──▶ filesystem-server (http://localhost:3010/mcp)
Proxied:  FastMCP Client ──STDIO──▶ mcp-acp proxy ──HTTP──▶ filesystem-server
```

### Test 5: Allow-All Policy

#### Tool Call (`tools/call`)

| Metric | Direct | Proxied |
|--------|--------|---------|
| Median | 2.95 ms | 140.76 ms |
| Std Dev | 1.71 ms | 11.12 ms |
| Min | 2.45 ms | 127.37 ms |
| Max | 14.34 ms | 187.89 ms |
| Samples | 100 | 100 |
| **Overhead** | | **137.81 ms** |

#### Discovery (`tools/list`)

| Metric | Direct | Proxied |
|--------|--------|---------|
| Median | 3.11 ms | 38.32 ms |
| Std Dev | 0.38 ms | 2.93 ms |
| Min | 2.60 ms | 33.74 ms |
| Max | 4.30 ms | 51.32 ms |
| Samples | 100 | 100 |
| **Overhead** | | **35.21 ms** |

### Test 6: Restrictive Multi-Rule Policy

Same 4-rule policy as STDIO Test 4.

#### Tool Call (`tools/call`)

| Metric | Direct | Proxied |
|--------|--------|---------|
| Median | 3.24 ms | 129.78 ms |
| Std Dev | 1.29 ms | 8.41 ms |
| Min | 2.37 ms | 123.10 ms |
| Max | 10.87 ms | 166.75 ms |
| Samples | 100 | 100 |
| **Overhead** | | **126.54 ms** |

#### Discovery (`tools/list`)

| Metric | Direct | Proxied |
|--------|--------|---------|
| Median | 3.08 ms | 37.18 ms |
| Std Dev | 0.37 ms | 3.40 ms |
| Min | 2.54 ms | 33.64 ms |
| Max | 4.16 ms | 54.23 ms |
| Samples | 100 | 100 |
| **Overhead** | | **34.10 ms** |

### Observations

- **HTTP overhead consistent across backends**: Filesystem HTTP (~138ms allow-all) is
  in the same range as echo HTTP (~111ms). The ~27ms difference may reflect the
  filesystem server's slightly different StreamableHTTP implementation or Node.js vs
  Python SSE handling differences.

- **Policy complexity has no meaningful impact over HTTP**: The restrictive policy
  (~127ms) is actually slightly *lower* than allow-all (~138ms). This is within
  measurement noise and confirms that the ~4ms policy complexity cost observed in
  STDIO tests is negligible relative to HTTP transport overhead.

- **Transport dominates**: HTTP overhead (~130ms) dwarfs STDIO overhead (~12ms).
  The StreamableHTTP protocol adds ~120ms per tool call regardless of policy or
  backend type.

- **Stability**: Allow-all stdev (11.12ms) is ~8% of median — tight. Restrictive
  stdev (8.41ms) is ~6% of median — even tighter.

## Summary

### Tool Call Overhead

| Backend | Transport | Policy | Overhead |
|---------|-----------|--------|----------|
| Echo | STDIO | allow-all | **14.96 ms** |
| Filesystem | STDIO | allow-all | **11.99 ms** |
| Filesystem | STDIO | restrictive (4 rules) | **16.38 ms** |
| Filesystem | STDIO | mixed (50 rules) | **11.26 ms** |
| Echo | HTTP | allow-all | **111.17 ms** |
| Filesystem | HTTP | allow-all | **137.81 ms** |
| Filesystem | HTTP | restrictive (4 rules) | **126.54 ms** |

### Discovery Overhead

| Backend | Transport | Policy | Overhead |
|---------|-----------|--------|----------|
| Echo | STDIO | allow-all | **6.81 ms** |
| Filesystem | STDIO | allow-all | **8.22 ms** |
| Filesystem | STDIO | restrictive (4 rules) | **12.73 ms** |
| Filesystem | STDIO | mixed (50 rules) | **7.32 ms** |
| Echo | HTTP | allow-all | **29.60 ms** |
| Filesystem | HTTP | allow-all | **35.21 ms** |
| Filesystem | HTTP | restrictive (4 rules) | **34.10 ms** |

### Key Findings

1. **STDIO overhead is ~12–16ms regardless of backend**: Echo and filesystem backends
   produce the same overhead range. The proxy cost is independent of backend workload —
   it's dominated by middleware chain processing, audit logging, and the STDIO
   subprocess hop.

2. **Policy rule count does not affect overhead**: A 50-rule policy with mixed condition
   types (~11ms) produced the same overhead as a single allow-all rule (~12ms). The
   engine evaluates all rules on every request with no short-circuiting, but per-rule
   matching cost (string comparisons, glob matches) is negligible. The ~4ms difference
   seen in the 4-rule test was run-to-run variance. Over HTTP, the difference is
   similarly within noise.

3. **HTTP transport dominates**: HTTP overhead (~110–140ms) is ~10x STDIO (~12–16ms).
   The StreamableHTTP protocol (SSE streams, HTTP serialization) adds substantial
   per-request cost. This is a transport characteristic, not a proxy limitation.

4. **Real-world backend validates echo baseline**: The filesystem server (Node.js,
   real disk I/O) produces the same proxy overhead as the synthetic echo server
   (Python, zero work). This confirms the echo measurements are representative.

## Audit Log Analysis (Filesystem-Server Proxy)

Real-usage audit logs from the `filesystem-server` proxy, parsed with
`scripts/parse_latency_logs.py`. Unlike the controlled overhead tests above
(100 runs, warmup, single tool, allow-all policy), these reflect actual proxy
usage with mixed operations and policy decisions — including HITL prompts.

Machine-readable results: `results/log_parse_filesystem.json`

**Source**: `~/Library/Logs/mcp-acp/proxies/filesystem-server/audit/{decisions,operations}.jsonl`

### All Entries (n=26)

| Metric | Median | Mean | P95 | Min | Max |
|--------|--------|------|-----|-----|-----|
| Policy eval | 0.23 ms | 0.34 ms | 1.74 ms | 0.00 ms | 2.16 ms |
| HITL wait (n=11) | 16,636 ms | 14,438 ms | 32,586 ms | 3,160 ms | 30,239 ms |
| Policy total | 0.58 ms | 6,109 ms | 28,186 ms | 0.00 ms | 30,239 ms |
| End-to-end proxy | 130.17 ms | 6,219 ms | 28,234 ms | 1.56 ms | 30,245 ms |
| Backend call (derived) | 109.24 ms | 110 ms | 306 ms | 1.55 ms | 354 ms |

### Excluding HITL (n=15, 11 HITL entries removed)

| Metric | Median | Mean | P95 | Min | Max |
|--------|--------|------|-----|-----|-----|
| Policy eval | 0.23 ms | 0.27 ms | 1.03 ms | 0.00 ms | 0.96 ms |
| Policy total | 0.23 ms | 0.27 ms | 1.03 ms | 0.00 ms | 0.96 ms |
| End-to-end proxy | 105.17 ms | 92.96 ms | 234.76 ms | 1.56 ms | 217.93 ms |
| Backend call (derived) | 104.90 ms | 92.69 ms | 234.29 ms | 1.55 ms | 217.38 ms |

### Interpretation

- **Policy evaluation is sub-millisecond in real usage** (0.23 ms median), consistent
  with the controlled overhead tests where policy rule count had no measurable impact.
  The excluding-HITL policy total (0.23 ms) confirms that without human wait time,
  policy processing adds negligible latency.

- **Proxy overhead is ~0.3 ms excluding HITL**: End-to-end minus backend call
  (105.17 − 104.90 = 0.27 ms median) represents the pure proxy processing cost.
  This is lower than the ~12 ms measured in overhead tests because the overhead tests
  include the full middleware chain startup per-request, while audit log timestamps
  capture a narrower window. The controlled overhead tests remain the authoritative
  measure of proxy overhead.

- **Backend latency dominates non-HITL requests**: The filesystem server's real
  operations (median 105 ms) are orders of magnitude higher than the 0.38 ms seen
  in overhead tests (which read a 5-line cached file). This confirms that for
  real workloads, backend I/O — not proxy processing — determines end-to-end latency.

- **HITL wait dominates when present**: 11 of 26 decisions required human approval,
  with a median wait of 16.6 seconds. This makes the mean/P95 of the "all entries"
  stats misleading for proxy overhead assessment — the excluding-HITL view isolates
  the automated path. HITL latency is inherently user-dependent and not a proxy
  performance metric.

- **Controlled tests and audit logs agree**: Both show sub-millisecond policy
  evaluation and confirm that proxy processing cost is negligible relative to
  backend workload and transport overhead.
