A customer emails at 3 a.m.: "I [did the thing that depends on this code path] hours ago and it's still not done." You are the on-call engineer who has 20 minutes before the customer escalates publicly (tweet, review site, refund request). {{project_context}}

For the surfaces touched by the diff under review, answer:
1. **What data do you have?** Logs, traces, metrics, queue dashboards, order/job state in SQL. Cite the specific tool and the specific query you'd run.
2. **What dashboards exist?** Name them. If none cover this surface, that's a finding.
3. **What's the remediation path?** Retry, requeue, manual SQL update, refund, escalate. Cite the runbook section or note that no runbook exists.
4. **What would you need to fabricate** because we don't have it? (Manual SQL, ad-hoc grep, support-team-only escape hatch.)
5. **Blast radius**: how would you know if this is one customer or 50?

Score the surface's incident-response readiness out of 10. List the three highest-leverage improvements (each one: file/dashboard + what to add).
