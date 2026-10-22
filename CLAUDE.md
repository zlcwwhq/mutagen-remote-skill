# mutagen-remote skill Agent Guide

This repository holds two agent skills for
[zlcwwhq/mutagen](https://github.com/zlcwwhq/mutagen) and is the Claude Code
plugin marketplace that distributes them in one plugin. `mutagen-remote`
documents `remote`, whose source of truth in the fork is `cmd/remote/cli` (help
text in `cli.go` and `help.go`) and the README. `mutagen-setup` sets Mutagen up
for a project with the `mutagen` CLI on the daemon's system; its sources of
truth in the fork are the release bundle layout (`scripts/build.go`,
`.github/workflows/ci.yml`), agent bundle lookup (`pkg/agent/bundle.go`),
project files (`pkg/project`), and the README.

- `mutagen-remote` must only direct agents to use `remote` itself, since agents
  may run on endpoints without the `mutagen` CLI. Anything that requires
  `mutagen` belongs with the user, or with `mutagen-setup` when the user asks
  for setup.
- `mutagen-setup` changes the user's sessions and daemon, so it must have
  agents confirm plans with the user before creating, replacing, or
  terminating sessions and before stopping the daemon.
- Installations update from `main`, so `main` must describe the `remote` of
  the latest published fork release. Changes for unreleased `remote` behavior
  go on another branch (such as `next`), whose commit the fork's
  `skills/mutagen-remote` submodule pins, and are merged into `main` once the
  fork release that supports them is published.
- Keep the skills consistent with `remote --help` and the fork's README. When
  `remote` behavior changes (options, exit statuses, working directory
  mapping, synchronization, prologues, or conflicts), update all three. Update
  `mutagen-setup` when release assets, installation layout, project
  configuration, or daemon commands change.
- Keep each `SKILL.md` short: it's read for every task that uses the skill. Put
  details that only some tasks need in the skill's `references` directory.
- Check scripts in `skills/*/scripts` with `sh -n` (and `shellcheck` if
  available); they must run under POSIX `sh`.
- Don't set `version` in `.claude-plugin/plugin.json` or `marketplace.json`.
  Without it, every commit is an update; with it, installations ignore commits
  until it changes.
- Run `claude plugin validate .` after changing the manifests. Codex reads the
  same `.claude-plugin/marketplace.json` (checked with Codex CLI 0.163 via
  `codex plugin marketplace add` and `codex plugin add`), so keep it
  compatible with both.
- Use Conventional Commits and sign off commits (`git commit -s`).
