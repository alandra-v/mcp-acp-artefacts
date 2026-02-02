# Performance Testing Documentation

> This document records the complete methodology, deviations, and limitations for
> all performance measurements. It is the primary reference for how results in
> `measurement-results.md` were obtained.
>
> **Scope**: Feasibility measurement — proving the proxy doesn't add unacceptable
> latency. These are not benchmarks and should not be used as optimization targets.

## Metrics

Three performance aspects are documented:

| Metric | Description | Approach |
|--------|-------------|----------|
| **Policy decision latency** | Time added by per-request policy evaluation | Log parsing: aggregate `policy_eval_ms` from audit DecisionEvent |
| **HITL overhead** | Additional delay when human approval required | Log parsing: aggregate `policy_hitl_ms` (human time dominates) |
| **Proxy overhead** | End-to-end proxy vs direct comparison | Standalone measurement script, order-of-magnitude feasibility indicator |

### Hybrid Measurement Approach

We use a hybrid approach: log parsing for metrics already captured in audit logs,
standalone measurement for proxy overhead comparison.

| Metric | Approach | Script |
|--------|----------|--------|
| Policy decision latency | Log parsing | `scripts/parse_latency_logs.py` |
| HITL overhead | Log parsing | `scripts/parse_latency_logs.py` |
| Proxy overhead | Standalone measurement | `scripts/measure_overhead.py` |

**Why this split:**
- Policy eval + HITL times are already logged in every DecisionEvent — use real data.
- Proxy overhead requires a direct vs proxied comparison — must be measured live.

| Approach | Pros | Cons |
|----------|------|------|
| **Log parsing** | Data already exists from real usage; reflects actual usage patterns; historical analysis possible; no test infrastructure needed | Tied to log format; can't control test conditions; only works for metrics already logged |
| **Standalone measurement** | Controlled, reproducible conditions; can compare direct vs proxied; can test different backends | Requires test setup; results depend on test environment; synthetic workload may not reflect reality |

## Measurement Methodology

The standalone measurement script (`scripts/measure_overhead.py`) is completely
standalone — not part of the proxy, not in the test suite. It uses FastMCP `Client`
with `StdioTransport` to send MCP requests as real subprocesses, matching how the
proxy runs in production (Claude Desktop spawns it as a subprocess over STDIO).

The measurement is **external**: a client-side stopwatch (`time.perf_counter()`)
around `call_tool()` and `list_tools()`. No internal proxy instrumentation is needed
for this comparison. The Client doesn't know or care whether it's talking to a proxy
or a backend — it's just MCP over STDIO either way.

**Key methodology decisions:**
- **Warmup**: First N requests discarded (cold caches, lazy imports, policy first-parse).
- **Separate measurement**: Discovery (`tools/list`) and tool calls (`tools/call`)
  measured independently — they take different code paths. Discovery bypasses the
  policy engine entirely via `discovery_bypass` in middleware, so its overhead profile
  differs from tool calls which hit the full policy engine. Combining them into one
  number muddies the picture.
- **Same backend**: Identical backend used for both direct and proxied tests.
- **StdioTransport**: Reflects real deployment (subprocess IPC), not in-memory.
- **External timing**: Stopwatch is in the script, not inside the proxy.
- **Median (not average)**: Median better represents typical user experience and isn't
  skewed by outliers.

### Echo Backend

`scripts/echo_server.py` — minimal FastMCP server with a single `echo` tool that
returns its input. Near-zero processing time, near-zero variance. Gives the cleanest
overhead number because the measured difference is purely proxy processing + transport
overhead.

## Sample Size: Why 100 Runs

100 measured requests per operation type (after 10 warmup discards).

The main consideration is variance. With STDIO subprocess IPC, there is jitter from OS
scheduling and pipe buffering. 100 samples gives a reliable median (median is robust
against outliers), but stdev might still be noisy. If stdev comes out high relative to
the median (e.g., median 15ms but stdev 20ms), bumping to 200-500 would help stabilize.

For a thesis feasibility claim of "proxy adds ~Xms, not ~Xs", 100 is sufficient. We are
establishing order of magnitude, not optimizing. The script supports `--runs 200` if
results look unstable.

