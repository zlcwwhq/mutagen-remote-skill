# Node discovery and commands

Run `remote --nodes` (or `--nodes --json`) from the source workspace. It shows
all configured nodes, including offline members, the current node, each path,
and connection availability. It never flushes or executes a command. A target
shown as available can still have conflicts or fail synchronization.

```sh
remote --nodes
remote --node gpu --timeout 5m pytest -x
remote --node gpu --conflicts
```

Node names are scoped to the source graph. Declared trees use configured names;
standalone pairs use `alpha` and `beta`. Omit `--node` only when there is exactly
one other node, counting offline nodes. Independent pairs sharing the same
root are ambiguous and should become a tree through `mutagen-setup` with the
user's authorization. Outside all roots, explicit `--node` or `--nodes`
requires one unambiguous source workspace on this system; commands then use
the destination root and skip its prologue.

`--session`, `-s`, `--sessions`, and `MUTAGEN_REMOTE_SESSION` are deprecated and
fail with 125. They do not select nodes or remain as aliases. Unset the variable
and migrate selectors to `--node`. Session identifiers stay internal.

For foreground commands/scripts in a tree, the daemon synchronizes the unique
source-to-target path, executes directly on the target, then synchronizes in
reverse. Any conflict, scan/transition problem, or failed preflight prevents
execution. `--no-flush` is rejected. Other branches needn't finish for this
invocation. This isn't a snapshot or isolation from concurrent writers.

If synchronization back fails after execution, `remote` returns 125 and reports
the command's exit status and failed edge. **The command already ran.** Timeout
(124), connection loss (255), and interruption can also leave results on the
target. Inspect before retrying side effects. A topology change after discovery
refuses the stale selection; an active tree call is interrupted if its topology,
path, or submission connection is lost. No automatic rerouting or retry occurs.

`remote --node <target> --conflicts` inspects a multi-edge path and identifies
the actual adjacent node pair for each conflict. Paths are relative to those
roots. To resolve `server <-> gpu`, operate from server with `--node gpu`, or
from gpu with `--node server`, after reading [conflicts.md](conflicts.md).
Do not treat copies separated by intermediate nodes as a resolvable pair.

- Foreground commands, scripts, and conflict inspection can span a path.
- Jobs, diff/pull, explicit flush, and conflict checkout/apply/discard require
  an adjacent target. Keep the same `--node` for a job's start/wait/kill.
- A saved checkout can be discarded outside the roots without a target: its
  metadata identifies its owner. An explicit different node pair is refused.
- Working directories map relative to source/target roots. `--cwd` overrides
  the target directory; ignored content still isn't synchronized.
- Commands use the target node's prologue or workspace override.
  `MUTAGEN_REMOTE_NODE` identifies the target and overrides submitted values;
  alpha/beta edge roles can vary for an internal tree node.
- `--progress` shows tree synchronization edges as they begin; `--timeout`
  includes both synchronization phases and execution.
