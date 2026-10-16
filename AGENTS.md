# AGENTS.md

## Overview

Configuration for a bash shell: opinionated defaults, used across different machines.

## Public repository: no private information

This repository will become public. Treat every commit as published.

Never commit private, sensitive or secret information. Off limits, among others:

- Personal names, email addresses, usernames and home directory paths that identify a person
- Secrets, tokens, API keys, passwords, private keys and certificates
- Hostnames, IP addresses, internal URLs and other details of private networks or machines
- Names of employers, clients or internal systems

Author and license credits in vendored third-party code are fine; keep them.

Keep machine-specific or private values out of tracked files: read them from environment
variables or from a local, untracked file that the tracked config sources if present.
Before committing, review the diff for anything on the list above.
