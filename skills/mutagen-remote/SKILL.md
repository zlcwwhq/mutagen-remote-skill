---
name: mutagen-remote
description: Run commands on the other side of a Mutagen synchronization session with the `remote` executable — tests, builds, training or benchmark scripts, GPU checks, or anything else that has to execute on the server or container holding the synced copy of the code. Use this whenever the working directory is synced by Mutagen and the task needs execution on the other machine (the user says "run it on the server/remote/GPU box/container", mentions `remote`, `mutagen sync`, or a conda environment on the server, or the local machine lacks the needed hardware, OS, or dependencies), even if they don't name the tool. Also use it when `remote` fails or warns.
---

# Running commands with `remote`

Use `remote --nodes` to discover the current workspace's nodes and connection
availability, then `remote --node <name> <command> [args...]` to run on the
chosen node in the corresponding directory. Omit the name only when there is
exactly one other node. Ordinary pairs expose `alpha` and `beta`; declared
stars use their configured names. Use only `remote`: endpoint systems may
lack the `mutagen` CLI. Setup and topology changes belong to `mutagen-setup`.

In a star, the center reaches every node, while every other node reaches only
the center: from a non-center node, plain `remote <command>` runs on the
center, and selecting another node fails with 125 (no multi-hop), so run such
commands from the center. Read [nodes.md](references/nodes.md) for stars and
star problems. `--nodes` is read-only; availability is not a synchronization
guarantee. `--session`, `-s`, `--sessions`, and the exported
`MUTAGEN_REMOTE_SESSION` are deprecated and rejected; unset the variable and
select nodes explicitly. Check the installed `remote --help` before using new
options. Add the same `--node` to subsequent job and file operations.

- **Your shell runs first.** Variables, globs, `~`, pipes, and `&&` are
  processed locally, so `remote echo $HOME` prints the local home. For shell
  code, pass a script on standard input, which needs no escaping:
  `remote --script - <<'EOF'`, the code, then `EOF` runs it with bash (or the
  interpreter of its `#!` line) on the other side; arguments after `-` become
  `$1`, `$2`, .... `remote sh -c '...'` suits one-liners.
- **No terminal.** Use non-interactive flags, and `--timeout <seconds>` for
  anything that might hang. For immediate Python output, use `remote python -u`
  or `-e PYTHONUNBUFFERED=1`; colors need the program's own force-color option.
  See `remote --help environment` for buffering details.
- **Long jobs run detached.** `id=$(remote --detach --log train.log python
  train.py)` starts a job that survives `remote` exiting and the session
  reconnecting, and prints its ID. `remote --wait "$id"` blocks until it ends,
  synchronizes, and exits with its status, even if synchronization warns, so
  heed its warnings before using outputs; add `--tail 40` to also print the
  last 40 log lines, including ignored logs. To watch a job, run
  `remote --wait "$id" --follow 2>&1` in the background or under a line-based
  monitor, filtered to the lines you need: it prints the log as it's written
  and ends like `--wait`. Without background commands, poll with
  `remote --wait "$id" --tail 20 --timeout 300` (124 means still running).
  `remote --jobs` lists jobs, and `remote --kill "$id"` stops one. `--detach`
  also takes `--script -`. Don't hand-roll `nohup ... &`, `tail -f`, or
  polling loops, and have job scripts `wait` for any background processes
  they start: a job ends when its command exits.
- **Keep synchronization enabled.** A skipped flush silently runs outdated
  code, while an extra one only costs a rescan (well under a second for most
  trees). Use `--no-flush` only for commands that read and write no synced
  files, such as `nvidia-smi`; if you edited anything or aren't sure, flush.
  If synchronizing is slow, add `--progress`: its final `remote: synchronized
  in ...` line says where the time went.
- **Ignored paths aren't synced.** If a file that a command wrote is missing
  locally, `remote --ignores <path>` shows whether the session ignores it;
  `remote --pull <path>` copies ignored files or directories here, so local
  tools can read them. Tell the user if outputs they want locally are ignored.
- **Edit sources locally.** Let remote commands write only outputs, and avoid
  `git` commands that write remotely: a file changed on both sides becomes a
  conflict and stops synchronizing. Even `git status`, `git diff`, and
  `git describe --dirty` rewrite a synced `.git/index`, so compute Git state
  locally and pass it in:
  `remote -e GIT_REV="$(git describe --always --dirty)" python train.py`.

`remote --help` lists the options and help topics of the installed `remote`.
If it lacks an option described here, that `remote` is older than this skill:
follow its help instead. Read a reference only when you need it:

- [troubleshooting.md](references/troubleshooting.md) if `remote` exits with
  125, 255, 126, or 127, prints a `remote:` error or warning, or doesn't return; if
  a command is missing remotely (such as an inactive conda environment) or sees
  outdated files; for detached jobs, scripts, ignored outputs, or Git on the
  other side; or to run outside the current session or directory.
- [conflicts.md](references/conflicts.md) before resolving a conflict in any
  way, including by editing or deleting either copy.
