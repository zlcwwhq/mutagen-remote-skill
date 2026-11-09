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
are wildcards, and `!pattern` re-includes. For a Git repository, use
[Git mode](#git-mode), which reads `.gitignore` files and replaces
`ignore.vcs`. Otherwise, `ignore.vcs: true` ignores `.git`, `.svn`, `.hg`,
`.bzr`, and `_darcs`; omit it if beta needs the repository, and then avoid
running Git commands that write on beta. These include `git status`,
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

## Git mode

On releases that support it (`mutagen sync create --help` lists `--git`), a
Git repository should use `git: enabled` (`--git` for `mutagen sync create`)
under the session, `sync.defaults`, or `star.sync`, instead of `ignore.vcs:
true` and `ignore.paths` that repeat `.gitignore`. It applies to the whole
session (not per endpoint) and implies `ignore.vcs: true`; combining it with
`ignore.vcs: false` (`--no-ignore-vcs`) is an error.

- **Ignores**: the rules of `.gitignore` files at every level beneath the root
  and of the root repository's `.git/info/exclude` apply, case-sensitively,
  but not global excludes or files above the root. Inside a nested repository,
  only its own `.gitignore` files and exclude file apply, as for Git run in it. Each endpoint reads its
  own copy, so put shared ignores in `.gitignore`: `.git/info/exclude` exists
  only where the repository does. `ignore.paths` takes precedence, so
  `!.env` synchronizes a file that `.gitignore` ignores. `.git` entries (files
  too) are never synchronized and can't be unignored, so the other side has no
  superproject repository. Rules follow Git 2.52 and later; older versions of
  Git treat patterns like `foo**/bar` differently.
- **What an endpoint receives**: an endpoint applies its own rules here too,
  including to paths that it doesn't have yet. An excluded path isn't written
  and is reported as a warning, while the rest of its directory still arrives,
  and so do `.gitignore` files themselves. So a `.git/info/exclude` on one
  endpoint keeps the other endpoint's copies of what it excludes away.
- **Tracked files that `.gitignore` ignores** aren't synchronized, and the
  endpoint with the repository reports a problem that suggests the pattern to
  unignore them (`!path`, or `!directory` for a file inside an ignored
  directory). Adding a rule later never deletes files that were synchronized.
- **One-way-replica** keeps content on beta that beta's rules ignored until a
  change of rules exposed it (the session removing a `.gitignore` that only
  beta had, alpha removing a rule, or an edit of beta's `.git/info/exclude`),
  and beta reports a problem until it's deleted, identical to alpha's, or
  ignored again. Put ignores that only beta needs in its `.git/info/exclude`.
- **Submodules** (nested repositories with a commit checked out and an
  origin) have their files synchronized, uncommitted changes included, but not
  their `.git`, so branches and unpushed commits stay on the endpoint that has
  them. Each endpoint follows the commit that the other checks out, fetching it
  from the origin in the background, so both systems need `git` (2.29 or
  later), network access, and read access to the submodules' repositories, and
  commits have to be pushed. Origins have to be `https`, `http`, `ssh`
  (including `host:path`), or `git` URLs: a submodule whose origin is a local
  path or a `file://` URL can't be cloned or fetched from. An endpoint without
  a submodule gets a clone. If
  both check out different commits, two-way-safe sessions synchronize nothing
  in the submodule until they agree (`remote --conflicts` lists it), and
  two-way-resolved sessions follow alpha's commit. Deleting a submodule isn't
  synchronized. Existing checkouts need the same line ending settings, or line
  endings pinned in `.gitattributes`, since their text files otherwise
  conflict. Other nested repositories are synchronized as ordinary
  directories, without their `.git`.
- **Problems that stop synchronization**: a rule file that can't be read keeps
  its directory from being synchronized until it's fixed. A `.gitignore` that
  can't be written on an endpoint stops everything else in the session until
  it's fixed, because a cycle that has rule files to deliver does only that. This
  is what keeps files that new rules ignore from being copied or deleted before
  the rules arrive.

### Moving a session from `ignore.vcs` to Git mode

With the user's consent: in `mutagen.yml`, replace `ignore: vcs: true` with
`git: enabled` and remove the `ignore.paths` that repeat `.gitignore` files,
then preview and apply. The session is recreated with fresh synchronization
history (prepare as for a first synchronization, step 4 of the main workflow).

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
    git: enabled
    ignore:
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
whole machines, and must not overlap one another, including the center: the
daemon refuses such edges, and `project start` and `apply` refuse such
declarations, as well as sessions in the same project file that overlap star
workspaces. Sessions of other projects, or created with `mutagen sync create`,
aren't checked; don't plan them to overlap star workspaces, since they behave
like overlapping pairs: changes propagate through both sessions, and the most
specific workspace containing a directory is the source for `remote`.
Detection can't see through host aliases or remote symlinks, so they must not
give the same workspace multiple identities.

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
including ignores and `git`, which nodes can't set. A non-center node's `mode` sets the mode of its own edge,
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
`remote --nodes` reports a star problem, the star's loaded edges disagree on
the center's endpoint, which the daemon refuses when creating edges: with the
user's consent, terminate the edge that disagrees and apply the project again.
See `remote --help nodes` for operational details.

### Migrating from workspace trees

Releases with stars refuse project files that declare `tree:`, which earlier
releases used for workspace trees. With the user's consent:

1. Replace `tree:` with `star:`, remove each node's `parent`, and add `center:`
   naming a node, usually the former root, where the user works. Settings
   under `tree.sync` move to `star.sync`.
2. Preview with `mutagen project apply --dry-run`, then apply. This removes
   the `tree-<node>` sessions and creates `star-<node>` sessions, which start
   with fresh synchronization history, so prepare as for a first
   synchronization (step 4 of the main workflow). The migration relies on
   `apply` first flushing the running tree sessions together, repeatedly,
   until changes such as deletions have reached every node; paused sessions
   aren't flushed, so if the plan notes a paused `tree-<node>` session,
   resume it (with the user's consent) before applying.
3. Tell the user that commands between two non-center nodes no longer exist,
   and that star commands warn about conflicts instead of refusing to run.

## Changing the configuration later

Edit `mutagen.yml`, then preview and apply as in the main workflow:
`apply` recreates changed sessions and renamed ones. `mutagen project pause`
and `mutagen project resume` pause and resume all of the project's sessions,
and `mutagen project terminate` terminates them, leaving the files on both
endpoints in place.
