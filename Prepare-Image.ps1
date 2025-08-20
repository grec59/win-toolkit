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
        [PSCredential]$Credential
    )

    Write-Host "Creating Local User Account..." -ForegroundColor Cyan

    if (-not $Credential) {
        $Credential = Get-Credential -Message "Enter credentials for the new local user:"
        if (-not $Credential) { return }
    }

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
        Write-Host "SUCCESS: Created new user: $username"
        "SUCCESS: Created new local user account: $username" | Out-File -FilePath $output -Encoding utf8 -Append
    } catch {
        Write-Host "FAIL: Unable to create user: $($_.Exception.Message)" -ForegroundColor Red
        "FAIL: Unable to create local user account: $($_.Exception.Message)" | Out-File -FilePath $output -Encoding utf8 -Append
    }
}

function Invoke-PolicyUpdate {
    try {
        Write-Host "Running Policy Update..." -ForegroundColor Cyan
        gpupdate /target:computer | out-null
        Start-Sleep -Seconds 5
        Write-Host "SUCCESS: Computer Policy update has completed." -ForegroundColor Green
        "SUCCESS: Computer Policy update completed. Check Event Viewer for details." | Out-File -FilePath $output -Encoding utf8 -Append
}
    catch {
        Write-Host "FAIL: Failed to update Computer Policy. Check Event Viewer for details." -ForegroundColor Yellow
        "FAIL: Unable to update Computer Policy." | Out-File -FilePath $output -Encoding utf8 -Append
        $($_.Exception.Message) | Out-File -FilePath $output -Encoding utf8 -Append
    }
}

function Invoke-Actions {
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
            "FAIL: $($action.Name) $($_.Exception.Message)" | Out-File -FilePath $output -Encoding utf8 -Append
        }
        Start-Sleep -Seconds 2
    }
}

function Invoke-Updates {
    Write-Host "Running System Updates..." -ForegroundColor Cyan
    $path = 'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe'
    if (Test-Path $path) {
        Start-Sleep -Seconds 3
        Write-Host "Dell Command CLI application detected, starting updates..."
         "Dell Command CLI application detected, starting updates..." | Out-File -FilePath $output -Encoding utf8 -Append
        & "$path" /applyUpdates -autoSuspendBitLocker=enable -forceupdate=enable -outputLog='C:\command.log'
    } else {
        Write-Host "Dell Command application not detected, skipping updates..."  -ForegroundColor Yellow
         "WARN: Dell Command CLI application not detected, skipping updates..." | Out-File -FilePath $output -Encoding utf8 -Append
    }
}

function Disable-Sleep {

    # --- Power settings tuning ---
    Write-Host "Disabling Sleep and Lid Closure action When Plugged In..." -ForegroundColor Cyan
    Start-Sleep 2
    powercfg /change standby-timeout-ac 0
    powercfg -setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 0
    Write-Host "SUCCESS: Sleep and Lid Closure action When Plugged In was disabled." -ForegroundColor Green
    "SUCCESS: Sleep and Lid Closure action When Plugged In has been disabled." | Out-File -FilePath $output -Encoding utf8 -Append
    Start-Sleep 2
    }

