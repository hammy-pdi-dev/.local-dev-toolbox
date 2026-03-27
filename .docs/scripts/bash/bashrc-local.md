# .bashrc.local

A per-user override file for secrets, API tokens, and machine-specific configuration. Sourced at the end of `.bashrc` so anything defined here takes precedence.

## Overview

The shared `.bashrc` is designed to be committed to version control. Personal settings that vary per developer -- credentials, project-specific aliases, startup commands -- belong in `~/.bashrc.local` instead. This file is gitignored and never shared.

## Setup

```bash
# Copy the template and fill in your values
cp scripts/bash/.bashrc.local.example ~/.bashrc.local

# Edit with your secrets and personal config
vim ~/.bashrc.local
```

## What Goes Here

| Category | Examples |
|----------|---------|
| **Cloud credentials** | `AWS_PROFILE`, `AWS_REGION`, `CLAUDE_CODE_USE_BEDROCK` |
| **API tokens** | `AZURE_DEVOPS_PAT`, `ATLASSIAN_API_TOKEN` |
| **Service config** | `AZURE_DEVOPS_ORG_URL`, `ATLASSIAN_SITE_NAME` |
| **Personal aliases** | `cdfs`, `cdlib`, `downloads` (paths that vary per machine) |
| **Startup commands** | Auto-cd to a project, run `git status`, trigger SSO login |
| **Editor overrides** | `export EDITOR=nvim` if different from the team default |

## Template

A [`.bashrc.local.example`](../../../scripts/bash/.bashrc.local.example) template is provided in `scripts/bash/` with commented-out sections for all common settings. Copy it and uncomment what you need.

## Security

- **Never commit `.bashrc.local`** -- it is listed in `.gitignore`.
- The shared `.bashrc` contains no secrets, tokens, or personal paths.
- If you rotate a token, update it in `~/.bashrc.local` and run `reload` to pick up the change.
