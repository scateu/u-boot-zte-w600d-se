#!/usr/bin/env bash
#
# map-winkey-back.sh: make the keyboard's Windows (Meta) key act as Android BACK
# (the same as `adb shell input keyevent 4`), using only adb.
#
# It installs a per-keyboard key layout file:
#   /data/system/devices/keylayout/Vendor_XXXX_Product_YYYY.kl
# Android prefers that file over /system/usr/keylayout/Generic.kl. Nothing in /system is
# modified. The file survives reboots and is removed by a factory reset.
#
# Requirements: adb on the PC, and root on the device (adb root, `su 0`, or Magisk `su -c`).
#
# Usage:
#   ./map-winkey-back.sh                 # Windows key -> BACK
#   ./map-winkey-back.sh --esc           # also Esc -> BACK
#   ./map-winkey-back.sh --undo          # remove the custom layout
#   ./map-winkey-back.sh -s <serial>     # pick an adb device
#   ./map-winkey-back.sh -k 258a:0001    # pick a keyboard by USB vendor:product
#
# Tested on: ZTE W600D (RK3568, Android 11), keyboard SINO WEALTH 258a:0001.

set -euo pipefail

# ── pretty output ──────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  B=$'\e[1m'; D=$'\e[2m'; R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; M=$'\e[35m'; N=$'\e[0m'
else
  B=; D=; R=; G=; Y=; C=; M=; N=
fi
step() { printf '\n%s▶ %s%s\n' "$C$B" "$*" "$N"; }
ok()   { printf '  %s✔%s %s\n' "$G" "$N" "$*"; }
info() { printf '  %s•%s %s\n' "$D" "$N" "$*"; }
warn() { printf '  %s⚠%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '\n  %s✘ %s%s\n\n' "$R$B" "$*" "$N" >&2; exit 1; }

banner() {
  printf '%s' "$M$B"
  cat <<'EOF'

   ╔══════════════════════════════════════════════════╗
   ║   ⊞  Windows key  ──────▶  ◀  Android BACK       ║
   ║          keylayout remapper over adb             ║
   ╚══════════════════════════════════════════════════╝
EOF
  printf '%s' "$N"
}

# ── args ───────────────────────────────────────────────────────────────────────
ESC=0; UNDO=0; KBD=""; ADB=(adb)
while [ $# -gt 0 ]; do
  case "$1" in
    --esc)  ESC=1 ;;
    --undo) UNDO=1 ;;
    -s)     shift; ADB=(adb -s "${1:?-s needs a serial}") ;;
    -k)     shift; KBD="${1:?-k needs vendor:product}" ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done

KL_DIR=/data/system/devices/keylayout
TMP_REMOTE=/data/local/tmp
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

ash() { "${ADB[@]}" shell "$@" | tr -d '\r'; }

# Run a multi-line shell script on the device as root (pushed as a file to avoid quoting hell).
SU=""
root_sh() {
  printf '%s\n' "$1" > "$WORK/job.sh"
  "${ADB[@]}" push "$WORK/job.sh" "$TMP_REMOTE/winkey_job.sh" >/dev/null 2>&1
  case "$SU" in
    none)  ash sh "$TMP_REMOTE/winkey_job.sh" ;;
    su0)   ash su 0 sh "$TMP_REMOTE/winkey_job.sh" ;;
    suc)   ash "su -c 'sh $TMP_REMOTE/winkey_job.sh'" ;;
  esac
  ash rm -f "$TMP_REMOTE/winkey_job.sh" >/dev/null 2>&1 || true
}

banner

# ── 1. device ──────────────────────────────────────────────────────────────────
step "Looking for your Android device"
command -v adb >/dev/null || die "adb not found. Install Android platform-tools first."
STATE="$("${ADB[@]}" get-state 2>/dev/null || true)"
[ "$STATE" = device ] || die "No adb device ready (state: ${STATE:-none}). Check 'adb devices' or use -s <serial>."
MODEL="$(ash getprop ro.product.model)"; [ -n "$MODEL" ] || MODEL="$(ash getprop ro.product.device)"
BRAND="$(ash getprop ro.product.manufacturer)"
REL="$(ash getprop ro.build.version.release)"
ok "Connected: ${B}${BRAND} ${MODEL}${N} (Android ${REL})"

