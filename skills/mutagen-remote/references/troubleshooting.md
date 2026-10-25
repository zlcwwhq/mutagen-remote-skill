# Troubleshooting `remote`

Diagnose with `remote` alone: the `mutagen` CLI may not be installed where you
run, and sessions (their state, configuration, and conflicts) are managed by the
user. When a fix requires changing a session, tell the user what's wrong and
what to change.

## Where things are

- On the daemon's machine, `remote` is installed alongside Mutagen. On SSH and
  Docker endpoints, it's at `~/.mutagen/agents/<version>/remote` and usually
  isn't on `PATH`.
- `remote --flush` checks routing and synchronization without running a
  command.
- `remote --help <topic>` documents sessions, synchronization, environment
  setup, termination, and conflicts in detail.

## Error messages

| Message | Cause | Fix |
| --- | --- | --- |
| `no connected session with remote commands enabled contains <dir>` (255) | Outside every synced root, or the session is paused, disconnected, or doesn't execute commands on the other side (they can be enabled in one direction only) | `cd` into the synced directory (`remote --sessions` lists the connected sessions' roots); otherwise tell the user |
| `unable to connect to session ...: dial unix ...: connect: operation not permitted` (255) | A sandbox around your commands blocks Unix sockets, such as Codex's `workspace-write` sandbox without network access | Request to run `remote` outside the sandbox, or ask the user to allow it (for Codex, `network_access = true` under `[sandbox_workspace_write]` in `~/.codex/config.toml`) |
| `<alpha\|beta> is not connected for remote commands` (255) | Session just started or is reconnecting | Retry after a few seconds; if it persists, tell the user |
| `multiple sessions match ...` (255) | The name given with `-s` or `MUTAGEN_REMOTE_SESSION` is shared by the sessions listed in the message | Use a session identifier from the message |
| `<dir> is synchronized by session X, not Y` (255) | `-s` selected a session whose roots don't contain the directory, which another session's root does: the command would run at the selected session's remote root, not in a corresponding directory | Drop `-s` to use the session containing the directory, or add `--cwd` to say where to run on the selected session's side |
| `<dir> is ignored by session X` / `<dir> is inside <dir2>, which session X ignores` (255) | The session containing the directory doesn't synchronize it. Usually it's the root of a nested session that's paused or disconnected (or doesn't run commands from this side); sometimes it's a directory such as a build directory that exists separately on each side | For a nested session, tell the user that it isn't running; don't work around it with `--cwd`, which would run in the enclosing session's unsynchronized copy. Only if the directory is meant to exist separately on the other side, add `--cwd .` |
| `both endpoints of session ... are on this system` (255) | `--session` used outside both roots of a local session | Run from inside the root you want to submit from |
| `session ... is no longer connected for remote commands on this system` (255) | The session paused, reconnected, or was terminated after `remote` located it; `remote` doesn't switch to another session midway | Retry after a few seconds; if it persists, tell the user |
| `the connection to the executing endpoint was lost ...` (255) | The session stopped synchronizing while the command ran (paused, reconnecting, replaced, or the daemon stopped), so the command was terminated: SIGTERM, then SIGKILL 5 seconds later | Files that it was writing may be incomplete. Once `remote --flush` succeeds, check them and rerun the command; run long commands with `--detach`. If it recurs, tell the user |
| `registered by Mutagen X, but this is Mutagen Y` (255) | `remote` from a different Mutagen version, such as a `PATH` entry for an older agent after an upgrade | Use the `remote` installed with version X (on SSH and Docker endpoints, `~/.mutagen/agents/X/remote`); tell the user that the `mutagen-setup` skill installs a `remote` that follows upgrades |
| `warning: sessions X and Y both synchronize the current directory; using X` | Several sessions synchronize the directory, such as one directory synced to several machines, or nested roots; `remote` used the most specific root, then the session created first | Nothing, if X is the intended session (ask the user if unsure); otherwise add `-s <session>` with a session from the warning. `remote --sessions` shows their roots |
| `warning: unable to synchronize before/after the command` | The session stopped synchronizing during a flush, or `--timeout` expired | The command still ran; retry with `remote --flush`, and tell the user if it keeps failing |
| `synchronization stopped before the flush completed` (255 with `--flush`) | Same as above | Same as above |
| `unable to find command` (127) | Not on the remote `PATH` | See "Commands missing from the remote environment" |
| `remote: prologue <path> failed with exit status N` (126) | The prologue returned non-zero, had a syntax error, or exited | Inspect with `remote --no-prologue cat <path>`; repair a workspace override locally, preserving existing setup |
| `unable to access prologue` (126) | A prologue is missing or inaccessible, or an override is a dangling link | Use `--no-prologue` to inspect the reported path; repair the workspace override, or tell the user if their configured script is unavailable |
| `unable to access working directory` (126) | The corresponding directory doesn't exist remotely | See "Conflicts and unsynchronized content", or use `--cwd` |
| `is checked out through the opposite endpoint` (255) | The conflict was checked out from the other side, which alone can apply or discard it | Leave it and its paths alone; if it seems abandoned, ask the user to discard it on that side (`remote --conflict-discard <path>`) |
| `is already checked out in <dir>` (255) | The conflict has a workspace on this side, which may be another agent's or the user's resolution in progress | If you checked it out, do what the message says; otherwise leave it, or ask the user |
| `no job <id> exists on this endpoint` (255) | Wrong ID, or the job ended more than 7 days ago | `remote --jobs` lists the jobs |
| `job <id> was started at another synchronization root` (255) | The job belongs to another session's root on that system | Run from inside that session's root, or select it with `-s` |
| `job <id> ended without recording its exit status` (255 from `--wait`) | The job was killed with SIGKILL outside `remote`, or its system or container restarted | Read its log (shown by `remote --jobs`) and rerun it if needed; if jobs keep ending this way, see "Detached jobs" |
| `remote: job <id> is still running` after `timed out` (124 from `--wait`) | `--timeout` expired; the job wasn't affected. With `--tail N`, the last N lines so far were printed first | Wait or poll again, or `remote --kill <id>` |
| `warning: unable to follow the log of job <id>: the executing endpoint doesn't support following logs` | The other side runs an older Mutagen | The wait continues (with `--tail N`, the last N lines are printed at the end); read progress with `remote tail -n 40 <log>` and tell the user an upgrade adds `--follow` |
| `warning: unable to follow the log of job <id>: ... is not a regular file` / `no such file or directory` / `was replaced since remote last read it` | The job logs to `/dev/null` or a device, or its log was deleted or replaced | Nothing; the wait continues and reports the job's status |
| `warning: the log of job <id> became shorter than the N bytes followed so far` | The log was truncated, such as by log rotation or another job started with the same `--log` | Following restarts at the log's beginning; check `remote --jobs` for another job writing the same log |
| `--timeout can't be combined with --detach` (255) | `--detach` returns as soon as the job starts | Limit the job itself: `remote --detach timeout 2h python train.py` |
| `unable to open log` (126) | `--log`'s directory doesn't exist on the other side, or the log is a FIFO, socket, or directory rather than a regular file or character device | Create the directory, or choose another path, such as a regular file or `/dev/null` |
| `unable to find the script's interpreter` (127) | Scripts without a `#!` line run with bash, which isn't on the other side's `PATH`, or the `#!` interpreter is missing | Add `#!/bin/sh` for POSIX scripts, or fix `PATH` (see "Commands missing from the remote environment") |
| `the script exceeds the size limit` (255) | `--script` takes at most 512 KiB | Save the script in the synced tree and run `remote bash <path>` |
| `unable to pull <path>: the session synchronizes it` (255) | `--pull` only copies ignored paths; synchronized ones arrive through synchronization | `remote --flush`; if the file is still missing, check for a conflict or problem warning |
| `... synchronizes some content beneath it, so remote doesn't pull it as a whole` (255) | The directory is ignored, but some content beneath it is unignored and synchronized | Pull the ignored files or directories beneath it instead |
| `... resolves to <path> through a symbolic link, and the session synchronizes that` (255) | An ignored local symbolic link among the path's parents leads into synchronized content, which `--pull` doesn't overwrite | Read the file with `remote cat`, or tell the user; `remote --ignores <path>` shows `synchronized as <path>` |
| `... synchronized by <session>, so remote doesn't write it` / `doesn't create it` (255) | Another session on this machine synchronizes the path, or a missing parent of it, so that session updates it | Leave it to that session, or read the remote copy with `remote cat`; tell the user if that session lacks the content |
| `... in only some Unicode normalization forms of its path and may synchronize it` (255) | An ignore pattern spells an accented name in only one Unicode normalization form, so the session may synchronize the name | Read it with `remote cat`, or ask the user to make the pattern match both forms, such as `caf*.txt` |
| `... aren't supported on Windows endpoints` / `... on Windows or AIX endpoints` (126) | Scripts need a POSIX system on the executing side, and detached jobs one other than AIX | Run commands instead, such as `remote powershell -Command ...` on Windows; on AIX, run long commands in the foreground |

