<#
.SYNOPSIS
  Quick Utilities Script for System Prep and Maintenance.

.DESCRIPTION
  This script executes administrative tasks on a Windows system, including:
    - Updating Group Policy
    - Initiating Configuration Manager client actions
    - Installing Dell system updates
    - Creating a local user account

.PARAMETER Verbose
  Enhance script logging for troubleshooting and debugging. 
.PARAMETER Remote
  Switches to CLI mode and disables GUI elements for remote use over a PSSession.

.NOTES
  - Requires administrative privileges.
  - Designed for interactive use with GUI-based action selection.    
  - Outputs log to C:\results.txt
  - Ensures administrative privileges.

.EXAMPLE
  .\Prepare-Image.ps1 -Verbose
#>

# --- Function Definitions ---

function Create-User {
    param(
        [Parameter(Mandatory)]
        [PSCredential]$Credential
    )
    $username = $Credential.UserName
    $password = $Credential.Password

    $params = @{
        Name                     = $username
        Password                 = $password
        AccountNeverExpires      = $true
        PasswordNeverExpires     = $true
    }

    try {
        New-LocalUser @params -ErrorAction Stop
        Write-Host "Created user $username"
    } catch {
        Write-Host "Failed to create user: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-GroupPolicy {
    try {
        gpupdate /target:computer | Out-Null
        Get-WinEvent -FilterHashtable @{LogName='System'; Id=1500} | Select-Object -First 1 | ForEach-Object { $_.Message }
        Start-Sleep -Seconds 5
}
    catch {
        Write-Host "WARNING: Failed to update Computer Policy: $($_.Exception.Message)" -ForegroundColor Yellow  
    }
}
function Execute-Actions {
    $SCCMActions = @(
        [PSCustomObject]@{ Guid = "{00000000-0000-0000-0000-000000000021}"; Name = "Machine policy retrieval Cycle" },
        [PSCustomObject]@{ Guid = "{00000000-0000-0000-0000-000000000022}"; Name = "Machine policy evaluation cycle" },
        [PSCustomObject]@{ Guid = "{00000000-0000-0000-0000-000000000001}"; Name = "Hardware inventory cycle" },
        [PSCustomObject]@{ Guid = "{00000000-0000-0000-0000-000000000002}"; Name = "Software inventory cycle" },
        [PSCustomObject]@{ Guid = "{00000000-0000-0000-0000-000000000003}"; Name = "Discovery Data Collection Cycle" },
        [PSCustomObject]@{ Guid = "{00000000-0000-0000-0000-000000000113}"; Name = "Software updates scan cycle" },
        [PSCustomObject]@{ Guid = "{00000000-0000-0000-0000-000000000114}"; Name = "Software updates deployment evaluation cycle" },
        [PSCustomObject]@{ Guid = "{00000000-0000-0000-0000-000000000031}"; Name = "Software metering usage report cycle" },
        [PSCustomObject]@{ Guid = "{00000000-0000-0000-0000-000000000121}"; Name = "Application deployment evaluation cycle" },
        [PSCustomObject]@{ Guid = "{00000000-0000-0000-0000-000000000032}"; Name = "Windows installer source list update cycle" },
        [PSCustomObject]@{ Guid = "{00000000-0000-0000-0000-000000000010}"; Name = "File collection" }
    )

    foreach ($action in $SCCMActions) {
        try {
            Invoke-WMIMethod -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule -ArgumentList $action.Guid -ErrorAction Stop | Out-Null
            Write-Host "SUCCESS: $($action.Name)" -ForegroundColor Green
        } catch {
            Write-Host "FAIL: $($action.Name) $($_.Exception.Message)" -ForegroundColor Red
        }
        Start-Sleep -Seconds 2
    }
}

function Run-DellUpdates {
    $path = 'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe'
    if (Test-Path $path) {
        Start-Sleep -Seconds 3
        Write-Host "Dell Command application detected, starting updates..."
        & "$path" /applyUpdates -autoSuspendBitLocker=enable -forceupdate=enable -outputLog='C:\command.log'
    } else {
        Write-Host "Dell Command application not detected, skipping updates..."
    }
}

# --- Script Logic ---

Clear-Host

$log = 'C:\results.txt'
$pspath = (Get-Process -Id $PID).Path

# Force TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Ensure admin privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process $pspath -Verb runAs -ArgumentList '-NoExit', '-ExecutionPolicy RemoteSigned', '-Command', "& {Invoke-WebRequest 'https://agho.me/provision' -UseBasicParsing | Invoke-Expression}"
    Stop-Process -Id $PID
}

