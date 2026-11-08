#!/bin/bash
# Build the chain-loaded mainline U-Boot for the ZTE W600D SE (RK3568) and the
# files for the USB stick. Linux (aarch64-linux-gnu-) or macOS (Homebrew
# aarch64-elf-). See README.md.
#
#   ./build.sh                  clone U-Boot into ./u-boot (pinned commit), patch, build
#   U_BOOT_DIR=/path ./build.sh use an existing U-Boot checkout at that commit
#   CROSS_COMPILE=... ./build.sh override the toolchain prefix
#
# Output: out/stick/{boot.scr,u-boot-w600d.bin,w600d-chain.bin,SHA256SUMS}
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
U_BOOT_URL=${U_BOOT_URL:-https://source.denx.de/u-boot/u-boot.git}
U_BOOT_REV=709a97a05df66e394f40d249105d0baade46f107   # 2027.01-rc1
U_BOOT_DIR=${U_BOOT_DIR:-$HERE/u-boot}
OUT=$HERE/out
DEFCONFIG=zte-w600d-chain-rk3568_defconfig

MAKE=make
EXTRA=()
if [ "$(uname -s)" = Darwin ]; then
	# brew install aarch64-elf-gcc aarch64-elf-binutils make bison openssl@3 dtc
	: "${CROSS_COMPILE:=aarch64-elf-}"
	MAKE=gmake
	BREW=$(brew --prefix)
	export PATH=$BREW/opt/bison/bin:$PATH
	# Not -I$BREW/include: Homebrew's libfdt headers clash with U-Boot's.
	EXTRA+=(HOSTCFLAGS=-I$BREW/opt/openssl@3/include
		HOSTLDFLAGS=-L$BREW/opt/openssl@3/lib)
	JOBS=$(sysctl -n hw.ncpu)
else
	: "${CROSS_COMPILE:=aarch64-linux-gnu-}"
	JOBS=$(nproc)
fi
# NO_PYTHON: u-boot.bin needs no binman/pylibfdt. check-local-export needs
# bash >= 4.2 (macOS ships 3.2); it is only a build-time lint.
EXTRA+=(NO_PYTHON=1 cmd_check_local_export=true)

# --- 1. U-Boot source at the pinned commit ---------------------------------
if [ ! -d "$U_BOOT_DIR/.git" ]; then
	git clone "$U_BOOT_URL" "$U_BOOT_DIR"
	git -C "$U_BOOT_DIR" checkout -q "$U_BOOT_REV"
fi
have=$(git -C "$U_BOOT_DIR" rev-parse HEAD)
[ "$have" = "$U_BOOT_REV" ] || echo "warning: $U_BOOT_DIR is at $have, tested at $U_BOOT_REV" >&2

# --- 2. board patches + typewriter -------------------------------------------
"$HERE/patch-u-boot.sh" "$U_BOOT_DIR"

# --- 3. U-Boot ---------------------------------------------------------------
cd "$U_BOOT_DIR"
$MAKE O="$OUT/build" CROSS_COMPILE="$CROSS_COMPILE" "${EXTRA[@]}" $DEFCONFIG
$MAKE O="$OUT/build" CROSS_COMPILE="$CROSS_COMPILE" "${EXTRA[@]}" -j"$JOBS" u-boot.bin

# The vendor U-Boot loads it to 0x00800000 while its own boot.scr sits at
# 0x00c00000: the image must stay below 4 MiB.
size=$(wc -c < "$OUT/build/u-boot.bin")
[ "$size" -lt $((0x400000)) ] || { echo "error: u-boot.bin is $size bytes (> 4 MiB)" >&2; exit 1; }

# --- 4. shim + boot.scr ------------------------------------------------------
mkdir -p "$OUT/shim" "$OUT/stick"
"${CROSS_COMPILE}gcc" -c "$HERE/chain/chain.S" -o "$OUT/shim/chain.o"
"${CROSS_COMPILE}ld" -Ttext=0x10000000 "$OUT/shim/chain.o" -o "$OUT/shim/chain.elf"
"${CROSS_COMPILE}objcopy" -O binary "$OUT/shim/chain.elf" "$OUT/stick/w600d-chain.bin"
python3 -I "$HERE/chain/mkscr.py" "$HERE/chain/boot-nc.cmd" "$OUT/stick/boot.scr"
cp "$OUT/build/u-boot.bin" "$OUT/stick/u-boot-w600d.bin"

cd "$OUT/stick"
if command -v sha256sum >/dev/null; then
	sha256sum boot.scr u-boot-w600d.bin w600d-chain.bin > SHA256SUMS
else
	shasum -a 256 boot.scr u-boot-w600d.bin w600d-chain.bin > SHA256SUMS
fi
cat SHA256SUMS
echo "copy $OUT/stick/* to the root of a FAT32 USB stick (MBR, partition 1)"
