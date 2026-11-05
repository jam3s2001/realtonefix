# Building the patched Wine

This guide builds the patched Wine that ships in your Proton and deploys it
in place. Two supported routes: **podman** (Valve's official route, matches
the Steam Runtime SDK) or a **native build** if you know your toolchain
matches the Steam Runtime.

## 0. Requirements

- git, podman **or** docker, ccache (recommended), ~10 GB disk, ≥4 cores
- A Proton source checkout with the Wine submodule matching your installed
  Proton. For Proton Experimental 11.0-100 this is `ValveSoftware/proton`
  with wine submodule `proton-wine-11.0` (commit `e60892cc`).
- SELinux note (Fedora/Bazzite): the podman build needs either
  `chcon -R -t container_file_t` on the proton and ccache trees, or
  `--relabel-volumes` in configure.

## 1. Get the sources

```sh
git clone https://github.com/ValveSoftware/proton.git
cd proton
git submodule update --init --recursive
# verify: wine submodule tag should be proton-wine-11.0
git -C wine describe --tags
```

## 2. Apply the patches

```sh
/path/to/realtonewine/scripts/apply-patches.sh "$PWD"
# sanity: git -C wine log --oneline -5   (patches applied on top of base)
```

The script applies `patches/0001…0005` with `git apply --3way` into the wine
submodule. No Proton-level (non-wine) files are modified.

## 3. Build

```sh
/path/to/realtonewine/scripts/build-wine.sh "$PWD"
```

This wraps Proton's own build system:

```sh
mkdir -p build && cd build
CCACHE_DIR=~/.cache/proton-ccache ../configure.sh --container-engine=podman --enable-ccache
make wine -j$(nproc)        # wine only; add `make dist` targets as needed
```

First build is long (the dependency chain — gstreamer, ffmpeg, openfst —
builds first); subsequent builds are incremental and fast. A Wine-only
incremental rebuild after touching one DLL is ~1 minute:

```sh
rm -f build/.wine-i386-build build/.wine-x86_64-build \
      build/.wine-i386-dist build/.wine-x86_64-dist
rmdir build/wine 2>/dev/null
make wine -j$(nproc) -C build
```

(Yes, removing those stamps is required — Proton's `make wine` is a no-op
after the first build even with changed sources.)

Artifacts land in `build/dist/files/lib/wine/`.

## 4. Deploy into your installed Proton

Back up first:

```sh
cp -a "~/.local/share/Steam/steamapps/common/Proton - Experimental/files/lib/wine" \
      ~/proton-wine-backup
```

Then:

```sh
/path/to/realtonewine/scripts/deploy-to-proton.sh build/dist \
    "~/.local/share/Steam/steamapps/common/Proton - Experimental"
```

The script copies (both architectures):

```
i386-windows/:  setupapi.dll ksuser.dll ntdll.dll kernelbase.dll mmdevapi.dll winepulse.drv
x86_64-windows/: (same list)
i386-unix/:     winepulse.so winealsa.so
x86_64-unix/:   winepulse.so winealsa.so
```

…and makes them read-only, exactly like the rest of Proton.

## 5. Fix the game prefix's ksuser.dll

Wine resolves `ksuser.dll` from the prefix if a file/symlink exists there;
the stock prefix ships a symlink into the Proton directory which must point
at the *new* build (an absolute path fixes the classic "dead relative
symlink" failure):

```sh
/path/to/realtonewine/scripts/setup-prefix.sh \
    "~/.local/share/Steam/steamapps/compatdata/221680/pfx" \
    "~/.local/share/Steam/steamapps/common/Proton - Experimental"
```

## 6. Configure the game

In `steamapps/common/Rocksmith2014/Rocksmith.ini`:

```ini
ForceWDM=0
ExclusiveMode=0
DumpAudioLog=1
```

Launch via Steam as usual. `WINE_HEAP_TAIL_GUARD=1` is **not** required for
`ForceWDM=0`.

## 7. Verify

Play; then check `steamapps/common/Rocksmith2014/audiodump.txt`:

```
DetectInputDevices_PortAudio Id N API 0 : Microphone (Rocksmith Guitar Adapter Mono)[p:00ff v:12ba]
DetectInputDevices_PortAudio Id N API 0 : … INPUT ON Slot N
```

`INPUT ON` with `[p:00ff v:12ba]` = the cable is live.

## Troubleshooting

- **No `[p:00ff v:12ba]` on any device** → the cable isn't exposed to
  PipeWire; check `pactl list sources short | grep -i rocksmith`.
- **`InputOn … err -9996`** → you're running an unpatched (or stale) mmdevapi;
  confirm `deploy-to-proton.sh` copied `mmdevapi.dll` for *both*
  architectures and that the prefix symlinks point at the installed Proton.
- **Game crashes right after input opens (ForceWDM=1 only)** → that's the
  OOB-read bug; use `ForceWDM=0` (recommended) or set
  `WINE_HEAP_TAIL_GUARD=1` in the game's launch options.
- **Rollback** → restore `~/proton-wine-backup` over `files/lib/wine` and
  rerun `setup-prefix.sh`.
