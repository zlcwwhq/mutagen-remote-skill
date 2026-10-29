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
- One directory synchronized to several machines should use a star, so
  `remote --nodes` can discover named targets and `--node` can select one.
  Independent pairs sharing a source root are ambiguous.

## Star workspaces

On versions whose `remote --help nodes` describes stars, one project can
declare a star of directory workspaces: a center node joined to every other
node by its own pair session. All endpoints must be reachable from the same
daemon:

```yaml
star:
  remote: true
  sync:
    ignore:
      vcs: true
      paths: ["/mutagen.yml.lock", ".venv/", "__pycache__/"]
  center: local
  nodes:
    local:
      endpoint: "."
    server:
      endpoint: "server:~/project"
    gpu:
      endpoint: "gpu:~/project"
      mode: one-way-safe
      remotePrologue: "~/.config/gpu-prologue.sh"
```

`center` is required and names one of the nodes, and there must be at least one
other node. Any node can be the center, with any endpoint type, but only the
center reaches every node with `remote`; every other node reaches only the
center. Choose the center with the user: usually where they work and their
agents run, such as the project directory on the daemon's system. A center on
another system works too; the daemon then relays its edges as it relays a pair
whose endpoints are both remote. Node names start with an ASCII letter,
contain letters, digits, or dashes, end with a letter or digit, and are at
most 63 characters; `defaults` is reserved. Nodes represent directories, not
whole machines. Reject overlapping node directories and extra sessions
overlapping star workspaces, even in another project. Host aliases and remote
symlinks must not give the same workspace multiple identities.

The project generates one pair session per non-center node, named
`star-<node>`, with the center as alpha and the node as beta. Existing
unchanged edges retain their histories on `project apply`; changed edges are
recreated as usual. Each edge records its membership itself, not in labels, so
it persists across daemon restarts; `mutagen sync list -l` shows it. New or
replaced edges reuse the center's endpoint from the retained edges, including
its captured Docker environment, to preserve its identity. If retained edges
disagree on it, `apply` fails and names them; with the user's consent,
terminate one of them and apply again.

Shared settings under `star.sync` extend global and `sync.defaults` settings,
including ignores. A non-center node's `mode` sets the mode of its own edge,
overriding `star.sync.mode` and the defaults; edges use `two-way-safe` if
nothing sets a mode. `mode` can't be set on the center. The center is alpha on
every edge, so it wins conflicts in `two-way-resolved` mode, and one-way modes
flow from the center to the node: the node's changes, including command
outputs, don't reach the center. Pair-specific endpoint defaults don't apply,
and neither do `remote` and `remotePrologue` from global or project defaults,
which `star.sync` can't set either. Set each node's prologue on the node,
including the center's, and use `MUTAGEN_REMOTE_NODE` in shared scripts, such
as `.remote-prologue.sh`, instead of alpha/beta roles.

`star.remote: true` explicitly authorizes commands between the center and every
other node, in both directions. It defaults to false regardless of pair
defaults. Confirm this authorization, and the choice of center, in the setup
plan. Configure daemon connectivity to each endpoint; nodes needn't reach each
other.

After previewing and applying the project, run from the center's directory:

```sh
remote --nodes
remote --node gpu --timeout 30s pwd
```

Every command crosses one edge and behaves as for a pair: the edge is flushed
before and after it, and conflicts produce warnings rather than preventing it.
From another node, `remote pwd` runs on the center, and commands for another
non-center node fail with 125, since stars have no multi-hop routes. If
`remote --nodes` reports a star problem, the edges disagree on the center's
endpoint, such as after a partially applied project: apply the project again.
See `remote --help nodes` for operational details.

### Migrating from workspace trees

Releases with stars refuse project files that declare `tree:`, which earlier
releases used for workspace trees. With the user's consent:

1. Replace `tree:` with `star:`, remove each node's `parent`, and add `center:`
   naming a node, usually the former root, where the user works. Settings
   under `tree.sync` move to `star.sync`.
2. Preview with `mutagen project apply --dry-run`, then apply. This removes
   the `tree-<node>` sessions, flushing running ones first, and creates
   `star-<node>` sessions, which start with fresh synchronization history, so
   prepare as for a first synchronization (step 4 of the main workflow).
3. Tell the user that commands between two non-center nodes no longer exist,
   and that star commands warn about conflicts instead of refusing to run.

## Changing the configuration later

Edit `mutagen.yml`, then preview and apply as in the main workflow:
`apply` recreates changed sessions and renamed ones. `mutagen project pause`
and `mutagen project resume` pause and resume all of the project's sessions,
and `mutagen project terminate` terminates them, leaving the files on both
endpoints in place.
