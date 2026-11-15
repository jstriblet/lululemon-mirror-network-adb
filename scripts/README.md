# Scripts

All scripts are local-only. None of the build scripts opens a device or calls
`fastboot`/`adb`. Only `preflash-gates.sh` and `adb_connect_example.py` talk to the
Mirror, and the gate script is read-only.

| Script | What it does | Touches device? |
| --- | --- | --- |
| `build-userdata-tcp.sh` | Builds the userdata image (key + USB-config + TCP-port properties), or a blank fallback (`--blank`). Wraps the upstream `build-userdata.py` and `sparse-userdata.py`, then appends the zeroed crypto footer. | No |
| `append-crypto-footer.py` | Extends the filesystem-only sparse to cover the whole partition and writes the final 16 KiB as explicit RAW zeros. Re-expands and verifies. (This repo's MIT code; generalizes porcuswine's RevP18 finalize step.) | No |
| `property.debugfs` | The `debugfs` command template that plants `/property/persist.sys.usb.config = adb` and `/property/persist.adb.tcp.port`. `@OUT@` is filled in by the build script. | No |
| `preflash-gates.sh` | The 7 hard gates (serial, product, secure, partition type/size, max-download-size, image SHA-256). Read-only `fastboot getvar`. Exits non-zero on any failure. | Read-only |
| `mirror-dhcp-up.sh <iface>` | macOS: serve DHCP on a direct-link interface, no NAT, no internet forwarding. Refuses to run if IP forwarding is on. | No (host only) |
| `mirror-dhcp-down.sh <iface>` | Tear down the above. | No (host only) |
| `adb_connect_example.py <ip>` | Connect over network ADB with the pure-Python `adb-shell` client (use when the native `adb` crashes). | Yes (after flash) |

## Build inputs

The builder and sparse tool come from the upstream project
`Onemoremichael/lulu-mirror-software-only`, **referenced at the pinned commit**
`efddcbdcaafeec087f16f009be6a13f77e0da3c1`, not vendored here. Clone it and pass
`--builder-repo /path/to/lulu-mirror-software-only`.

Required tools on `PATH` (or via `DEBUGFS_PATH` / `E2FSCK_PATH` / `DUMPE2FS_PATH`
and `MKE2FS_CONFIG`):

- Android platform-tools: `fastboot`, `adb`, `mke2fs` + its `mke2fs.conf`
  (tested 37.0.1).
- GNU e2fsprogs: `debugfs`, `e2fsck`, `dumpe2fs` (tested 1.47.4).
- `python3`.

## Exact reproduction (the test unit)

```sh
# 1. query geometry in fastboot (record your own values)
fastboot -s <SERIAL> getvar partition-size:userdata   # test unit: 0x14cccd000
fastboot -s <SERIAL> getvar max-download-size         # test unit: 0x10000000

# 2. build
scripts/build-userdata-tcp.sh \
  --builder-repo /path/to/lulu-mirror-software-only \
  --public-key /path/to/your/adbkey.pub \
  --partition-size 0x14cccd000 --filesystem-size 5583441920 \
  --port 5555 --out /path/to/out

# 3. gates (read-only), then flash
scripts/preflash-gates.sh --serial <SERIAL> \
  --image /path/to/out/userdata-adb.sparse \
  --expect-partition-size 0x14cccd000 \
  --expect-sha256 <SHA256-FROM-STEP-2>

caffeinate -i fastboot -s <SERIAL> -S 0 --verbose flash userdata \
  /path/to/out/userdata-adb.sparse
```

See the top-level `README.md` for the full procedure, the offline/DHCP steps, and
recovery.
