# Quick Utilities Script for System Prep and Maintenance

## Overview

This PowerShell script provides a streamlined way to perform essential system preparation and maintenance tasks on Windows machines. An interactive GUI allows users to select which tasks to run.

## Features

- Update Group Policy on the local machine
- Initiate Configuration Manager client actions
- Install Dell system updates
- Create a local user account
- Disable Sleep and Lid Close Action on AC

## Requirements

- Must be run with administrative privileges
- Windows OS with PowerShell 5 or newer
- `C:\Program Files\Dell\CommandUpdate\dcu-cli.exe`
- Configuration Manager client installed for SCCM tasks

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

1. Dell UEFI updates may fail on certain newer hardware models
2. Dell firmware updates may require EDR approval to begin installation
3. Dell CLI utility may fail to be invoked if Dell Command is self-updating during task execution

## Notes
   
- There is no individual selection of Configuration Manager client actions.
- When creating a local user account, the user will be of the standard (non-administrative) type.
- It is recommended to plug in portable devices when running the configuration manager tasks and Dell system updates.
- This script is not compatible over a remote CLI session.
- There is no password verification or confirmation when creating a local user.
