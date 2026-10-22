---
name: mutagen-setup
description: Set up Mutagen synchronization with remote commands (the zlcwwhq/mutagen fork) for a project — install or upgrade the fork's `mutagen` and `remote` from its latest GitHub release when they're missing or outdated, start the daemon, write `mutagen.yml` in the project directory with the alpha and beta endpoints, start the sessions, and make `remote` usable on the endpoints. Use when the user wants to sync a project with a server, GPU box, or container, set or change alpha, beta, or what's synchronized, install, upgrade, or repair Mutagen or its daemon, check for a newer release, or when `mutagen` is missing, reports a client/daemon version mismatch, or `remote` isn't found or belongs to another Mutagen version.
---

# Setting up Mutagen for a project

Sessions run in the Mutagen daemon on the system where `mutagen` is used,
usually the user's machine, which is then alpha. Run everything there unless
noted. Sessions are the user's: confirm the plan before creating, replacing, or
terminating sessions, and before stopping the daemon, which stops every
session's synchronization and terminates running `remote` commands (detached
jobs keep running).

Installing, the daemon, and SSH need network access and write outside the
project (such as to `~/.local` and `~/.mutagen`), so in a sandbox, such as
Codex's, request to run those commands outside it. `remote` also fails in
Codex's default sandbox (`connect: operation not permitted`) unless network
access is allowed: `network_access = true` under `[sandbox_workspace_write]`
in `~/.codex/config.toml`. Mention this to Codex users.

## 1. Settle the plan

Ask for what you can't infer, then summarize the plan for confirmation:

- **Project directory**: where `mutagen.yml` goes, normally alpha's root
  (`alpha: "."`).
- **Beta**: `[user@]host[:port]:path` over SSH (hosts from `~/.ssh/config`
  work; relative paths start at the remote home), `docker://[user@]container/path`,
  or a local path. Use a directory dedicated to the project, never a home
  directory itself or one holding unrelated files.
- **Who runs commands** (`remote`): `beta` when agents work on alpha and run
  commands on beta (the usual case), `alpha` for the reverse, `true` for both.
  Any process of the user's on a submitting system can then run commands on
  the executing one, so enable only directions that the user trusts.
- **What not to synchronize**: VCS directories, virtual environments,
  dependencies, caches, build outputs, datasets, checkpoints. Keep outputs that
  the user wants back from remote jobs, such as logs and results, synchronized.
- **Environment setup** that commands need on the executing side, such as a
  conda environment: it becomes a prologue.

## 2. Check the installation

```sh
sh <skill-directory>/scripts/install.sh --check
type -a mutagen remote
```

