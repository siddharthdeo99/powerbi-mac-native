# Power BI Desktop on macOS via patched Wine

Reverse-engineering project that gets **Microsoft Power BI Desktop** running on
Apple Silicon macOS (M1, 8 GB RAM) through Wine 11.18, by fixing the Wine bugs
Power BI hits — mostly found by diffing behavior against Windows and reading
`msedge.dll` / `msolap.dll` in a disassembler.

**Current state:** the Power BI Desktop Home screen renders and works (data
source tiles, sign-in, options), the analysis engine (msmdsrv) answers DAX over
1M rows, and report web views load. Open items: launching `PBIDesktop.exe`
directly (the harness launcher works), Microsoft sign-in TLS, full report-canvas
rendering. See [docs/HANDOFF.md](docs/HANDOFF.md) for the full, dated status.

## Quick start (one command)

```bash
git clone https://github.com/siddharthdeo99/powerbi-mac-native.git
cd powerbi-mac-native/scripts
./setup.sh          # 30–60 min, mostly unattended; ~15 GB disk
./run_powerbi.sh
```

`setup.sh` downloads and verifies **Gcenx wine-devel 11.18**, the **prebuilt
patched binaries** from [release v0.1](https://github.com/siddharthdeo99/powerbi-mac-native/releases/tag/v0.1),
a Win10 prefix with **.NET 4.8 + WebView2** (winetricks), **Power BI Desktop**
from Microsoft, and applies every registry tweak. Requirements: macOS (Apple
Silicon or Intel), Homebrew for winetricks. Power BI itself is not
redistributed — the script fetches it from Microsoft's official link.

## How it works

A prebuilt Gcenx Wine Devel 11.18 runtime, with patched PE/Unix DLLs copied
into it, running Power BI in a Win10 prefix. The patched binaries (9 files) are
published as [release v0.1](https://github.com/siddharthdeo99/powerbi-mac-native/releases/tag/v0.1)
so nobody has to build Wine; building them yourself from `patches/` is
documented below.

## Patches (`patches/`)

Each file is a `git diff` against wine-11.18; apply with `git apply <file>`
inside a Wine 11.18 checkout.

| Patch | Component | What it fixes |
|---|---|---|
| `secur32-lsafreereturnbuffer-ntstatus.patch` | secur32 | `LsaFreeReturnBuffer` returned a BOOL instead of an NTSTATUS; msolap.dll read non-zero as an error and abandoned NTLM login → "Failed to open the MSOLAP connection" |
| `oleaut32-variant-maxdate-rounding.patch` | oleaut32 | `VarUdateFromDate` rounded `DateTime.MaxValue` (trace `StopTime`) into year 10000, so the round-trip back failed → model load failure |
| `win32u-cross-process-child-surfaces.patch` | win32u | WebView2 child windows owned by another process got no window surface on macOS → blank web views; now drawn via shared-memory surfaces composited by the parent |
| `dcomp-eaccessdenied.patch` | dcomp | `DCompositionCreateDevice` returns `E_ACCESSDENIED` (no DWM); `msedge.dll` deliberately int3-crashes on anything else → GPU process crash |
| `ntdll-macos-fixes.patch` | ntdll | `NtImpersonateAnonymousToken` semi-stub (engine startup) + `fill_vm_counters` reports phys_footprint (engine thought RAM was exhausted) |
| `mshtml-text-overflow.patch` | mshtml | Implemented CSS `text-overflow`; the Power Query Navigator's startup script aborted on the stub → hang dialog |
| `msv1_0-ntlm-connection-flag.patch` | msv1_0 | Round 2 of `InitializeSecurityContext` dropped `ISC_RET_CONNECTION` |
| `ncrypt-dpapi-ng.patch` | ncrypt | DPAPI-NG implementation (written; not needed at startup) |
| `wintypes-roresolve-namespace.patch` | wintypes | `RoResolveNamespace` implementation; lets the Power BI main window open |

## Scripts (`scripts/`)

- **`run_powerbi.sh`** — launch Power BI through the patched runtime
  (`--debug` for Wine logging, `--stop` to kill everything).
  Requires the layout from `docs/HANDOFF.md` under `~/reverengineer`
  (Wine runtime, `pbi-prefix`, `/opt/homebrew/bin` on PATH for `ntlm_auth`).
- **`build-dll.sh`** — rebuild one patched DLL into the arm64 build tree.
  (The x86_64 `win32u.so` build has extra FreeType/Vulkan config flags — see HANDOFF §13.)

## Documentation (`docs/`)

- **[HANDOFF.md](docs/HANDOFF.md)** — the canonical, dated log of all 17 fixes:
  root causes (with RVAs), fixes, verification steps, gotchas, and pending items.
  **Start here.**
- `docs/analysis/` — porting requirements, Wine architecture and DLL-structure
  notes made while scoping the project.
- `docs/archive/` — the stop-time-fix investigation trail: intermediate
  solutions, instructions, and one-off fix scripts, kept for history. The final
  story is HANDOFF §9 + `patches/oleaut32-variant-maxdate-rounding.patch`.

## Building the patches

```bash
git clone --branch wine-11.18 https://gitlab.winehq.org/wine/wine.git wine
cd wine && git apply ../patches/*.patch
# arm64 host, PE (Windows-side) DLLs:
../scripts/build-dll.sh oleaut32
# x86_64 host, Unix-side .so (only win32u needed this): see HANDOFF §13
```

Copy the built DLL into the Wine runtime's
`Contents/Resources/wine/lib/wine/x86_64-windows/` (keep a backup of the stock
file first).

## Status dashboard

| Works | Pending |
|---|---|
| Home screen, engine + DAX over 1M rows, WebView2 UI (win7 override), model load, NTLM login | `PBIDesktop.exe` direct launch, Microsoft sign-in TLS 1.2/1.3, full report canvas, 8 GB RAM pressure |

Several of these fixes (dcomp, ntdll, wintypes) are candidates to upstream to
Wine.

*Personal research project. Power BI is a Microsoft trademark; this repo
contains no Microsoft code — only patches to Wine (LGPL 2.1) and original
documentation.*
