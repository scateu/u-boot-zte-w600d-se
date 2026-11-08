#!/bin/bash
# SPDX-License-Identifier: GPL-2.0+
# Apply the ZTE W600D SE changes to a U-Boot checkout. See PATCHING.md.
#
#   ./patch-u-boot.sh [--am] [--check] <u-boot-dir>
#
#   (default)  git apply: changes are left uncommitted in the working tree
#   --am       git am: one commit per patch (needs git user.name/user.email)
#   --check    only test whether the series applies, change nothing
#
# Then cmd/typewriter/ is filled from ./typewriter/. Running it again on an
# already patched tree only refreshes cmd/typewriter/.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
U_BOOT_REV=709a97a05df66e394f40d249105d0baade46f107   # 2027.01-rc1
SERIES=("$HERE"/patches/u-boot/*.patch)
mode=apply

while [ $# -gt 1 ]; do
	case $1 in
	--am)    mode=am ;;
	--check) mode=check ;;
	*)       echo "unknown option $1" >&2; exit 2 ;;
	esac
	shift
done
[ $# -eq 1 ] || { sed -n '3,12p' "$0" >&2; exit 2; }
U=$(cd "$1" && pwd)
g() { git -C "$U" "$@"; }

g rev-parse --git-dir >/dev/null 2>&1 || { echo "error: $U is not a git checkout" >&2; exit 1; }
have=$(g rev-parse HEAD)
if [ "$have" != "$U_BOOT_REV" ] && ! g merge-base --is-ancestor "$U_BOOT_REV" HEAD 2>/dev/null; then
	echo "warning: $U is at $have; the series was made for $U_BOOT_REV" >&2
fi

# Already applied? (the last patch reverses cleanly)
last=${SERIES[${#SERIES[@]}-1]}
if g apply --check -R "$last" 2>/dev/null; then
	echo "series already applied in $U"
	[ $mode = check ] && exit 0
else
	for p in "${SERIES[@]}"; do
		echo "  $(basename "$p")"
	done
	case $mode in
	check)
		# each patch on top of the previous ones, in a scratch index
		tmp=$(mktemp -d)
		trap 'rm -rf "$tmp"' EXIT
		export GIT_INDEX_FILE=$tmp/index
		g read-tree HEAD
		for p in "${SERIES[@]}"; do
			g apply --cached "$p" || { echo "error: $(basename "$p") does not apply" >&2; exit 1; }
		done
		echo "series applies cleanly"
		exit 0 ;;
	apply)
		# all-or-nothing: --check the whole series first, in a scratch index
		"$0" --check "$U" >/dev/null
		for p in "${SERIES[@]}"; do g apply "$p"; done ;;
	am)
		g am -3 "${SERIES[@]}" ;;
	esac
fi

mkdir -p "$U/cmd/typewriter"
cp "$HERE"/typewriter/{*.c,*.h,Kconfig,Makefile} "$U/cmd/typewriter/"
echo "patched $U (+ cmd/typewriter/)"
echo "next: make zte-w600d-chain-rk3568_defconfig && make u-boot.bin  (see README.md)"
