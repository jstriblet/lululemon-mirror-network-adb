# The test unit — RevP17, stock 1.16.0 (first RevP17 data point)

This records the one unit this method was verified on. Serials, keys, MACs and
local network details are redacted; placeholders like `<SERIAL>` stand in.

## Hardware and firmware

| Field | Value |
| --- | --- |
| Model | Lululemon Studio Mirror (Model One) |
| Board | `MIR63A0-00-P1` / `PCA#500240` **RevP17** |
| SoC (fastboot `product`) | `MSM8916` |
| Android | 6.0.1 |
| `ro.build.fingerprint` | `mirror/mirror/msm8916_64:6.0.1/IFC-6309-2.0-MIR/673:user/release-keys` |
| Build family | `IFC-6309-2.0-MIR`, build `673` |
| `os_version` (status page) | `1.16.0` |
| `proto_version` (status page) | `0.0.12` |
| fastboot `secure` | `yes` |
| fastboot `unlocked` | (empty) |
| fastboot USB VID:PID | `18d1:d00d` |
| `partition-size:userdata` | `0x14cccd000` (5,583,458,304 bytes) |
| `max-download-size` | `0x10000000` (268,435,456 bytes) |

**RevP17 is a new data point.** Every prior owner report is RevP18/20/21. RevP17 is
older than RevP18. The partition size and download limit matched the newer boards,
confirmed by the hard gates before the flash.

## What was new about this unit

1. **It never enumerates on USB in Android.** Across 30+ minutes after boot, the
   board did not appear on the host's USB at all — not even as an unauthorized
   `05c6:9039` device — whether through the external data port or the board's J1
   socket directly. The same cable and port enumerate fine in **fastboot**
   (`18d1:d00d`). So the common USB-ADB recipes could not be checked on this unit.
2. **Key-only userdata (the porcuswine recipe) booted but stayed dark on USB.** The
   first image planted the ADB key and `persist.sys.usb.config = adb`. It flashed
   cleanly and booted to the stock "Let's set up your Mirror" screen, but USB stayed
   dark, so ADB could not be reached. That property had **no visible effect** on this
   firmware.
3. **Adding `persist.adb.tcp.port = 5555` opened network ADB.** The second image
   added that one 4-byte property. After the flash, with a direct Ethernet cable and
   the host serving DHCP (no internet forwarding), TCP 5555 opened and `adb connect`
   authorized with the planted key. This is the working path on this unit.
4. **Stock `adbd` TCP is closed by default here.** Before the second flash, a full
   TCP port scan of the unit (on the same direct link) showed only ports `7000` and
   `8080` open — `5555` closed. So the open port after the flash is attributable to
   the planted property, not a pre-existing listener.

## Flash results (redacted logs)

Image #1 (key + `persist.sys.usb.config`):

```
fastboot ... flash userdata .../userdata/userdata-adb.sparse
Sending 'userdata' (151337 KB)   OKAY [  4.778s]
Writing 'userdata'               OKAY [  7.128s]
Finished. Total time: 11.928s
```

- All 7 pre-flash gates passed. Read-only re-check OK, reboot OKAY.
- Booted to the stock setup screen (not bricked).
- STOP: USB never enumerated in Android (30+ min). ADB unverified. Stayed offline.

Image #2 (same, plus `persist.adb.tcp.port = 5555`):

```
fastboot ... flash userdata .../userdata-tcp/userdata-adb.sparse
Sending 'userdata' (151341 KB)   OKAY [  4.749s]
Writing 'userdata'               OKAY [  7.164s]
Finished. Total time: 11.935s
```

- All 7 gates passed. Host IP forwarding confirmed `0` (IPv4 and IPv6). Reboot OKAY.
- The Mirror took a DHCP lease from the host on a direct Ethernet link. **TCP 5555
  opened** within a few minutes.
- The native Homebrew `adb` (37.0.1) daemon crashed right after connect (libunwind
  on macOS 27). The pure-Python `adb-shell` client connected **AUTHORIZED** with the
  planted key.
- `getprop ro.build.fingerprint` =
  `mirror/mirror/msm8916_64:6.0.1/IFC-6309-2.0-MIR/673:user/release-keys`.
- Per plan, stopped after `getprop`. Nothing was installed.

## Image geometry (both images)

- Partition 5,583,458,304 B = `0x14cccd000`.
- ext4 filesystem 5,583,441,920 B (partition minus a 16,384-byte crypto footer).
- Final sparse covers the whole partition; the last chunk is RAW zeros for the
  footer. ext4 features (Android-6 safe, no `metadata_csum`/`64bit`/`encrypt`):
  `has_journal ext_attr dir_index filetype extent sparse_super large_file huge_file
  uninit_bg dir_nlink extra_isize`. `e2fsck -fn` clean.
- Image #2 is byte-identical to image #1 except for one added 4 KiB block holding
  `/property/persist.adb.tcp.port` (`5555`, 4 bytes, no newline), so it is exactly
  4,096 bytes larger.

## Honest unknowns

- Whether stock setup can be completed again after the wipe was not tested.
- Whether this works on any other RevP17 unit, any other firmware, or survives a
  stock update is unknown. Firmware 1.2x+ is reported by other owners to break the
  `adb_keys` method.
- Why USB never enumerates in Android on this unit is not explained here; the TCP
  path sidesteps it rather than fixing it.
