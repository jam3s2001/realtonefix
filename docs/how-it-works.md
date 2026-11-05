# How this works — the full story

This document explains why the Realtone cable never worked under Wine/Proton,
what we changed, and why the resulting architecture matches what the game
actually does on modern Windows. It doubles as the review guide for the
patch series.

## 0. The cable and the game

The licensed Rocksmith Realtone cable (USB `12BA:00FF`, "Licensed by Sony
Computer Entertainment America Rocksmith Guitar Adapter") is a plain USB
Audio Class device: a 16-bit mono capture endpoint (8–48 kHz) plus a HID
interface. No vendor driver, no proprietary protocol. The game identifies it
by USB VID/PID and treats it as a guitar rather than a generic microphone.

RS2014's audio stack (`audiodump.txt`, its own log, is a goldmine) has two
sides:

- **Output (the "sink")**: the game's own WASAPI client
  (`WASAPI::OpenStream(output)`), shared mode, driven by `ForceWDM=0`/`1` and
  `ExclusiveMode`.
- **Input ("NSoundInputMgr_Win32")**: a vendored PortAudio fork with several
  host-API backends. `mUsePortAudio 1` selects it. Two input paths exist:
  - `ForceWDM=1` → PortAudio's **WDM-KS** backend (kernel-streaming),
  - `ForceWDM=0` → PortAudio's **WASAPI** backend (plus MME fallback).

## 1. Why it never worked on Linux

PortAudio's WDM-KS backend (the path the game preferred with its default
`ForceWDM=1` config) does something brutal: it enumerates audio devices
through the Windows SetupAPI device interfaces, opens the KS filter objects
directly, and negotiates kernel-streaming properties. On Windows this talks
to `usbaudio.sys`/`hdaud.sys` etc. Wine has no kernel-side audio KS drivers,
so:

- the device interfaces existed only as registry text,
- `SetupDiGetDeviceInterfaceAlias` (used to correlate the KS view of a device
  with its WASAPI/endpoint view) was a stub returning nothing,
- opening `\?\usb#…#{6994ad04…}` device paths led nowhere,
- every KS property probe returned garbage or failure,
- `ksuser!KsCreatePin` — the function that instantiates a pin — was a stub.

The detection chain (fully traced and decoded from the game's live memory:
see the research log) is:

```
SetupDiGetClassDevs(KSCATEGORY_AUDIO)
→ SetupDiEnumDeviceInterfaces
→ SetupDiGetDeviceInterfaceAlias ×3        [patch 0001]
→ SetupDiGetDeviceInterfaceDetail → FriendlyName ("Microphone (Rocksmith
   USB Guitar Adapter)")
→ CreateFileW(KS filter path)              [patch 0002: map to emulation]
→ KS property gauntlet (CTYPES, ranges, topology, data ranges…)  [0002]
→ KsCreatePin                              [0002: implemented in ksuser]
→ per-pin verdict → device accepted, identity [p:00ff v:12ba] recorded
→ WASAPI endpoint join → PortAudio device registered → "INPUT ON Slot N"
```

Patches 0001/0002 (plus a Wine-side KsCreatePin and a KS property emulation
layer shaped byte-exact against a real Windows reference capture of the
cable) make that chain pass under Wine for the `ForceWDM=1` path.

## 2. The crash, and the heap-luck problem

With input opening under `ForceWDM=1`, a game bug surfaced: its input-manager
reads an *IAudioEndpointVolume\** pointer from a stream field at `+0x1fc`,
but the stream object it caches comes from a constructor that allocates only
`0x1f0` bytes and never initializes that offset — an out-of-bounds read into
the neighboring heap block. On Windows the neighbor was (heuristically) zero
→ the game treats it as "volume control unavailable" and continues. On Wine
the neighbor held live data (timestamps) → the game called through a garbage
pointer and crashed.

