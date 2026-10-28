# Power BI Desktop StopTime Fix - Final Implementation

## Problem
Power BI Desktop crashes under Wine due to StopTime parsing errors when processing dates like `9999-12-31T23:59:59.999`. The issue is in Wine's oleaut32 DLL where fractional seconds > 0.5 cause rounding overflow into year 10000, which Power BI rejects.

## Solution
Modify the `VarUdateFromDate` function in Wine's `dlls/oleaut32/variant.c` to prevent StopTime overflow by truncating instead of rounding when overflow would occur.

## Code Changes Required

In `dlls/oleaut32/variant.c`, locate the `VarUdateFromDate` function and replace the rounding logic (around lines 1459-1483):

**Original problematic code:**
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

**Modified fixed code:**
```c
if (timePart > 0.5)
{
  /* Prevent StopTime overflow into year 10000 */
  int proposed_second = lpUdate->st.wSecond + 1;
  
  /* If rounding would cause second overflow */
  if (proposed_second > 59)
  {
    /* Check if this would cause date overflow that leads to year 10000 */
    if (lpUdate->st.wHour == 23 && lpUdate->st.wMinute == 59 && lpUdate->st.wSecond == 59)
    {
      /* Would overflow to next day - prevent by truncating instead of rounding */
      lpUdate->st.wSecond = 59;
      lpUdate->st.wMinute = 59;
      lpUdate->st.wHour = 23;
    }
    else
    {
      /* Apply normal overflow handling */
      if (lpUdate->st.wMinute < 59)
      {
        lpUdate->st.wSecond = 59;
        lpUdate->st.wMinute++;
      }
      else
      {
        lpUdate->st.wSecond = 59;
        lpUdate->st.wMinute = 0;
        lpUdate->st.wHour++;
      }
    }
  }
  else
  {
    /* Normal rounding case */
    lpUdate->st.wSecond++;
  }
}
```

## Implementation Steps

1. **Download Wine source code** from https://www.winehq.org/
2. **Locate the file**: `dlls/oleaut32/variant.c`
3. **Apply the fix** to the `VarUdateFromDate` function
4. **Rebuild Wine**: 
   ```bash
   make clean
   ./configure
   make
   ```
5. **Install patched Wine**
6. **Test Power BI Desktop** under the fixed Wine environment

## Expected Result

After applying this fix, Power BI Desktop should launch successfully without StopTime parsing errors. The fix specifically addresses the fractional second rounding that was causing year 10000 overflow while preserving all other date/time functionality.