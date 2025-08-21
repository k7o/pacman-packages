# pacman-packages

This repository stores source PKGBUILD files used to build Arch/Arch-derivative packages.

## Goal

Keep a plain collection of `PKGBUILD` scripts here. Use `makepkg` locally to build packages and `repoctl` to add the resulting `.pkg.tar.zst` files into a package repository.

## Quick checklist

- Edit or add `PKGBUILD` files in per-package directories (for example `oras/PKGBUILD`).
- Build packages with `makepkg -si` (or `makepkg -cf` in CI).
- Use `repoctl` to add built package files to your repository (local or remote).

## Writing `PKGBUILD` files

A `PKGBUILD` is a shell script that describes how to fetch, verify, build and package a piece of software. Minimal shape:

1. Start with metadata variables: `pkgname`, `pkgver`, `pkgrel`, `arch`, `url`, `license`, `depends`, `makedepends`, and `source`.
2. Implement `prepare()` (optional), `build()` (optional for interpreted/lang packages), and `package()` functions.
3. Export checksums with `sha512sums` or another `sha*` and keep sources reproducible.

Example minimal `PKGBUILD` (conceptual):

```sh
# Maintainer: Your Name <you@example.com>
pkgname=example
pkgver=1.2.3
pkgrel=1
arch=(x86_64)
url="https://example.org"
license=(MIT)
depends=(libc)
source=("https://example.org/example-${pkgver}.tar.gz")
sha512sums=("<fill-in-checksum>")

build() {
  cd "$srcdir/${pkgname}-${pkgver}"
  ./configure --prefix=/usr
  make
}

package() {
  cd "$srcdir/${pkgname}-${pkgver}"
  make DESTDIR="$pkgdir" install
}
```

For full guidance and best practices, see the Arch Wiki: https://wiki.archlinux.org/title/PKGBUILD

## Building packages

Install the base build tools on an Arch-based system:

```bash
sudo pacman -S --needed base-devel git
```

To build a package locally from its directory:

```bash
# change into the package directory containing PKGBUILD
cd path/to/package-dir
# fetch sources and build a package in the current directory
makepkg -c
```

Common flags:

- `-s` — resolve dependencies from the repos (install required deps)
- `-i` — install the resulting package after building
- `-c` — clean build files after a successful build
- `-f` — force build even if package exists

In CI or reproducible builds, prefer `makepkg -cf` and run inside a clean chroot (e.g., `devtools` or `arch-chroot`/`docker`).

## Adding built packages to a repo with `repoctl`

`repoctl` is a tool to manage pacman package repositories. To add generated packages into your repo:

1. Build packages with `makepkg` so you have `*.pkg.tar.zst` files.
2. Use `repoctl add` to add them to a repository directory or remote endpoint.

Example: add packages to a local repo directory

```bash
# assume REPO_DIR is where your repoctl-managed repo lives
REPO_DIR=/var/www/html/repos/community
# add one or more packages
repoctl add "$REPO_DIR" ./mypkg-1.2.3-1-x86_64.pkg.tar.zst
```

If your repository is served over HTTP (for clients to use), make sure the repo directory is readable by the webserver and you run `repoctl` against the repo path it manages.

repoctl documentation and source:

- Project page / README (search GitHub or your distro's packaging): https://github.com/archlinuxfr/repoctl (example; your distro may host a fork)
- man page: `man repoctl` (after installing)

Notes on signing and publishing

- If you sign packages or repository metadata, ensure `gpg` keys and `repoctl` configuration are set up. Some workflows sign individual packages and/or the `repo.db` files.
- Test adding packages to a local repo and configuring a test client to consume it before publishing widely.

## Examples

- Build `oras` in this repo:

```bash
cd oras
makepkg -c
# Result: oras-<ver>-<rel>-x86_64.pkg.tar.zst
```

- Add built package to a repository:

```bash
repoctl add /srv/pacman/repo oras-*.pkg.tar.zst
```

If you want, I can:

- Add a short example `PKGBUILD` for one of the packages in this tree.
- Add a small script to build all `PKGBUILD` files under the repo and collect outputs into `out/`.

## Repository placement and ownership

Where you place a built-package repository matters for permissions and consumption. The repository directory should be managed as a system resource and owned by `root` so package metadata can be read by pacman (which runs as root) and by server processes when served over HTTP.

Recommended locations

- `/srv/pacman/repo/eric` — preferred for system-hosted repos.
- `/var/www/html/repos/eric` — if you will serve the repo over HTTP from a webserver.
- `/opt/pacman/repo/eric` or `/usr/local/share/pacman/repo` — for local admin-managed repos.

Ownership and permissions

- Owner: `root:root` (or `root:<web-group>` if the webserver needs group access).
- Directories: `755` (or `750` with a webserver group).
- Files: `644` (or `640` with a webserver group).

Example safe move and permission commands

```bash
# create destination and copy (keeps original until verified)
sudo mkdir -p /srv/pacman/repo/eric
sudo rsync -aHAX --progress /home/eric/pkgs/ /srv/pacman/repo/eric/

# set root ownership and readable perms
sudo chown -R root:root /srv/pacman/repo/eric
sudo find /srv/pacman/repo/eric -type d -exec chmod 755 {} +
sudo find /srv/pacman/repo/eric -type f -exec chmod 644 {} +
```

If you serve the repo with a webserver that runs under a specific group (for example `www-data`), set the group and tighten perms:

```bash
sudo chown -R root:www-data /srv/pacman/repo/eric
sudo find /srv/pacman/repo/eric -type d -exec chmod 750 {} +
sudo find /srv/pacman/repo/eric -type f -exec chmod 640 {} +
```

Update `pacman.conf` to point to the final location (example):

```
[eric]
Server = file:///srv/pacman/repo/eric
```

Notes

- Prefer serving via HTTP for easier client access and clearer permissions. If so, place files under your webserver document root or `/srv` and configure the webserver accordingly.
- Keep repo data out of a user home directory to avoid traversal and privacy issues.
- Automate `repo-add`/`repoctl` invocation in a root-run CI job or systemd timer that updates the repo in its final location.

## Bundle

This folder contains a simple bundle that builds selected PKGBUILD packages from this repository and produces a meta-package `pacman-bundle`.

How it works

- `packages/` contains per-package directories. Copy or edit PKGBUILD files here.
- `bundle/PKGBUILD` is a meta-package that depends on the listed package names.
- `scripts/build-all.sh` builds each package and puts results into `out/`.
- `scripts/repoctl-add.sh` adds built packages to a repo using `repoctl` or `repo-add`.

Quick start

```sh
cd pacman-bundle/pacman-bundle
make build
# then add to repo
make repo-add REPO=/srv/pacman/repo
```

Notes

- This repo expects to run on an Arch-like system with `makepkg`, `repoctl`/`repo-add` available.
- `build-all.sh` uses `makepkg -cf` which will attempt network fetches. Run inside a chroot or container for clean builds.

## Troubleshooting

- If `makepkg` fails, check that `sha512sums` match the downloaded sources; update checksums with `updpkgsums`.
- For dependency issues, install `base-devel` and any `makedepends` listed in the PKGBUILD.
- If `repoctl` can't write or update the repo, check permissions and that the repo path is correct.

## References

- Arch Wiki: PKGBUILD — https://wiki.archlinux.org/title/PKGBUILD
- makepkg — https://wiki.archlinux.org/title/Makepkg
- repoctl (project repository / man page) — check your distribution's packaging or upstream GitHub.
