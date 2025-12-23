# Quick Utilities Script for System Prep and Maintenance

## Overview

This PowerShell script provides a streamlined way to perform system preparation and maintenance tasks on Windows 10 or 11 operating systems.

## Features

- Update Group Policy on the local machine
- Initiate Configuration Manager client actions
- Install Dell system updates
- Create a local user account
- Disable sleep and lid close action on A/C
- Remove temporary files
- Add system hosts entry
- Repair Microsoft Teams
- Generate system audit report

Features in Development

- Unattended script execution
- Remoting compatibility (PS-Remoting, PsExec)
- Microsoft Configuration Manager client repair
- Software Center rebase / reset
- Network computer data transfer
- Automatic system diagnostic report and bundle
- Secure Boot and TPM 2.0 status on startup
- Enable Remote Desktop service

## Requirements

- Consistent network and internet connection
- Must be run with administrative privileges
- Windows OS and PowerShell 5.1 or newer
- `C:\Program Files\Dell\CommandUpdate\dcu-cli.exe`
- Configuration Manager client installed (for execution of client actions)
- Valid endpoint SCCM site configuration

## Usage

Open PowerShell as Administrator
Navigate to the directory containing the script:

   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process

   .\Prepare-Image.ps1
   ```

As a convenience, this script is also accessible through any administrative Windows Terminal session:

   ```powershell
   irm agho.me/dev | iex
   ```

## Script Execution

Summary

Upon execution, this script shows a basic system summary and prompts the user for permission to continue with task selection. Upon receiving valid input, the prompt opens an interactive GUI window for task selection. 

1. Ensure the computer has an active internet connection, plug in portable devices, and close all applications.
2. Right-click the Start menu and select Windows PowerShell (Admin) or Terminal (Admin).
3. Use the `cd` command to go to the folder where Prepare-Image.ps1 is located.
4. Enter `.\Prepare-Image.ps1` to start the script.
5. Review the information displayed to ensure it is correct before proceeding.
6. Use the interactive GUI window to select the tasks you want the script to execute.
7. Confirm task selections and allow the script to complete execution.
8. Review the output and logs, restart the computer if necessary.

## Known Issues

1. Dell Command - UEFI updates may fail on certain newer hardware models.
2. Dell Command - Firmware updates may require application whitelisting approval to begin installation.
3. Dell Command - Launching update utility may fail if Dell Command is self-updating.
4. System Audit - generated report does not support printing due to interactive tables. (fix pending)
5. Logging - user profile Desktop logic is incomplete and logging is under development. (fix pending)

## Notes
   
- When creating a local user account, the user will be of the standard (non-administrative) type.
- There is no password verification or confirmation when creating a local user.
- It is strongly recommended to plug in portable devices when running system updates.
- Designed for interactive use and incompatible with command-line execution (PS-Remoting, PsExec)
- The Microsoft Teams repair function applies only to per-user MSIX installations.

This PowerShell script is under active development. Please review the code before execution and report unexpected behavior.

Significant structural changes will be made as future updates focus on maintainability, security, and bug fixes.
