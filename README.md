# dotfiles

Personal Windows / PowerShell 7 dotfiles with a clean, reproducible workflow.

This repository manages:

- PowerShell 7 profile
- Starship prompt configuration
- Windows Terminal settings
- Installed tools (winget export)
- PowerShell modules list
- Work applications (allowlist-based)

Everything is designed to be:

- **Idempotent**
- **Safe to re-run**
- **Diff-friendly**
- **Symlink-first, copy-fallback**

---

## Requirements

- Windows 10 / 11
- PowerShell **7+**
- Git
- (Optional, recommended)
  - winget
  - Windows Terminal
  - Starship

---

## Repository structure

```
dotfiles/
├─ powershell/
│  └─ Microsoft.PowerShell_profile.ps1
│
├─ starship/
│  └─ starship.toml
│
├─ windows-terminal/
│  └─ settings.json
│
├─ scripts/
│  ├─ install.ps1
│  └─ backup.ps1
│
├─ exports/
│  ├─ winget.json
│  ├─ winget.allowlist.txt
│  ├─ winget.work.json
│  └─ modules.txt
│
├─ .gitattributes
└─ README.md
```

---

## Installation (new machine)

Clone the repository:

```powershell
git clone https://github.com/kixygod/dotfiles.git $HOME\dotfiles
```

Run install:

```powershell
cd $HOME\dotfiles
.\scripts\install.ps1
```

What `install.ps1` does:

- Creates **symbolic links** to repo files
- Falls back to copying if symlinks are not allowed
- Optionally installs PowerShell modules (Terminal-Icons by default)
- Optionally restores packages via `winget`
- Backs up existing files before overwriting

Optional flags:

```powershell
.\scripts\install.ps1 -CopyInsteadOfSymlink
.\scripts\install.ps1 -Winget
.\scripts\install.ps1 -WingetUpgrade
.\scripts\install.ps1 -SkipBootstrap
```

---

## Daily workflow

All interaction is done through the `dots` helper function.

### Typical flow

```powershell
dots save
dots commit "your message"
dots push
```

---

## `dots` command reference

Run anytime:

```powershell
dots help
```

### Core commands

#### `dots help`

Show built-in help.

#### `dots doctor`

System health check:

- Verifies PowerShell version
- Checks for git, winget, starship
- Reports missing tools

#### `dots check`

Health check:

- Verifies symlinks
- Ensures files point to the repo versions

#### `dots root`

Print dotfiles repository path.

### Dotfiles management

#### `dots install`

Apply dotfiles to the system.
Runs `scripts/install.ps1`.

#### `dots backup`

Sync current system configs into the repo.
Runs `scripts/backup.ps1`.

### Git workflow

#### `dots status`

Show git status.

#### `dots diff`

Show git diff.

#### `dots save`

Local preparation step:

- Runs backup
- Stages all changes
- Shows status and staged diff summary

Does **not** commit.

#### `dots commit "message"`

Commit staged changes.

Notes:

- If nothing is staged, prints a warning
- Expects `dots save` to be run first

#### `dots push`

Push current `HEAD` to `origin`.

### Apps management (allowlist-based)

Work applications are managed via an allowlist system.

#### `dots apps export`

Generate `exports/winget.work.json` from `exports/winget.allowlist.txt`.

You maintain the allowlist file manually.

#### `dots apps sync`

Install missing applications from `exports/winget.work.json`.

#### `dots apps upgrade`

Upgrade all installed packages via `winget upgrade --all`.

#### `dots apps diff`

Compare installed packages vs allowlist:

- Shows missing (in allowlist but not installed)
- Shows extra (installed but not in allowlist)

---

## Backup behavior

`backup.ps1` is designed to be **safe and quiet**:

- Detects and skips:

  - identical paths
  - symlink loops

- Copies by **content**, not filesystem semantics
- Normalizes `winget.json` to reduce noisy diffs
- Removes volatile fields (like `CreationDate`)
- Writes files **only if content changed**

This keeps git history clean and meaningful.

---

## Apps management workflow

1. Edit `exports/winget.allowlist.txt` (one package identifier per line)
2. Run `dots apps export` to generate `exports/winget.work.json`
3. Run `dots apps sync` to install missing packages
4. Use `dots apps diff` to verify state

The allowlist file is tracked in git; `winget.work.json` is auto-generated.

---

## Line endings & formatting

Handled via `.gitattributes`:

- LF enforced in repo
- Windows-friendly on checkout
- JSON / PowerShell / TOML normalized

This avoids CRLF noise in commits.

---

## Design principles

- Explicit > implicit
- No magic state
- Every command can be re-run safely
- Errors are visible
- No silent git operations

---

## License

Personal dotfiles.
Use, fork, or adapt freely.
