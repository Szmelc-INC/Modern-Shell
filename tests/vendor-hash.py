#!/usr/bin/env python3
"""vendor-hash.py — compute buildGoModule's vendorHash without nix.

Runs `go mod vendor` into a temp dir, serializes it as a NAR (the format nix
hashes fixed-output derivations with), and writes the SRI sha256 into
flake.nix. Run with: python3 -I tests/vendor-hash.py
"""
import base64
import hashlib
import os
import re
import stat
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def nar_str(h, data: bytes):
    h.update(len(data).to_bytes(8, "little"))
    h.update(data)
    h.update(b"\0" * ((8 - len(data) % 8) % 8))


def nar_node(h, path):
    st = os.lstat(path)
    nar_str(h, b"(")
    if stat.S_ISLNK(st.st_mode):
        nar_str(h, b"type"); nar_str(h, b"symlink")
        nar_str(h, b"target"); nar_str(h, os.readlink(path).encode())
    elif stat.S_ISREG(st.st_mode):
        nar_str(h, b"type"); nar_str(h, b"regular")
        if st.st_mode & 0o111:
            nar_str(h, b"executable"); nar_str(h, b"")
        with open(path, "rb") as f:
            nar_str(h, b"contents"); nar_str(h, f.read())
    elif stat.S_ISDIR(st.st_mode):
        nar_str(h, b"type"); nar_str(h, b"directory")
        for name in sorted(os.listdir(path), key=lambda n: n.encode()):
            nar_str(h, b"entry"); nar_str(h, b"(")
            nar_str(h, b"name"); nar_str(h, name.encode())
            nar_str(h, b"node"); nar_node(h, os.path.join(path, name))
            nar_str(h, b")")
    else:
        sys.exit(f"unsupported file type: {path}")
    nar_str(h, b")")


def main():
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "vendor")
        env = dict(os.environ, GOFLAGS="-mod=mod")
        subprocess.run(["go", "mod", "vendor", "-o", out], cwd=ROOT, check=True, env=env)
        h = hashlib.sha256()
        nar_str(h, b"nix-archive-1")
        nar_node(h, out)
        sri = "sha256-" + base64.b64encode(h.digest()).decode()
    flake = os.path.join(ROOT, "flake.nix")
    text = open(flake).read()
    new = re.sub(r'vendorHash = "[^"]*";', f'vendorHash = "{sri}";', text)
    open(flake, "w").write(new)
    print(sri)


if __name__ == "__main__":
    main()
