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

## Troubleshooting

- If `makepkg` fails, check that `sha512sums` match the downloaded sources; update checksums with `updpkgsums`.
- For dependency issues, install `base-devel` and any `makedepends` listed in the PKGBUILD.
- If `repoctl` can't write or update the repo, check permissions and that the repo path is correct.

## References

- Arch Wiki: PKGBUILD — https://wiki.archlinux.org/title/PKGBUILD
- makepkg — https://wiki.archlinux.org/title/Makepkg
- repoctl (project repository / man page) — check your distribution's packaging or upstream GitHub.

If you want, I can:

- Add a short example `PKGBUILD` for one of the packages in this tree.
- Add a small script to build all `PKGBUILD` files under the repo and collect outputs into `out/`.
