<#
create-arch-wsl.ps1
Simplified PowerShell helper that installs Arch on WSL using `wsl --install` and then provisions a user and packages.

This script only supports the `--install` path. It will fail if `wsl --install` is not available or if an
Arch-related WSL distribution is already installed.
#>

param(
    [Parameter(Mandatory=$false)] [string]$DistroName = 'archlinux',
    [Parameter(Mandatory=$true)] [string]$Username,
    [Parameter(Mandatory=$false)] [System.Security.SecureString]$Password,
    [switch]$DryRun = $false,
    [string[]]$Packages = @('base','base-devel','sudo','vim','git','curl','wget','openssh','pacman-contrib'),
    [int]$PollTimeoutSeconds = 120,
    [string]$LocalRepoPath = $PSScriptRoot,
    [string]$LocalRepoName = 'localrepo',
    [string]$LocalRepoSigLevel = 'Optional TrustAll',
    [switch]$LocalRepoPrepend = $true,
    [switch]$Force = $false,
    [string]$SummaryJsonPath = ''
)

function Write-ErrAndExit($msg){ Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# Environment checks
if (-not $env:windir) { Write-ErrAndExit 'This script must be run on Windows PowerShell.' }
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { Write-ErrAndExit 'wsl.exe not found. Install WSL first (https://aka.ms/wslinstall).' }

# If an Arch-related distro already exists, bail out to avoid conflicts
$installedList = & wsl.exe -l -v 2>$null
if ($installedList -and ($installedList | Where-Object { $_ -match '(?i)arch' })) {
    Write-ErrAndExit 'An Arch-related WSL distribution already exists. Unregister or remove it before running this script.'
}

# Convert securestring password to plain text for provisioning (kept local only)
if (-not $Password) {
    if (-not $DryRun) { Write-ErrAndExit 'Password is required unless using -DryRun.' }
    $PlainPassword = ''
} else {
    $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    $PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($ptr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
}

# Find local UAR packages in the provided repo path (Windows path expected)
function Convert-WindowsPathToWsl($path) {
    # Convert 'C:\some\path' -> '/mnt/c/some/path'
    if ($path -match '^(?i)([A-Za-z]):\\(.*)') {
        $drive = $matches[1].ToLower()
        $rest = $matches[2] -replace '\\','/'
        return "/mnt/$drive/$rest"
    }
    # If already looks like /mnt or unix path, return as-is
    return $path
}

$localPkgWslPaths = @()
if ($LocalRepoPath) {
    if (-not (Test-Path -Path $LocalRepoPath)) {
        Write-Host "LocalRepoPath '$LocalRepoPath' does not exist; skipping local packages." -ForegroundColor Yellow
    } else {
        try {
            $localPkgs = Get-ChildItem -Path $LocalRepoPath -Recurse -Include '*.pkg.tar.zst' -File -ErrorAction SilentlyContinue
            if ($localPkgs) {
                foreach ($p in $localPkgs) {
                    $wslPath = Convert-WindowsPathToWsl $p.FullName
                    $localPkgWslPaths += $wslPath
                }
                Write-Host "Found local packages to install: $($localPkgWslPaths -join ', ')"
            }
        } catch {
            Write-Host "Error scanning LocalRepoPath: $_" -ForegroundColor Yellow
            }
        
            # Also look for PKGBUILD directories to build inside WSL
            $pkgbuildFiles = Get-ChildItem -Path $LocalRepoPath -Recurse -Filter 'PKGBUILD' -File -ErrorAction SilentlyContinue
            $pkgbuildDirs = @()
            if ($pkgbuildFiles) {
                foreach ($f in $pkgbuildFiles) { $pkgbuildDirs += $f.Directory.FullName }
                $pkgbuildDirs = $pkgbuildDirs | Sort-Object -Unique
                $pkgbuildWslDirs = @()
                foreach ($d in $pkgbuildDirs) { $pkgbuildWslDirs += Convert-WindowsPathToWsl $d }
                Write-Host "Found PKGBUILD dirs to build: $($pkgbuildWslDirs -join ', ')"
            }
        }
    }
}

# Ensure pkgbuildWslDirs is defined even if empty
if (-not (Get-Variable -Name pkgbuildWslDirs -Scope Local -ErrorAction SilentlyContinue)) { $pkgbuildWslDirs = @() }

# If SummaryJsonPath is provided, write a machine-readable summary and exit (unless DryRun is false)
if ($SummaryJsonPath) {
    $summary = [pscustomobject]@{
        DistroName = $DistroName
        Packages = $Packages
        LocalRepoPath = $LocalRepoPath
        LocalRepoName = $LocalRepoName
        LocalRepoSigLevel = $LocalRepoSigLevel
        LocalRepoPrepend = [bool]$LocalRepoPrepend
        PrebuiltPackages = $localPkgWslPaths
        PKGBUILDDirs = $pkgbuildWslDirs
        PollTimeoutSeconds = $PollTimeoutSeconds
    }
    $json = $summary | ConvertTo-Json -Depth 5
    Set-Content -Path $SummaryJsonPath -Value $json -Encoding UTF8
    Write-Host "Wrote summary JSON to $SummaryJsonPath"
    if ($DryRun) { exit 0 }
}

# Confirm before proceeding unless forced or dry-run
if (-not $Force -and -not $DryRun) {
    $resp = Read-Host "Proceed with installation? (y/N)"
    if ($resp -notin @('y','Y','yes','YES')) { Write-Host 'Aborted by user.'; exit 0 }
}

# Build provisioning command to run inside new distro
$pkgList = $Packages -join ' '
$escapedPassword = $PlainPassword -replace "'","'\\''"

# Prepare local repo commands if we found packages
$localRepoCmd = ''
    if ($localPkgWslPaths.Count -gt 0) {
    $quoted = $localPkgWslPaths | ForEach-Object { "'" + ($_ -replace "'","'\\''") + "'" }
    $copyArgs = $quoted -join ' '
    # Build robust local-repo setup: copy pkgs, repo-add (will update existing DB), optionally prepend repo to /etc/pacman.conf for priority
    $sig = $LocalRepoSigLevel
    $prependCmd = ''
    if ($LocalRepoPrepend) {
        # Prepend local repo stanza to /etc/pacman.conf if not already present
        $prependCmd = "if ! grep -q '^\\[$LocalRepoName\\]' /etc/pacman.conf; then printf '%s\\n' '[$LocalRepoName]' 'SigLevel = $sig' 'Server = file:///opt/localrepo' | cat - /etc/pacman.conf > /etc/pacman.conf.new && mv /etc/pacman.conf.new /etc/pacman.conf; fi;"
    }
    $localRepoCmd = "; mkdir -p /opt/localrepo; cp $copyArgs /opt/localrepo/; ls -1 /opt/localrepo > /tmp/localrepo-files.txt; cd /opt/localrepo; repo-add $LocalRepoName.db.tar.gz *.pkg.tar.zst; $prependCmd pacman -Sy --noconfirm; pacman -U --noconfirm *.pkg.tar.zst"
        # Build PKGBUILD dirs first (if any), then copy prebuilt pkgs and repo-add
        $buildCmd = ''
        if ($pkgbuildWslDirs -and $pkgbuildWslDirs.Count -gt 0) {
            # join directories quoted for shell
            $dirsQuoted = $pkgbuildWslDirs | ForEach-Object { '"' + $_ + '"' } -join ' '
            # export USE_AUR flag into shell and create a dedicated build root per state
            $useAURFlag = if ($UseAURHelper) { '1' } else { '0' }
            $buildCmd = "; pacman -Syu --noconfirm base-devel fakeroot git; pacman-key --init || true; pacman-key --populate archlinux || true; export USE_AUR=$useAURFlag; BUILD_ROOT=/opt/builds/$stateId; mkdir -p \"$BUILD_ROOT\"; for d in $dirsQuoted; do pkgbase=$(basename \"$d\"); WORK=\"$BUILD_ROOT/$pkgbase\"; rm -rf \"$WORK\"; mkdir -p \"$WORK\"; cp -a \"$d\"/. \"$WORK\"/; cd \"$WORK\"; if [ -f .use_yay ] && [ "$useAURFlag" = '1' ]; then echo "Building with AUR helper (yay)"; if ! command -v yay >/dev/null 2>&1; then git clone https://aur.archlinux.org/yay.git /tmp/yay-build && cd /tmp/yay-build && makepkg -si --noconfirm; fi; pkgname=$(awk -F= '/^pkgname=/{gsub(/["'\"']/,"",$2); print $2; exit}' PKGBUILD); yay -S --noconfirm --mflags '--skipinteg' "$pkgname" || exit 3; else if [ -f .buildenv ]; then set -a; . .buildenv; set +a; fi; flags=\"\"; if [ -f .makepkgflags ]; then flags=$(cat .makepkgflags); fi; env PACMAN='pacman --noconfirm' makepkg -s --noconfirm $flags || exit 2; mv -f *.pkg.tar.zst /opt/localrepo/; fi; done"
        }

        $localRepoCmd = "; mkdir -p /opt/localrepo$buildCmd; cp $copyArgs /opt/localrepo/; ls -1 /opt/localrepo > /tmp/localrepo-files.txt; cd /opt/localrepo; repo-add $LocalRepoName.db.tar.gz *.pkg.tar.zst; $prependCmd pacman -Sy --noconfirm; pacman -U --noconfirm *.pkg.tar.zst"
}

