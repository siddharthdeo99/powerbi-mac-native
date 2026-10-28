# Power BI Desktop StopTime Fix for Wine

## Problem Summary

Power BI Desktop fails to launch under Wine due to StopTime parsing errors. The error occurs when processing date/time values like `9999-12-31T23:59:59.999` where fractional seconds cause rounding overflow into year 10000, which Power BI rejects.

## Root Cause

The issue is in Wine's `oleaut32` DLL (`dlls/oleaut32/variant.c`) in the `VarUdateFromDate` function. The rounding logic rounds fractional seconds > 0.5 up, causing overflow when processing near-year-end dates.

## Solution

I've created a patch that modifies the rounding behavior to prevent StopTime overflow:

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

1. **Apply the patch** to Wine's `dlls/oleaut32/variant.c` file
2. **Rebuild Wine** with the modified source code
3. **Test Power BI Desktop** under the patched Wine environment

This fix ensures that when fractional seconds would cause overflow, the system truncates instead of rounds, preventing the year 10000 overflow that was causing StopTime parsing errors in Power BI Desktop.