**Stability check**: If stdev exceeds ~50% of the median, results are likely too noisy
and should be re-run with more samples. All actual results had stdev/median ratios
between 6% and 29% — well within acceptable range (see `measurement-results.md`).

## Rate Limiter Modifications During Testing

Two separate rate limiters had to be dealt with during measurement.

### 1. FastMCP DoS Rate Limiter (RateLimitingMiddleware)

**What**: FastMCP's built-in `RateLimitingMiddleware` — limits global request rate to
10 requests/second with a burst capacity of 50. This sits at the outermost position in
the middleware stack: DoS → Context → Audit → ClientLogger → Enforcement.

**Problem**: The measurement script fires ~220 requests (warmup + discovery + tool calls)
as fast as possible, immediately blowing through the burst capacity. The limiter
**rejects** (not delays) excess requests, causing `McpError: Global rate limit exceeded`.

**Solution**: Added `--delay` parameter to `measure_overhead.py` (default: 0.12 seconds).
This throttle runs **between** requests but **outside** the timing window, so it does not
affect per-request latency measurements. At 0.12s delay, the request rate is ~8.3 req/s,
safely under the 10 req/s limit.

**Note**: The delay is only applied to **proxied** tests (which hit the DoS limiter).
Direct tests (Client -> Backend, no proxy) do not go through the rate limiter and use
no delay.

**Not modified**: The DoS rate limiter configuration itself was NOT changed. The delay
in the script was sufficient.

### 2. Session Rate Limiter (SessionRateTracker)

**What**: mcp-acp's own per-session rate tracker in
`src/mcp_acp/security/rate_limiter.py`. Tracks calls per tool per session using a
sliding window. When the threshold is exceeded, it triggers a HITL (Human-in-the-Loop)
approval dialog — the user must manually approve continuation.

**Configuration**: `DEFAULT_RATE_THRESHOLD = 30` calls per tool per
`DEFAULT_RATE_WINDOW_SECONDS = 60` second window.

**Problem**: After 30 `echo` tool calls in the 60-second window, the session rate limiter
triggered HITL approval prompts. During initial testing, the user had to manually approve
the prompts multiple times to complete the measurement run, which also interfered with
timing measurements.

**Solution**: Temporarily bumped `DEFAULT_RATE_THRESHOLD` from 30 to 500 in
`src/mcp_acp/security/rate_limiter.py` for the duration of the measurement runs.
Reverted to 30 after measurements were complete.

## STDIO Backend Test

### Command

```bash
python scripts/measure_overhead.py \
    --proxy-name echo-stdio \
    --backend-cmd ".venv/bin/python scripts/echo_server.py" \
    --output results/results_stdio.json
```

**Proxy**: `echo-stdio` — STDIO connection type, allow-all policy, full OIDC auth active.

### Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| Warmup | 10 | Discards cold cache, lazy imports, policy first-parse |
| Runs | 100 | Per operation type (discovery + tool call) |
| Delay (proxied) | 0.12s | Between requests, outside timing window |
| Delay (direct) | 0s | No rate limiter on direct backend path |
| Session rate threshold | 500 | Temporarily bumped from default 30 |

## HTTP Backend Test

### Command

```bash
# Start echo server first (in separate terminal)
.venv/bin/python scripts/echo_server.py --http --port 8766

# Run measurement
python scripts/measure_overhead.py \
    --proxy-name echo-http \
    --backend-url http://127.0.0.1:8766/mcp \
    --output results/results_http.json
```

**Proxy**: `echo-http` — HTTP connection type, same allow-all policy.

**Port note**: Port 8766 used instead of default 8765 because the mcp-acp manager was
already running on 8765.

### Parameters

Same as STDIO test (warmup 10, runs 100, delay 0.12s, session threshold 500).


## Filesystem Backend Tests (STDIO)

Two tests using a real-world MCP backend (cyanheads filesystem server, Node.js) to
validate that proxy overhead is consistent regardless of backend workload and to measure
the impact of policy complexity.

### Backend

`node <test-workspace>/filesystem-mcp-server/dist/index.js` — cyanheads
filesystem MCP server. Exposes 10 tools: `read_file`, `write_file`, `update_file`,
`list_files`, `copy_path`, `move_path`, `delete_file`, `delete_directory`,
`create_directory`, `set_filesystem_default`. Real filesystem I/O, not a synthetic echo.

