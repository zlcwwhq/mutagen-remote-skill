# Node discovery and commands

Run `remote --nodes` (or `--nodes --json`) from the source workspace. It lists
the nodes that the current node can reach, including paused or disconnected
ones, marks the current node and a star's center, and shows each node's host,
root, the synchronization mode of the edge to it, and availability: a node is
available when it executes commands and its edge is connected at both ends. It
never flushes or executes a command. A target shown as available can still
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
the same root are ambiguous and should become a star through the `setup`
skill with the user's authorization. Outside all roots, explicit `--node` or
`--nodes` requires one unambiguous source workspace on this system; commands
then use the destination root and skip its prologue.

`--session`, `-s`, `--sessions`, and `MUTAGEN_REMOTE_SESSION` are deprecated and
fail with 125. They do not select nodes or remain as aliases. Unset the variable
and migrate selectors to `--node`. Session identifiers stay internal.

## Stars

A star joins its center to every other node, each by its own synchronization
session, called an edge:

- From the center, `--node` selects any node. It can be omitted only if the
  star has a single other node.
- From any other node, omit `--node` (or name the center) to run on the
  center, or name another node to run on it through the center. `--nodes`
  lists such nodes with the center in their `path` (`through <center>` in text
  output).

An operation on the center, or from it, crosses one edge, which is an ordinary
pair session, and behaves as for a pair: the edge is flushed before and after
commands, conflicts produce warnings rather than preventing commands, and
detached jobs, `--no-flush`, `--flush`, `--pull`, `--diff`, `--ignores`,
`--progress`, and conflict resolution work as they do for pairs. An operation
depends only on its own edges: pausing, replacing, removing, or adding other
nodes doesn't affect it. While a node's edge isn't connected at the center,
such as while it reconnects, `--nodes` on the center shows the node as
unavailable and operations on it fail with 255; retry after a few seconds.
Keep the same `--node` for a job's start, wait, and kill, and for every
conflict operation.

An operation from one non-center node on another crosses both of their edges,
through the center:

- Before a command, the submitting node's edge is flushed and then the
  destination's; after it, the reverse, so the command sees local changes and
  its changes come back. `--wait` flushes as after a command, and `--flush`
  without a command does both, so it also fetches a finished job's files.
  Warnings name the edge they come from (`on the edge to the center <name>`
  or `on <node>'s edge with the center <name>`).
- Jobs, `--no-flush`, `--pull`, `--diff`, and `--ignores` work as on the
  center. Conflict operations fail with 125 and name where to run them: list
  and resolve the destination edge's conflicts from the center
  (`remote --node <name> --conflicts`) or tell the user, and this node's own
  edge's conflicts with plain `remote --conflicts`.
- One-way edges flow from the center only: a one-way submitting node's
  changes don't reach the destination, and a one-way destination's changes
  don't come back.

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

If `--nodes` prints `Star problem:` (JSON `problem`), the star's loaded
sessions disagree on the center's endpoint; the daemon refuses to create such
edges. Every new operation from or through the center then fails with 125,
whatever the target, while operations already in progress and the other nodes'
operations on the center keep using their own edges. Don't retry: tell the user
the reported problem; terminating the edge that disagrees and applying the
project again repairs it. A terminated edge only removes its node: `--nodes` no
longer lists it, and selecting it fails as an unknown node.
