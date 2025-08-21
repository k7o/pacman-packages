#!/bin/sh
set -euo pipefail
ROOTDIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTDIR="$ROOTDIR/out"
mkdir -p "$OUTDIR"

# Build each package directory under packages/
for d in "$ROOTDIR"/packages/*; do
  [ -d "$d" ] || continue
  echo "Building package in $d"
  (cd "$d" && makepkg -cf --packagetype=custom) || { echo "build failed for $d"; exit 1; }
  # move built package(s) to out/
  mv ./*.pkg.tar.* "$OUTDIR/" 2>/dev/null || true
done

# Build bundle meta package
cd "$ROOTDIR/bundle"
makepkg -cf
mv ./*.pkg.tar.* "$OUTDIR/" 2>/dev/null || true

echo "All packages built into $OUTDIR"