Statuses 128+N mean that the remote command was killed by signal N.

## Which session and directory are used

`remote` uses the session whose root most specifically contains the current
directory and runs commands in the corresponding remote directory, so prefer
`cd`-ing into the synced tree. Among equally specific roots, such as one
directory synced to several machines, it uses the session created first, and
it warns whenever several sessions synchronize the directory. `remote pwd`
shows where commands run, and `remote --sessions` lists the connected
sessions, marking the one used by default and those whose roots contain the
current directory.

- `-s <name-or-id>` selects a session explicitly; prefer it for one-off
  disambiguation. From outside the session's root, commands run at the root of
  its opposite endpoint, or in `--cwd` (relative paths are resolved against
  that root). From inside another session's root, `-s` naming a session whose
  roots don't contain the directory fails unless `--cwd` is given.
- `MUTAGEN_REMOTE_SESSION`, if exported, only chooses among the sessions whose
  roots contain the current directory, and is ignored if none of them matches
  it, so it never overrides the session containing the directory. Outside
  every synced root, it selects a session as `-s` does.
- `remote` can't find sessions that are paused, disconnected, or that don't run
  commands submitted from this side. Inside the root of such a session nested
  in another synced root, the enclosing session is used: if it ignores the
  nested root, as it typically does, commands fail (see `... which session X
  ignores` above); otherwise, they silently run in the enclosing session's copy
  of the directory, and the flushes synchronize only the enclosing session. If
  a nested session matters, pass `-s <nested>`, which fails instead while it's
  unavailable, and tell the user if it isn't running.
