# Template overrides

Anvil ships canonical templates under `templates/` (e.g. `plan-template.md`, `plan-folder-template/`). Adopting projects often want a customised plan shape — extra required sections, a stricter validation checklist, project-specific slice tags. Forking anvil for that is overkill. Instead, anvil resolves templates through a **2-layer hierarchy** and lets each project drop a local override without touching the install.

## How it works

The shared helper `av_resolve_template <name>` (in `shared/lib.sh`) searches in this order:

1. **Project override:** `${PWD}/.anvil/templates/overrides/<name>`
2. **Core default:** `$(av_anvil_root)/templates/<name>`

First hit wins. The function prints the absolute path on stdout and exits 0. Callers `cat` the resolved path.

Refusals:

- Missing argument — exit non-zero, stderr: `av_resolve_template: missing template name argument`.
- Path traversal in `<name>` (leading `/`, any `..` segment, backslash) — exit non-zero, stderr: `av_resolve_template: refusing path traversal in <name>`. The check runs **before** any filesystem access.
- Name not found at any layer — exit non-zero, stderr: `av_resolve_template: <name> not found (project: <path>, core: <path>)` so the operator can see which paths were searched.

The resolver reuses anvil's existing `av_anvil_root()` and the canonical `ANVIL_ROOT` env var. It does **not** introduce a new `ANVIL_HOME` variable — `ANVIL_HOME` is already in use across `bin/` with a different meaning (Claude install dir fallback). Don't conflate them.

## Why no preset layer?

Spec-kit (anvil's nearest analogue) ships a 3-layer resolver: project → preset → core. Anvil deliberately stops at 2 layers in v1:

- The preset layer assumes an extension ecosystem (community-shipped preset packs that adopting projects pick from). Anvil doesn't have one yet — shipping the layer preemptively would produce dead documentation and an unexercised code path.
- Promoting to 3 layers is a one-function edit once a real preset use-case appears.
- 2 layers cover 100% of real customisation today: a project either uses anvil's defaults or overrides them locally.

If a preset use-case materialises, file an issue with the concrete pack + adopter motivating it; the resolver's contract leaves room to insert a `${HOME}/.anvil/presets/templates/<name>` layer between project and core without breaking callers.

## Worked example — customise the flat plan template

Suppose your project wants every flat-layout plan to carry a "Compliance" section between Goal and Scope. Copy the canonical template into the project override slot, edit it, commit:

```bash
# From the project root
mkdir -p .anvil/templates/overrides
cp "$(av_anvil_root)/templates/plan-template.md" \
   .anvil/templates/overrides/plan-template.md
$EDITOR .anvil/templates/overrides/plan-template.md
git add .anvil/templates/overrides/plan-template.md
git commit -m "chore(plans): override plan template with Compliance section"
```

From now on, every `/spec` invocation in this project loads the override. Other projects (or operators who clone fresh) still get anvil's default.

Verify the resolver picks up the override:

```bash
source shared/lib.sh   # or wherever lib.sh lives relative to your cwd
av_resolve_template plan-template.md
# -> /path/to/your-project/.anvil/templates/overrides/plan-template.md
```

Delete the override file to fall back to the core default:

```bash
rm .anvil/templates/overrides/plan-template.md
av_resolve_template plan-template.md
# -> /path/to/anvil/templates/plan-template.md
```

## Worked example — override one file inside the folder template

The folder-layout template lives under `templates/plan-folder-template/`. Override individual files by mirroring the path:

```bash
mkdir -p .anvil/templates/overrides/plan-folder-template
cp "$(av_anvil_root)/templates/plan-folder-template/tasks.md" \
   .anvil/templates/overrides/plan-folder-template/tasks.md
# customise, commit, done.
```

Callers resolve via `av_resolve_template plan-folder-template/tasks.md`. The override wins; the other files in the folder still resolve from core.

## Caveats

- The resolver only finds templates anvil already knows the name of. Adding a brand-new template kind (one core never shipped) means shipping it in `templates/` first.
- Override files inherit anvil's licence semantics — they live in your project repo, so the licence is whatever your project uses.
- Don't override files that aren't templates (`shared/lib.sh`, `bin/*.sh`). The override resolver only searches under `templates/overrides/`.
