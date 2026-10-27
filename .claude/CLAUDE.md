# Rustfield.eu node — rules for work in this repo

This repo is **PUBLIC**. Never put secrets, server addresses, real node names with their IPs, or private plans here
(code, docs, commits, `.claude/` notes). The design and the decisions live in the main project (private repo
`rustfield.eu`, `.claude/docs/NODES.md`); these notes cover only this repo's code.

- Read `.claude/memory/README.md` first.
- Same rules as the main project: simple English, Docker only, exact image versions, memory fence + log limit on
  every container, the "one tree" look for every script, ShellCheck clean, Conventional Commits.
- The look in `tools/steps.sh` is a copy of the main project's: change it in both repos.
