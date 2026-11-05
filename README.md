# RealtoneWine — native Rocksmith Realtone cable support for RS2014 on Linux/Proton

Rocksmith Remastered 2014 (2014, re-released on Steam) ships with a licensed
USB guitar cable (TonePort/Realtone, USB VID `12BA:00FF`). On Windows the game
talks to it natively; on Linux under Proton/Wine it has never worked — the
community answer has been a decade of workarounds (rs_asio, NoCableLauncher,
routing the cable as a generic microphone).

This project fixes it **at the Wine/Proton level**: with these patches the
game detects the cable by its USB identity, opens its input, hears your
guitar, and its calibration/tuner respond — using the game's own
WASAPI input path (the same architecture the game uses on Windows 11, where
the legacy WDM-KS audio stack is no longer reachable by user-mode code).

**Status:** working end-to-end on the reference machine (Bazzite/Fedora,
Proton Experimental / proton-wine-11.0): cable detected, input on, game
calibration hears the instrument. See *Known limitations* below.

## TL;DR — what you need

1. A patched Wine build (this repo's patches, applied to the Wine tree inside
   your Proton, or our prebuilt DLL drop-in if provided for your Proton
   version).
2. `Rocksmith.ini`: set `ForceWDM=0` (this is the supported configuration on
   modern Windows too — `ForceWDM=1` targets a Windows audio path that
   Windows 11 no longer exposes to applications at all).
3. The Realtone cable plugged in. PipeWire/WirePlumber exposes it as a
   capture source (default ALSA plug mapping is fine).

No RS_ASIO, no NoCableLauncher, no mic-device fiddling, no virtual audio
routing.

## How it works (short version)

The game's input stack (a vendored PortAudio fork) enumerates capture devices
through Windows audio APIs and looks for the Realtone cable's USB identity.
Under Wine three things were broken or missing:

| # | Patch | What it fixes |
|---|-------|----------------|
| 0001 | setupapi: `SetupDiGetDeviceInterfaceAlias` | Implemented (stubbed even upstream). The game's device walk needs interface aliases to correlate KS/WASAPI/SysAudio views of the same device. |
| 0002 | kernelbase: KS filter/probe emulation for audio device interfaces | The game's boot-scan opens KS filter handles and runs a property gauntlet (`KSPROPERTY_PIN_*`, topology, data ranges). Wine maps audio device-interface paths to real KS drivers only via kernel drivers that don't exist for USB audio here; this provides user-mode answers (byte-shaped from a real Windows reference). Needed for the legacy `ForceWDM=1` path; harmless otherwise. |
| 0003 | ntdll: `WINE_HEAP_TAIL_GUARD` (opt-in) | A game bug (reading a volume-interface pointer 12 bytes past a heap block) is benign on Windows' heap and fatal on Wine's. The env-gated guard over-allocates and zeroes 16 tail bytes so the OOB read lands on owned zeros. Only needed for `ForceWDM=1`. |
| 0004 | winepulse: KS capture bridge (+ shared unixlib table) | Routes the emulated KS capture pin to the real PipeWire source (the ForceWDM=1 data path). Not used by the ForceWDM=0 path. |
| 0005 | mmdevapi: serve WASAPI exclusive clients as shared | **The one the game actually needs today.** The game opens its input in WASAPI exclusive mode; Wine has no exclusive mode and rejects every device, which PortAudio reports as `paInvalidDevice` (-9996) for *all* inputs. We map exclusive → shared, exactly how modern Windows degrades it in practice. |