# ── 2. root ────────────────────────────────────────────────────────────────────
step "Checking for root"
if   [ "$(ash id -u 2>/dev/null)" = 0 ];                    then SU=none; ok "adbd is already root"
elif [ "$(ash su 0 id -u 2>/dev/null)" = 0 ];               then SU=su0;  ok "root via ${B}su 0${N}"
elif [ "$(ash "su -c 'id -u'" 2>/dev/null)" = 0 ];          then SU=suc;  ok "root via ${B}su -c${N} (Magisk-style)"
else die "No root. Try 'adb root' (userdebug builds) or a rooted su. Writing $KL_DIR needs root."
fi

# ── 3. keyboard ────────────────────────────────────────────────────────────────
step "Finding the physical keyboard"
# Parse `dumpsys input` Event Hub entries: name | classes | vendor | product | layout file.
ash dumpsys input | awk '
  /Input Reader State/ { done=1 }
  done { next }
  /^ +[0-9]+: / { if (name != "") print_dev(); sub(/^ +[0-9]+: /, ""); name=$0; cls=""; ven=""; pro=""; kl=""; path=""; next }
  /^ +Classes:/        { cls=$2 }
  /^ +Path:/           { path=$2 }
  /^ +Identifier:/     { for (i=1;i<=NF;i++) { if ($i ~ /^vendor=/) { ven=$i; sub(/vendor=0x/,"",ven); sub(/,/,"",ven) }
                                                 if ($i ~ /^product=/) { pro=$i; sub(/product=0x/,"",pro); sub(/,/,"",pro) } } }
  /^ +KeyLayoutFile:/  { kl=$2 }
  function print_dev() { print name "|" cls "|" ven "|" pro "|" kl "|" path }
  END { if (name != "") print_dev() }
' > "$WORK/devs.txt"

# Alphabetic keyboards: class bit 0x2 (ALPHAKEY), real device node, not vendor 0000.
: > "$WORK/kbds.txt"
while IFS='|' read -r name cls ven pro kl path; do
  [ -n "$cls" ] || continue
  [ "$path" = "<virtual>" ] && continue
  [ $(( cls & 0x2 )) -ne 0 ] || continue
  [ "$ven" = 0000 ] && continue
  grep -q "|$ven|$pro|" "$WORK/kbds.txt" 2>/dev/null && continue   # one entry per vendor:product
  echo "$name|$ven|$pro|$kl" >> "$WORK/kbds.txt"
done < "$WORK/devs.txt"

