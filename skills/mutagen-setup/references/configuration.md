# Writing `mutagen.yml`

A project file defines sessions under `sync` (and port forwarding under
`forward`). Settings directly under a session apply to both endpoints, those
under `configurationAlpha` or `configurationBeta` to one endpoint, and those
under `sync.defaults` to every session in the file. Ignore paths from all
levels are combined. Global settings in `~/.mutagen.yml` (`sync.defaults`) also
apply, unless `--no-global-configuration` is passed consistently to `project`
commands.

## Endpoint URLs

| Endpoint | Examples | Notes |
| --- | --- | --- |
| Local | `"."`, `"/data/project"` | Relative paths start at the directory containing `mutagen.yml` |
| SSH | `"gpu-box:~/project"`, `"user@host:2222:/srv/project"` | Uses the system's `ssh`, with `~/.ssh/config`; the port goes between host and path; relative paths start at the remote home |
| Docker | `"docker://dev/app"`, `"docker://user@dev/~/project"` | Uses the `docker` CLI and its environment (`DOCKER_HOST`, contexts); paths are absolute, or start with `~` after the container's slash |

## Modes

- `two-way-safe` (default): changes propagate both ways; a path changed on
  both sides becomes a conflict, which `remote --conflicts` can resolve. The
  usual choice with `remote`, since commands' outputs on beta come back.
- `two-way-resolved`: like `two-way-safe`, but alpha's version wins conflicts.
- `one-way-safe`: alpha's changes propagate to beta; beta's changes stay on
  beta and become conflicts if alpha changes the same path.
- `one-way-replica`: beta mirrors alpha exactly, overwriting or deleting
  anything that commands write on beta. Avoid it for directories where remote
  commands write outputs.

## Ignores

`ignore.paths` uses `.gitignore`-like patterns: `name` matches at any depth,
`/name` only at the root, a trailing `/` matches directories only, `*` and `**`
are wildcards, and `!pattern` re-includes. `ignore.vcs: true` ignores `.git`,
`.svn`, `.hg`, `.bzr`, and `_darcs`; omit it if beta needs the repository, and
then avoid running Git commands that write on beta. These include `git status`,
`git diff`, and `git describe --dirty`: Mutagen doesn't synchronize
modification times, so they rewrite `.git/index` to match beta's files, the
rewritten index synchronizes back, and concurrent rewrites on both sides
conflict (`GIT_OPTIONAL_LOCKS=0` prevents this for `git status` only).

Ignored paths aren't synchronized and keep a separate copy on each side, which
suits per-system build directories and virtual environments; `remote` refuses
to run in them unless given `--cwd .`, and `remote --pull` copies ignored
content from the other side on request.

Common candidates: `.venv/`, `node_modules/`, `__pycache__/`, `*.pyc`,
`.pytest_cache/`, `.mypy_cache/`, `build/`, `dist/`, `.DS_Store`, and large
data, checkpoint, or experiment-tracking directories such as `/data/` or
`wandb/`. Ask before ignoring anything that the user might expect on both
sides.

## Remote commands and prologues

`remote` names the endpoints that execute commands: `beta`, `alpha`, `true`
(both), or `false` (the default). A prologue is a POSIX shell script that the
executing endpoint sources before each command, such as to activate a conda
environment. Configure it per endpoint, since paths differ between systems.
Absolute and `~` paths are on the executing system, other paths are relative to
its root, and the script must exist there:

```yaml
sync:
  code:
    alpha: "."
    beta: "gpu-box:~/projects/myproject"
    remote: beta
    configurationBeta:
      remotePrologue: "~/.config/remote-prologue.sh"
```

```sh
# ~/.config/remote-prologue.sh on gpu-box
eval "$("$HOME/miniconda3/bin/conda" shell.posix hook)"
conda activate "${CONDA_ENV:-base}"
```

