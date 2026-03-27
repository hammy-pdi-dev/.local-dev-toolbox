# .bash_profile

A minimal login-shell entry point that loads the standard POSIX profile and then sources `.bashrc` for interactive sessions.

## Overview

Bash distinguishes between **login shells** (SSH, first terminal on TTY) and **non-login shells** (new terminal tabs, subshells). Login shells read `~/.bash_profile` but skip `~/.bashrc` by default. This file bridges the gap so that the same environment is available regardless of how the shell was started.

## What It Does

1. Sources `~/.profile` if it exists -- picks up POSIX-compatible environment variables shared with other shells (sh, dash).
2. If this is an **interactive Bash** session, sources `~/.bashrc` -- loads aliases, functions, prompt, and all the tooling.

## Installation

```bash
cp scripts/bash/.bash_profile ~/.bash_profile
```

No further configuration needed. All customisation goes in `.bashrc` and `.bashrc.local`.