if [ -n "$KBD" ]; then
  KV="$(echo "${KBD%%:*}" | tr 'A-F' 'a-f')"; KP="$(echo "${KBD##*:}" | tr 'A-F' 'a-f')"
  LINE="$(grep "|$KV|$KP|" "$WORK/kbds.txt" | head -1 || true)"
  [ -n "$LINE" ] || LINE="(user specified)|$KV|$KP|"
else
  COUNT=$(wc -l < "$WORK/kbds.txt" | tr -d ' ')
  [ "$COUNT" -gt 0 ] || die "No physical keyboard found. Plug it in, or pass -k vendor:product."
  if [ "$COUNT" -eq 1 ]; then
    LINE="$(cat "$WORK/kbds.txt")"
  else
    info "Several keyboards found:"
    n=0; while IFS='|' read -r name ven pro kl; do n=$((n+1)); printf '     %s%d)%s %s  %s(%s:%s)%s\n' "$B" $n "$N" "$name" "$D" "$ven" "$pro" "$N"; done < "$WORK/kbds.txt"
    printf '  %s?%s Which one? [1-%d]: ' "$Y" "$N" "$COUNT"; read -r pick </dev/tty
    LINE="$(sed -n "${pick}p" "$WORK/kbds.txt")"; [ -n "$LINE" ] || die "Invalid choice."
  fi
fi
IFS='|' read -r KNAME KV KP KL <<EOF
$LINE
EOF
TARGET="$KL_DIR/Vendor_${KV}_Product_${KP}.kl"
ok "Keyboard: ${B}${KNAME}${N} ${D}(USB ${KV}:${KP})${N}"
info "current layout: ${KL:-unknown}"

# Re-plug the keyboard in software so Android reloads its layout (USB only).
replug() {
  step "Re-plugging the keyboard (software) so Android reloads the layout"
  OUT="$(root_sh "for d in /sys/bus/usb/devices/*; do
  [ -f \$d/idVendor ] || continue
  if [ \"\$(cat \$d/idVendor)\" = $KV ] && [ \"\$(cat \$d/idProduct)\" = $KP ]; then
    echo 0 > \$d/authorized; sleep 1; echo 1 > \$d/authorized; echo \$d
  fi
done")"
  if [ -n "$OUT" ]; then ok "re-enumerated ${D}${OUT//$'\n'/ }${N}"; sleep 2
  else warn "Not a USB keyboard I can re-plug. Reconnect it or reboot to apply."; fi
}

show_layout() {
  NOW="$(ash dumpsys input | awk -v v="vendor=0x$KV," -v p="product=0x$KP," '
    /Input Reader State/ {done=1} done {next} /Identifier:/ { m = (index($0,v) && index($0,p)) } m && /KeyLayoutFile:/ { print $2; m=0 }' | sort -u)"
  echo "$NOW"
}

# ── undo ───────────────────────────────────────────────────────────────────────
if [ "$UNDO" = 1 ]; then
  step "Removing custom layout"
  root_sh "rm -f $TARGET" >/dev/null
  ok "deleted $TARGET"
  replug
  NOW="$(show_layout)"
  ok "Android now uses: ${B}${NOW:-?}${N}"
  printf '\n  %s↩  Restored. The Windows key is Meta again.%s\n\n' "$G$B" "$N"
  exit 0
fi

# ── 4. build layout ────────────────────────────────────────────────────────────
step "Building the new key layout"
BASE="$KL"
if [ -z "$BASE" ] || [ "$BASE" = "$TARGET" ]; then
  # Already remapped (or unknown): start again from the stock layout Android would pick.
  BASE=/system/usr/keylayout/Generic.kl
  for f in /odm/usr/keylayout /vendor/usr/keylayout /system/usr/keylayout; do
    if [ "$(ash "[ -f $f/Vendor_${KV}_Product_${KP}.kl ] && echo y")" = y ]; then BASE="$f/Vendor_${KV}_Product_${KP}.kl"; break; fi
  done
fi
ash cat "$BASE" > "$WORK/base.kl"
[ -s "$WORK/base.kl" ] || die "Could not read base layout $BASE"
info "based on ${BASE}"

# Rewrite key 125 (and key 1 with --esc).
cp "$WORK/base.kl" "$WORK/new.kl"
setkey() {  # $1 = scancode, $2 = Android key name
  if grep -Eq "^key[[:space:]]+$1[[:space:]]" "$WORK/new.kl"; then
    sed -E "s/^key[[:space:]]+$1[[:space:]].*/key $1   $2/" "$WORK/new.kl" > "$WORK/t.kl" && mv "$WORK/t.kl" "$WORK/new.kl"
  else
    echo "key $1   $2" >> "$WORK/new.kl"
  fi
}
setkey 125 BACK; ok "key 125 ${D}(Left Windows/Meta)${N} → ${B}BACK${N}"
if [ "$ESC" = 1 ]; then setkey 1 BACK; ok "key 1   ${D}(Esc)${N} → ${B}BACK${N}"; fi
{ echo "# map-winkey-back.sh: $KNAME ($KV:$KP), Windows key -> BACK$( [ "$ESC" = 1 ] && echo ', Esc -> BACK')"; cat "$WORK/new.kl"; } > "$WORK/final.kl"

# ── 5. install ─────────────────────────────────────────────────────────────────
step "Installing on the device"
"${ADB[@]}" push "$WORK/final.kl" "$TMP_REMOTE/winkey.kl" >/dev/null 2>&1
root_sh "set -e
mkdir -p $KL_DIR
cp $TMP_REMOTE/winkey.kl $TARGET
rm -f $TMP_REMOTE/winkey.kl
chown -R system:system /data/system/devices
chmod 755 /data/system/devices $KL_DIR
chmod 644 $TARGET
restorecon -R /data/system/devices >/dev/null 2>&1 || true"
ok "wrote ${B}${TARGET}${N}"

replug

# ── 6. verify ──────────────────────────────────────────────────────────────────
step "Verifying"
NOW="$(show_layout)"
if echo "$NOW" | grep -qx "$TARGET"; then
  ok "Android is using the new layout ✨"
  printf '\n  %s🎉  Done! Press the ⊞ Windows key in any app to go back.%s\n' "$G$B" "$N"
  printf '  %s   Undo any time with: %s --undo%s\n\n' "$D" "$0" "$N"
else
  warn "Android still reports: ${NOW:-nothing}"
  warn "Reconnect the keyboard or reboot the device, then press ⊞ to test."
  echo
fi
