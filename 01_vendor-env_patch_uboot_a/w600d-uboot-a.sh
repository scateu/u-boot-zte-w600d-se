#!/bin/bash
# SPDX-License-Identifier: GPL-2.0+
# Patch the ZTE W600D SE vendor U-Boot (uboot_a) over adb so it boots a USB
# stick first. Run on the PC; the laptop runs Android with root (`su 0`).
# See README.md, step 1.
#
#   w600d-uboot-a.sh [-s <adb-serial>] install        backup + patch + flash (the usual way)
#   w600d-uboot-a.sh [-s ...] backup [dir]            dump uboot_a, uboot_b, misc to dir
#   w600d-uboot-a.sh [-s ...] flash <uboot_a.img>     write an image to uboot_a (asks first)
#   w600d-uboot-a.sh [-s ...] check                   slot, uboot_a hash, A/B state
#   YES=1 w600d-uboot-a.sh ...                        no confirmation prompts
#
# Restore the original: w600d-uboot-a.sh flash <backup dir>/uboot_a.img
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
STOCK_SHA=2375420f37c0d1c435e6e359d9e25fab13120007869457b4ff8d7d81fd38ad1c    # uboot_a 2024-05-29
PATCHED_SHA=36e264b12dc757a2a92900d101f7423c5681585ad7cc524c924582bad54e629d  # its USB-first version
TMP=/data/local/tmp

ADB=(adb)
if [ "${1:-}" = -s ]; then ADB=(adb -s "$2"); shift 2; fi
cmd=${1:-}; shift || true

sha() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
ash() { "${ADB[@]}" shell "$@" | tr -d '\r'; }
root() { ash "su 0 sh -c '$1'"; }

need_device() {
	"${ADB[@]}" get-state >/dev/null || { echo "error: no adb device" >&2; exit 1; }
	[ "$(root "id -u")" = 0 ] || { echo "error: no root (su 0)" >&2; exit 1; }
	model=$(ash getprop ro.product.device)
	[ "$model" = rk3568_r_w600d2 ] || { echo "error: device is '$model', not rk3568_r_w600d2" >&2; exit 1; }
}

backup() {
	dir=${1:-w600d-uboot-backup-$(date +%Y%m%d-%H%M%S)}
	mkdir -p "$dir"
	for p in uboot_a uboot_b misc; do
		root "dd if=/dev/block/by-name/$p of=$TMP/$p.img bs=1048576 2>/dev/null"
		"${ADB[@]}" pull "$TMP/$p.img" "$dir/$p.img" >/dev/null 2>&1
		dev=$(root "sha256sum $TMP/$p.img" | cut -d' ' -f1)
		[ "$(sha "$dir/$p.img")" = "$dev" ] || { echo "error: $p copy mismatch" >&2; exit 1; }
		root "rm -f $TMP/$p.img"
	done
	(cd "$dir" && for f in uboot_a.img uboot_b.img misc.img; do echo "$(sha "$f")  $f"; done > SHA256SUMS)
	echo "backup in $dir:"; cat "$dir/SHA256SUMS"
	BACKUP=$dir
}

flash() {
	img=$1
	want=$(sha "$img")
	[ "$(wc -c < "$img")" -eq $((4 * 1024 * 1024)) ] || { echo "error: $img is not a 4 MiB uboot image" >&2; exit 1; }
	slot=$(ash getprop ro.boot.slot_suffix)
	[ "$slot" = _a ] || { echo "error: running slot is '$slot'; boot slot A first (slot B is the rescue)" >&2; exit 1; }
	echo "write $img ($want) to uboot_a"
	echo "  current uboot_a: $(root 'dd if=/dev/block/by-name/uboot_a bs=1048576 2>/dev/null | sha256sum' | cut -d' ' -f1)"
	ok=${YES:-}; [ "$ok" = 1 ] && ok=YES || read -r -p "type YES to write: " ok
	[ "$ok" = YES ] || { echo aborted; exit 1; }

	"${ADB[@]}" push "$img" "$TMP/uboot_a-new.img" >/dev/null 2>&1
	[ "$(root "sha256sum $TMP/uboot_a-new.img" | cut -d' ' -f1)" = "$want" ] || { echo "error: push corrupted" >&2; exit 1; }
	root "dd if=$TMP/uboot_a-new.img of=/dev/block/by-name/uboot_a bs=1048576 && sync"
	got=$(root 'dd if=/dev/block/by-name/uboot_a bs=1048576 2>/dev/null | sha256sum' | cut -d' ' -f1)
	root "rm -f $TMP/uboot_a-new.img"
	[ "$got" = "$want" ] || { echo "ERROR: read-back $got != $want. Do not reboot; flash your backup." >&2; exit 1; }
	echo "uboot_a written and verified"
	# slot A unverified with tries: if it boot-loops, the vendor U-Boot falls back to slot B
	root "bootctl set-active-boot-slot 0"
	check
	echo "reboot when ready: adb reboot"
}

check() {
	echo "slot: $(ash getprop ro.boot.slot_suffix)"
	h=$(root 'dd if=/dev/block/by-name/uboot_a bs=1048576 2>/dev/null | sha256sum' | cut -d' ' -f1)
	case $h in
	"$STOCK_SHA")   what="stock 2024-05-29" ;;
	"$PATCHED_SHA") what="USB-first (this package)" ;;
	*)              what="unknown" ;;
	esac
	echo "uboot_a: $h ($what)"
	echo "misc A/B (slot A prio/tries/ok, slot B ...):"
	root 'dd if=/dev/block/by-name/misc bs=2048 skip=1 count=1 2>/dev/null | od -A x -t x1 | head -n 1'
}

case $cmd in
backup)
	need_device; backup "${1:-}" ;;
flash)
	[ $# -eq 1 ] || { echo "usage: $0 flash <uboot_a.img>" >&2; exit 2; }
	need_device; flash "$1" ;;
check)
	need_device; check ;;
install)
	need_device
	backup
	stock=$(sha "$BACKUP/uboot_a.img")
	case $stock in
	"$STOCK_SHA") ;;
	"$PATCHED_SHA") echo "uboot_a is already patched"; exit 0 ;;
	*)
		echo "warning: your uboot_a ($stock) is not the tested stock image." >&2
		strings "$BACKUP/uboot_a.img" | grep -q bootcmd_usb0 || {
			echo "error: it has no bootcmd_usb0 (ZTE OTA U-Boot?), cannot patch" >&2; exit 1; }
		ok=${YES:-}; [ "$ok" = 1 ] && ok=YES || read -r -p "patch it anyway? type YES: " ok
		[ "$ok" = YES ] || exit 1 ;;
	esac
	python3 -I "$HERE/patch-uboot-env.py" "$BACKUP/uboot_a.img" "$BACKUP/uboot_a-usbfirst.img"
	if [ "$stock" = "$STOCK_SHA" ] && [ "$(sha "$BACKUP/uboot_a-usbfirst.img")" != "$PATCHED_SHA" ]; then
		echo "error: patched image hash differs from the expected $PATCHED_SHA" >&2; exit 1
	fi
	flash "$BACKUP/uboot_a-usbfirst.img"
	echo "to undo: $0 flash $BACKUP/uboot_a.img" ;;
*)
	sed -n 3,13p "$0" >&2; exit 2 ;;
esac
