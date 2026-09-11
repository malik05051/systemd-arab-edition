#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later

"""Rewrite Arch's systemd PKGBUILD so it builds this fork under its own package names.

The packaging repository builds packages called systemd, systemd-libs and so on, which is what we
want for the images mkosi builds, but not for packages published in a repository of our own: there
they would be indistinguishable from the distribution's and any later systemd upgrade would quietly
replace them. So every package is renamed with a suffix and declares that it provides and conflicts
with the name it was built from, which is what lets pacman swap one for the other.

The package list is read out of the PKGBUILD rather than hardcoded, so packages appearing or
disappearing on the packaging side need no change here.
"""

import re
import sys

SUFFIX = "-arab-edition"


def read_pkgnames(pkgbuild: str) -> list[str]:
    match = re.search(r"^pkgname=\((.*?)\)", pkgbuild, re.MULTILINE | re.DOTALL)
    if not match:
        raise ValueError("no pkgname=(…) array found")

    names = re.findall(r"""['"]([^'"]+)['"]""", match.group(1))
    if not names:
        raise ValueError("pkgname=(…) array is empty")

    return names


def rename_in_array(pkgbuild: str, keyword: str, names: list[str]) -> str:
    """Rename our own packages where they are listed in a keyword=(…) array."""

    def sub(match: re.Match) -> str:
        body = match.group(2)
        for name in names:
            # optdepends entries are "name: why you might want it", hence the colon.
            body = re.sub(rf"""(['"]){re.escape(name)}(['":])""", rf"\g<1>{name}{SUFFIX}\g<2>", body)
        return match.group(1) + body + match.group(3)

    return re.sub(
        rf"^(\s*{keyword}=\()(.*?)(\))",
        sub,
        pkgbuild,
        flags=re.MULTILINE | re.DOTALL,
    )


def declare_replacement(pkgbuild: str, name: str) -> str:
    """Append provides/conflicts for the original name at the end of a package function.

    makepkg reads the metadata variables once the package function has run, so appending is enough,
    and it keeps the provides and conflicts the packaging already sets (udev, systemd-tools, …).
    """
    opening = f"package_{name}{SUFFIX}() {{"
    start = pkgbuild.index(opening)
    end = pkgbuild.index("\n}\n", start)

    declaration = (
        f'\n  provides+=("{name}=$pkgver")\n'
        f"  conflicts+=('{name}')"
    )
    return pkgbuild[:end] + declaration + pkgbuild[end:]


def main() -> None:
    source, target = sys.argv[1], sys.argv[2]
    pkgbuild = open(source).read()

    names = read_pkgnames(pkgbuild)

    # GitHub rewrites the characters it does not like in the name of a release asset, a tilde among
    # them, so a package built as 262~rc2 is published as 262.rc2 while the database still asks for
    # the name it was built under. Spell the version so that it survives being published.
    pkgbuild = re.sub(
        r"^pkgver=(.*)$",
        lambda m: "pkgver=" + m.group(1).replace("~", "."),
        pkgbuild,
        flags=re.MULTILINE,
    )

    # pkgbase is deliberately left alone. It is not a package pacman installs, and the packaging uses
    # it as the name of the directory the sources are expected in, which is prepared for us under the
    # name the packaging repository knows.
    pkgbuild = rename_in_array(pkgbuild, "pkgname", names)

    # The packages depend on and recommend each other by name, so those references move too.
    # makedepends is deliberately left alone: it names what has to be installed to run the build,
    # which is still the distribution's own systemd, not ours.
    for keyword in ("depends", "optdepends"):
        pkgbuild = rename_in_array(pkgbuild, keyword, names)

    for name in names:
        pkgbuild = re.sub(
            rf"^package_{re.escape(name)}\(\)",
            f"package_{name}{SUFFIX}()",
            pkgbuild,
            flags=re.MULTILINE,
        )
        pkgbuild = declare_replacement(pkgbuild, name)

    open(target, "w").write(pkgbuild)

    print(f"renamed: {' '.join(name + SUFFIX for name in names)}", file=sys.stderr)


if __name__ == "__main__":
    main()
