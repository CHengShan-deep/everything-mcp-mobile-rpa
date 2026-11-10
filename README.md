# everything-mcp-mobile-rpa

Build recipes for the Android runtime used by the mobile MCP/RPA stack.

## What this builds

A Termux bootstrap archive compiled from source for an application id of our own
(`com.ynk.virtualdisplay.runtime` by default) rather than `com.termux`.

The published Termux bootstrap archives cannot be reused: the prefix
(`/data/data/<package>/files/usr`) is compiled into every ELF interpreter and
rpath, so a rename is not possible without rebuilding. `termux-packages` hardcodes
`TERMUX_APP__PACKAGE_NAME` in `scripts/properties.sh`; the build script patches
that single line before compiling, and everything below `TERMUX_APP__DATA_DIR`
inherits it.

The archive contains the default bootstrap package set plus `python`. It is
built with the default (non `--android10`) layout, which includes apt/dpkg and
does **not** pull in proot.

## Running

Push to `main`, or trigger the `bootstrap` workflow manually. One job per
architecture runs in parallel; a cold build takes roughly 40-90 minutes on a
standard runner. Built debs and their "already built" markers are cached under a
key that includes the resolved termux-packages commit, so a run against an
unchanged upstream only re-assembles the archive.

Workflow inputs:

| input | default | meaning |
| --- | --- | --- |
| `arches` | `aarch64,x86_64` | comma-separated target architectures |
| `package_name` | `com.ynk.virtualdisplay.runtime` | application id owning the prefix |
| `termux_ref` | pinned commit | termux-packages commit to build from; pinning keeps both the build reproducible and the CI cache usable |
| `extra_packages` | `python` | packages added on top of the default bootstrap set |

Artifacts are named `bootstrap-<arch>-<run_id>` and contain
`bootstrap-<arch>.zip` plus the resolved `termux-packages.commit`.

## Local reproduction

Requires Docker (the official `ghcr.io/termux/package-builder` image carries the
toolchain and an NDK). The image is run directly rather than through
`scripts/run-docker.sh`, whose AppArmor profile denies writes to the bind mount.

```sh
ARCH=aarch64 ./scripts/build-bootstrap.sh
```
