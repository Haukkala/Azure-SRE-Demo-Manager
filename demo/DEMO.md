# Demo instructions

## Pre-demo checklist

Run through this before every customer demo — a stale environment or an unbuilt image will make
Chat 1/3 look broken even though the platform itself is fine:

- [ ] **Deploy/verify the environment.** `cd infrastructure && ./deploy.sh` completes with zero
      failed resources. If the resource groups were torn down since the last demo, this takes
      ~15-20 minutes end to end.
- [ ] **Build and push the real container image(s) to ACR.** Lisbon, Berlin, and Chaos Control
      currently run the placeholder `mcr.microsoft.com/azuredocs/containerapps-helloworld` image —
      see the warning below. Build and push the actual parking-api images before relying on the
      backend-validation or dependency-diagram chats for meaningful output.
- [ ] **Update `allowedSourceIpPrefix`** in `infrastructure/main.parameters.json` if your IP has
      changed since the last deploy, then redeploy — otherwise SSH/RDP to the VMs is blocked.
- [ ] **Verify the SRE Agent's resource mapping/discovery** reflects the current environment —
      re-run resource discovery in the SRE Agent console if the environment was redeployed or
      resource names changed (e.g. a new ACR/Storage account suffix after a from-scratch redeploy).

## Demo agenda (60 min)

> ⚠️ **Placeholder images in use.** Lisbon, Berlin, and Chaos Control container apps currently run
> the default `mcr.microsoft.com/azuredocs/containerapps-helloworld` demo image, not the real
> parking-api logic (see `infrastructure/DEPLOYMENT_CHANGES.md` for why). Their telemetry is real —
> Application Insights, dependency calls, response codes — but reflects a generic "hello world" app,
> not actual parking-availability logic. **Build and push the real container images before a
> customer demo**, or Chat 1 (backend validation) and Chat 3 (dependency diagram) will produce
> technically-correct-but-meaningless results.

- 15 min — What is Azure SRE? What Azure SRE is not.
  - Azure Docs
  - Azure SRE Console
    - Assigned resources
    - Monitor + resource mapping (requires Azure Log Analytics workspace)
    - One SRE per application
  - Settings
  - Daily Reports
  - Builder — Subagent builder to create custom agents
  - Scheduled tasks — Create a task with text and refine with AI

- 5 min — Demo app overview: use cases (Linux, Windows, App Insights, 3rd-party monitoring)

- 20 min — Azure SRE Chat Demo
  - Chat #1 — Generic — Daily Report + follow-up to validate backend APIs with available tools
  - Chat #2 — Alerts — Open alert, check results + create a GitHub issue
  - Chat #3 — App Dependencies — Understand application dependencies via telemetry
  - Chat #4 — Windows Logs (Madrid API)
  - Chat #5 — Linux Logs (Paris API) — **not available with the default config** (`deployParisVm=false`); Chat #4 covers the VM/OS-log scenario in full instead
  - Chat #6 — 3rd-party API — Assess Berlin API via MCP

## Chat 1 — Generic — Daily Report + backend validation

```prompt
Validate backend APIs for the Parking Manager application using Application Insights over the last 24h. Return a table by dependency target with: calls, failures, success rate (%), avg latency (ms), p95 (ms), max (ms). Highlight top 5 by failures and call out any >2s spikes.
```

## Chat 2 — Alerts — Open alert + create GitHub issue

```prompt
Use the learnings from this issue to create a GitHub issue on the connected repository and assign it to GitHub Copilot.
```

## Chat 3 — App Dependencies

