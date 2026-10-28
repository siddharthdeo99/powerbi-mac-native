#!/bin/bash

# Test script for Power BI Desktop StopTime fix
echo "Testing Power BI Desktop with StopTime fix..."

# Kill any existing Power BI processes
pkill -9 -f "zz_pbiharness|msedgewebview2|msmdsrv|wineserver|Wine Devel.app"; sleep 2

# Check system resources
echo "System swap usage:"
sysctl -n vm.swapusage

echo "Disk space:"
df -h / | tail -1

# Set up environment for testing
R=/Users/siddharthdeo/reverengineer/runtime
W="$R/Wine Devel.app/Contents/Resources/wine/bin"
export PATH="$W:/opt/homebrew/bin:$PATH"
WINEPREFIX=/Users/siddharthdeo/reverengineer/pbi-prefix

# Run Power BI with detailed logging
B="/Users/siddharthdeo/reverengineer/pbi-prefix/drive_c/Program Files/Microsoft Power BI Desktop/bin"
L=$R/harness_test.log

echo "Starting Power BI test..."
cd "$B" && (
  WINEDEBUG=err+all,fixme-all,+seh,+loaddll wine zz_pbiharness.exe 2>&1 | \
  grep -aE "c0000005|EXCEPTION_ACCESS|loaddll:.*(msedge|libGLESv2|libEGL|d3d11|dxgi|wined3d|d3dcompiler|vulkan|ntdll)|WebView2 Process Failed|FIRST CHANCE|rip=|rax=|rsp=|err:" > $L
) &

# Wait for completion or timeout
n=0
until grep -qaE "WebView2ProcessCrashException|WebView2 Process Failed" $L 2>/dev/null || [ $n -ge 120 ]; do
  sleep 2
  n=$((n+1))
done

echo "Waited ~$((n*2))s; log $(du -h $L | cut -f1)"
grep -aoE "WebView2 Process Failed: [^\r]*" $L | head -1 | cut -c80-200

echo "Test complete. Check $L for detailed results."