# Power BI Desktop on macOS (Wine): handoff, 2026-10-28

Goal: run Power BI Desktop on an M1 Mac (8 GB RAM) through Wine. We use a prebuilt Wine plus our own patched DLLs.

## Layout (all under `~/reverengineer`)
| Path | What |
|---|---|
| `runtime/Wine Devel.app` | Gcenx wine-devel 11.18, the runtime we use. Patched DLLs are copied into `Contents/Resources/wine/lib/wine/x86_64-windows/` |
| `pbi-prefix/` | Win10 prefix: Power BI MSI, .NET 4.8, WebView2 runtime 156.0.4314.50 |
| `wine/` | Wine source (tag wine-11.18) holding our patches (`git diff` shows them) |
| `wine-build/` | arm64-host build tree for PE DLLs. Build: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk PATH=/opt/homebrew/opt/bison/bin:$PATH make -j8 dlls/<dll>/x86_64-windows/<dll>.dll` |
| `wine-build64/` | x86_64-host build tree for `ntdll.so` |
| `pbi-prefix/drive_c/pbitest/client/` | Test programs (`tracetest.exe <port> [values...]`): `daxtest` (engine DAX test), `tracetest` (XMLA trace StopTime test), `timetest` (Win32 time API test) |
| `runtime/harnessNN.log` | Logs from each Power BI launch. The newest is `harness20.log` |

## How to launch Power BI
```bash
R=~/reverengineer/runtime; W="$R/Wine Devel.app/Contents/Resources/wine/bin"
export PATH="$W:/opt/homebrew/bin:$PATH" WINEPREFIX=~/reverengineer/pbi-prefix   # /opt/homebrew/bin is REQUIRED (Samba ntlm_auth)
cd "$WINEPREFIX/drive_c/Program Files/Microsoft Power BI Desktop/bin"
WINEDEBUG=err+all,fixme-all wine zz_pbiharness.exe > $R/harness21.log 2>&1 &
# stop everything:  pkill -9 -f "zz_pbiharness|msedgewebview2|msmdsrv|wineserver|Wine Devel.app"
```
`zz_pbiharness.exe` starts Power BI and prints every first-chance .NET exception. Launching `PBIDesktop.exe` directly still crashes; see Pending.

## Done (verified)
1. **ntdll `NtImpersonateAnonymousToken`**: semi-stub. Without it the engine fails at startup with "Service cannot be started".
2. **ntdll `fill_vm_counters` (macOS)**: reports the `TASK_VM_INFO` phys_footprint instead of virtual size, so the engine no longer thinks memory is exhausted.
3. **wintypes `RoResolveNamespace`**: implemented. Also installed the Microsoft SDK Contracts winmd (test only; Wine's own winmd is backed up at `runtime/winmetadata.wine-backup`). This lets the Power BI main window open.
4. **ncrypt DPAPI-NG**: patch written, but not needed at startup.
5. Font replacement Segoe UI → Tahoma.
6. **Engine (msmdsrv)** works: login and DAX over 1M rows give correct results.
7. **WebView2 GPU-process crash fixed.** Root cause found by reverse engineering `msedge.dll`: the function at `+0x36acd00` creates a WARP D3D11 device and then calls `DCompositionCreateDevice`. On failure it tolerates only `E_ACCESSDENIED` and deliberately crashes (int3) on anything else. Wine returned `E_NOTIMPL`.
   - Fix: `wine/dlls/dcomp/device.c`, where `DCompositionCreateDevice/2/3` now return `E_ACCESSDENIED` (no desktop compositor, as on Windows without DWM). Installed; the stock DLL is backed up at `runtime/dcomp.dll.stock-11.18`.
   - **DXVK removed for `msedgewebview2.exe`**: DXVK rejects `D3D_DRIVER_TYPE_WARP`, which caused an access violation. Wine's d3d11 falls back from WARP to hardware. Do not block `dcomp` per app; that only causes a delay-load crash.
   - Edge "hardware acceleration" is set off in `Local State` (backup at `runtime/LocalState.backup.json`).
   - Result: the GPU process stays alive and the report web views load.
8. **"Authentication failed" dialog**: Samba `ntlm_auth` wasn't on PATH. Fixed by adding `/opt/homebrew/bin` to PATH (see the launch commands).

9. **Model load ("Failed to open the MSOLAP connection") fixed.** AMO sends trace `StopTime = DateTime.MaxValue` (`9999-12-31T23:59:59.9999999`). The engine round-trips it through `VariantTimeToSystemTime` → `SystemTimeToVariantTime`, which a relay trace confirmed. Wine's `VarUdateFromDate` rounded the 0.999 s up to `10000-01-01`, so the conversion back failed.
   - Fix: `wine/dlls/oleaut32/variant.c`, which no longer rounds past 31 Dec 9999. Installed; the stock DLL is backed up at `runtime/oleaut32.dll.stock-11.18`.
   - Verified with `tracetest.exe` on a standalone engine, and Power BI showed no model errors in IST. It was not a time-zone bug: `TZ=UTC` did not help.

10. **Blank WebView2 window fixed** with a Windows 7 version override for Edge only (from [Wine bug 58921](https://bugs.winehq.org/show_bug.cgi?id=58921)): `wine reg add 'HKCU\Software\Wine\AppDefaults\msedgewebview2.exe' /v Version /d win7`. Chromium then skips DirectComposition and draws with plain GDI. The web UI renders and responds to clicks. The intermittent GPU crash did not recur in this mode.
11. `msv1_0` (NTLM client): round 2 of InitializeSecurityContext dropped `ISC_RET_CONNECTION`. Fixed in `wine/dlls/msv1_0/main.c`; stock DLL backed up at `runtime/msv1_0.dll.stock-11.18`. Correct, but NOT the cause of item 12.

12. **MSOLAP connection (report canvas data) fixed.** Root cause: Wine's `LsaFreeReturnBuffer` (`dlls/secur32/lsa.c`) returned `VirtualFree`'s BOOL (1) instead of an NTSTATUS. `FreeContextBuffer` passes that on, and msolap.dll (at RVA `0x2825bd`, right after `QueryContextAttributesW(PACKAGE_INFO)`) treats any non-zero result as `HRESULT_FROM_WIN32` → `0x80070001`, then abandons the NTLM login before sending AUTHENTICATE. Fix: `NtFreeVirtualMemory(...)` returning the real status. Stock DLL backed up at `runtime/secur32.dll.stock-11.18`. Verified: `oledbtest.exe` gives `OPEN OK`; Power BI shows 0 MSOLAP and 0 model errors.
   - How it was found: temporary return-value + `__builtin_return_address` TRACEs in `secur32/wrapper.c` gave the exact msolap call sites, then `llvm-objdump` of msolap showed the check after `FreeContextBuffer` (SSPI table slot `+0x80`).

13. **Blank web views fixed: cross-process child windows now display on macOS.** Each Edge page window (`Chrome_WidgetWin_1`, owned by msedgewebview2.exe) is a child of Power BI's window (another process). In win32u a child whose top-level belongs to another process gets no window surface (`update_visible_region`: `WND_OTHER_PROCESS` → no surface), so its GDI drawing was lost on winemac (X11 hides this by drawing into the shared X window). CrossOver has the same gap.
   - Fix in `wine/dlls/win32u/dce.c`: such windows draw into a shared-memory surface (`\KernelObjects\__wine_xproc_surface_<hwnd>`, a header + 32bpp bits up to 4096x2560). The process owning the top-level window copies the visible parts of those children (server visible region, z-order aware) into its own surface in `flush_window_surfaces`. The child wakes the parent with `WM_NULL` after each flush.
   - Repro/test: `C:\pbitest\client\xproc.exe parent` should show a red box with text inside a blue window.
   - The win32u.so runtime is the **x86_64** build (`wine-build64`), installed in `x86_64-unix/`; stock backed up at `runtime/win32u.so.stock-11.18`. **Build gotchas:** the wine-build64 `include/config.h` needs `HAVE_FT2BUILD_H`, `SONAME_LIBFREETYPE "libfreetype.6.dylib"` and `SONAME_LIBVULKAN "libvulkan.1.dylib"`, plus `make ... FREETYPE_CFLAGS=-I/opt/homebrew/include/freetype2`. After installing, run `install_name_tool -add_rpath @loader_path/../../` on win32u.so and re-sign (`codesign -s - -f`); otherwise there is no text at all (FreeType not found).

14. **Intermittent Edge GPU crash fixed:** DXVK's `d3d11.dll`/`d3d10core.dll` had been copied into Edge's app folder and kept loading as native even after the overrides were removed. Moved them to `runtime/dxvk-from-edge-folder/`. Edge now uses Wine's builtin d3d11/wined3d.
15. Compositing order fix in `dce.c`: cross-process children are composited top to bottom with occlusion clipping, all of them whenever any one changes, so switching views no longer leaves a stale page on top.

16. **Memory:** `msedge.dll` realigned (file layout == memory layout, DYNAMIC_BASE cleared) so Wine maps it from disk and shares it across ~10 Edge processes: about 10 GB down to 2.9 GB. Script: scratchpad `tools/pe_realign.py`; original at `runtime/msedge.dll.original`.
17. **Load sample data / Navigator hang fixed:** the Power Query Navigator is IE-control HTML (Wine Gecko). Its startup script set `style.textOverflow`, a Wine `mshtml` stub returning E_NOTIMPL, so the script aborted and the dialog stayed at layered alpha 0 with the main window disabled. Implemented `text-overflow` in `wine/dlls/mshtml/htmlstyle.c/h`; stock DLL at `runtime/mshtml.dll.stock-11.18`.

## Current state (2026-10-28, 8:55 PM)
- **The Power BI Desktop Home screen renders and works on macOS** (data source tiles, Recommended, Recent, Sign in, Options).
- Next: open a Blank report and check the report canvas, ribbon and visuals; load sample data and test visuals and DAX.

## Other pending items
- Launching `PBIDesktop.exe` directly gives an AccessViolation in `AppModule.Run`; the harness avoids it. Cause unknown.
- Microsoft sign-in / HTTPS fails: `SslProtocolType` enumeration error, then "underlying connection was closed" (Wine schannel / TLS 1.2-1.3).
- Once the model loads, confirm the report canvas actually renders (GPU path: Wine d3d11 → wined3d GL).
- Memory: 8 GB RAM is tight. Swap reached about 14 GB and the disk once filled. Close Chrome/Teams/WhatsApp before testing.
- Optional: offer the dcomp, ntdll and wintypes patches upstream to Wine.

## Tools that helped
- Crashpad dumps: `pbi-prefix/.../Power BI Desktop/WebView2/EBWebView/Crashpad/reports/*.dmp`, parsed with small Python minidump scripts.
- REA (Hopper) on a mini-PE carved from `msedge.dll` (the full 355 MB DLL is too large for 8 GB RAM). Scripts are in the session scratchpad and are gone when it expires.
- `dnfile` (pip, in a venv) for reading .NET IL when no decompiler is installed.