- `remote` locates the session once per invocation and uses it for the flushes
  and the command, failing rather than switching sessions if it disconnects in
  between.

## Conflicts and unsynchronized content

After each flush, `remote` warns about content that it couldn't synchronize,
with paths relative to the current directory:

- `these conflicts aren't synchronized until resolved`: the path changed on
  both sides since the last synchronization, so neither copy propagates.
  `remote --diff` shows how the copies differ (`-` local, `+` remote). Resolve
  conflicts with the [conflict workflow](conflicts.md). If `remote --conflicts`
  says that the session's mode doesn't support resolution, or lists the
  conflict as one that remote can't resolve, first check whether it involves
  a directory. Checkout and apply reject directory conflicts, including
  existing workspaces; preserve the copies and report the conflict to the user
  for manual resolution. For other unsupported conflicts involving content
  that can't be synchronized or read, fix unreadable content if you can.
  Otherwise, copy both versions somewhere outside the synced tree first, put
  the content you want in one copy (merging both sides' changes if needed),
  delete the other copy (`rm <path>` or `remote rm <path>`), and run
  `remote --flush`. In one-way-safe sessions, put the content in alpha's copy
  and delete beta's: synchronization copies alpha's copy over a deleted beta
  copy, but leaves beta's copy unsynchronized if alpha's is deleted, and never
  copies beta's changes to alpha. Check the result with `remote --diff <path>`.
  Nothing checks that the deleted copy is unchanged, so do this promptly. If
  it's unclear which changes to keep, show the user the diff and ask.
- `this content couldn't be synchronized`: the side in parentheses couldn't
  read or write the path, for example because of permissions. Fix it on that
  side if you can, or tell the user.

Ignored paths are never synchronized and aren't reported; if a file is missing
on one side without a warning, it's probably ignored. `remote --ignores` lists
the session's ignores, and `remote --ignores <path>...` checks paths (exit
status 1 if any is ignored); `possibly synchronized` and `synchronized as
<path> (through a symbolic link)` mean that the session may synchronize the
path, so `--pull` refuses it. `remote --pull <path>...` copies ignored files,
directories, or symbolic links from the other side, replacing local files that
differ but never deleting local ones; read single files with `remote cat` if
you don't need a local copy. It also refuses paths that another session on
this machine synchronizes, but it only knows sessions that are connected and
run by this version of Mutagen or a later one, so don't pull into another
project's synchronized directories. If outputs that the user wants locally are
ignored, tell the user, who may want to stop ignoring them.