### Test File

`/tmp/mcp-acp-test.txt` — 5 lines of text, ~200 bytes. Small size minimizes I/O
variance while exercising a real filesystem read path (open, read, close, UTF-8 decode).

### Test 3: Filesystem STDIO — Allow-All Policy

```bash
python scripts/measure_overhead.py \
    --proxy-name cyanheads \
    --backend-cmd "node <test-workspace>/filesystem-mcp-server/dist/index.js" \
    --tool read_file --tool-args '{"path": "/tmp/mcp-acp-test.txt"}' \
    --output results/results_fs_stdio.json
```

**Proxy**: `cyanheads` — STDIO connection type (auto-fallback from HTTP), allow-all policy.

**Policy**: `{"id":"allow-all","effect":"allow","conditions":{"tool_name":"*"}}`

**Parameters**: Same as echo tests (warmup 10, runs 100, delay 0.12s, session threshold 500).

### Test 4: Filesystem STDIO — Restrictive Multi-Rule Policy

Same command but with different output and a restrictive policy:

```bash
python scripts/measure_overhead.py \
    --proxy-name cyanheads \
    --backend-cmd "node <test-workspace>/filesystem-mcp-server/dist/index.js" \
    --tool read_file --tool-args '{"path": "/tmp/mcp-acp-test.txt"}' \
    --output results/results_fs_stdio_policy.json
```

**Policy** (4 rules with different condition types):
```json
{
  "version": "1",
  "default_action": "deny",
  "rules": [
    {"id": "allow-read-tmp", "effect": "allow", "conditions": {"tool_name": "read_file", "path_pattern": "/tmp/**"}},
    {"id": "allow-list-tmp", "effect": "allow", "conditions": {"tool_name": "list_files", "path_pattern": "/tmp/**"}},
    {"id": "deny-sensitive-extensions", "effect": "deny", "conditions": {"extension": [".key", ".pem", ".env"]}},
    {"id": "hitl-write-ops", "effect": "hitl", "conditions": {"operations": ["write", "delete"]}}
  ]
}
```

**Purpose**: Stress the policy engine with multiple rules containing different condition
types (tool name matching, glob patterns, extension lists, operation arrays). Measures
whether policy evaluation cost scales with rule count and complexity.

**What is and isn't tested**: The `read_file` call on `/tmp/mcp-acp-test.txt` matches
the `allow-read-tmp` rule. The deny and HITL rules are loaded and parsed by the engine,
but never matched — this test measures the cost of evaluating a larger rule set to find
an allow match, not the cost of deny or HITL decision paths. See "Allowed Path Only"
under Methodology Limitations for details.

**Parameters**: Same as Test 3.

### Test 5: Filesystem STDIO — 50-Rule Mixed Policy

Tests whether policy evaluation cost scales with rule count. 50 rules with mixed
condition types: allow rules with tool_name + path_pattern, deny rules with extension
lists, HITL rules with operations arrays. The engine evaluates all rules on every
request with no short-circuiting (confirmed by code inspection: `engine.py:260` uses
a list comprehension over all rules).

```bash
python scripts/measure_overhead.py \
    --proxy-name cyanheads \
    --backend-cmd "node <test-workspace>/filesystem-mcp-server/dist/index.js" \
    --tool read_file --tool-args '{"path": "/tmp/mcp-acp-test.txt"}' \
    --runs 50 --warmup 5 \
    --output results/results_fs_stdio_50rules.json
```

**Policy**: 50 rules — `allow-read-tmp` as rule 1 (matches the test call), plus 49
rules with varied effects and condition types. Full policy not preserved (generated
for this test only).

**Parameters**: Reduced sample size (50 runs, 5 warmup) since this is a scaling
comparison against the primary measurements, not a standalone measurement.

**What this tests**: Same `read_file` call as Tests 3–4. The matching rule is first in
the list, but rule position doesn't matter — the engine evaluates all 50 rules
regardless. The question is whether 50× the rule evaluation adds measurable overhead.

### Proxy Note: Auto-Fallback to STDIO

The `cyanheads` proxy is configured with `"transport": "auto"`, which tries HTTP first
(`http://localhost:3010/mcp`) and falls back to STDIO. During STDIO measurement, the HTTP
backend was not running, so the proxy fell back to STDIO after the 3 retry attempts
(~6s startup delay, not affecting measurement timing since it occurs during warmup).

