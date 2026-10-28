#!/bin/bash
# Power BI Desktop on macOS via patched Wine — one-shot setup.
#
# Installs into ~/powerbi-mac-native (override: PBI_MAC_HOME=/some/dir ./setup.sh):
#   1. Gcenx wine-devel 11.18 runtime   (from Gcenx/macOS_Wine_builds, checksum-verified)
#   2. Patched Wine binaries            (from this repo's release v0.1, checksum-verified)
#   3. Win10 prefix + .NET 4.8 + WebView2 (winetricks; .NET alone takes 10–30 min)
#   4. Power BI Desktop                 (downloaded from Microsoft, silent install)
#   5. Registry tweaks                  (Edge win7 override, Segoe UI→Tahoma)
#   6. zz_pbiharness.exe                (launcher; direct PBIDesktop.exe still crashes)
#
# Needs ~15 GB free disk and 30–60 minutes, mostly unattended.
set -euo pipefail

BASE="${PBI_MAC_HOME:-$HOME/powerbi-mac-native}"
RUNTIME="$BASE/runtime"
APP="$RUNTIME/Wine Devel.app"
WINEBIN="$APP/Contents/Resources/wine/bin"
PREFIX="$BASE/pbi-prefix"
PBI_BIN="$PREFIX/drive_c/Program Files/Microsoft Power BI Desktop/bin"

REL="https://github.com/siddharthdeo99/powerbi-mac-native/releases/download/v0.1"
WINE_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.18/wine-devel-11.18-osx64.tar.xz"
WINE_SHA256="aa0ea4c82e636ae7bca2076387cb0a5affa26509ad13f119ecd0d62bd7ba6f82"
# Microsoft's official Power BI Desktop download link (standalone installer)
PBI_URL="https://go.microsoft.com/fwlink/?LinkId=521862&clcid=0x409"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------- 0. environment checks ----------
[[ "$(uname)" = "Darwin" ]] || die "This installer is macOS-only."
command -v curl >/dev/null || die "curl is required."
command -v python3 >/dev/null || die "python3 is required (ships with macOS/dev tools)."

if ! command -v winetricks >/dev/null; then
    command -v brew >/dev/null || die "Homebrew is required to install winetricks. Install it from https://brew.sh and re-run."
    say "Installing winetricks via Homebrew"
    brew install winetricks
fi

if [[ "$(uname -m)" = "arm64" ]]; then
    say "Ensuring Rosetta 2 is installed (this Wine build is x86_64)"
    /usr/bin/softwareupdate --install-rosetta --agree-to-license >/dev/null 2>&1 || true
fi

mkdir -p "$RUNTIME"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------- 1. Wine runtime ----------
if [[ -x "$WINEBIN/wine" ]]; then
    say "Wine runtime already present at: $APP"
else
    say "Downloading Gcenx wine-devel 11.18 (~350 MB)"
    curl -fL --progress-bar "$WINE_URL" -o "$TMP/wine.tar.xz"
    echo "$WINE_SHA256  $TMP/wine.tar.xz" | shasum -a 256 -c - >/dev/null \
        || die "Wine tarball checksum mismatch — aborting."
    say "Extracting Wine"
    tar -xf "$TMP/wine.tar.xz" -C "$RUNTIME"
    [[ -x "$WINEBIN/wine" ]] || die "Wine did not extract where expected ($APP)."
fi
# De-quarantine: Wine dlopen()s .so files from inside the bundle, and
# Gatekeeper refuses quarantined dylibs.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# ---------- 2. patched binaries from release v0.1 ----------
say "Downloading patched binaries from release v0.1"
ASSETS="oleaut32.dll secur32.dll dcomp.dll mshtml.dll msv1_0.dll wintypes.dll ncrypt.dll ntdll.so win32u.so zz_pbiharness.exe SHA256SUMS"
for f in $ASSETS; do curl -fsSL "$REL/$f" -o "$TMP/$f" \
    || die "Could not download $f from $REL — check your connection."; done
(cd "$TMP" && shasum -a 256 -c SHA256SUMS --quiet) || die "Release asset checksum mismatch — aborting."