Patch 0003 (`WINE_HEAP_TAIL_GUARD=1`, opt-in) over-allocates every heap block
by 16 zeroed bytes so such OOB tail reads deterministically land on owned
zeros — reproducing the Windows outcome honestly rather than patching the
game (which is impossible anyway: the game's packer verifies its own code).

## 3. The plot twist: Windows 11 killed WDM-KS

Investigation on a real Windows 11 machine (2026-11-04, see
`captures/ForceWDM.txt` in the project notes) established that **Windows 11
no longer permits user-mode kernel-streaming access to the audio stack at
all**: every audio KS filter — including the Realtone cable's — rejects
`KSPROPERTY_PIN_CTYPES` with `ERROR_INVALID_FUNCTION`. PortAudio's WDM-KS
backend cannot enumerate a single device. `ForceWDM=1` therefore cannot work
on any current Windows machine; the game runs there exclusively via
`ForceWDM=0`.

That made the decision for us: the architecture to support is the game's
**WASAPI path** — which Wine implements (via its pulseaudio/pipewire audio
driver) — not WDM-KS.

## 4. The real fix: exclusive mode (patch 0005)

With `ForceWDM=0`, the game's PortAudio-WASAPI backend enumerates capture
endpoints and — with `ExclusiveMode=1` — probes them in **WASAPI exclusive
mode**. Wine's audio stack has no exclusive mode: `IAudioClient::Initialize`
and `IsFormatSupported` reject `AUDCLNT_SHAREMODE_EXCLUSIVE` outright
(`AUDCLNT_E_EXCLUSIVE_MODE_NOT_ALLOWED` → `AUDCLNT_E_UNSUPPORTED_FORMAT`).
PortAudio then reports every device as invalid (`paInvalidDevice`, -9996) —
for *all* inputs, cable or not.

The fix is six lines at both entry points in `dlls/mmdevapi/client.c`:
map `AUDCLNT_SHAREMODE_EXCLUSIVE` to `AUDCLNT_SHAREMODE_SHARED`. This mirrors
reality — on Windows 11 the game's exclusive mode never engages either (the
system silently opens shared); Wine simply doesn't pretend.

With that, under `ForceWDM=0`:

```
DetectInputDevices_PortAudio Id 1 API 0 : Microphone (Rocksmith Guitar
    Adapter Mono)[p:00ff v:12ba]  INPUT ON Slot 1
```

— the cable opens through the game's own WASAPI layer onto Wine's
PipeWire-backed capture, the game hears the guitar, and its calibration and
tuner respond. The `ResetEvents`/`Make-some-noise` flow that dead-ends the
WDM path never trips here; there is no restart gate to satisfy.

## 5. Why WASAPI identity works without the KS layer

The `[p:00ff v:12ba]` VID/PID identity the game's detector requires is
available through the WASAPI endpoint property store: Wine's pulse driver
parses PipeWire's USB device properties (`device.vendor.id`,
`device.product.id`) into the endpoint's identity data. The game's detector
accepts the device once the input opens and the identity matches. The KS-side
patches (0001/0002) still run (the game does a light KS scan at boot) and
keep that path honest, but the input data path is plain WASAPI.

## 6. Patch-by-patch

| Patch | Path | Required for ForceWDM=0 | Purpose |
|-------|------|--------------------------|---------|
| 0001 | setupapi | contributes to device identity/correlation | implement `SetupDiGetDeviceInterfaceAlias` |
| 0002 | kernelbase | harmless (idle) | KS filter/probe emulation for the legacy WDM path |
| 0003 | ntdll | not needed (env-gated) | `WINE_HEAP_TAIL_GUARD` OOB-tail mitigation |
| 0004 | winepulse + mmdevapi unixlib | not needed for 0005 path | KS capture bridge for the legacy path |
| 0005 | mmdevapi | **YES** | exclusive → shared |

A minimal build for `ForceWDM=0` is patch 0005 plus 0001 (0001 keeps the
boot-scan happy on prefixes where the game's KS leg runs). Applying the whole
series is supported and recommended; everything except 0003 is default-on
and inert where unused.

## 7. Evidence trail

Everything above was derived against live evidence: USB captures, Windows
reference property dumps, in-game memory probes of the running game, the
game's own `audiodump.txt`, and — decisively — a controlled experiment on a
real Windows 11 machine proving the WDM path dead. The full lab notebook
(~2500 lines) lives in the project's research log; this document is the
distilled version.
