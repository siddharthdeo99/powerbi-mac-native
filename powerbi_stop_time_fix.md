# Power BI Desktop StopTime Fix for Wine

## Problem Analysis

The issue occurs when Power BI Desktop running under Wine attempts to parse StopTime values. Specifically, when processing dates like `9999-12-31T23:59:59.999`, Wine's oleaut32 implementation rounds the fractional seconds (0.999 > 0.5) up, causing an overflow that results in year 10000, which is outside the valid date range for Power BI.

## Root Cause

In `dlls/oleaut32/variant.c`, the `VarUdateFromDate` function contains this problematic code:

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

When `timePart` is 0.999, it's greater than 0.5, so rounding occurs and can cause overflow into year 10000.

## Solution

The fix modifies the rounding logic to prevent StopTime overflow by truncating instead of rounding when overflow would occur:

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

1. Apply the patch to Wine's oleaut32/variant.c file
2. Rebuild Wine with the modified source code
3. Test Power BI Desktop under the patched Wine environment

This solution ensures that fractional seconds that would cause overflow are handled gracefully, allowing Power BI Desktop to process StopTime values correctly without the year 10000 overflow error.