WINE_LIB="$APP/Contents/Resources/wine/lib/wine"
install_patched() { # <file> <subdir>
    local dst="$WINE_LIB/$2/$1"
    if [[ -f "$dst" && ! -f "$dst.stock-11.18" ]]; then
        cp "$dst" "$dst.stock-11.18"
        echo "    backed up stock: $(basename "$dst")"
    fi
    cp "$TMP/$1" "$dst"
}
say "Installing patched Wine files (stock copies kept as *.stock-11.18)"
for f in oleaut32 secur32 dcomp mshtml msv1_0 wintypes ncrypt; do install_patched "$f.dll" x86_64-windows; done
for f in ntdll win32u; do install_patched "$f.so" x86_64-unix; done
# win32u.so needs a valid signature + self-contained rpath after copy (HANDOFF §13)
codesign -s - -f "$WINE_LIB/x86_64-unix/win32u.so" 2>/dev/null || true
xattr -dr com.apple.quarantine "$WINE_LIB" 2>/dev/null || true

# ---------- 3. prefix: win10 + .NET 4.8 + WebView2 ----------
export WINEPREFIX="$PREFIX"
export PATH="$WINEBIN:/opt/homebrew/bin:/usr/local/bin:$PATH"  # /opt/homebrew/bin = ntlm_auth (engine login)

if [[ -d "$PREFIX/drive_c" ]]; then
    say "Prefix already exists: $PREFIX"
else
    say "Creating Win10 prefix, then .NET 4.8 + WebView2 (10–30 min — do not interrupt)"
    winetricks -q win10       || die "winetricks win10 failed."
    winetricks -q dotnet48    || die "winetricks dotnet48 failed (this is the longest step)."
    winetricks -q webview2    || die "winetricks webview2 failed."
fi

# ---------- 4. Power BI Desktop (from Microsoft) ----------
if [[ -f "$PBI_BIN/PBIDesktop.exe" ]]; then
    say "Power BI Desktop already installed"
else
    say "Downloading Power BI Desktop from Microsoft (~700 MB)"
    curl -fL --progress-bar "$PBI_URL" -o "$TMP/PBIDesktopSetup.exe"
    say "Installing Power BI Desktop (silent)"
    if ! wine "$TMP/PBIDesktopSetup.exe" /quiet /norestart; then
        echo "    Silent install failed — launching the installer GUI; click through it."
        wine "$TMP/PBIDesktopSetup.exe"
    fi
    [[ -f "$PBI_BIN/PBIDesktop.exe" ]] || die "Power BI install did not produce PBIDesktop.exe."
fi

# ---------- 5. registry tweaks ----------
say "Applying registry tweaks"
# Blank WebView2 window fix: Chromium must skip DirectComposition (HANDOFF §10)
wine reg add 'HKCU\Software\Wine\AppDefaults\msedgewebview2.exe' /v Version /d win7 /f
# Font substitution: register macOS Tahoma as the shell font (HANDOFF §5)
wine reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts' /v 'Tahoma (TrueType)'      /t REG_SZ /d 'Z:\System\Library\Fonts\Supplemental\Tahoma.ttf'      /f
wine reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts' /v 'Tahoma Bold (TrueType)' /t REG_SZ /d 'Z:\System\Library\Fonts\Supplemental\Tahoma Bold.ttf' /f
wine reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes' /v ProportionalFont /t REG_SZ /d Tahoma /f
wine reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes' /v FixedWidthFont  /t REG_SZ /d Tahoma /f

# Edge hardware acceleration off (HANDOFF §7) — best-effort; the win7 override
# above already avoids the GPU crash path.
say "Disabling Edge hardware acceleration in WebView2 Local State (best-effort)"
python3 - "$PREFIX" <<'PYEOF' || true
import glob, json, sys, shutil
prefix = sys.argv[1]
for f in glob.glob(prefix + "/drive_c/users/**/Local State", recursive=True):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    changed = False
    if d.get("hardware_acceleration_mode", {}).get("enabled", True):
        d.setdefault("hardware_acceleration_mode", {})["enabled"] = False
        changed = True
    if changed:
        shutil.copy(f, f + ".orig")
        json.dump(d, open(f, "w"))
        print("    patched:", f)
PYEOF

# ---------- 6. harness ----------
say "Installing launcher (zz_pbiharness.exe)"
cp "$TMP/zz_pbiharness.exe" "$PBI_BIN/"

# ---------- done ----------
say "Setup complete"
cat <<EOF

  Launch Power BI:
      $(cd "$(dirname "$0")" && pwd)/run_powerbi.sh

  Stop everything:
      $(cd "$(dirname "$0")" && pwd)/run_powerbi.sh --stop

  First launch takes 20–30 s; logs land in $RUNTIME/powerbi.log
  Keep Chrome/Teams closed on 8 GB Macs (HANDOFF "Memory").
EOF
