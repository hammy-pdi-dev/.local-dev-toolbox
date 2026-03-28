# pre-commit Hook — Gitleaks Secret Scanning

A Git pre-commit hook that runs [gitleaks](https://github.com/gitleaks/gitleaks) against staged changes to prevent secrets (API keys, tokens, passwords) from being committed.

## Prerequisites

Install gitleaks:

```bash
# macOS
brew install gitleaks

# Linux (snap)
sudo snap install gitleaks

# Linux (binary)
# Download from https://github.com/gitleaks/gitleaks/releases

# Windows (scoop)
scoop install gitleaks

# Windows (chocolatey)
choco install gitleaks
```

## Installation

Copy the hook into your repository's `.git/hooks/` folder:

```bash
cp scripts/git-hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## How It Works

1. On every `git commit`, the hook runs `gitleaks git --pre-commit --staged --verbose`.
2. Gitleaks scans only the staged diff (not the full repo history) for patterns matching known secret formats.
3. If secrets are found, the commit is blocked with a summary of findings.
4. If gitleaks is not installed, the hook prints a warning and allows the commit through.

## Configuration

### `.gitleaks.toml`

The repository-level `.gitleaks.toml` extends the default gitleaks ruleset. Use it to:

- **Allow specific paths** that generate false positives (e.g. IDE config directories).
- **Allow specific patterns** via regex in `[allowlist.regexes]`.
- **Add custom rules** for project-specific secret patterns.

See the [gitleaks configuration docs](https://github.com/gitleaks/gitleaks#configuration) for the full schema.

### Inline Allowlisting

For individual false positives, add an inline comment:

```python
api_url = "https://example.com/v1"  # gitleaks:allow
```

### Bypassing the Hook

If a false positive is blocking and you need to commit urgently:

```bash
SKIP_GITLEAKS=1 git commit -m "message"
```

Use this sparingly — prefer fixing the allowlist instead.

## Scanning Repository History

To scan the full repository history for previously committed secrets:

```bash
gitleaks git --verbose
```

This is useful for auditing existing commits but is not run by the pre-commit hook (which only checks staged changes).
