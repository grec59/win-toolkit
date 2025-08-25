# Quick Utilities Script for System Prep and Maintenance

## Overview

This PowerShell script provides a streamlined way to perform system preparation and maintenance tasks on Windows machines.

## Features

- Update Group Policy on the local machine
- Initiate Configuration Manager client actions
- Install Dell system updates
- Create a local user account
- Disable sleep and lid close action on A/C
- Remove temporary files
- Schedule boot volume disk check on reboot

## Requirements

- Must be run with administrative privileges
- Windows OS and PowerShell 5.1 or newer
- `C:\Program Files\Dell\CommandUpdate\dcu-cli.exe`
- Configuration Manager client installed
- Valid endpoint SCCM site configuration

## Usage

Open PowerShell as Administrator
Navigate to the directory containing the script:

   ```powershell
   .\Prepare-Image.ps1
   ```

## Script Execution

Upon execution, this script shows a basic system summary and prompts the user for permission to continue with task selection. Upon receiving valid input, the prompt displays with an interactive GUI window for task selection. 

Choose 'Proceed' when satisfied with task selection. The script will execute automatically unless local user creation is selected. When creating a local user using the script utility, real-time credential input will be required.

## Known Issues

1. Dell Command - UEFI updates may fail on certain newer hardware models
2. Dell Command - Firmware updates may require EDR approval to begin installation
3. Dell Command - Startup may fail if Dell Command is self-updating during task execution

## Notes
   
- When creating a local user account, the user will be of the standard (non-administrative) type.
- It is recommended to plug in portable devices when running system updates.
- This script is interactive and is not compatible over a remote CLI session.
- There is no password verification or confirmation when creating a local user.