Each flush rescans both roots. An idle flush took about 0.02 seconds for 900
files and 0.2 seconds for 50,000 files on a local session, plus a few network
round trips over SSH, and longer for very large trees. That cost is small
compared to running outdated code, so use `--no-flush` only for commands that
read and write no synchronized files, never right after editing files, and
suggest that the user ignore large generated directories in the session.

If `remote` seems stuck before a command starts or after it finished, it's
usually synchronizing. Flushes that take over 3 seconds show their progress on
standard error: automatically on a terminal, and otherwise only with
`--progress`, which prints `remote:` lines when the phase changes and every 10
seconds. Add `--progress` (before the command) to runs in the background or
under a monitor. The final line says where the time went, such as
`remote: synchronized in 44s: scanning 31s; staging on alpha (local) 12s, 1 file, 5.0 MiB`:

- Long `scanning`: the trees are large, since every flush rescans both roots in
  full. Suggest that the user ignore large generated or data directories.
- Long `staging on <endpoint>`: changed files are being transferred to that
  endpoint (`local` or `remote` says which side), with their count and
  approximate size. Write large outputs to ignored paths and copy what's needed
  with `--pull`, or tell the user that the link is slow.
- Repeated phases mean that the session was already synchronizing other changes
  when the flush started.

`--progress=false` turns it off. If the other side's Mutagen doesn't report
phases, only the elapsed time is shown.

For a session that synchronizes a single file, run `remote -s <name-or-id>
--diff` from outside its root, or pass the local file's absolute path after
`--diff`. File/directory conflicts are supported: children beneath a file are
treated as missing on that endpoint. Large reports may omit change details and
show an omitted count; use `remote --diff <path>` to compare specific omitted
files. `--timeout` also covers reading and hashing files during comparison.

## Commands missing from the remote environment

Remote commands inherit the Mutagen agent's non-interactive environment, so
`.bashrc` setup such as `conda init` usually hasn't run. Diagnose with
`remote sh -c 'echo "$PATH"; command -v python'`, and repeat it with
`--no-prologue` to see what the endpoint's prologue, if any, changes. Then pick
one:

- Use the prologue: it's sourced before the command is looked up and sees `-e`
  variables, so it may support selecting an environment (the example below
  reads `CONDA_ENV`).
- Activate inline:
  `remote sh -c 'eval "$(~/miniconda3/bin/conda shell.posix hook)" && conda activate torch && python train.py'`.
- Use an absolute path to the executable.

Avoid `-e PATH=$PATH`: your local shell expands it to the local `PATH`.

For repeated environment setup, create or edit `.remote-prologue.sh` at the
synchronization root. Inspect an existing file first and preserve its setup;
check the current prologue's effects before replacing them. No session change
or restart is needed. This POSIX shell script is sourced before each eligible
command and completely replaces the session's configured prologue. It needs
no executable permission.

Discover the executing side with
`remote --no-prologue sh -c 'printf "%s\n" "$MUTAGEN_REMOTE_ENDPOINT"'`.
`remote` supplies `alpha` or `beta` to scripts and commands, overriding inherited
values and values passed with `-e` or `--env-file`. Since the file synchronizes
to both endpoints, use this variable for setup that differs between them:

