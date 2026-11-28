---
name: leaks
description: Use when the user invokes `/leaks` (`$leaks` in Codex), alone to check local changes, or together with a commit, push, merge or pull request instruction. Checks that nothing private, personal, sensitive or secret is about to be published in a public repository, and stops the commit, push or merge if something is found.
argument-hint: "[commit|push|merge|pr instructions]"
disable-model-invocation: true
---

# Leaks

Treat everything that leaves this machine as published for good: a public repository
is cloned, cached and indexed within minutes, so a later fix does not unpublish it.

Check what is about to be published. If the user also asked to commit, push, merge or
open a pull request, do the check first and go on only if it is clean.

## What to review

Cover every step the request includes; "commit and push" means both the local changes
and the push range.

- **Local changes** (alone, or before a commit): staged and unstaged changes
  (`git diff --cached`, `git diff`) and untracked files
  (`git ls-files --others --exclude-standard`).
- **Push**: every commit the destination doesn't have yet. Compare with the remote
  branch you push to, not just the upstream: `git log -p --cc <remote>/<branch>..HEAD`.
  If that branch doesn't exist there yet, compare with the remote's default branch.
- **Merge another branch into the current one**: `git log -p --cc HEAD..<branch>`.
- **Open or merge a pull request from the current branch**:
  `git log -p --cc <default-branch>..HEAD`, or `gh pr diff` for an existing PR.
- **Always**: the text you write or publish: commit messages, branch and tag names,
  PR title and body.

`--cc` matters: without it, `git log -p` shows no diff for merge commits, so content
added while resolving a conflict would be missed. For pushes and PRs, also read the net
diff (`git diff <base>...HEAD`) to see what ends up in the tree.

Look at file names and paths as well as content: test fixtures, sample configs, logs,
data dumps. You can't read binaries such as images or PDFs: list them, and treat them as
unchecked (see Report).

## Off limits

- Personal names, email addresses, usernames and home paths that identify a person
- Postal addresses and phone numbers
- Secrets: tokens, API keys, passwords, private keys, certificates, `.env` contents
- Hostnames, IP addresses, internal URLs, other details of private networks or machines
- Names of employers, clients or internal systems
- Real personal or customer data, for example in logs, fixtures or screenshots

Allowed: author and license credits in vendored third-party code, the repository's own
public URL, and placeholders such as `example.com`, `user@example.com`, `192.0.2.1`,
`/home/user` or `+1 555 0100`.

## Commit author

The author and committer name is fine. In a public repository the email must be a
private one, such as GitHub's `<id>+<user>@users.noreply.github.com`. A real address is
a finding: suggest setting `user.email` for this repository, and rewriting the commits
not pushed yet (`git commit --amend --reset-author`, or a rebase the user runs). In a
private repository a real email is fine. Check the visibility with
`gh repo view --json visibility`. Treat the repository as public if you can't tell, or
if its `AGENTS.md` or `CLAUDE.md` says it will become public.

## Repo rules

Read the repository's `AGENTS.md` or `CLAUDE.md` for extra allowances and for paths
never to read. Never open gitignored private folders (such as `private/`) to check them,
and never force-add them: reading them puts their contents into this conversation.

## Report

If nothing is found and there are no unchecked binaries, say so in one line, name what
you checked, and go on with the rest of the request.

If there are unchecked binaries, list them and stop until the user confirms them.

If something is found, stop: don't commit, push or merge. List each finding as
`file:line` (or commit and file), what it is and why it matters. Mask secrets (first few
characters, then `…`): the report should not leak them again. Suggest a fix for each: an
environment variable, a placeholder, or an untracked local file that the tracked config
sources if present.

Where the finding is matters:

- **Only in the working tree or index**: fixing the files is enough.
- **In a commit not pushed yet**: a fix in a new commit on top is not enough, since the
  push still publishes the old commit. Rewrite it (amend, or an interactive rebase the
  user runs) so the leak is gone from every commit about to be pushed.
- **Already pushed**: a secret must be revoked and replaced; rewriting history does not
  undo the leak. Other private data stays exposed in clones and caches; say so.
