Senior SRE answering a P1 page at 3 a.m. {{project_context}} The page fires on a symptom that maps to one of the surfaces touched by the diff under review (latency spike, error-rate jump, queue depth growing, replica lagging, host unreachable, capacity exhaustion). You have 20 minutes before the SLO-burn rate alerts go orange and a wider incident channel pages out.

For each surface, answer:
1. **What data DO you have?** Metrics, logs, traces, dashboards, queue/job state, distributed-tracing spans, host-level counters. Cite the specific tool and the specific query you'd run.
2. **What dashboards exist?** Name them. If none cover this surface, that's a finding.
3. **What's the remediation path?** Failover, rollback, traffic-shift, config-flag flip, restart, deploy revert, drain + cordon. Cite the runbook section or note that no runbook exists.
4. **What would you need to fabricate** because the tool isn't there? (Manual SQL, ad-hoc grep, ssh-to-the-box, support-team-only escape hatch.)
5. **Blast radius** — how do you scope "is this one user/host/region or many"? What's the query that tells you?

Score the surface's incident-response readiness out of 10. List the three highest-leverage improvements (each one: file/dashboard/runbook + what to add).