Find the paths on that system first (such as with
`ssh gpu-box 'ls ~/miniconda3/bin/conda ~/anaconda3/bin/conda'`), create the
script there, and apply the configuration. Alternatively, a
`.remote-prologue.sh` at the synchronization root, which is synchronized,
replaces the configured prologue on every executing endpoint without changing
the session; it can branch on `$MUTAGEN_REMOTE_ENDPOINT` (`alpha` or `beta`).
Prologues aren't supported on Windows endpoints.

## Several sessions

- Several directories, such as code and a large dataset synchronized
  differently, take one session each. If one root is nested in another, ignore
  the nested root in the outer session.
- One directory synchronized to several machines should use a workspace tree,
  so `remote --nodes` can discover named targets and `--node` can select one.
  Independent pairs sharing a source root are ambiguous.

## Workspace trees

On versions with `remote --help nodes`, one project can declare a tree of
directory workspaces. All endpoints must be reachable from the same daemon:

```yaml
tree:
  remote: true
  sync:
    mode: two-way-safe
    ignore:
      vcs: true
      paths: ["/mutagen.yml.lock", ".venv/", "__pycache__/"]
  nodes:
    local:
      endpoint: "."
    server:
      endpoint: "server:~/project"
      parent: local
    gpu:
      endpoint: "gpu:~/project"
      parent: server
      remotePrologue: "~/.config/gpu-prologue.sh"
```

There must be at least two nodes, exactly one root without a parent, and one
parent for each remaining node, with no cycles. Node names start with an ASCII
letter, contain letters, digits, or dashes, end with a letter or digit, and are
at most 63 characters; `defaults` is reserved. The root is structural and has
no priority in conflict resolution. Nodes represent directories, not whole
machines. Reject overlapping node directories and extra sessions overlapping
tree workspaces, even in another project. Host aliases and remote symlinks must
not give the same workspace multiple identities.

The project generates pair sessions named `tree-<child>`. Existing unchanged
edges retain their histories on `project apply`; changed edges are recreated
as usual. Each edge records its membership itself, not in labels, so it
persists across daemon restarts; `mutagen sync list -l` shows it.
When a node has retained edges, new or replaced edges reuse that node's retained
endpoint, including its captured Docker environment, to preserve its identity.
Shared settings under `tree.sync` extend global and `sync.defaults` settings,
but only `two-way-safe` is accepted. Pair-specific endpoint defaults don't
apply to nodes, and neither does `remotePrologue` from global or project
defaults. Set each node's
prologue there, and use `MUTAGEN_REMOTE_NODE` in shared scripts instead
of alpha/beta roles, which depend on the incident edge.

`tree.remote: true` explicitly authorizes commands **between all nodes**, not
just parent and child. It defaults to false regardless of pair defaults.
Confirm this authorization in the setup plan. Parents define synchronization
edges, not SSH jump hosts; configure daemon connectivity to each endpoint.

After previewing and applying the project, run from a node's directory:

```sh
remote --node gpu --timeout 30s pwd
```

This synchronizes the source-to-target path, executes on the target, then
synchronizes the path in reverse. Conflicts/problems prevent execution;
failure to synchronize back returns 125 even if the command succeeded. Use
`remote --node <target> --conflicts` to inspect a path, and resolve from an
edge's endpoint with `--node <peer>`. Job/file operations and conflict changes
require adjacent nodes. Tree detached job starts also require strict preflight.
`--no-flush` skips these synchronizations and their conflict checks.
Changing an unrelated, valid branch doesn't interrupt a running tree command
unless it closes the submission connection. Changing its path or introducing
a problem that makes the path unsafe interrupts it.
The tree
doesn't provide writer isolation or whole-tree atomic synchronization. See `remote --help nodes` for operational details.

## Changing the configuration later

Edit `mutagen.yml`, then preview and apply as in the main workflow:
`apply` recreates changed sessions and renamed ones. `mutagen project pause`
and `mutagen project resume` pause and resume all of the project's sessions,
and `mutagen project terminate` terminates them, leaving the files on both
endpoints in place.
