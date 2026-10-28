# Power BI Desktop on macOS via patched Wine

This project runs **Microsoft Power BI Desktop on Apple Silicon macOS** (tested
on M1, 8 GB RAM) through Wine 11.18. It works by fixing a series of Wine bugs
that Power BI hits — each one found by reverse-engineering `msedge.dll`,
`msolap.dll` and friends and comparing behavior with Windows. This repo ships
the resulting patched binaries, a one-command installer, and the full
investigation log.

---

## Run Power BI on your Mac

### What you need

- A Mac on **macOS 12+** (Apple Silicon **or** Intel — Intel runs it natively, Apple Silicon via Rosetta, installed automatically)
- **~15 GB free disk space** (Wine + prefix + .NET + Power BI)
- Internet (one-time downloads: Wine ~350 MB, .NET/WebView2 ~1 GB, Power BI ~700 MB)
- 30–60 minutes for the first install — **mostly unattended**; the .NET step alone is 10–30 min

### What works today

| ✅ Works | ❌ Not yet |
|---|---|
| Power BI Home screen (data source tiles, options, recent) | **Microsoft account sign-in** and online data sources (TLS bug in Wine's schannel) |
| Opening PBIX / local data, the data model | Launching `PBIDesktop.exe` directly — use the included launcher |
| DAX queries over 1M+ rows (msmdsrv engine) | Full report-canvas GPU rendering (visuals render via a fallback path) |
| Power Query Navigator, load sample data | |

### Step 1 — Install Homebrew (skip if you have it)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Only needed for `winetricks`, which the installer uses.

### Step 2 — Get this project

```bash
git clone https://github.com/siddharthdeo99/powerbi-mac-native.git
cd powerbi-mac-native/scripts
```

No git? Click the green **Code** button on the repo page → **Download ZIP** →
unzip → open the `scripts` folder in Terminal.

### Step 3 — Run the installer

```bash
./setup.sh
```

One command, no questions asked. It:

1. Downloads and checksum-verifies **Gcenx wine-devel 11.18**
2. Downloads and checksum-verifies our **prebuilt patched Wine binaries**
   ([release v0.1](https://github.com/siddharthdeo99/powerbi-mac-native/releases/tag/v0.1)) — no compiling
3. Builds a Windows 10 prefix with **.NET 4.8 + WebView2** (winetricks — the long step)
4. Downloads **Power BI Desktop from Microsoft** and installs it silently
5. Applies every fix (registry tweaks, font substitution, WebView2 settings)
6. Installs the launcher into Power BI's folder

Everything lands in `~/powerbi-mac-native/`. If the script stops partway,
**re-run it** — finished steps are skipped. If the Power BI installer falls
back to a GUI window, click through it and re-run `./setup.sh` to finish.

### Step 4 — Launch

```bash
./run_powerbi.sh
```

The Power BI window appears in 20–30 seconds. Logs go to
`~/powerbi-mac-native/runtime/powerbi.log`.

```bash
./run_powerbi.sh --debug   # launch with Wine error logging
./run_powerbi.sh --stop    # kill Power BI and every Wine process
```

### If something goes wrong

| Symptom | Fix |
|---|---|
| "Power BI not found … run setup.sh first" | `setup.sh` didn't complete — re-run it |
| Nothing appears after 60 s | `./run_powerbi.sh --debug`, then check the tail of `runtime/powerbi.log` |
| Engine reports out of memory | Close Chrome/Teams/Slack first (8 GB Macs swap heavily), then `--stop` and relaunch |
| Free disk space ran out | The install needs ~15 GB; check **About This Mac → Storage** and re-run `./setup.sh` |
| Went to sleep mid-install | Just re-run `./setup.sh` |

To remove everything: `rm -rf ~/powerbi-mac-native` — nothing outside that
folder is touched (plus whatever Homebrew packages you let it install).

---

## What's under the hood

A prebuilt Gcenx Wine Devel 11.18 runtime with nine patched Wine files copied
into it (published, checksummed, on
[release v0.1](https://github.com/siddharthdeo99/powerbi-mac-native/releases/tag/v0.1)),
running Power BI in a Win10 prefix. You never build anything unless you want to.

## The patches (`patches/`)

Each file is a `git diff` against the wine-11.18 tag; apply with
`git apply <file>` inside a Wine 11.18 checkout.

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

- **`setup.sh`** — the installer described above. Re-run any time; idempotent.
- **`run_powerbi.sh`** — launch / `--debug` / `--stop`. Install location resolves
  as `$PBI_MAC_HOME` → `~/powerbi-mac-native`.
- **`build-dll.sh`** — for maintainers: rebuild one patched DLL into the arm64
  build tree and install it (the x86_64 `win32u.so` case has extra flags —
  see HANDOFF §13).

## Documentation (`docs/`)

- **[HANDOFF.md](docs/HANDOFF.md)** — the canonical, dated log of all 17 fixes:
  root causes (with RVAs), fixes, verification steps, gotchas, and pending items.
  **Start here if you want to understand any fix.**
- `docs/analysis/` — porting requirements, Wine architecture and DLL-structure
  notes made while scoping the project.
- `docs/archive/` — the stop-time-fix investigation trail: intermediate
  solutions, instructions, and one-off fix scripts, kept for history. The final
  story is HANDOFF §9 + `patches/oleaut32-variant-maxdate-rounding.patch`.

## Building the patches yourself

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

Several fixes (dcomp, ntdll, wintypes) are candidates to upstream to Wine.

---

*Personal research project. Power BI is a Microsoft trademark; this repo
contains no Microsoft code — only patches to Wine (LGPL 2.1) and original
documentation. The setup script downloads Power BI from Microsoft and Wine
from Gcenx's official builds; you use them under their respective licenses.*