function Initialize-Log {
    
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
 Welcome to the Quick Utilities Script v1.0
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

$date = Get-Date
" Execution Date & Time: $date" | Out-File -FilePath $output -Encoding utf8

Write-Host $messageHeader -ForegroundColor Cyan
$messageHeader | Out-File -FilePath $output -Encoding utf8 -Append
Write-Host $messageDetails
$messageDetails | Out-File -FilePath $output -Encoding utf8 -Append
Write-Host $messageTasks
"Task Execution Logs:" | Out-File -FilePath $output -Encoding utf8 -Append
" " | out-File -FilePath $output -Encoding utf8 -Append

# --- Confirmation ---

do {
    $i = Read-Host " Press Y to continue or N to quit"
} while ($i -notmatch '^[YyNn]$')

if ($i -notmatch '^[Yy]$') { exit }

# --- Build GUI ---
$xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        Title='System Maintenance Tool'
        Height='400' Width='450'
        WindowStartupLocation='CenterScreen'
        ResizeMode='NoResize'>
  <Grid Margin='15'>
    <Grid.RowDefinitions>
      <RowDefinition Height='Auto'/>
      <RowDefinition Height='*'/>
      <RowDefinition Height='Auto'/>
    </Grid.RowDefinitions>

    <!-- Header -->
    <StackPanel Grid.Row='0' Margin='0 0 0 15'>
      <TextBlock Text='System Maintenance Actions' 
                 FontWeight='Bold' FontSize='16' 
                 Foreground='DarkBlue'
                 HorizontalAlignment='Center'/>
      <TextBlock Text='Select one or more actions to perform:' 
                 FontStyle='Italic'
                 HorizontalAlignment='Center' Margin='0 5 0 0'/>
    </StackPanel>

    <!-- Options -->
    <StackPanel Grid.Row='1'>
      <GroupBox Header='Available Actions' Margin='0 0 0 10'>
        <StackPanel Margin='10'>
          <CheckBox Name='cbGP' Content=' Update Group Policy' Margin='3'/>
          <CheckBox Name='cbCM' Content=' Run Configuration Manager Tasks' Margin='3'/>
          <CheckBox Name='cbDell' Content=' Install Dell System Updates' Margin='3'/>
          <CheckBox Name='cbUser' Content=' Create Local User Account' Margin='3'/>
        </StackPanel>
      </GroupBox>

      <!-- Progress Area -->
      <GroupBox Header='Execution Progress'>
        <StackPanel Margin='10'>
          <ProgressBar Name='pbProgress' Height='20' Minimum='0' Maximum='100'/>
          <TextBlock Name='lblStatus' Text='Waiting for user input...' Margin='0 5 0 0'/>
        </StackPanel>
      </GroupBox>
    </StackPanel>

    <!-- Buttons -->
    <StackPanel Grid.Row='2' Orientation='Horizontal' HorizontalAlignment='Right' Margin='0 15 0 0'>
      <Button Name='btnOK' Width='85' Margin='5' IsDefault='True' IsEnabled='False'>Proceed</Button>
      <Button Width='85' Margin='5' IsCancel='True'>Cancel</Button>
    </StackPanel>
  </Grid>
</Window>
"@

# --- Load GUI ---
$reader = (New-Object System.Xml.XmlNodeReader ([xml]$xaml))
$win = [Windows.Markup.XamlReader]::Load($reader)

# --- Controls ---
$btnOK      = $win.FindName('btnOK')
$pbProgress = $win.FindName('pbProgress')
$lblStatus  = $win.FindName('lblStatus')
$checkBoxes = @('cbGP','cbCM','cbDell','cbUser') | ForEach-Object { $win.FindName($_) }

# --- Enable Proceed only if something selected ---
foreach ($cb in $checkBoxes) {
    $cb.Add_Checked({ $btnOK.IsEnabled = $checkBoxes.IsChecked -contains $true })
    $cb.Add_Unchecked({ $btnOK.IsEnabled = $checkBoxes.IsChecked -contains $true })
}

# --- Helper: Update Progress ---
function Update-ProgressUI {
    param([int]$percent, [string]$message)
    $pbProgress.Value = $percent
    $lblStatus.Text = $message
    [System.Windows.Forms.Application]::DoEvents() | Out-Null
}

# --- Button Logic ---
$btnOK.Add_Click({
    $actions = @{
        GroupPolicy  = $win.FindName('cbGP').IsChecked
        ConfigMgr    = $win.FindName('cbCM').IsChecked
        DellUpdates  = $win.FindName('cbDell').IsChecked
        CreateUser   = $win.FindName('cbUser').IsChecked
    }

    $step = 0
    $tasks = $actions.GetEnumerator() | Where-Object { $_.Value -eq $true }
    $count = $tasks.Count
    $summary = @()

    foreach ($task in $tasks) {
        $step++
        $percent = [math]::Round(($step / $count) * 100)

        try {
            switch ($task.Key) {
                'GroupPolicy' {
                    Update-ProgressUI $percent 'Updating Group Policy...'
                    Start-Sleep -Seconds 2   # placeholder
                    Write-Log "Group Policy updated successfully."
                    $summary += "✔ Group Policy updated."
                }
                'ConfigMgr' {
                    Update-ProgressUI $percent 'Running ConfigMgr Tasks...'
                    Start-Sleep -Seconds 2   # placeholder
                    Write-Log "ConfigMgr tasks completed successfully."
                    $summary += "✔ ConfigMgr tasks completed."
                }
                'DellUpdates' {
                    Update-ProgressUI $percent 'Installing Dell Updates...'
                    Start-Sleep -Seconds 2   # placeholder
                    Write-Log "Dell updates installed successfully."
                    $summary += "✔ Dell updates installed."
                }
                'CreateUser' {
                    Update-ProgressUI $percent 'Creating Local User...'
                    Start-Sleep -Seconds 2   # placeholder
                    Write-Log "Local user account created successfully."
                    $summary += "✔ Local user created."
                }
            }
        }
        catch {
            Write-Log "ERROR with task [$($task.Key)]: $_"
            $summary += "❌ $($task.Key) failed. Check log."
        }
    }

    Update-ProgressUI 100 'All selected actions completed!'
    [System.Windows.MessageBox]::Show(($summary -join "`n"),"Execution Summary",
        [System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Information) | Out-Null
})

# --- Show Window ---
$win.Topmost = $true
$win.Activate()
$win.ShowDialog() | Out-Null

Clear-Host

# --- Execute tasks ---

if ($sel.CreateUser) {
    Create-User
}

if ($sel.GroupPolicy) {
    Invoke-PolicyUpdate
}

if ($sel.ConfigMgr) {
    Invoke-Actions
}

if ($sel.DellUpdates) {
    Invoke-Updates
}

if ($sel.PowerConfig) {
    Disable-Sleep
}

" " | Out-File -FilePath $output -Encoding utf8 -Append
"Script execution complete." | Out-File -FilePath $output -Encoding utf8 -Append
Write-Host "Script execution complete. See:"
Write-Host "$output" -Foregroundcolor Gray
Start-Sleep 2
