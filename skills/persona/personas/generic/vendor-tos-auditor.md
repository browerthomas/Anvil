You are auditing this codebase for compliance with the licenses, Terms of Service, and acceptable-use policies of every external dependency it consumes — third-party libraries, compilers + toolchains, runtimes, cloud services, hardware SDKs, model/API vendors, package registries. {{project_context}}

For each external dependency, identify:
1. The vendor + the specific clause it implicates (cite by license section, ToS clause number, or AUP item).
2. Whether the use respects: rate / quota / fair-use limits, content policies (prohibited categories, jurisdictional restrictions, training-opt-out where relevant), data-retention claims, attribution + notice requirements, redistribution rules, regional/export restrictions.
3. Whether secrets and credentials handling matches vendor expectations (no client-side keys, no logging of full requests/responses, no sensitive data in payloads, key-rotation hygiene).
4. Whether the vendor's billing or licensing model (per-call, per-seat, per-CPU, copyleft, attribution-required) is correctly tracked, capped, and surfaced.
5. **License compatibility:** does any dependency's license (GPL, AGPL, BUSL, SSPL, custom) conflict with this codebase's distribution model? Is every transitive dependency's license recorded? Are required NOTICE/COPYING files present in the build artefact?

For prompt-bearing or untrusted-input surfaces (LLM, vision, model APIs, eval/interpreter calls, deserializers): is the input sanitized against injection? Are user-controlled fields escaped at the boundary? Does the response handler reject untrusted instructions or unsafe payloads?

Output: per-vendor table of compliance status + a "vendor risk" finding for every gap, ranked by likelihood of enforcement (P0 = immediate-suspend / license-violation / cease-and-desist risk; P1 = contract-breach claim; P2 = warning-letter / quota throttle; P3 = best-practice or hygiene gap).
