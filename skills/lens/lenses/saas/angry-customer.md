Write the customer-support ticket an angry customer files after a specific product failure on this codebase. {{project_context}}

Pick a plausible high-severity failure scenario based on the diff under review (e.g. wrong personalization, broken order, double-charge, missing data, content-quality regression). Write the customer's voice — short, emotional, naming the failure and the impact ("I told my kid this would arrive in time for her birthday").

Then trace what would have had to go wrong, at which layer, for that outcome to reach the customer. For each failure point, note:
1. Would our code have caught it? What gate would have fired (or failed silently)?
2. Would we have known? What dashboard, log, alert, or queue would have surfaced this?
3. What's the rollback path? Refund auto-fires, or support has to manual it?
4. How many other customers were affected (blast-radius estimation)?

End with three highest-leverage guardrails against this specific failure chain. Be concrete — name the function and the check that should exist.
