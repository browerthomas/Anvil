# anvil — installable groups

Anvil ships as three composable plugin groups + a meta-bundle. Pick what you need.

```
groups/
├── core/                  # anvil-core      → 3 skills (everyday helpers)
├── pr/                    # anvil-pr        → 3 skills (per-PR cycle)
└── orchestrator/          # anvil-orchestrator → 2 skills (end-to-end driver)
```

The top-level `.claude-plugin/plugin.json` (one directory up) is the meta-bundle that installs all 8 skills — the simplest path for new users.

## Why groups?

Different operators want different surface area:

- **Just want cleanup + recap?** `anvil-core` is enough.
- **Already have a workflow but want the gate?** `anvil-pr` slots in without the orchestrator.
- **Want the full plan-to-merged-PR drive?** `anvil-orchestrator` (which composes the other two).

Each group has its own marketplace identity, so you discover and install the slice that matches your need.

## Group composition

```
                 anvil-orchestrator
                 ┌──────────────┐
                 │ /spec /grind │
                 └──────┬───────┘
                        │ composes
                        ▼
                    anvil-pr
        ┌──────────────────────────────┐
        │ /dispatch-slice              │
        │ /pre-merge-gate              │
        │ /auto-merge                  │
        └──────────────┬───────────────┘
                       │ composes
                       ▼
                   anvil-core
        ┌──────────────────────────────┐
        │ /sweep-worktrees             │
        │ /self-review                 │
        │ /recap                       │
        └──────────────────────────────┘
```

Higher groups recommend lower groups but don't require them — `anvil-orchestrator` works standalone if you have your own equivalents of `/dispatch-slice` etc, but you'll get the best experience by installing the lower groups too.

## Install

### Symlink mode (development)

```bash
~/Desktop/anvil/bin/install.sh                        # all 8 skills (meta-bundle)
~/Desktop/anvil/bin/install.sh --group core           # just anvil-core (3 skills)
~/Desktop/anvil/bin/install.sh --group pr             # just anvil-pr (3 skills)
~/Desktop/anvil/bin/install.sh --group orchestrator   # just anvil-orchestrator (2 skills)
```

### Marketplace install (when published)

```
/plugin install anvil              # meta-bundle, all 8 skills
/plugin install anvil-core         # 3 skills only
/plugin install anvil-pr           # 3 skills only
/plugin install anvil-orchestrator # 2 skills only
```

## Uninstall

`bin/uninstall.sh` removes ALL anvil-installed skills regardless of which group they came from. To remove just one group, delete the specific skill symlinks/copies under `~/.claude/skills/`:

```bash
# remove just anvil-pr
rm ~/.claude/skills/{dispatch-slice,pre-merge-gate,auto-merge}
```

## Why not split the repo?

Considered: separate repos per group. Rejected because:
1. The skills share `shared/lib.sh` — keeping them in one repo avoids duplication.
2. The plan template + examples + landing page belong with the orchestrator group; splitting them across repos fragments documentation.
3. A monorepo with per-group manifests gets us marketplace-level composability without the publishing overhead.

If a group ever grows enough to deserve its own repo, the manifests here become independent — easy to extract.
