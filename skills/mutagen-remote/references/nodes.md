# Workspace tree commands

Run from inside a node's workspace and select the destination explicitly:

```sh
remote --node gpu --timeout 5m pytest -x
remote --node server --script - <<'EOF'
make test
EOF
```

Node names belong to one project. The current directory identifies the source;
`MUTAGEN_REMOTE_SESSION` does not select it. Ambiguous sources, unknown nodes,
and selecting the current node are errors. Ask the user or use `mutagen-setup`
if the tree needs configuration; don't change sessions from this skill.

The daemon synchronizes the unique source-to-target path in order, executes
directly on the target, then synchronizes the path in reverse. A conflict,
scan/transition problem, or failed preflight prevents the command from
starting. Other branches continue background synchronization; they needn't
finish for this invocation. This is not a snapshot or isolation from concurrent
writers. Keep source edits on one node where possible.

If synchronization back fails after execution, `remote` returns 125 and reports
the command's exit status and the failed edge. **The command already ran.**
Inspect its results and resolve the synchronization problem before deciding to
retry; never automatically repeat a command with side effects. Timeout (124),
connection loss (255), and interruption can also leave results on the target.
Pausing/disconnecting a path endpoint or changing tree membership interrupts
active calls; external session creation/removal can also invalidate them.
Reconnection doesn't redirect or retry an invocation.

Use the reported edge's `remote --session <name-or-id> --conflicts` from one of
its endpoints to inspect conflicts, and read [conflicts.md](conflicts.md)
before resolving them. For an edge that isn't attached to the current node,
ask the user to inspect it from an endpoint; don't assume `--session` routes
across the tree.

- Working directories map relative to node roots. `--cwd` overrides the target
  directory as for pair commands; ignored content still isn't synchronized.
- Commands use the target node's prologue or `.remote-prologue.sh` override.
  `MUTAGEN_REMOTE_NODE` is the stable target identity and overrides submitted
  values. Alpha/beta roles can differ between incident edges.
- `--progress` prints edges as synchronization begins. `--timeout` covers both
  synchronization phases and execution.
- `--node` supports foreground commands and scripts only. Don't combine it
  with `--session`, `--no-flush`, `--flush`, detached jobs, diff/pull, or conflict
  operations. Existing pair commands retain their original behavior.