## Filesystem Backend Tests (HTTP)

Same cyanheads filesystem server, accessed via HTTP instead of STDIO. The filesystem
server was started separately with `FS_BASE_DIRECTORY=/tmp` to allow access to the
test file.

### Test 5: Filesystem HTTP — Allow-All Policy

```bash
python scripts/measure_overhead.py \
    --proxy-name cyanheads \
    --backend-url http://localhost:3010/mcp \
    --tool read_file --tool-args '{"path": "/tmp/mcp-acp-test.txt"}' \
    --output results/results_fs_http.json
```

**Proxy**: `cyanheads` — HTTP connection type (auto-detected from running server), allow-all policy.

**Parameters**: Same as other tests (warmup 10, runs 100, delay 0.12s, session threshold 500).

### Test 6: Filesystem HTTP — Restrictive Multi-Rule Policy

```bash
python scripts/measure_overhead.py \
    --proxy-name cyanheads \
    --backend-url http://localhost:3010/mcp \
    --tool read_file --tool-args '{"path": "/tmp/mcp-acp-test.txt"}' \
    --output results/results_fs_http_policy.json
```

**Policy**: Same 4-rule restrictive policy as Test 4.

**Parameters**: Same as Test 5.

### Proxy Note: HTTP Transport

With the filesystem server running on `http://localhost:3010/mcp`, the `cyanheads` proxy's
auto-transport detected the HTTP backend and used `streamablehttp` transport (confirmed
in proxy startup output: `Backend transport: streamablehttp`).

## Known Issues During Testing

### Wrong mcp-acp Binary Path

**Problem**: The script originally used `command="mcp-acp"` for the proxy transport,
which resolved to a system-level installation using FastMCP 2.13.0.2 instead of the
venv's FastMCP 2.14.1. The MCP initialize handshake failed with
`McpError: Invalid request parameters`.

**Fix**: Derive the binary path from the running Python's venv:
```python
_MCP_ACP_CMD = str(Path(sys.executable).parent / "mcp-acp")
```

### Warning: tools/list Returned Unexpected Type

Both STDIO and HTTP proxied tests produce a harmless warning:
```
WARNING: tools/list returned unexpected type: list
```
This appears to be a FastMCP Client issue with how it handles the proxied response type.
It does not affect functionality or measurements.

### Config Path on macOS

The proxy configuration path on macOS is
`~/Library/Application Support/mcp-acp/proxies/<name>/`, not `~/.config/mcp-acp/` as
might be assumed from Linux conventions.

## Measurement Limitations

These factors could influence results but are out of scope for this POC evaluation.
Acknowledging limitations strengthens the methodology for thesis credibility.

### Environmental Factors (Not Controlled)

| Factor | Impact | Why Out of Scope |
|--------|--------|-----------------|
| **CPU load** | Other processes compete for CPU time, adding jitter | Single-machine dev setup; no isolated benchmark environment |
| **OS scheduling** | Context switches and thread scheduling add variance | Controlled environments require dedicated hardware |
| **Memory pressure** | GC pauses (Python) cause occasional latency spikes | Would require JVM-style GC tuning; Python GC is non-deterministic |
| **Disk I/O contention** | Filesystem backend latency varies with disk load | Relevant for filesystem tests; echo backend avoids this |
| **STDIO pipe buffering** | OS-level pipe buffers introduce micro-delays | Inherent to subprocess IPC; same in production |

### Methodology Limitations

| Limitation | Implication | Mitigation |
|------------|-------------|------------|
| **Sequential requests only** | No concurrent load; doesn't test contention | Matches typical MCP usage (single client per proxy) |
| **Single machine** | Client, proxy, and backend on same host | Eliminates network variance; matches STDIO deployment |
| **Small sample size** (N=100) | Limited statistical power | Sufficient for order-of-magnitude feasibility |
| **No confidence intervals** | Can't quantify measurement uncertainty | Would require larger N and statistical framework |
| **No percentile breakdown** | Only median reported; misses tail latency | Median is chosen metric for "typical experience" |
| **No coordinated omission awareness** | If proxy stalls, measurement loop waits, hiding queuing | Sequential requests partially mitigate this |
| **Warmup heuristic** (N=10) | May not fully warm all caches and lazy paths | Conservative; can increase if results show instability |
| **No cold-start measurement** | Only measures warm steady-state | Cold start is a one-time event; not relevant for ongoing overhead |
| **Allowed path only** | Only measures requests that are allowed by policy; deny and HITL decision paths are not measured | Denied requests short-circuit before the backend call, so overhead comparison (direct vs proxied) doesn't apply the same way. HITL requests block on human approval, which can't be automated in the measurement script. Denied-path overhead measurement is future work. |

