#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
set -eu
set -o pipefail

# Publish the packages built by
#
#     mkosi -d arch -E RENAME_PACKAGES=1 -t none -f
#
# as a pacman repository, hosted as the assets of a GitHub release. Assembles the repository
# directory from the freshly built packages, signs its database, and replaces the release.
#
# Everything is overridable from the environment:

SRCDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REPO_NAME="${REPO_NAME:-malik05}"                       # pacman.conf section name, hence <name>.db
REPO_DIR="${REPO_DIR:-/srv/malik05}"
GITHUB_REPO="${GITHUB_REPO:-malik05051/malik05-repo}"
RELEASE_TAG="${RELEASE_TAG:-repo}"
BUILD_DIR="${BUILD_DIR:-$SRCDIR/build/mkosi.builddir}"

# Signing needs our own gpg keyring and agent, which root does not have: under sudo the key is
# simply "not in your keyring". The repository directory therefore has to be ours, so that none of
# this needs privileges at all.
if [[ "$(id -u)" -eq 0 ]]; then
    echo "Run this as yourself, not as root: signing needs your gpg keyring." >&2
    echo "If $REPO_DIR is owned by root, hand it over once with" >&2
    echo "    sudo chown -R \"\$USER\" $REPO_DIR" >&2
    exit 1
fi

for tool in repo-add zstd gh; do
    command -v "$tool" >/dev/null || { echo "$tool is not installed." >&2; exit 1; }
done

mapfile -t packages < <(find "$BUILD_DIR" -name '*.pkg.tar' -o -name '*.pkg.tar.zst' | sort)
if [[ "${#packages[@]}" -eq 0 ]]; then
    echo "No packages under $BUILD_DIR. Build them first with" >&2
    echo "    mkosi -d arch -E RENAME_PACKAGES=1 -t none -f" >&2
    exit 1
fi

# GitHub rewrites the characters it does not like in the name of a release asset, so a package whose
# name carries one is published under a name the database does not know and every download of it
# answers 404. Catch that here rather than on the machine trying to install it.
for package in "${packages[@]}"; do
    if [[ "$(basename "$package")" =~ [^A-Za-z0-9._-] ]]; then
        echo "Package name survives publishing badly: $(basename "$package")" >&2
        echo "GitHub rewrites anything outside [A-Za-z0-9._-] in a release asset's name." >&2
        exit 1
    fi
done

mkdir -p "$REPO_DIR"
# Start from an empty directory: packages left over from an earlier version would otherwise stay in
# the database next to the ones we just built.
rm -f "$REPO_DIR"/*.pkg.tar "$REPO_DIR"/*.pkg.tar.zst "$REPO_DIR"/*.sig \
      "$REPO_DIR/$REPO_NAME".db* "$REPO_DIR/$REPO_NAME".files*
cp -t "$REPO_DIR" "${packages[@]}"

cd "$REPO_DIR"

# mkosi builds uncompressed packages for speed; compress before repo-add, as the database records
# the file names it is given.
shopt -s nullglob
for package in *.pkg.tar; do
    zstd --quiet --rm "$package"
done
shopt -u nullglob

# --sign takes the key from GPGKEY in makepkg.conf, or pass --key here.
repo-add --sign "$REPO_NAME.db.tar.zst" ./*.pkg.tar.zst

# pacman asks for <name>.db and <name>.files, which repo-add leaves as symlinks to the archives it
# wrote. A symlink cannot be a release asset, so publish copies instead. The signatures cover the
# bytes, so they are valid for the copies too.
for suffix in db files; do
    cp --remove-destination "$REPO_NAME.$suffix.tar.zst" "$REPO_NAME.$suffix"
    cp --remove-destination "$REPO_NAME.$suffix.tar.zst.sig" "$REPO_NAME.$suffix.sig"
done

# The signatures are the step most easily forgotten, and their absence only shows up as a 404 on the
# machine trying to sync, so refuse to publish without them.
for required in "$REPO_NAME".db "$REPO_NAME".db.sig "$REPO_NAME".files "$REPO_NAME".files.sig; do
    [[ -s "$required" ]] || { echo "$required is missing or empty, not publishing." >&2; exit 1; }
done

version="$(cat "$SRCDIR/meson.version" 2>/dev/null || echo unknown)"

published=( ./*.pkg.tar.zst )
echo "Publishing ${#published[@]} packages as $GITHUB_REPO release '$RELEASE_TAG'."

# The release is replaced rather than added to: an asset of a version we no longer ship would linger
# forever otherwise.
gh release delete "$RELEASE_TAG" --repo "$GITHUB_REPO" --yes --cleanup-tag 2>/dev/null || true
gh release create "$RELEASE_TAG" --repo "$GITHUB_REPO" \
   --title "systemd-arab-edition v$version" \
   --notes "Packages built from systemd $version." \
   "${published[@]}" "$REPO_NAME".db* "$REPO_NAME".files*

cat <<EOF

Published. On a machine that does not have the repository yet:

    [$REPO_NAME]
    SigLevel = DatabaseRequired PackageOptional TrustedOnly
    Server = https://github.com/$GITHUB_REPO/releases/latest/download

above [core] in /etc/pacman.conf, with our key imported:

    gpg --export --armor \$GPGKEY > key.asc
    sudo pacman-key --add key.asc
    sudo pacman-key --lsign-key \$GPGKEY

then:

    sudo pacman -Syy
EOF