`--check` (Linux, macOS, and FreeBSD; for Windows, see
[install.md](references/install.md#windows)) changes nothing. It reports the
`mutagen` on `PATH`, where an installation goes (in place for an existing fork
installation, else `~/.local`), the version installed there, the latest
release, and a status. Install with [install.md](references/install.md) if it's
`not installed` or `incomplete`, or if the `mutagen` on `PATH` isn't a fork
release (no `-zlcwwhq.`). For `update available`, offer an
[upgrade](#upgrading). The first `mutagen` and `remote` on `PATH` must be the
installed ones.

## 3. Start the daemon

Run `mutagen daemon start`, then `mutagen sync list`. If that reports
`client/daemon version mismatch`, a daemon of another version is running: with
the user's consent, run `mutagen daemon stop` (it works across versions) and
start it again. To start it at login, see
[install.md](references/install.md#starting-the-daemon-at-login).

## 4. Check the endpoints

- **SSH**: `ssh -o BatchMode=yes <host> true` must succeed, since the daemon
  connects in the background and can't answer password or host key prompts.
  Otherwise, ask the user to set up key authentication, or to accept the host
  key by connecting once (`! ssh <host>` in Claude Code).
- **Docker**: the container must be running (`docker ps`).
- **Beta's directory**: list it (`ssh <host> 'ls -A <path>'`). A missing or
  empty directory is safest; Mutagen creates it. If it has content, show the
  user and confirm: the first synchronization copies files that exist on one
  side to the other and turns files that differ into conflicts, except that
  `two-way-resolved` and `one-way-replica` overwrite them with alpha's version
  and `one-way-replica` deletes files that exist only on beta.

## 5. Write `mutagen.yml`

If the project directory has a `mutagen.yml`, edit it, preserving existing
sessions and settings. Otherwise, start from:

```yaml
sync:
  code:
    alpha: "."
    beta: "gpu-box:~/projects/myproject"
    mode: "two-way-safe"
    remote: beta
    ignore:
      vcs: true
      paths:
        - "/mutagen.yml.lock"
        - ".venv/"
        - "__pycache__/"
```

Keep `/mutagen.yml.lock` ignored: `mutagen` keeps that file next to
`mutagen.yml` while the project runs. In a Git repository, also add it to
`.gitignore`. Session names start with a letter and contain only letters,
digits, and dashes; `remote` shows them in warnings and accepts them with `-s`.
[configuration.md](references/configuration.md) covers endpoint URLs, modes,
ignores, prologues, and several sessions.

## 6. Start or update the sessions

From the project directory:

```sh
mutagen project apply --dry-run   # show the plan to the user
mutagen project apply             # starts the project if it isn't running
mutagen project flush             # waits for a synchronization cycle
mutagen project list              # status, conflicts, and problems
```

`apply` keeps unchanged sessions and recreates changed ones, including for
changes to `remote` or `remotePrologue`. Recreated sessions lose their
synchronization history, so the plan's replacements behave like a first
synchronization (step 4): before applying them, have the user stop processes
that write synchronized files and resume paused sessions.

Then check remote commands from the project directory: `remote pwd` prints
beta's directory, and `remote --sessions` lists the sessions connected for
remote commands. Command channels connect shortly after the session, so retry
`not connected for remote commands` for a few seconds.

## 7. Prepare the endpoints for agents

- **`remote` on SSH and Docker endpoints that submit commands** (`remote:
  alpha` or `true`): agents provide it at `~/.mutagen/agents/<version>/remote`,
  whose version changes with every upgrade. Install
  [scripts/remote.sh](scripts/remote.sh) there as `remote` on `PATH` instead; it
  runs the version that the daemon uses. Remove `PATH` entries that point into
  `~/.mutagen/agents`, then check from beta's directory in a login shell:

  ```sh
  ssh <host> 'mkdir -p ~/.local/bin && cat > ~/.local/bin/remote && chmod 755 ~/.local/bin/remote' < <skill-directory>/scripts/remote.sh
  ssh <host> 'cd <path> && "$SHELL" -lc "remote --sessions"'
  ```

  For Docker, use `docker exec -i <container> sh -c '...'` instead of
  `ssh <host> '...'`. If `remote` isn't found, add `~/.local/bin` to `PATH` in
  that system's shell profile. On the daemon's system, `remote` comes with
  `mutagen` (step 2).
- **Prologue**: configure environment setup as described in
  [configuration.md](references/configuration.md#remote-commands-and-prologues),
  and check it with `remote sh -c 'command -v python'` (or the relevant tool).
- **The mutagen-remote skill**, which teaches agents to use `remote`: on each
  system where agents submit commands, install it in Claude Code with
  `claude plugin marketplace add zlcwwhq/mutagen-remote-skill` and
  `claude plugin install mutagen-remote@mutagen-remote-skill`.

Finish by reporting what was installed (version and paths), the sessions and
their status, and what the user still has to do, such as `PATH` changes in
shell profiles, starting the daemon at login, or SSH keys.

## Upgrading

When the user asks to upgrade, or `--check` reports `update available`:

1. Tell the user what the release changes (`gh release view <tag> -R
   zlcwwhq/mutagen`, or its page) and that the daemon restarts: synchronization
   pauses for a moment, and running `remote` commands are terminated (detached
   jobs keep running). Get their consent, preferably once running commands have
   finished. Don't install an older release unless asked (`--version <tag>`).
2. Run `sh <skill-directory>/scripts/install.sh --restart-daemon`. It downloads
   and verifies the release first, then stops the daemon (or the systemd user
   service from [install.md](references/install.md#starting-the-daemon-at-login)),
   replaces the installation in place, and waits until the new daemon answers.
   On Windows, stop the daemon, install, and start it as install.md describes.
3. Check that `mutagen version` and `remote --version` print the new version
   and that `mutagen sync list` shows every session back at `Watching for
   changes`; endpoints receive the new agents as their sessions reconnect.
   Then run `remote pwd` from a project directory.
4. On endpoints that submit commands, the wrapper from step 7 follows the
   upgrade by itself. Reinstall it if it differs from `scripts/remote.sh`
   (`ssh <host> cat ~/.local/bin/remote | cmp - <skill-directory>/scripts/remote.sh`),
   replace any `PATH` entry pointing into `~/.mutagen/agents/<version>` with
   it, and check `remote --version` there from a session root.
5. Old agent versions stay in `~/.mutagen/agents` on endpoints (about 10 MB
   each). With the user's consent, delete versions that no registration in
   `~/.mutagen/remote/*.json` names; a daemon that still uses one reinstalls it
   when it reconnects.