### Architectural Simplifications

- **Single proxy, single backend**: No multi-proxy or load-balanced scenarios.
- **Limited policy complexity range**: Tested allow-all (1 rule) and restrictive (4 rules).
  Not tested: very large rule sets (50+ rules), deeply nested conditions, or regex-heavy patterns.
- **No mTLS overhead**: Default test config doesn't use client certificates.
- **Rate limiting adjusted**: Test load required rate limiter modifications (see above).
- **No concurrent client sessions**: One client connection at a time.
- **No resource consumption tracking**: CPU%, memory, file descriptor count not measured.

### Python-Specific Factors

- **CPython interpreter overhead**: GIL, reference counting, no JIT compilation.
- **Asyncio event loop scheduling**: Cooperative scheduling adds non-deterministic delays.
- **Import time and lazy initialization**: Partially mitigated by warmup phase.
- **`time.perf_counter()` resolution**: Sub-microsecond on modern OS; not a limiting factor.

### Transport-Specific Considerations

- **STDIO backend**: Subprocess IPC adds overhead not present in in-process testing.
  This is intentional — it matches production deployment via Claude Desktop.
- **HTTP backend**: Localhost networking removes real network latency. HTTP tests
  measure proxy processing + STDIO-to-HTTP transport bridging, not network costs.
- **Results are hardware-specific**: CPU speed, disk performance, OS version all affect
  absolute numbers. Relative overhead (proxied minus direct) is more meaningful.

### What Results Show vs. Don't Show

**Results demonstrate:**
- Order-of-magnitude feasibility: "proxy adds ~Xms, not ~Xs"
- Relative comparison: proxied overhead vs direct backend access
- Policy evaluation cost in isolation (from audit logs)
- Discovery vs tool call overhead separation (different middleware paths)
- Stability of results (low stdev relative to median)
- Backend independence: overhead is consistent across echo and real filesystem backends
- Policy complexity scaling: 4-rule restrictive policy adds ~4ms vs allow-all (STDIO)

**Results do NOT demonstrate:**
- Production performance under concurrent load
- Tail latency behavior (p95, p99)
- Performance degradation over time or under sustained load
- Resource consumption impact (CPU, memory, file descriptors)
- Multi-proxy or multi-backend scenarios
- Performance with very large policy rule sets (50+ rules)
- Overhead of denied or HITL decision paths (only allowed path measured)

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `scripts/echo_server.py` | Minimal echo backend (STDIO default, `--http` for HTTP) |
| `scripts/measure_overhead.py` | Standalone overhead measurement (direct vs proxied) |
| `scripts/parse_latency_logs.py` | Parses audit logs for `policy_eval_ms` and `policy_hitl_ms` |

Results are saved in `results/`.

## Proxy Configuration Reference

Both proxies were configured with:
- Auth: OIDC (production stack)
- Policy: Allow-all (`tool_name: *`)
- Config path: `~/Library/Application Support/mcp-acp/proxies/<name>/`
- Log path: `~/Library/Logs/mcp-acp/proxies/<name>/audit/decisions.jsonl`

### echo-stdio
- Connection type: STDIO
- Command: `.venv/bin/python scripts/echo_server.py`

### echo-http
- Connection type: HTTP
- URL: `http://127.0.0.1:8766/mcp`
- Backend must be started separately before measurement

### cyanheads
- Connection type: auto (STDIO fallback)
- STDIO command: `node <test-workspace>/filesystem-mcp-server/dist/index.js`
- HTTP URL: `http://localhost:3010/mcp`
- Backend: cyanheads filesystem MCP server (Node.js, 10 tools)
- Policy varied per test (allow-all and restrictive multi-rule)
