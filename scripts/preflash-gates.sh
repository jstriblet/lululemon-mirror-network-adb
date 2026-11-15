#!/bin/bash
# Hard pre-flash gates for a Lululemon Mirror userdata flash. Read-only: it runs
# only `fastboot getvar`/`devices` and a local hash. It writes NOTHING. Run it in
# one session immediately before the flash, device on a direct USB port (no hub).
# ANY failure prints FAIL and exits non-zero: do not flash.
set -uo pipefail

SERIAL=""
EXPECT_PART_SIZE="0x14cccd000"
IMAGE=""
EXPECT_SHA=""

usage() {
  cat <<U
Usage: preflash-gates.sh --serial SERIAL --image FILE --expect-sha256 HEX [options]
  --serial SERIAL              fastboot serial of the target (from fastboot devices)
  --image FILE                 the sparse image you will flash
  --expect-sha256 HEX          full 64-char SHA-256 of that image (from the build)
  --expect-partition-size HEX  required partition-size:userdata (default 0x14cccd000)
U
}

while [ $# -gt 0 ]; do
  case "$1" in
    --serial) SERIAL="$2"; shift 2;;
    --image) IMAGE="$2"; shift 2;;
    --expect-sha256) EXPECT_SHA="$2"; shift 2;;
    --expect-partition-size) EXPECT_PART_SIZE="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "unknown argument: $1" >&2; usage; exit 2;;
  esac
done
[ -n "$SERIAL" ] && [ -n "$IMAGE" ] && [ -n "$EXPECT_SHA" ] || { usage; exit 2; }
[ -f "$IMAGE" ] || { echo "FAIL: image not found: $IMAGE" >&2; exit 1; }

fail() { echo "FAIL: $1" >&2; exit 1; }
getvar() { fastboot -s "$SERIAL" getvar "$1" 2>&1 | sed -n "s/^$1: //p" | head -1; }
to_num() { case "$1" in 0x*|0X*) printf '%d' "$1" 2>/dev/null;; '') echo "";; *) printf '%d' "$1" 2>/dev/null;; esac; }

echo "== gate 1: exactly one device, serial $SERIAL =="
DEVS="$(fastboot devices | grep -c . || true)"
[ "$DEVS" = "1" ] || fail "expected exactly one fastboot device, saw $DEVS"
fastboot devices | grep -q "$SERIAL" || fail "serial $SERIAL not present"
echo "  ok  (also confirm VID:PID 18d1:d00d via ioreg/system_profiler on macOS, lsusb on Linux)"

echo "== gate 2: product == MSM8916 =="
V="$(getvar product)"; [ "$V" = "MSM8916" ] || fail "product=$V, expected MSM8916"; echo "  ok"

echo "== gate 3: secure == yes =="
V="$(getvar secure)"; [ "$V" = "yes" ] || fail "secure=$V, expected yes"; echo "  ok"

echo "== gate 4: partition-type:userdata == ext4 =="
V="$(getvar partition-type:userdata)"; [ "$V" = "ext4" ] || fail "partition-type:userdata=$V, expected ext4"; echo "  ok"

echo "== gate 5: partition-size:userdata == $EXPECT_PART_SIZE exactly =="
V="$(getvar partition-size:userdata)"
VN="$(to_num "$V")"; EN="$(to_num "$EXPECT_PART_SIZE")"
[ -n "$VN" ] && [ -n "$EN" ] || fail "could not parse partition size ('$V' vs '$EXPECT_PART_SIZE')"
[ "$VN" = "$EN" ] || fail "partition-size:userdata=$V ($VN), expected $EXPECT_PART_SIZE ($EN); REBUILD, do not flash"
echo "  ok  ($V)"

echo "== gate 6: max-download-size >= image size (guards against a partial/split write) =="
IMG_SIZE="$(wc -c < "$IMAGE" | tr -d ' ')"
V="$(getvar max-download-size)"; VN="$(to_num "$V")"
[ -n "$VN" ] && [ "$VN" -gt 0 ] || fail "max-download-size missing/0/unparseable ('$V'); STOP"
[ "$VN" -ge "$IMG_SIZE" ] || fail "max-download-size=$V ($VN) < image $IMG_SIZE; a split write risks a partial userdata. STOP"
echo "  ok  (max $V = $VN >= image $IMG_SIZE)"

echo "== gate 7: image SHA-256 matches the build =="
if command -v sha256sum >/dev/null 2>&1; then ACT="$(sha256sum "$IMAGE" | awk '{print $1}')"
else ACT="$(shasum -a 256 "$IMAGE" | awk '{print $1}')"; fi
EXP="$(echo "$EXPECT_SHA" | tr 'A-F' 'a-f' | tr -d ' ')"
[ "${#EXP}" = "64" ] || fail "--expect-sha256 must be 64 hex chars"
[ "$ACT" = "$EXP" ] || fail "sha256 $ACT != expected $EXP; wrong image. STOP"
echo "  ok  ($ACT)"

echo
echo "ALL GATES PASSED. Only now flash, userdata only:"
echo "  caffeinate -i fastboot -s $SERIAL -S 0 --verbose flash userdata $IMAGE"
echo "  (drop caffeinate on Linux; do not power-cycle until both OKAY lines + Finished)"