```sh
# .remote-prologue.sh at the synchronization root
case "$MUTAGEN_REMOTE_ENDPOINT" in
  alpha)
    . "$HOME/venvs/local/bin/activate"
    ;;
  beta)
    eval "$("$HOME/miniconda3/bin/conda" shell.posix hook)"
    conda activate "${CONDA_ENV:-gpu}"
    ;;
esac
```

Adapt the paths and environments to what you have verified on each endpoint;
only add the branches that need setup. Shared initialization can go outside
the `case`. An empty file or a branch that does nothing still replaces the
configured prologue. Delete the override to restore the session default.

Validate edits with `remote sh -c 'command -v python; python --version'` (or the
relevant tool). The default flush transfers edits before execution; ignored
files, sync failures, or `--no-flush` can leave the executing copy outdated.
If the script fails, commands stop with status 126 and don't fall back to the
session default. Use `--no-prologue` for diagnosis and repair, then validate
with prologues enabled again.

Only the synchronization root is checked, including with `--cwd`; relative
paths inside the script use the command's working directory. `--no-prologue`
skips both workspace and configured scripts, as does submission from outside
the root with `--session`. Prologues aren't supported on Windows endpoints.

## Detached jobs

Run anything that takes long, or that must survive the session reconnecting, as
a detached job:

```sh
id=$(remote --detach --log train.log python train.py)   # prints only the ID
remote --jobs                  # state, running time, log, and command
remote --wait "$id" --follow 2>&1   # prints the log as it's written, then waits
remote --wait "$id" --tail 40 --timeout 300   # last 40 lines; 124 if running
remote --wait "$id"            # waits, synchronizes, exits with its status
remote --kill "$id"            # SIGTERM, then SIGKILL 5 seconds later
```

- Jobs run where commands would, with the prologue and environment options,
  but without input. `--log` is relative to the command's directory; without
  it, the log is in the other side's Mutagen data directory, at the path that
  `--jobs` shows (read it with `remote tail <path>`). `remote` warns if the
  log is ignored, and so not synchronized. The log must be a regular file or
  a character device such as `/dev/null`, not a FIFO.
- `remote --kill` returns once every process in the job's process group has
  exited. Processes still running 5 seconds after SIGTERM, such as workers
  that ignore it, get SIGKILL; the status shown is the command's. Interrupting
  `remote --kill` doesn't cut that short, and repeating it doesn't send
  SIGTERM again. It never synchronizes; `--no-flush` is accepted and has no
  effect.
- A job ends when its command exits. Processes that the command leaves running
  in the background aren't part of the job afterwards: `--wait` doesn't wait
  for them and `--kill` doesn't terminate them. So have job scripts `wait` for
  the background processes they start. On Linux, `--jobs`, `--wait`, and
  `--kill` list those left running (`left running: <pid> <command>`), which
  `remote -- kill <pid>...` terminates; elsewhere, they only say that the
  job's process group may still have processes.
- `remote --wait "$id" --timeout 10m` bounds the wait (exit 124) without
  stopping the job. If the connection is lost while waiting, `remote` retries
  for a minute. `--wait` synchronizes afterwards, so the job's outputs are
  local when it returns. With large outputs, add `--progress` to see that
  synchronization.
- Add `--tail N` to `--wait` to print the final N log lines on standard
  output after the job ends, or, if `--timeout` expires while it runs, before
  exiting with 124. This reads the executing side's log directly, including
  ignored logs and the default log outside the synchronized tree. `--tail 0`
  leaves output unchanged; negative counts are rejected. Tails are limited to
  the last 1 MiB, with a warning if the requested lines exceed it. Missing,
  unreadable, or non-regular logs produce a warning without changing the
  job's exit status. Waiting without `--tail` or `--follow` doesn't print log
  contents.
