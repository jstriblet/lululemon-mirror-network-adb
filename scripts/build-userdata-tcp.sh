#!/bin/bash
# Build a userdata image that enables authorized ADB over TCP on a Lululemon
# Mirror. Local files only: this never opens a device and never calls
# fastboot/adb. Flashing the result REPLACES ALL USERDATA.
#
# The ext4 builder and the sparse converter come from the upstream project
# `lulu-mirror-software-only` (referenced, not vendored). Point --builder-repo at
# a local checkout at the pinned commit:
#   efddcbdcaafeec087f16f009be6a13f77e0da3c1
# The explicit zeroed crypto footer is appended by this repo's
# scripts/append-crypto-footer.py (MIT).
set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILDER_REPO=""
PARTITION_SIZE="0x14cccd000"      # query your own: fastboot getvar partition-size:userdata
FS_SIZE="5583441920"              # partition size minus the 16384-byte footer
FOOTER_SIZE="16384"
PUBLIC_KEY=""                     # your adbkey.pub (PUBLIC key only)
PORT="5555"
OUT=""
BLANK=0                           # 1 = blank fallback image (no planted files)

usage() {
  cat <<U
Usage: build-userdata-tcp.sh --builder-repo DIR --public-key FILE --out DIR [options]
  --builder-repo DIR    local checkout of lulu-mirror-software-only (pinned commit)
  --public-key FILE     your adbkey.pub (public key only; never a private key)
  --out DIR             output directory (must not already exist)
  --partition-size HEX  target userdata size (default 0x14cccd000)
  --filesystem-size N   ext4 size = partition - footer (default 5583441920)
  --footer-size N       crypto footer bytes (default 16384)
  --port N              TCP port for adbd (default 5555)
  --blank               build a blank fallback image (no key, no properties)
Tools required on PATH: fastboot/adb platform-tools (mke2fs + mke2fs.conf),
GNU e2fsprogs (debugfs, e2fsck, dumpe2fs), python3.
U
}

while [ $# -gt 0 ]; do
  case "$1" in
    --builder-repo) BUILDER_REPO="$2"; shift 2;;
    --public-key) PUBLIC_KEY="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --partition-size) PARTITION_SIZE="$2"; shift 2;;
    --filesystem-size) FS_SIZE="$2"; shift 2;;
    --footer-size) FOOTER_SIZE="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --blank) BLANK=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "unknown argument: $1" >&2; usage; exit 2;;
  esac
done

[ -n "$BUILDER_REPO" ] || { echo "--builder-repo is required" >&2; exit 2; }
[ -n "$OUT" ] || { echo "--out is required" >&2; exit 2; }
[ -e "$OUT" ] && { echo "--out already exists: $OUT" >&2; exit 2; }
if [ "$BLANK" -eq 0 ]; then
  [ -n "$PUBLIC_KEY" ] || { echo "--public-key is required (unless --blank)" >&2; exit 2; }
  case "$PUBLIC_KEY" in *.pub) ;; *) echo "public key must be a .pub file" >&2; exit 2;; esac
fi

# Let sparse-userdata.py / debugfs find GNU e2fsprogs if a prefix is set.
: "${DEBUGFS_PATH:=$(command -v debugfs || true)}"
: "${E2FSCK_PATH:=$(command -v e2fsck || true)}"
: "${DUMPE2FS_PATH:=$(command -v dumpe2fs || true)}"
export DEBUGFS_PATH E2FSCK_PATH DUMPE2FS_PATH

if [ "$BLANK" -eq 1 ]; then
  echo "== blank fallback: plain ext4, no planted files =="
  mkdir -p "$OUT"
  BLOCKS=$(( FS_SIZE / 4096 ))
  MKE2FS_CONF="${MKE2FS_CONFIG:-}"
  mke2fs -t ext4 -F -b 4096 -I 256 -m 0 -L userdata -M /data \
    -E lazy_itable_init=0,lazy_journal_init=0 "$OUT/userdata-blank.img" "$BLOCKS"
  python3 -I "$BUILDER_REPO/tools/sparse-userdata.py" \
    "$OUT/userdata-blank.img" "$OUT/userdata-blank.sparse"
  python3 -I "$SELF_DIR/append-crypto-footer.py" \
    --sparse "$OUT/userdata-blank.sparse" --raw "$OUT/userdata-blank.img" \
    --partition-size "$PARTITION_SIZE" --footer-size "$FOOTER_SIZE"
  echo "built: $OUT/userdata-blank.sparse"
  sha256sum "$OUT/userdata-blank.sparse" 2>/dev/null || shasum -a 256 "$OUT/userdata-blank.sparse"
  exit 0
fi

echo "== 1. key-only ext4 (upstream build-userdata.py) =="
python3 -I "$BUILDER_REPO/tools/build-userdata.py" \
  --size "$PARTITION_SIZE" --filesystem-size "$FS_SIZE" \
  --public-key "$PUBLIC_KEY" --output-dir "$OUT"

echo "== 2. plant properties (persist.sys.usb.config = adb, persist.adb.tcp.port = $PORT) =="
printf 'adb' > "$OUT/usb-config.value"
printf '%s' "$PORT" > "$OUT/tcp-port.value"
printf 'u:object_r:property_data_file:s0\0' > "$OUT/property_data_file.label"
# Render the property debugfs script with this build's absolute paths.
sed -e "s#@OUT@#$OUT#g" "$SELF_DIR/property.debugfs" > "$OUT/property.debugfs"
"$DEBUGFS_PATH" -w -f "$OUT/property.debugfs" "$OUT/userdata-adb.img"

echo "== 3. sparse (upstream sparse-userdata.py) + zeroed crypto footer =="
python3 -I "$BUILDER_REPO/tools/sparse-userdata.py" \
  "$OUT/userdata-adb.img" "$OUT/userdata-adb.sparse"
python3 -I "$SELF_DIR/append-crypto-footer.py" \
  --sparse "$OUT/userdata-adb.sparse" --raw "$OUT/userdata-adb.img" \
  --partition-size "$PARTITION_SIZE" --footer-size "$FOOTER_SIZE"

echo "== done =="
echo "FLASH THIS: $OUT/userdata-adb.sparse"
sha256sum "$OUT/userdata-adb.sparse" 2>/dev/null || shasum -a 256 "$OUT/userdata-adb.sparse"
echo "Record this SHA-256 and pass it to preflash-gates.sh --expect-sha256."
