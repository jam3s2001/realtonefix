# Licenses & compliance

What is what, and why this distribution is license-clean.

## Wine (and every patch in `patches/`)

Wine is distributed under the **GNU Lesser General Public License, version
2.1** (LGPL-2.1). Every file our patches touch — `setupapi`, `kernelbase`,
`ntdll`, `mmdevapi`, `winepulse`, `ksuser` — is part of Wine, so the patches
are derivative works of Wine and are therefore distributed under **LGPL-2.1**.
This applies to:

- the patch files themselves (the preferred modification form — LGPL-2.1
  section 4 explicitly contemplates patches as a way to distribute
  modifications while keeping the source requirement satisfied),
- any binary Wine builds or DLL drop-ins created from them (the "corresponding
  source" is this repository).

Wine's copyright headers in the touched files are preserved verbatim; new
files added by the patches (e.g. the `ksuser` implementation) carry Wine's
standard LGPL-2.1 header with the project's copyright line added.

Upstreaming status: patch 0005 (exclusive→shared) and 0001
(`SetupDiGetDeviceInterfaceAlias`) are written in upstream-reviewable style;
the rest (0002–0004) implement functionality for a Windows code path that
Windows 11 itself no longer exposes, so upstream Wine may or may not want
them — they are maintained here regardless.

## Proton / Valve build glue

Proton (ValveSoftware/proton) is BSD-3-Clause. We modify nothing in it — the
patches live entirely in the Wine submodule — and the build scripts in
`scripts/` only wrap Proton's own `configure.sh`/`make` targets.

## Everything else in this repository

Documentation, shell scripts, and tooling that are original to this project
are provided under the **MIT license** (see `LICENSE-MIT`). If you fork or
repost, that's the license for the non-Wine parts; it may be swapped freely
as long as the Wine-derived parts remain under LGPL-2.1.

## Third-party references used

- The RS2014 community tooling (rs_asio, NoCableLauncher) — studied for
  behavior; no code taken.
- Microsoft's public KS/WDM documentation — reference only.
- A Windows 11 machine owned by the project author — used for controlled
  experiments, results documented in the project notes. No Microsoft code is
  included.
