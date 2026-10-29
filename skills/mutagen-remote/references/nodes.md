# Node discovery and commands

Run `remote --nodes` (or `--nodes --json`) from the source workspace. It lists
the nodes that the current node can reach, including paused or disconnected
ones, marks the current node and a star's center, and shows each node's host,
root, the synchronization mode of the edge to it, and connection availability.
It never flushes or executes a command. A target shown as available can still
have conflicts or fail synchronization.

```sh
remote --nodes
remote --node gpu --timeout 5m pytest -x    # from the center
remote --node gpu --conflicts               # from the center
remote make test                            # from gpu: runs on the center
```

Node names are scoped to the source workspace. Declared stars use configured
names; standalone pairs use `alpha` and `beta`. Omit `--node` only when there
is exactly one other node, counting offline nodes. Independent pairs sharing
the same root are ambiguous and should become a star through `mutagen-setup`
with the user's authorization. Outside all roots, explicit `--node` or
`--nodes` requires one unambiguous source workspace on this system; commands
then use the destination root and skip its prologue.

`--session`, `-s`, `--sessions`, and `MUTAGEN_REMOTE_SESSION` are deprecated and
fail with 125. They do not select nodes or remain as aliases. Unset the variable
and migrate selectors to `--node`. Session identifiers stay internal.

## Stars

A star joins its center to every other node, each by its own synchronization
session, called an edge. Only the center reaches every node:

- From the center, `--node` selects any node. It can be omitted only if the
  star has a single other node.
- From any other node, the center is the only destination, so omit `--node`
  or name the center. Selecting another node fails with 125 and
  `stars have no multi-hop`, naming the center. Run such commands from the
  center, or tell the user that the command needs to run there.

Every operation crosses exactly one edge, which is an ordinary pair session,
and behaves as for a pair: the edge is flushed before and after commands,
conflicts produce warnings rather than preventing commands, and detached jobs,
`--no-flush`, `--flush`, `--pull`, `--diff`, `--ignores`, `--progress`, and
conflict resolution work as they do for pairs. Keep the same `--node` for a
job's start, wait, and kill, and for every conflict operation.

- Each non-center node's mode configures its own edge, shown by `--nodes`.
  The center is alpha on every edge, so it wins conflicts in
  `two-way-resolved` mode. One-way modes flow from the center to the node:
  changes made on such a node, including files that commands write there,
  don't reach the center. Read such outputs with `remote --node <name> cat
  <path>` from the center, or tell the user.
- Working directories map relative to source/target roots. `--cwd` overrides
  the target directory; ignored content still isn't synchronized.
- Commands use the target node's prologue or workspace override.
  `MUTAGEN_REMOTE_NODE` identifies the target and overrides submitted values.
  Use it in scripts shared by several nodes: `MUTAGEN_REMOTE_ENDPOINT` is
  `alpha` on the center and `beta` on every other node.
- `--conflicts --json` returns an `edges` array with a single entry, which
  contains `alpha`, `beta`, `source`, `target`, and `listing`. Local and remote
  changes in the listing belong to that entry's source and target.
- A saved checkout can be discarded outside the roots without a target: its
  metadata identifies its owner. An explicit different node pair is refused.

## Star problems

If `--nodes` prints `Star problem:` (JSON `problem`), the star's sessions
disagree on the center's endpoint, for example after a partially applied
project. Every operation from the center then fails with 125, whatever the
target, while the other nodes keep using their own edges to the center. Don't
retry: tell the user the reported problem; applying the project again usually
repairs it. A terminated edge only removes its node: `--nodes` no longer
lists it, and selecting it fails as an unknown node.
