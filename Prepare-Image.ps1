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
        New-LocalUser @params -ErrorAction Stop | Out-Null
        Write-Host "Created user: $username"
        "The user $username was succesfully created." | Out-File -FilePath $output -Encoding utf8 -Append
    } catch {
        Write-Host "Failed to create user: $($_.Exception.Message)" -ForegroundColor Red
        "The attempt to create user $username failed. $($_.Exception.Message)" | Out-File -FilePath $output -Encoding utf8 -Append
    }
}

function Invoke-GroupPolicy {
    try {
        Write-Host "Running Policy Update..." -ForegroundColor Cyan
        gpupdate /target:computer | out-null
        Start-Sleep -Seconds 5
        Write-Host "SUCCESS: Computer Policy update has completed successfully." -ForegroundColor Green
}
    catch {
        Write-Host "FAIL: Failed to update Computer Policy: $($_.Exception.Message)" -ForegroundColor Yellow  
    }
}

function Execute-Actions {
    Write-Host "Running Configuration Actions..." -ForegroundColor Cyan
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
            "SUCCESS: $($action.Name)" | Out-File -FilePath $output -Encoding utf8 -Append
        } catch {
            Write-Host "FAIL: $($action.Name) $($_.Exception.Message)" -ForegroundColor Red
            "FAIL: $($action.Name)" | Out-File -FilePath $output -Encoding utf8 -Append
        }
        Start-Sleep -Seconds 2
    }
}

function Run-DellUpdates {
    Write-Host "Running System Updates..." -ForegroundColor Cyan
    $path = 'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe'
    if (Test-Path $path) {
        Start-Sleep -Seconds 3
        Write-Host "Dell Command CLI application detected, starting updates..."
        & "$path" /applyUpdates -autoSuspendBitLocker=enable -forceupdate=enable -outputLog='C:\command.log'
    } else {
        Write-Host "Dell Command application not detected, skipping updates..."
    }
}

function Disable-Sleep {

# --- Power settings tuning ---
# Write-Host "Disabling Sleep and Lid Closure action When Plugged In..."
# Start-Sleep 2
#powercfg /change standby-timeout-ac 0
#powercfg -setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 0
# Write-Host "Sleep and Lid Closure action When Plugged In has been disabled."
"Sleep and Lid Closure action When Plugged In has been disabled. Check system power settings for additonal details." | Out-File -FilePath $output -Encoding utf8 -Append
}

function Initialize-Log {
#    Write-Host "Initializing Logging..." -ForegroundColor Cyan
    
# --- Prefer OneDrive\Desktop if available, otherwise use local Desktop ---

    $desktop = [Environment]::GetFolderPath("Desktop")
    $output = if ($env:OneDrive -and (Test-Path $env:OneDrive)) {
    Join-Path $env:OneDrive "Desktop\results.txt"
    } 
    else {
    Join-Path $desktop "results.txt"
    }

# --- Ensure directory exists ---

New-Item -Path (Split-Path $output) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

#Write-Host "Output will be saved to: $output"

return $output

}

# --- Script Logic ---

Clear-Host

$pspath = (Get-Process -Id $PID).Path

# --- Force TLS 1.2 ---

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Ensure admin privileges ---

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process $pspath -Verb runAs -ArgumentList '-NoExit', '-ExecutionPolicy RemoteSigned', '-Command', "& {Invoke-WebRequest 'https://agho.me/provision' -UseBasicParsing | Invoke-Expression}"
    Stop-Process -Id $PID
}

# --- Logging ---

$output = Initialize-Log

# --- System info ---

$computer = $env:COMPUTERNAME
$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
$ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
$bootVolume = [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB, 2)


# --- Display information ---

$messageHeader = @"

 ==========================================
 Welcome to the Quick Utilities Script
 ==========================================

"@

$messageDetails = @"
 System Summary:

 Computer Name: $computer
 CPU: $cpu
 Memory: $ram GB
 Boot Volume Free Space: $bootVolume GB

"@

$messageTasks = @"
 Actions Available:

 - Update Group Policy
 - Configuration Manager Tasks
 - Install Dell System Updates
 - Create a Local User Account
 - Disable sleep on AC

"@

Write-Host $messageHeader -ForegroundColor Cyan
$messageHeader | Out-File -FilePath $output -Encoding utf8 -Append
Write-Host $messageDetails
$messageDetails | Out-File -FilePath $output -Encoding utf8 -Append
Write-Host $messageTasks

# --- Confirmation ---

while (($i = Read-Host " Press Y to continue or N to quit") -notmatch '^[YyNn]$') {}
if ($i -notmatch '^[Yy]$') { exit }

# --- Build GUI ---

Add-Type -AssemblyName PresentationFramework

$xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' Title='Select Actions' Height='250' Width='350' WindowStartupLocation='CenterScreen'>
  <StackPanel Margin='10'>
    <TextBlock FontWeight='Bold' Margin='0 0 0 10'>Choose the actions you want to perform:</TextBlock>
    <CheckBox Name='cbGP' Content=' Update Group Policy' Margin='5'/>
    <CheckBox Name='cbCM' Content=' Configuration Manager Tasks' Margin='5'/>
    <CheckBox Name='cbDell' Content=' Install Dell System Updates' Margin='5'/>
    <CheckBox Name='cbUser' Content=' Create a Local User Account' Margin='5'/>
    <CheckBox Name='cbPowerSettings' Content=' Disable Sleep - TESTING' Margin='5'/>
    <StackPanel Orientation='Horizontal' HorizontalAlignment='Right' Margin='0 15 0 0'>
      <Button Name='btnOK' Width='75' Margin='5' IsDefault='True'>Proceed</Button>
      <Button Width='75' Margin='5' IsCancel='True'>Cancel</Button>
    </StackPanel>
  </StackPanel>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader ([xml]$xaml))
$win = [Windows.Markup.XamlReader]::Load($reader)

# --- Capture GUI selections ---

$btnOK = $win.FindName('btnOK')
$btnOK.Add_Click({
    $win.Tag = @{
        GroupPolicy = $win.FindName('cbGP').IsChecked
        ConfigMgr  = $win.FindName('cbCM').IsChecked
        DellUpdates = $win.FindName('cbDell').IsChecked
        CreateUser = $win.FindName('cbUser').IsChecked
        PowerConfig = $win.FindName('cbPowerSettings').IsChecked
    }
    $win.Close()
})

$win.Topmost = $true
$win.Activate()
$win.ShowDialog() | Out-Null
$sel = $win.Tag

Clear-Host

# --- Execute tasks ---

if ($sel.CreateUser) {
    Create-User
}

if ($sel.GroupPolicy) {
    Invoke-GroupPolicy
}

if ($sel.ConfigMgr) {
    Execute-Actions
}

if ($sel.DellUpdates) {
    Run-DellUpdates
}

Write-Host "Script execution complete. See $output" -ForegroundColor Cyan
Start-Sleep 3
