# Power BI Native Porting Project

This repository contains all the documentation, scripts, and analysis related to porting Power BI to native environments, particularly focusing on fixing stop time issues in Wine.

## Project Overview

The goal of this project is to successfully port Microsoft Power BI to run natively on Unix-like systems (primarily macOS) using Wine. The main focus area has been resolving the stop time issue that occurs when running Power BI through Wine.

## Key Files and Documentation

- `powerbi_native_porting.md` - Main documentation of the porting approach and considerations
- `dll_structure_analysis.md` - Analysis of DLL structures and dependencies
- `wine_architecture.md` - Wine architecture insights for the Power BI porting effort
- `native_porting_requirements.md` - Requirements and constraints for native porting
- `final_stop_time_fix.md` - Final solution for stop time issues
- `powerbi_stop_time_fix_solution.md` - Solution documentation for Power BI stop time fix
- `powerbi_wine_stop_time_solution.md` - Wine-specific stop time fix approach
- `stop_time_fix.patch` - The actual patch file to fix stop time issues
- `wine_oleaut32_fix.txt` - OLEAUT32 DLL specific fixes

## Scripts

- `run_powerbi.sh` - Script to run Power BI with Wine
- `test_powerbi_fix.sh` - Test script for verifying the fix
- `verify_stop_time_fix.sh` - Verification script for stop time fix
- `wine_stop_time_fix.sh` - Wine-specific stop time fix script
- `actual_fix_for_powerbi.sh` - The actual implementation of the Power BI fix
- `direct_fix_command.sh` - Direct command to apply the fix

## Usage

1. Clone this repository
2. Navigate to the powerbi-port directory
3. Apply the patch using the provided scripts
4. Run Power BI through Wine as normal

## Contributing

This project is for personal research and development purposes. Contributions are welcome via pull requests or issues.
