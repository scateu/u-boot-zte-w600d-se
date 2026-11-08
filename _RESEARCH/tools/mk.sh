#!/bin/bash
# Build mainline U-Boot on macOS (aarch64-elf-gcc from Homebrew).
# usage: mk.sh <outdir> <make targets...>     e.g. mk.sh w600d zte-w600d-chain-rk3568_defconfig u-boot.bin
set -e
W=/Volumes/Lexar/ztebook-claude-workspace
out=$1; shift
export PATH=/opt/homebrew/opt/bison/bin:$PATH
cd "$W/u-boot"
exec gmake O="$W/b/$out" CROSS_COMPILE=aarch64-elf- NO_PYTHON=1 \
	cmd_check_local_export=true \
	HOSTCFLAGS=-I/opt/homebrew/opt/openssl@3/include \
	HOSTLDFLAGS=-L/opt/homebrew/opt/openssl@3/lib -j8 "$@"
