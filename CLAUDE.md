# mutagen-remote skill Agent Guide

This repository holds the `mutagen-remote` agent skill and is the Claude Code
plugin marketplace that distributes it. The skill documents `remote` from
[zlcwwhq/mutagen](https://github.com/zlcwwhq/mutagen), whose source of truth
for `remote` behavior is `cmd/remote/cli` (help text in `cli.go` and
`help.go`) and its README.

- The skill must only direct agents to use `remote` itself, since agents may
  run on endpoints without the `mutagen` CLI. Anything that requires `mutagen`
  belongs with the user.
- Installations update from `main`, so `main` must describe the `remote` of
  the latest published fork release. Changes for unreleased `remote` behavior
  go on another branch (such as `next`), whose commit the fork's
  `skills/mutagen-remote` submodule pins, and are merged into `main` once the
  fork release that supports them is published.
- Keep the skill consistent with `remote --help` and the fork's README. When
  `remote` behavior changes (options, exit statuses, working directory
  mapping, synchronization, prologues, or conflicts), update all three.
- Keep `SKILL.md` short: it's read for every task that uses `remote`. Put
  details that only some tasks need in `skills/mutagen-remote/references`.
- Don't set `version` in `.claude-plugin/plugin.json` or `marketplace.json`.
  Without it, every commit is an update; with it, installations ignore commits
  until it changes.
- Run `claude plugin validate .` after changing the manifests.
- Use Conventional Commits and sign off commits (`git commit -s`).
