#!/usr/bin/env python3
"""Connect to the Mirror's network ADB with a pure-Python client.

Use this when the native `adb` client crashes right after connect (seen on macOS
27 with platform-tools 37.0.1: a libunwind crash seconds after `adb connect`).
The `adb-shell` pure-Python client does not have that problem.

    python3 -m venv /tmp/adbpy && /tmp/adbpy/bin/pip install adb-shell[usb]
    /tmp/adbpy/bin/python adb_connect_example.py 10.77.0.50 \\
        --key ~/.android/adbkey

It authenticates with YOUR adb key pair (the public half must be the key planted
in the userdata image). The private key stays on your machine and is only used to
sign Android's auth challenge. Never put a private key in the image or a report.
"""
import argparse
import os

from adb_shell.adb_device import AdbDeviceTcp
from adb_shell.auth.sign_pythonrsa import PythonRSASigner


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("host", help="Mirror IPv4 (e.g. 10.77.0.50)")
    p.add_argument("--port", type=int, default=5555)
    p.add_argument("--key", default=os.path.expanduser("~/.android/adbkey"),
                   help="path to your adb private key (default ~/.android/adbkey)")
    args = p.parse_args()

    with open(args.key) as f:
        priv = f.read()
    with open(args.key + ".pub") as f:
        pub = f.read()
    signer = PythonRSASigner(pub, priv)

    dev = AdbDeviceTcp(args.host, args.port, default_transport_timeout_s=10)
    dev.connect(rsa_keys=[signer], auth_timeout_s=15)
    print("connected and authorized")

    for prop in ("ro.build.fingerprint", "ro.crypto.state",
                 "persist.adb.tcp.port", "service.adb.tcp.port"):
        val = dev.shell(f"getprop {prop}").strip()
        print(f"{prop} = {val!r}")
    print("id =", dev.shell("id").strip())
    dev.close()


if __name__ == "__main__":
    main()
