# Bundled AirConnect

| | |
|---|---|
| Upstream | https://github.com/philippe44/AirConnect |
| Release | `1.12.4` (tag `1.12.4`, commit `f7dc3b39cece50b3230d072cf5b43b5694572635`) |
| Release asset | `AirConnect-1.12.4.zip` (sha256 `ae59d595be80db7f4e93c94c9029baff59dc7515ec03e44505ab2792bbcd1903`) |
| File in this repo | `airupnp-macos-arm64-static` |
| sha256 | `9bf54de8af7f981259d75c0b8dd85f5886f40246df6bd16fe57276249a7cef98` |
| Reports | `v1.12.4 (Sep 26 2026 @ 20:05:30)` |
| Author | Philippe (philippe44), philippe_44@outlook.com |

## Why the `-static` build

The plain `airupnp-macos-arm64` loads the system `libcrypto` in a way macOS refuses
("is loading libcrypto in an unsafe way", then `abort`). The `-static` build carries
its own OpenSSL and links only `libSystem`, so it runs as is.

## Licence

AirConnect's own code is MIT (see `LICENSE`). The binary also contains third-party
code (libupnp/pupnp, ALAC, FLAC, FAAC, OpenSSL, mDNS) and its `-t` licence terms state
**GNU GPL v3 or later** (see `COPYING`). The binary is redistributed unmodified; the
corresponding source is the upstream tag above.

## Updating

Run `scripts/update-airconnect.sh <version>`, then update this file and the
fixtures if the log format changed.
