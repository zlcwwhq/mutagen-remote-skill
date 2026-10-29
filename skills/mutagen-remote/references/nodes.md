# Node discovery and commands

Run `remote --nodes` (or `--nodes --json`) from the source workspace. It shows
all configured nodes, including offline members, the current node, each path,
and connection availability. It never flushes or executes a command. A target
shown as available can still have conflicts or fail synchronization. In JSON,
`adjacent` marks a neighbor whose own edge is connected.

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
execution. Other branches needn't finish for this invocation. This isn't a
snapshot or isolation from concurrent writers. Tree `--detach` also requires
strict preflight on its adjacent edge; conflicts or synchronization failures
prevent the job from starting. Use `--wait` or background synchronization for
its later results.

`--no-flush` skips both path synchronizations and their checks, so a command
runs even while path edges have conflicts. It neither synchronizes nor waits
for synchronization; background synchronization continues, but conflicts,
paused or disconnected edges, or disabled watching can keep its changes from
propagating. As for pairs, use it only for commands that read and write no
synced files, such as `nvidia-smi` or reading an ignored log; this also
inspects a target while a conflict refuses other commands. The tree must
still be valid and the path connected.

If synchronization back fails after execution, `remote` returns 125 and reports
the command's exit status and failed edge. **The command already ran.** Timeout
(124), connection loss (255), and interruption can also leave results on the
target. Inspect before retrying side effects. An active tree call is interrupted
if a path edge is replaced, a path or submission connection is lost, or a new
problem makes its path unsafe. Changes to unrelated, valid branches don't
cancel it unless they close the connection carrying the submission.
No automatic rerouting or retry occurs.

`remote --node <target> --conflicts` inspects a multi-edge path and identifies
the actual adjacent node pair for each conflict. Paths on the first edge, which
is adjacent, are relative to your current directory, as for pairs; paths on
later edges are relative to their roots, so don't use them from here. To
resolve `server <-> gpu`, operate from server with `--node gpu`, or from gpu
with `--node server`: list the conflicts again there and use those paths, after
reading [conflicts.md](conflicts.md). Do not treat copies separated by
intermediate nodes as a resolvable pair.
`--conflicts --json` always returns an `edges` array, even for an adjacent
destination or implicit pair. Each entry contains `alpha`, `beta`, `source`,
`target`, and `listing`. Local and remote changes in the listing belong to
that entry's source and target, which may be intermediate nodes.

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
- `--progress` uses the same delayed progress display for tree and pair
  synchronization, with edge context for tree paths; `--timeout` includes
  both synchronization phases and execution.

## Tree problems

If `--nodes` prints `Tree problem:` (JSON `problem`), the tree's sessions no
longer form the configured tree, for example after an edge was terminated or a
project apply partially failed, or another session overlaps a node. Every tree
command and path conflict listing then fails with 125, whatever the target.
Don't retry: tell the user the reported problem; applying the project again
usually repairs it. Meanwhile, operations on adjacent nodes still work over
connected edges (`adjacent` in JSON): `--jobs`, `--wait`, `--kill`,
conflicts, `--diff`, `--pull`, `--flush`, and `--ignores`. Starting a new detached
job still fails, even with `--no-flush`. Use these operations
to check on running jobs or resolve conflicts, not to run work that relies on
synchronization along the rest of the tree. `--node` stays required when the
graph lists more than one other node.
