#!/usr/bin/env python3
"""Append an explicit zeroed Android-6 crypto footer to a userdata sparse image.

The upstream builder makes an ext4 filesystem slightly smaller than the target
partition, leaving the final N bytes (default 16384) for Android 6's crypto
footer. A sparse image that merely stops short of the partition end would let the
bootloader keep whatever old encryption metadata already sits there. This step
extends the sparse to cover the whole partition and writes that tail as explicit
RAW zeros, so stale crypto metadata cannot describe the new plaintext filesystem.

It never opens a device. It reads and rewrites a local Android sparse file in
place, then re-expands the result and checks it equals the raw ext4 image plus a
zero footer.

Generalized (any partition size) from porcuswine's RevP18 finalize step:
https://github.com/Onemoremichael/lulu-mirror-software-only/issues/10

Usage:
    append-crypto-footer.py --sparse userdata-adb.sparse \\
        --raw userdata-adb.img \\
        --partition-size 0x14cccd000 [--footer-size 16384]
"""
import argparse
import hashlib
import struct
import sys

MAGIC, RAW, SKIP = 0xED26FF3A, 0xCAC1, 0xCAC3
HEADER = struct.Struct("<IHHHHIIII")
CHUNK = struct.Struct("<HHII")
BLOCK = 4096


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--sparse", required=True,
                   help="filesystem-only sparse to extend in place")
    p.add_argument("--raw", required=True,
                   help="the raw ext4 image the sparse was built from")
    p.add_argument("--partition-size", required=True, type=lambda v: int(v, 0),
                   help="target userdata partition size in bytes (e.g. 0x14cccd000)")
    p.add_argument("--footer-size", default=16384, type=lambda v: int(v, 0),
                   help="crypto footer size in bytes (default 16384)")
    args = p.parse_args()

    part = args.partition_size
    foot = args.footer_size
    if part % BLOCK or foot % BLOCK:
        sys.exit("partition-size and footer-size must be multiples of 4096")
    fs_bytes = part - foot

    # Rewrite the header to cover the whole partition, then append the zero footer.
    with open(args.sparse, "r+b") as s:
        values = list(HEADER.unpack(s.read(HEADER.size)))
        if values[:6] != [MAGIC, 1, 0, HEADER.size, CHUNK.size, BLOCK]:
            sys.exit("not a v1.0 / 4096-byte-block Android sparse image")
        if values[6] * BLOCK != fs_bytes:
            sys.exit(f"sparse covers {values[6] * BLOCK} B, expected fs size {fs_bytes} B")
        values[6] += foot // BLOCK          # total blocks
        values[7] += 1                      # total chunks
        s.seek(0)
        s.write(HEADER.pack(*values))
        s.seek(0, 2)
        s.write(CHUNK.pack(RAW, 0, foot // BLOCK, CHUNK.size + foot))
        s.write(bytes(foot))

    # Verify: the complete stream must equal the raw ext4 image plus a zero footer.
    expanded = hashlib.sha256()
    encoded = hashlib.sha256()
    blocks = 0
    last = None
    with open(args.sparse, "rb") as s, open(args.raw, "rb") as r:
        head = s.read(HEADER.size)
        encoded.update(head)
        values = HEADER.unpack(head)
        if values[6] * BLOCK != part:
            sys.exit("final sparse does not cover the whole partition")
        for _ in range(values[7]):
            blk = s.read(CHUNK.size)
            encoded.update(blk)
            kind, reserved, count, size = CHUNK.unpack(blk)
            if kind not in (RAW, SKIP) or reserved or count <= 0:
                sys.exit("invalid chunk header")
            if size != CHUNK.size + (count * BLOCK if kind == RAW else 0):
                sys.exit("chunk size field mismatch")
            remaining = count * BLOCK
            while remaining:
                n = min(remaining, 8 << 20)
                data = s.read(n) if kind == RAW else bytes(n)
                if len(data) != n:
                    sys.exit("truncated sparse payload")
                if kind == RAW:
                    encoded.update(data)
                ref = r.read(n)
                if len(ref) < n:
                    ref += bytes(n - len(ref))
                if data != ref:
                    sys.exit("sparse payload differs from raw image plus footer")
                expanded.update(data)
                remaining -= n
            blocks += count
            last = (kind, count, size)
        if s.read(1) or r.read(1):
            sys.exit("length mismatch between sparse and raw image")
        if blocks * BLOCK != part:
            sys.exit("final block coverage does not equal partition size")
        if last != (RAW, foot // BLOCK, CHUNK.size + foot):
            sys.exit("last chunk is not the zeroed RAW footer")

    print("ok: sparse covers whole partition with zeroed crypto footer")
    print("sparse_sha256  ", encoded.hexdigest())
    print("expanded_sha256", expanded.hexdigest())


if __name__ == "__main__":
    main()
