# dotfiles

Personal Windows / PowerShell 7 dotfiles with a clean, reproducible workflow.

This repository manages:

- PowerShell 7 profile
- Starship prompt configuration
- Windows Terminal settings
- Installed tools (winget export)
- PowerShell modules list

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
│  ├─ modules.txt
│  └─ choco-packages.config
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
- Optionally restores packages via `winget`
- Installs essential tools if missing

Optional flags:

```powershell
.\scripts\install.ps1 -CopyInsteadOfSymlink
.\scripts\install.ps1 -SkipWingetRestore
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

### Commands

#### `dots help`

Show built-in help.

#### `dots status`

Show git status.

#### `dots diff`

Show git diff.

#### `dots root`

Print dotfiles repository path.

#### `dots install`

Apply dotfiles to the system.
Runs `scripts/install.ps1`.

#### `dots backup`

Sync current system configs into the repo.
Runs `scripts/backup.ps1`.

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

#### `dots check`

Health check:

- Verifies symlinks
- Ensures files point to the repo versions

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
