# Making the Windows key act as Back on Android (via adb)

**Problem:** on the ZTE W600D laptop (RK3568, Android 11), Esc doesn't leave apps. You'd want
a keyboard key that does the same as `adb shell input keyevent 4` (`KEYCODE_BACK`).

**Result:** the left Windows (⊞) key now sends **BACK**. No change to `/system`, no reboot,
and it survives reboots.

**Script:** [`map-winkey-back.sh`](map-winkey-back.sh). It works on any rooted Android device
with a USB keyboard.

```sh
./map-winkey-back.sh            # ⊞ → BACK
./map-winkey-back.sh --esc      # ⊞ → BACK and Esc → BACK
./map-winkey-back.sh --undo     # back to stock
./map-winkey-back.sh -s 10.0.0.66:5555 -k 258a:0001   # pick device / keyboard explicitly
```

---

## How I found it

### 1. Which keyboard is it, and what layout file does Android use?

`dumpsys input` lists every input device Android knows, with its USB IDs and the key layout
(`.kl`) file it loaded:

```sh
adb shell dumpsys input | grep -A12 "SINO WEALTH USB KEYBOARD$"
```
```
9: SINO WEALTH USB KEYBOARD
  Classes: 0x80000083
  Path: /dev/input/event2
  Identifier: bus=0x0003, vendor=0x258a, product=0x0001, version=0x0110
  KeyLayoutFile: /system/usr/keylayout/Generic.kl
  KeyCharacterMapFile: /system/usr/keychars/Generic.kcm
```

* The built-in keyboard is a **USB** device, `258a:0001` (SINO WEALTH). It shows up three
  times: the main keyboard plus "System Control" and "Consumer Control", all with the same IDs.
* No device-specific layout existed, so Android fell back to **`Generic.kl`**.

`getevent -il` lists the same devices from the kernel side (`/dev/input/event*`).

### 2. What does the Windows key map to now?

In `.kl` files, `key <linux scancode> <Android key name>`. The Linux scancode for Left Meta
(the Windows key) is `KEY_LEFTMETA = 125`:

```sh
adb shell grep -nE "^key (1|125|158) " /system/usr/keylayout/Generic.kl
```
```
key 1     ESCAPE
key 125   META_LEFT
key 158   BACK
```

So ⊞ is `META_LEFT`, a modifier that does nothing on its own in most apps. Esc is `ESCAPE`.
On a PC-style keyboard, Android only treats Esc as Back in some apps. `BACK` (Android
keycode 4) is exactly what `input keyevent 4` injects.

To check a scancode live, run `adb shell getevent -l /dev/input/event2` and press the key.
You'll see `EV_KEY KEY_LEFTMETA DOWN/UP`.

### 3. Where can a custom layout go without touching /system?

Android's `InputDeviceConfigurationFileResolver` looks for key layouts in this order (first
match wins):

1. `/odm/usr/keylayout/`
2. `/vendor/usr/keylayout/`
3. `/system/usr/keylayout/`
4. **`/data/system/devices/keylayout/`** ← writable, persistent
5. Within each directory: `Vendor_XXXX_Product_YYYY_Version_ZZZZ.kl`, then
   `Vendor_XXXX_Product_YYYY.kl`, then the device name, and finally `Generic.kl`.

The **more specific filename wins over `Generic.kl`**. So
`/data/system/devices/keylayout/Vendor_258a_Product_0001.kl` beats
`/system/usr/keylayout/Generic.kl`, as long as nothing in odm/vendor/system already has a file
for this vendor/product. On this device the first three directories don't have one (odm/vendor
don't even have a `keylayout` dir).

This avoids remounting `/system`. That would be awkward here anyway: it's a dynamic `super`
partition with dm-verity.

### 4. Build the file

Copy `Generic.kl` and change one line:

```diff
-key 125   META_LEFT
+key 125   BACK
```

Copying the whole generic file (rather than writing a one-line file) matters. The new file
**replaces** `Generic.kl` for this keyboard, so it must contain every other key too.

### 5. Install it (needs root)

The device is a `userdebug` build with `su`, so:

```sh
adb push Vendor_258a_Product_0001.kl /data/local/tmp/
adb shell su 0 sh -c '
  mkdir -p /data/system/devices/keylayout
  cp /data/local/tmp/Vendor_258a_Product_0001.kl /data/system/devices/keylayout/
  chown -R system:system /data/system/devices
  chmod 644 /data/system/devices/keylayout/*.kl
  restorecon -R /data/system/devices'
```

`system_server` (uid `system`, SELinux label `system_data_file`) must be able to read it.
`chown` + `restorecon` take care of that.

### 6. Make Android reload it, without a reboot

Android reads `.kl` files when a device is **added**. Unplugging and replugging the keyboard
would work, but it's built in. Instead, de-authorize and re-authorize it on the USB bus:

```sh
adb shell su 0 sh -c '
  for d in /sys/bus/usb/devices/*; do
    [ "$(cat $d/idVendor 2>/dev/null)" = 258a ] && { echo 0 > $d/authorized; sleep 1; echo 1 > $d/authorized; }
  done'
```

(On this laptop that's `/sys/bus/usb/devices/7-1`.)

### 7. Verify

```sh
adb shell dumpsys input | grep KeyLayoutFile
```
```
KeyLayoutFile: /data/system/devices/keylayout/Vendor_258a_Product_0001.kl   (×3, one per interface)
```

Press ⊞ in an app and it goes back. 🎉

---

## What the script does

`map-winkey-back.sh` automates steps 1–7 and generalizes them:

1. **adb check:** finds the device (`-s` to pick one).
2. **Root detection:** in order: `adbd` already root → `su 0` → `su -c` (Magisk).
3. **Keyboard detection:** parses `dumpsys input` and keeps devices with the ALPHAKEY class
   bit (`0x2`), a real `/dev/input` path, and a non-zero vendor ID. If several keyboards are
   found it asks which one; `-k vvvv:pppp` overrides.
4. **Base layout:** the file Android is currently using for that keyboard. If that's already
   the script's own output, it falls back to the stock file
   (`odm`/`vendor`/`system` `Vendor_…kl`, else `Generic.kl`). That makes re-runs idempotent
   and lets `--esc` be turned off again.
5. **Rewrite:** sets `key 125` (and `key 1` with `--esc`) to `BACK`, and adds a header comment.
6. **Install:** to `/data/system/devices/keylayout/` with the right owner, mode and SELinux
   label. Root commands run from a pushed temp script, to avoid nested quoting through
   `adb shell su`.
7. **Reload:** re-authorizes the matching USB device. Bluetooth keyboards get a "reconnect
   or reboot" hint instead.
8. **Verify:** re-reads `dumpsys input` and checks that `KeyLayoutFile` points at the new
   file.

Tested on the ZTE W600D: install, `--esc`, plain re-run (Esc goes back to normal), and
`--undo`.

## Notes and limits

* **Root required:** `/data/system` isn't writable by the `shell` user. Without root, the
  options are an Accessibility-service remapper app, or an app shipping
  `android.hardware.input.action.QUERY_KEYBOARD_LAYOUTS`. That second route only changes
  character maps (`.kcm`), not key → BACK.
* **Factory reset** deletes `/data`, and the mapping with it.
* **Meta shortcuts:** after the remap, ⊞ no longer works as Meta (e.g. Meta+key shortcuts).
  The right Windows key (`key 126 META_RIGHT`), if the keyboard has one, is unchanged.
* **Other targets:** to map a different key to BACK, find its scancode with `getevent -l` and
  change that line instead. Other Android key names (`HOME`, `APP_SWITCH`, …) work the same way.
