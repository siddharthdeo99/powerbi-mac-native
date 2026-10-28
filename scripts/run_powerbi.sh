#!/bin/bash
# Start Power BI Desktop under the patched Wine runtime.
#   ./run_powerbi.sh          normal start (no diagnostics, fastest)
#   ./run_powerbi.sh --debug  start with Wine error logging into runtime/powerbi.log
#   ./run_powerbi.sh --stop   stop Power BI and every Wine process
#
# Install location is resolved as: $PBI_MAC_HOME, else the legacy
# ~/reverengineer dev layout, else ~/powerbi-mac-native (what setup.sh creates).

if [[ -n "${PBI_MAC_HOME:-}" ]]; then
    BASE="$PBI_MAC_HOME"
elif [[ -d "$HOME/reverengineer/runtime/Wine Devel.app" ]]; then
    BASE="$HOME/reverengineer"
else
    BASE="$HOME/powerbi-mac-native"
fi

RUNTIME="$BASE/runtime"
WINE_BIN="$RUNTIME/Wine Devel.app/Contents/Resources/wine/bin"
PBI_BIN="$BASE/pbi-prefix/drive_c/Program Files/Microsoft Power BI Desktop/bin"
LOG="$RUNTIME/powerbi.log"

export WINEPREFIX="$BASE/pbi-prefix"
export PATH="$WINE_BIN:/opt/homebrew/bin:$PATH"   # /opt/homebrew/bin provides ntlm_auth (engine login)

stop_wine() {
    pkill -9 -f '^C:\\' 2>/dev/null
    pkill -9 -f 'wineserver|Wine Devel.app' 2>/dev/null
    sleep 2
}

if [ "$1" = "--stop" ]; then
    stop_wine
    echo "Stopped."
    exit 0
fi

stop_wine

if [ "$1" = "--debug" ]; then
    export WINEDEBUG=err+all,fixme-all
else
    export WINEDEBUG=-all
fi

cd "$PBI_BIN" || { echo "Power BI not found at $PBI_BIN — run scripts/setup.sh first."; exit 1; }
nohup wine zz_pbiharness.exe > "$LOG" 2>&1 &
echo "Power BI is starting (log: $LOG). It takes about 20-30 seconds."

# The .NET optimizer and Edge updater only slow things down under Wine; stop them once they appear.
( for i in $(seq 1 30); do pkill -9 -f 'mscorsvw.exe|MicrosoftEdgeUpdate.exe' 2>/dev/null; sleep 4; done ) >/dev/null 2>&1 &