# System info
$computer = $env:COMPUTERNAME
$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
$ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
$bootVolume = [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB, 2)

# Display information
$messageHeader = @"

==========================================
Welcome to the Quick Utilities Script
==========================================

"@

$messageDetails = @"

Computer Name: $computer
CPU: $cpu
Memory: $ram GB
Boot Volume Free Space: $bootVolume GB

"@

$messageTasks = @"
Features Available:
1. Update Group Policy
2. Configuration Manager Tasks
3. Install Dell System Updates
4. Create a Local User Account

"@

Write-Host $messageHeader -ForegroundColor Cyan
Write-Host $messageDetails -ForegroundColor Green
Write-Host $messageTasks

# Confirmation
while (($i = Read-Host "Press Y to continue or N to quit") -notmatch '^[YyNn]$') {}
if ($i -notmatch '^[Yy]$') { exit }

# Build GUI
Add-Type -AssemblyName PresentationFramework

$xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' Title='Select Actions' Height='250' Width='350' WindowStartupLocation='CenterScreen'>
  <StackPanel Margin='10'>
    <TextBlock FontWeight='Bold' Margin='0 0 0 10'>Choose the actions you want to perform:</TextBlock>
    <CheckBox Name='cbGP' Content=' Update Group Policy' Margin='5'/>
    <CheckBox Name='cbCM' Content=' Configuration Manager Tasks' Margin='5'/>
    <CheckBox Name='cbDell' Content=' Install Dell System Updates' Margin='5'/>
    <CheckBox Name='cbUser' Content=' Create a Local User Account' Margin='5'/>
    <StackPanel Orientation='Horizontal' HorizontalAlignment='Right' Margin='0 15 0 0'>
      <Button Name='btnOK' Width='75' Margin='5' IsDefault='True'>Proceed</Button>
      <Button Width='75' Margin='5' IsCancel='True'>Cancel</Button>
    </StackPanel>
  </StackPanel>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader ([xml]$xaml))
$win = [Windows.Markup.XamlReader]::Load($reader)

# Capture GUI selections
$btnOK = $win.FindName('btnOK')
$btnOK.Add_Click({
    $win.Tag = @{
        GroupPolicy = $win.FindName('cbGP').IsChecked
        ConfigMgr  = $win.FindName('cbCM').IsChecked
        DellUpdates = $win.FindName('cbDell').IsChecked
        CreateUser = $win.FindName('cbUser').IsChecked
    }
    $win.Close()
})

$win.ShowDialog() | Out-Null
$sel = $win.Tag

Clear-Host

# Power settings tuning

#powercfg /change standby-timeout-ac 0
#powercfg -setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 0

# Execute tasks
if ($sel.CreateUser) {
    Create-User
}

if ($sel.GroupPolicy) {
    Write-Host "Running Policy Updates..." -ForegroundColor Cyan
    Invoke-GroupPolicy
}

if ($sel.ConfigMgr) {
    Write-Host "Running Configuration Actions..." -ForegroundColor Cyan
    Execute-Actions
}

if ($sel.DellUpdates) {
    Write-Host "Running System Updates..." -ForegroundColor Cyan
    Run-DellUpdates
}

Write-Host "Script execution complete. See $log" -ForegroundColor Cyan
Start-Sleep 3
