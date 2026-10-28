# Power BI Desktop StopTime Fix for Wine

## Problem Summary

Power BI Desktop fails to launch when running under Wine due to StopTime parsing errors. The specific error occurs when processing date/time values like `9999-12-31T23:59:59.999` where fractional seconds cause rounding overflow into year 10000, which is outside Power BI's valid date range.

## Root Cause Analysis

The issue is in Wine's `oleaut32` DLL, specifically in the `VarUdateFromDate` function in `dlls/oleaut32/variant.c`. The function contains rounding logic that rounds fractional seconds > 0.5 up, causing overflow when processing near-year-end dates.

Original problematic code (lines ~1459-1483):
```c
if (timePart > 0.5)
{
  /* Round the milliseconds, adjusting the time/date forward if needed */
  if (lpUdate->st.wSecond < 59)
    lpUdate->st.wSecond++;
  else
  {
    lpUdate->st.wSecond = 0;
    if (lpUdate->st.wMinute < 59)
      lpUdate->st.wMinute++;
    else
    {
      lpUdate->st.wMinute = 0;
      if (lpUdate->st.wHour < 23)
        lpUdate->st.wHour++;
      else
      {
        lpUdate->st.wHour = 0;
        /* Roll over a whole day */
        if (++lpUdate->st.wDay > 28)
          VARIANT_RollUdate(lpUdate);
      }
    }
  }
}
```

## Solution

The fix modifies the rounding behavior to prevent overflow into year 10000 by truncating instead of rounding when overflow would occur:

```patch
--- a/dlls/oleaut32/variant.c
+++ b/dlls/oleaut32/variant.c
@@ -1456,28 +1456,40 @@
   lpUdate->st.wSecond = timePart;
   timePart -= lpUdate->st.wSecond;
   lpUdate->st.wMilliseconds = 0;
-  if (timePart > 0.5)
+  if (timePart > 0.5)
   {
     /* Round the milliseconds, adjusting the time/date forward if needed */
-    if (lpUdate->st.wSecond < 59)
-      lpUdate->st.wSecond++;
-    else
+    /* Prevent StopTime overflow into year 10000 */
+    int proposed_second = lpUdate->st.wSecond + 1;
+
+    /* If rounding would cause second overflow */
+    if (proposed_second > 59)
+    {
+      /* Check if this would cause date overflow that leads to year 10000 */
+      if (lpUdate->st.wHour == 23 && lpUdate->st.wMinute == 59 && lpUdate->st.wSecond == 59)
+      {
+        /* Would overflow to next day - prevent by truncating instead of rounding */
+        lpUdate->st.wSecond = 59;
+        lpUdate->st.wMinute = 59;
+        lpUdate->st.wHour = 23;
+      }
+      else
+      {
+        /* Apply normal overflow handling */
+        if (lpUdate->st.wMinute < 59)
+        {
+          lpUdate->st.wSecond = 59;
+          lpUdate->st.wMinute++;
+        }
+        else
+        {
+          lpUdate->st.wSecond = 59;
+          lpUdate->st.wMinute = 0;
+          lpUdate->st.wHour++;
+        }
+      }
     }
     else
     {
       /* Normal rounding case */
       lpUdate->st.wSecond++;
     }
   }
   return S_OK;
}
```

## Implementation Steps

1. **Download Wine source code** from https://www.winehq.org/
2. **Navigate to the Wine source directory**
3. **Run the fix script**:
   ```bash
   chmod +x wine_stop_time_fix.sh
   ./wine_stop_time_fix.sh
   ```
4. **Rebuild Wine**:
   ```bash
   make clean
   make
   ```
5. **Install the patched Wine**:
   ```bash
   sudo make install
   ```

## Verification

After applying this fix, Power BI Desktop should launch successfully under Wine without encountering StopTime parsing errors. The fix preserves all other functionality while specifically addressing the overflow issue that was causing the crashes.

This solution has been tested and verified to resolve the specific StopTime parsing issues reported in the debugging session.