# Create a unique state id so we can rollback precisely if needed
$stateId = [guid]::NewGuid().ToString()
$provision = @"
set -euo pipefail
STATE_DIR=/tmp/arch-prov-$stateId
mkdir -p "$STATE_DIR"
# backup pacman.conf for possible rollback
cp /etc/pacman.conf "$STATE_DIR/pacman.conf.bak" || true
# record package lists before changes
pacman -Qq > "$STATE_DIR/pkgs-before.txt"
"@

# append the main package/install commands (including local repo handling)
$provision += "; pacman -Syu --noconfirm; pacman -S --noconfirm $pkgList"
if ($localRepoCmd) { $provision += "$localRepoCmd" }
$provision += "; pacman -Qq > \"/tmp/arch-prov-$stateId/pkgs-after.txt\"; ls -1 /opt/localrepo > \"/tmp/arch-prov-$stateId/localrepo-files-after.txt\" 2>/dev/null || true; id -u $Username >/dev/null 2>&1 || useradd -m -G wheel -s /bin/bash $Username; echo '$Username:$escapedPassword' | chpasswd; echo '$Username ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/90-$Username; chmod 0440 /etc/sudoers.d/90-$Username; touch \"/tmp/arch-prov-$stateId/success\""

Write-Host "Installing Arch via: wsl --install -d $DistroName"
if ($DryRun) {
    Write-Host "DRY RUN: Summary of actions to be performed"
    Write-Host "DistroName: $DistroName"
    Write-Host "Packages to install: $pkgList"
    Write-Host "LocalRepoPath: $LocalRepoPath"
    Write-Host "LocalRepoName: $LocalRepoName"
    Write-Host "LocalRepoSigLevel: $LocalRepoSigLevel"
    Write-Host "LocalRepoPrepend: $LocalRepoPrepend"
    if ($localPkgWslPaths.Count -gt 0) { Write-Host "Prebuilt local packages found (WSL paths):`n  $($localPkgWslPaths -join "`n  ")" }
    if ($pkgbuildWslDirs -and $pkgbuildWslDirs.Count -gt 0) { Write-Host "PKGBUILD dirs to be built (WSL paths):`n  $($pkgbuildWslDirs -join "`n  ")" }
    Write-Host "PollTimeoutSeconds: $PollTimeoutSeconds"
    Write-Host "UseWslInstall: $UseWslInstall"
    Write-Host "DryRun: $DryRun"
    exit 0
}
try {
    $proc = Start-Process -FilePath wsl.exe -ArgumentList @('--install','-d',$DistroName) -NoNewWindow -Wait -PassThru -ErrorAction Stop
} catch {
    Write-ErrAndExit "Failed to invoke 'wsl --install': $_"
}

if (-not $proc -or $proc.ExitCode -ne 0) { Write-ErrAndExit "'wsl --install' failed with exit code $($proc.ExitCode)" }

# Poll until the distro is listed and responsive, then provision
$found = $false
$endTime = (Get-Date).AddSeconds($PollTimeoutSeconds)
Write-Host "Waiting up to $PollTimeoutSeconds seconds for distro to become available..."
while ((Get-Date) -lt $endTime) {
    $list = & wsl.exe -l -v 2>$null
    $installedLine = $list | Where-Object { $_ -match '(?i)arch' } | Select-Object -First 1
    if ($installedLine) {
        if ($installedLine -match '^\s*(\S+)') { $InstalledDistro = $matches[1] } else { $InstalledDistro = $DistroName }

        # quick responsiveness test: run a harmless command
        try {
            $test = Start-Process -FilePath wsl.exe -ArgumentList @('-d', $InstalledDistro, '--', 'bash', '-lc', 'echo ready') -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue
            if ($test -and $test.ExitCode -eq 0) { $found = $true; break }
        } catch { }
    }
    Start-Sleep -Seconds 2
}

if (-not $found) { Write-ErrAndExit "Distro did not become available/respond within $PollTimeoutSeconds seconds." }

Write-Host "Provisioning installed distro: $InstalledDistro"
try {
    $proc2 = Start-Process -FilePath wsl.exe -ArgumentList @('-d', $InstalledDistro, '--', 'bash', '-lc', $provision) -NoNewWindow -Wait -PassThru -ErrorAction Stop
    if ($proc2.ExitCode -ne 0) { throw "Provisioning failed with exit code $($proc2.ExitCode)" }
} catch {
        Write-Host "Provisioning failed: $_" -ForegroundColor Red
        Write-Host "Attempting granular rollback inside the distro using state id: $stateId"
        $rollbackScript = @"
#!/bin/bash
set -euo pipefail
STATE_DIR=/tmp/arch-prov-$stateId
if [ ! -d "$STATE_DIR" ]; then
    echo "No state directory found: $STATE_DIR" >&2
    exit 2
fi
# restore pacman.conf
if [ -f "$STATE_DIR/pacman.conf.bak" ]; then
    cp "$STATE_DIR/pacman.conf.bak" /etc/pacman.conf || true
fi
# compute newly installed packages and remove them
if [ -f "$STATE_DIR/pkgs-before.txt" -a -f "$STATE_DIR/pkgs-after.txt" ]; then
    comm -13 <(sort "$STATE_DIR/pkgs-before.txt") <(sort "$STATE_DIR/pkgs-after.txt") > "$STATE_DIR/pkgs-to-remove.txt" || true
    if [ -s "$STATE_DIR/pkgs-to-remove.txt" ]; then
        xargs -r pacman -R --noconfirm < "$STATE_DIR/pkgs-to-remove.txt" || true
    fi
fi
# remove copied local files
if [ -f "$STATE_DIR/localrepo-files-after.txt" ]; then
    while read -r f; do
        rm -f "/opt/localrepo/$f" || true
    done < "$STATE_DIR/localrepo-files-after.txt"
fi
exit 0
"@

        # write the rollback script to a temp on Windows and run it inside WSL
        $rbFile = Join-Path $env:TEMP "wsl-rollback-$stateId.sh"
        Set-Content -Path $rbFile -Value $rollbackScript -Encoding UTF8
        try {
                # copy script into distro and execute
                Start-Process -FilePath wsl.exe -ArgumentList @('-d', $InstalledDistro, '--', 'bash', '-lc', "cat > /tmp/rollback-$stateId.sh <<'EOF'`n$(Get-Content -Raw $rbFile)`nEOF; chmod +x /tmp/rollback-$stateId.sh; /tmp/rollback-$stateId.sh") -NoNewWindow -Wait -PassThru -ErrorAction Stop
                Write-Host "Granular rollback executed inside distro"
        } catch {
                Write-Host "Granular rollback failed: $_" -ForegroundColor Yellow
                Write-Host "Falling back to full unregister of distro '$InstalledDistro'"
                try {
                        Start-Process -FilePath wsl.exe -ArgumentList @('--unregister', $InstalledDistro) -NoNewWindow -Wait -PassThru -ErrorAction Stop
                        Write-Host "Rollback: distro unregistered"
                } catch {
                        Write-Host "Rollback failed: could not unregister distro: $_" -ForegroundColor Red
                }
        }

        Write-ErrAndExit "Provisioning failed and rollback attempted. See messages above."
}

Write-Host "Done. You can now start the distro with: wsl -d $InstalledDistro"
Write-Host "First login: wsl -d $InstalledDistro -u $Username"

exit 0
