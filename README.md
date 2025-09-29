## .local-dev-toolbox

Developer automation and environment setup scripts.

## Contents


### Scripts
- `scripts/powershell/_update-repos.ps1` – Batch fetch/pull for multiple Git repositories by prefix.
- todo

## Quick Start
1. Clone this repository.
2. Adjust variables (like `$Script:ChildFolderPrefix`) in scripts as needed.
3. Run a script:

```powershell
pwsh ./scripts/powershell/_update-repos.ps1 -root-path D:\Repos --no-pull
```

## Contributing

### Scripts
- Add scripts under `scripts/<area>/`, add short description in content section abova and any additional notes with `<scripts-name>.md`.

