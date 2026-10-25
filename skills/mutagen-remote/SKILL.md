---
name: mutagen-remote
description: Run commands on the other side of a Mutagen synchronization session with the `remote` executable — tests, builds, training or benchmark scripts, GPU checks, or anything else that has to execute on the server or container holding the synced copy of the code. Use this whenever the working directory is synced by Mutagen and the task needs execution on the other machine (the user says "run it on the server/remote/GPU box/container", mentions `remote`, `mutagen sync`, or a conda environment on the server, or the local machine lacks the needed hardware, OS, or dependencies), even if they don't name the tool. Also use it when `remote` fails or warns.
---

# Running commands with `remote`

`remote <command> [args...]` runs a command on the other side of the Mutagen
session containing the current directory (so `cd` into the synced tree), in the
corresponding directory, and forwards stdio and the exit status. It
synchronizes before and after the command, so the command sees your edits and
its changes are present locally when it returns. Use only `remote`: the
`mutagen` CLI may not be installed where you run, and sessions are the user's
to manage. If the user asks to set up or change sessions, use the
`mutagen-setup` skill.

- **Your shell runs first.** Variables, globs, `~`, pipes, and `&&` are
  processed locally, so `remote echo $HOME` prints the local home. For shell
  code, pass a script on standard input, which needs no escaping:
  `remote --script - <<'EOF'`, the code, then `EOF` runs it with bash (or the
  interpreter of its `#!` line) on the other side; arguments after `-` become
  `$1`, `$2`, .... `remote sh -c '...'` suits one-liners.
- **No terminal.** Use non-interactive flags, and `--timeout <seconds>` for
  anything that might hang.
- **Long jobs run detached.** `id=$(remote --detach --log train.log python
  train.py)` starts a job that survives `remote` exiting and the session
  reconnecting, and prints its ID. `remote --wait "$id"` blocks until it ends,
  synchronizes, and exits with its status; add `--tail 40` to also print the
  last 40 log lines, including ignored logs. `remote --jobs` lists jobs, and
  `remote --kill "$id"` stops one. `--detach` also takes `--script -`. Don't
  hand-roll `nohup ... &` or polling loops, and have job scripts `wait` for
  any background processes they start: a job ends when its command exits.
- **Keep the default synchronization.** A skipped flush silently runs outdated
  code, while an extra one only costs a rescan (well under a second for most
  trees). Use `--no-flush` only for commands that read and write no synced
  files, such as `nvidia-smi`; if you edited anything or aren't sure, flush.
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
  255, 126, or 127, prints a `remote:` error or warning, or doesn't return; if
  a command is missing remotely (such as an inactive conda environment) or sees
  outdated files; for detached jobs, scripts, ignored outputs, or Git on the
  other side; or to run outside the current session or directory.
- [conflicts.md](references/conflicts.md) before resolving a conflict in any
  way, including by editing or deleting either copy.
