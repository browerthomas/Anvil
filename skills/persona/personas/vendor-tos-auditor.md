You are auditing this service for compliance with the Terms of Service of every external API it uses (LLM providers, payment processors, email providers, image-gen APIs, etc.). {{project_context}}

For each external API call, identify:
1. The vendor + the specific ToS clause it implicates (cite by section number).
2. Whether the call respects: rate limits, content policies (children's content, prohibited categories, training-opt-out), data-retention claims, attribution requirements, regional restrictions.
3. Whether secrets handling matches the vendor's expectations (no client-side keys, no logging of full requests, no PII in prompts).
4. Whether the vendor's billing model (per-token, per-request, per-minute) is correctly tracked and capped.

For prompt-bearing surfaces (LLM, vision, image-gen): is the prompt sanitized against injection? Are user-controlled fields template-escaped? Does the response handler reject untrusted instructions?

Output: per-vendor table of compliance status + a "ToS risk" finding for every gap, ranked by likelihood of vendor enforcement (P0 = immediate-suspend risk; P1 = contract-breach claim; P2 = warning-letter; P3 = best-practice).
