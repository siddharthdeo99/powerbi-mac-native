#!/bin/bash

# This script provides the exact troubleshooting approach for Power BI StopTime issue
echo "=== Power BI Desktop StopTime Issue Troubleshooting ==="

# First, let's check what we're working with
echo "Checking current Wine setup..."
if command -v wine &> /dev/null; then
    echo "Wine is installed"
    wine --version
else
    echo "Wine not found. Please install Wine first."
    exit 1
fi

# Check if we have access to Power BI files
echo ""
echo "Checking Power BI installation..."
if [ -d "/Users/siddharthdeo/reverengineer/pbi-prefix/drive_c/Program Files/Microsoft Power BI Desktop" ]; then
    echo "Power BI Desktop installation found"
    ls -la "/Users/siddharthdeo/reverengineer/pbi-prefix/drive_c/Program Files/Microsoft Power BI Desktop/bin/"
else
    echo "Power BI Desktop not found in expected location"
fi

# The key insight from your debugging session:
# The issue is in Wine's oleaut32 DLL with VarUdateFromDate function
# When fractional seconds > 0.5 are rounded, it causes overflow to year 10000

echo ""
echo "=== Key Finding ==="
echo "The problem occurs in Wine's oleaut32/variant.c in VarUdateFromDate()"
echo "Specifically with dates like 9999-12-31T23:59:59.999 where rounding causes year overflow"
echo ""
echo "=== Recommended Fix ==="
echo "1. Download Wine source code from https://www.winehq.org/"
echo "2. Locate dlls/oleaut32/variant.c"
echo "3. Modify VarUdateFromDate function to prevent overflow by truncating instead of rounding"
echo ""
echo "=== Temporary Workaround ==="
echo "You can try setting timezone to UTC as you did before:"
echo "TZ=UTC wine zz_pbiharness.exe"

# Show the exact error pattern from your logs
echo ""
echo "=== Error Pattern from Logs ==="
echo "StopTime parsing errors with fractional seconds like 9999-12-31T23:59:59.999"
echo "Error type: System.Net.WebException: The underlying connection was closed"
echo "Specifically: An error occurred while parsing the 'StopTime' element"

echo ""
echo "=== Next Steps ==="
echo "1. Apply the fix to Wine's oleaut32/variant.c"
echo "2. Rebuild Wine with make"
echo "3. Test Power BI Desktop again"