```prompt
Generate a diagram for the application dependencies of the frontend app-parking-frontend-x6z6kgmn65dc4 from the backend APIs. Analyze Application Insights dependency telemetry of the last 24h to infer the backend APIs if required. The output should be a pretty visual Mermaid diagram with aggregatted total number of calls and average response time.

Generate a diagram for the application dependencies of the frontend app-parking-frontend from the backend APIs. Analyze Application Insights dependency telemetry of the last 24h to infer the backend APIs if required. The output should be a pretty visual Mermaid diagram with aggregated total number of calls and average response time.


Generate a diagram for the application dependencies of the frontend from the backend APIs. Analyze Application Insights dependency telemetry of the last 24h to infer the backend APIs if required. The output should be a pretty visual ASCII diagram.

Generate a Mermaid diagram with number of calls and average response time.
Summarize this in a table.
```

## Chat 4 — Madrid API (Windows Logs — Event Viewer)

Runs with the default configuration and demonstrates the full VM/OS-log scenario — use this as the
primary "non-containerized backend" chat while Paris (Chat 5) is disabled.

```prompt
Check Madrid API response status codes, errors and response time in the last 24h, including a summary of call per operation. Format the results in a visual table.

```

## Chat 5 — Paris API (Linux Logs — Syslog)

> **Not available with the default configuration.** Paris does not deploy by default
> (`deployParisVm=false` in `infrastructure/main.parameters.json` — see the root `README.md` for
> why). Use **Chat 4 (Madrid API / Windows Event Viewer)** instead; it covers the same VM/OS-log
> scenario end to end. Re-enable Paris (`deployParisVm=true`, then redeploy) if the Linux/Syslog
> scenario specifically is needed for a demo. The prompt below is kept for that case.

```prompt
Check Paris API response status codes, errors and response time in the last 24h.

Format the output results in a table.

Also check external dependencies status of Paris API in the last 24h and summarize the results in a table.
```

## Chat 6 — 3rd-party API — Berlin Park API assessment via MCP

```prompt
Please assess the Berlin Park API right now. Check health, latency, throughput, error rate, and availability for the last 60 minutes. Use SLO thresholds: p95 < 100 ms, error rate < 1%, availability ≥ 99.9%. Summarize results in one table with columns: Category | Metric | Value | Threshold | Status. Then add: 1) a 2–3 sentence summary, 2) key evidence with timestamps, 3) likely causes/hypotheses, 4) recommended actions, 5) follow-ups/requests. If SLOs are failing, clearly call it out. If any data is unavailable, state the gaps. Include the latest parking occupancy snapshot if available.
```

> **Tip**: Prompt quality matters. Azure SRE is backed by an LLM and benefits from precise, structured prompts.

```prompt
You are an observability assistant. Assess the Berlin Park API for the last 60 minutes.

Inputs:

SLOs: p95 latency < 100 ms; error rate < 1%; availability ≥ 99.9%
Metrics to compute/report: health, p95 latency (ms), throughput (requests/min and total), error rate (%), availability (%)
Also include: latest parking occupancy snapshot (total, available, occupied, % occupied, per-level if present)
Output format (strict):

First render a GitHub-flavored Markdown table with EXACT columns: | Category | Metric | Value | Threshold | Status |
Populate rows for Health, Latency (p95), Throughput, Error Rate, Availability.
Status must be one of: PASS, FAIL, INFO.
Use ISO8601 UTC timestamps where relevant in Value.
If a metric is unavailable, use N/A and explain in Data gaps later.
Do not include any text before the table.
Then add these sections in order:
Summary (2–3 sentences, concise, call out SLO breaches clearly if any)
Key evidence (bulleted list with timestamps and concrete values)
Likely causes/hypotheses (bulleted, 2–4 items)
Recommended actions (bulleted, prioritized, concrete)
Follow-ups/requests (bulleted)
Data gaps (bulleted; list any unavailable data)
Rules:

If any SLO is failing, add a single line "SLOs FAILING" immediately after the table.
No emojis. Keep numbers to 2 decimal places where applicable.
Use UTC timestamps (ISO8601).
Throughput row should show both rpm and total (e.g., "5 rpm (total 1,887)").
Example table header (use this exact header): | Category | Metric | Value | Threshold | Status |
```