The result: the game's own PortAudio-WASAPI layer opens the cable as a capture
device (Wine maps it to the cable's PipeWire source), the game's detector
matches the `12BA:00FF` identity, and guitar input flows through the game's
normal calibration → tuner path.

A fuller write-up (detection chain, evidence trail, why WDM-KS had to be
abandoned) is in [`docs/how-it-works.md`](docs/how-it-works.md).

## Install

### Option A — one script, prebuilt DLLs (easiest)

From a checkout of this repo (or after unpacking the release zip):

```sh
cd realtonefix/scripts
./install-prebuilt.sh
```

That finds your Steam + Proton Experimental, backs up its wine directory,
installs the patched DLLs, fixes the game prefix, and sets `ForceWDM=0` in
`Rocksmith.ini`. Built for Proton Experimental 11.0-100; other versions need
`--force` (or Option B).

### Option B — build from source

Prerequisites: git, podman (or docker), ~10 GB disk, and a Proton source
checkout whose Wine matches your installed Proton (for Proton Experimental:
`ValveSoftware/proton`, branch `proton_11.0` era — verify the wine submodule
tag `proton-wine-11.0`).

```sh
git clone https://github.com/ValveSoftware/proton.git proton-src
cd proton-src
git submodule update --init --recursive   # checks out wine/

/path/to/this/repo/scripts/apply-patches.sh .            # apply our patches
/path/to/this/repo/scripts/build-wine.sh .               # podman build → build/dist
/path/to/this/repo/scripts/deploy-to-proton.sh build/dist \
    "~/.local/share/Steam/steamapps/common/Proton - Experimental"
/path/to/this/repo/scripts/setup-prefix.sh \
    "~/.local/share/Steam/steamapps/compatdata/<APPID>/pfx" \
    "~/.local/share/Steam/steamapps/common/Proton - Experimental"
```

Then in `…/steamapps/common/Rocksmith2014/Rocksmith.ini` set:

```ini
ForceWDM=0
ExclusiveMode=0        ; 1 also works (exclusive is served as shared)
DumpAudioLog=1         ; recommended while testing
```

### Option C — manual drop-in (no script)

Copy the DLLs from `prebuilt/` into the matching `files/lib/wine/…`
directories of your installed Proton, run `scripts/setup-prefix.sh`, set
`ForceWDM=0`. The DLLs are built from the patches in `patches/` (LGPL-2.1);
source is here.

## Verifying

Launch the game, go to the tuner (Learn a Song → any song session opens with
a calibration/tuner flow). The game log `audiodump.txt` (next to
`Rocksmith.ini`, with `DumpAudioLog=1`) should show:

```
DetectInputDevices_PortAudio Id N API 0 : Microphone (Rocksmith Guitar Adapter Mono)[p:00ff v:12ba]
…  INPUT ON Slot N
```

`[p:00ff v:12ba]` is the cable's USB identity — if you see it with `INPUT ON`,
the cable is live. Strum and the calibration meter/tuner should respond.

## Known limitations

- Validated on one machine (Fedora-family, PipeWire, Proton Experimental
  11.0-100). Other Protons (GE-Proton, CachyOS winepipewire builds) should
  work since the seam is Wine-internal, but are untested — feedback welcome.
- `ForceWDM=1` remains usable as a legacy path on Wine (it emulates enough of
  Windows' WDM-KS to work where real Windows ≥Win10 no longer allows it),
  but it needs `WINE_HEAP_TAIL_GUARD=1` in the game's environment and is not
  the recommended configuration.
- Hotplug (unplug/replug mid-session) relies on Wine's device-change
  notifications; the game should re-scan on its detection cycle.

## License / compliance

- The patches modify Wine, which is **LGPL-2.1**; the patches and any binary
  builds from them are therefore distributed under LGPL-2.1 as well, and the
  source (this repo) satisfies the corresponding-source requirement. Wine
  copyright headers in touched files are preserved; new files carry the
  standard LGPL header.
- Proton's build glue (Valve) is BSD-3-Clause; we don't modify or relicense
  it.
- Everything else in this repo (docs, scripts) is provided under the MIT
  license (see `LICENSE-MIT`); swap to whichever license suits you if you
  fork. See `docs/licenses.md` for the full breakdown.

## Credits

- The Wine/Proton projects — this fix is ~1000 lines of diff on top of decades
  of their work.
- The RS2014 community (rs_asio, NoCableLauncher maintainers) for a decade of
  workaround lore that mapped the minefield.
- Ubisoft/SMG Studios — the game's audio stack is genuinely interesting.
- See `docs/how-it-works.md` for the evidence trail.
