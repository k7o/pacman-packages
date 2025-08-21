
# Arch WSL provisioning helper

This repository includes `create-arch-wsl.ps1`, a PowerShell helper that installs Arch Linux into WSL using the modern `wsl --install` path and then provisions the distro.

## High level behavior

- Uses `wsl --install -d <DistroName>` (WSL installer path). The script does not perform `wsl --import` or manual tar extraction.
- Waits for the installed distro to become responsive before provisioning.
- Runs pacman to update the system and install a set of packages (configurable).
- Supports installing local packages present in the repository and building PKGBUILDs inside the newly created distro.
- Creates the requested user and writes a NOPASSWD sudoers entry by default.

## Key features and options

- `-DistroName` (default: `archlinux`) — name used with `wsl --install`.
- `-Username`, `-Password` — user created inside the distro (password optional when using `-DryRun`).
- `-Packages` — array of pacman packages to install (defaults include build tooling and `pacman-contrib`).
- `-LocalRepoPath` — path (Windows) to search for prebuilt packages (`*.pkg.tar.zst`) and PKGBUILD directories. Defaults to the script directory.
- Local packages are copied into `/opt/localrepo` inside the distro and `repo-add` is used to create a `file:///opt/localrepo` repository. The script adds a repo stanza to pacman configuration (configurable SigLevel and repo name).
- PKGBUILD directories found under `-LocalRepoPath` are staged into `/opt/builds/<stateId>/<pkg>` inside the distro and built with `makepkg` (staged builds avoid mutating the repo source). Per-PKGBUILD files supported:
	- `.buildenv` — environment variables to export before running `makepkg`.
	- `.makepkgflags` — extra flags appended to `makepkg`.
	- `.use_yay` — if present and AUR helper is enabled, builds/installs via `yay` instead of `makepkg`.
- `-UseAURHelper` (opt-in) — installs/builds AUR helper (`yay`) inside the distro and uses it when `.use_yay` is present.
- `-LocalRepoName`, `-LocalRepoSigLevel`, `-LocalRepoPrepend` — configure local repo name, signature policy (e.g. `Optional TrustAll`), and whether the repo stanza is prepended to `/etc/pacman.conf`.
- `-PollTimeoutSeconds` — how long to wait for the distro to become responsive before provisioning.
- `-DryRun` — prints a summary of planned actions and exits.
- `-SummaryJsonPath` — writes a machine-readable JSON summary (packages, local pkgs, PKGBUILD dirs) useful for automation.
- `-Force` — skip interactive confirmation prompt.

## Rollback and error handling

- The script uses strict error handling for repo steps and will attempt a granular rollback on provisioning failure. Rollback tries to:
	- restore the backed-up `/etc/pacman.conf`,
	- uninstall packages that were added during the failed provisioning run,
	- remove copied files from `/opt/localrepo`.
- If granular rollback fails, the script falls back to `wsl --unregister <DistroName>` to remove the distro (this is destructive).

## Security / behavior notes

- By default the script creates a NOPASSWD sudoers entry for convenience. Remove or edit the sudoers line in the script to require a password.
- The default local repo SigLevel is permissive (`Optional TrustAll`) to allow unsigned local packages; change `-LocalRepoSigLevel` to require signatures if you provide signed packages.
- The build steps run inside the WSL distro (not on Windows) to avoid cross-platform build issues.

## Example usage

Dry run / preview:

```powershell
.\create-arch-wsl.ps1 -Username eric -DryRun
```

Produce a JSON summary for automation:

```powershell
.\create-arch-wsl.ps1 -Username eric -DryRun -SummaryJsonPath summary.json
```

Run interactively with confirmation (default):

```powershell
$pw = Read-Host -AsSecureString "New user password"
.\create-arch-wsl.ps1 -Username eric -Password $pw
```

Run non-interactively (no prompt):

```powershell
$pw = Read-Host -AsSecureString "pw"
.\create-arch-wsl.ps1 -Username eric -Password $pw -Force
```

Build PKGBUILDs under the repo and install local packages:

```powershell
$pw = Read-Host -AsSecureString "pw"
.\create-arch-wsl.ps1 -Username eric -Password $pw -LocalRepoPath 'C:\path\to\repo'
```

## Notes for maintainers

- Test runs are best done in a disposable Windows user or VM because the script may unregister the distro during rollback.
- If you want package signatures enforced, sign packages or change `-LocalRepoSigLevel` and import keys into the distro before running.

If you'd like, I can add an optional `--parallel-builds` flag to speed up PKGBUILD builds, or add a `--no-rollback` mode for debugging.