- **Watching a job.** `remote --wait "$id" --follow` prints the log as it's
  written, from its beginning (`--tail N` starts with its last N lines,
  `--tail 0` with only new output), then ends like `--wait`: it synchronizes,
  prints `remote: job <id> exited with status N` on stderr, and exits with the
  job's status, so it needs no timeout. Run it in the background or under a
  line-based monitor and filter it, merging stderr so that the final status
  line and any warnings are seen too:
  `remote --wait "$id" --follow 2>&1 | grep --line-buffered -E 'loss|Error|^remote: '`.
  Output passes through unchanged, so progress bars that redraw with `\r`
  and no newline (such as tqdm's) don't reach line-based filters until a
  newline arrives; filter on lines the program prints. If the connection is
  lost, `remote` retries and resumes without repeating or skipping output.
  It warns if the log became shorter (it was truncated, or another job was
  started with the same `--log`) and then follows it from its beginning, and
  if the log was replaced while disconnected, which it then doesn't follow.
- **Polling without background commands.** `remote --wait "$id" --tail 20
  --timeout 300` waits up to 5 minutes. If the job ends, it prints the last
  20 lines, synchronizes, and exits with the job's status. If the job is
  still running, it prints the last 20 lines so far, says `job <id> is still
  running`, and exits with 124. Repeat it to check progress; `--timeout 1` is
  a quick peek. It returns up to a second early so that the tail arrives in
  time.
- A job is `lost` if it ended without recording its status. Jobs end with the
  machine or container that runs them, and service managers can end them too:
  stopping a Mutagen daemon that runs as a systemd service ends the jobs that
  it runs on its own machine, and logind's `KillUserProcesses` ends jobs on SSH
  hosts when the SSH connection closes. If jobs end early this way, tell the
  user.
- `--detach` works with `--script -` for multi-line jobs. Job state is kept for
  7 days after a job ends; `--jobs` only lists jobs started at the session's
  root.

## Scripts and quoting

`remote --script - <<'EOF'` followed by lines of code and `EOF` runs the code
on the other side exactly as written: the quoted delimiter keeps your shell
from expanding anything. Without a `#!` line the script runs with bash;
`#!/bin/sh`, `#!/usr/bin/env python3`, and similar lines select the
interpreter. Arguments after `-` (or after a local script file given instead of
`-`) are the script's, even ones that look like options. `$0` is a temporary
copy, so `$(dirname "$0")` doesn't find the script's siblings: run scripts that
are in the synced tree with `remote bash <path>` instead. With `-`, the
script's commands get no input. `remote bash -s <<'EOF'` also works for
foreground scripts, but commands in it that read input consume the rest of
the script, and it can't run detached.

## Commands that don't return

- The command is waiting for input: `remote` forwards stdin, so pass
  `< /dev/null` or use the program's non-interactive flags.
- A background process still holds stdout or stderr: `remote` waits for every
  process holding its output. Use `--detach` instead of starting background
  processes.
- Use `--timeout` to bound commands that might hang (in seconds, or with a
  unit such as `10m`); it exits with 124 and terminates the remote process
  group (SIGTERM, then SIGKILL 5 seconds later), without synchronizing
  afterwards.
- Commands are also terminated when the session stops synchronizing (see the
  lost connection above), but detached jobs keep running.

## Git on the other side

Mutagen doesn't synchronize modification times, so when `.git` is synchronized
(the session doesn't set `ignore.vcs`), the index never matches the other
side's files. Git commands that refresh the index then rewrite `.git/index`,
which synchronizes back, where local Git rewrites it again; rewrites on both
sides at once, such as by an editor's background `git status`, conflict. With
Git 2.53:

- `git status`, `git diff`, and `git describe --dirty` rewrite the index.
  `GIT_OPTIONAL_LOCKS=0` (or `git --no-optional-locks`) prevents it for
  `git status` only.
- `git rev-parse`, `git log`, and `git describe` without `--dirty` don't.

Compute Git state locally and pass it in, where local expansion is what you
want: `remote -e GIT_REV="$(git describe --always --dirty)" python train.py`.
If code on the other side must check for changes itself (such as experiment
tracking that records the revision), use
`GIT_OPTIONAL_LOCKS=0 git status --porcelain --untracked-files=no`, which is
empty for a clean tree, rather than `git describe --dirty`, for example by
exporting `GIT_OPTIONAL_LOCKS=0` in the prologue. Tools that run Git
internally, such as setuptools-scm, may still rewrite the index. If the other
side doesn't need the repository, suggest that the user set `ignore.vcs: true`.
