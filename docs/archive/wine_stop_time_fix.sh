#!/bin/bash

# Wine StopTime Fix for Power BI Desktop
# This script applies the necessary patch to prevent StopTime overflow errors

echo "Applying Power BI StopTime fix to Wine oleaut32..."

# Check if we're in the Wine source directory
if [ ! -f "dlls/oleaut32/variant.c" ]; then
    echo "Error: This script must be run from the Wine source root directory"
    exit 1
fi

# Create backup of original file
cp dlls/oleaut32/variant.c dlls/oleaut32/variant.c.backup

# Apply the fix to prevent StopTime overflow
cat > variant_stop_time_fix.patch << 'EOF'
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
EOF

# Apply the patch
patch -p1 < variant_stop_time_fix.patch

echo "Power BI StopTime fix applied successfully!"
echo "You can now rebuild Wine with: make"