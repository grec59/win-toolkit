<#
.DESCRIPTION
  This script executes administrative tasks on a Windows system, including:
    - Update Group Policy
    - Configuration Manager tasks
    - Install Dell system updates
    - Create a local user account
    - Disable sleep on AC
    - Remove temporary files
    - Add system hosts entry
    - Repair Microsoft Teams
    - Generate System Report

.NOTES
    - Requires administrative privileges
    - Designed for interactive use with GUI-based action selection
    - Logging to C:\results.txt is basic.
    - Incompatible with command-line execution (PS-Remoting, PsExec)
    - Initial Configuration Manager task selection interrupts unattenteded execution.
    - Dell BIOS updates may fail on some models through CLI utility.
    - Microsoft Teams application repair is per-user installation through MSIX.

.EXAMPLE
  .\Prepare-Image.ps1 
#>

# --- Begin Function Definitions ---

function Initialize-Log {
    $path = 'C:\results.txt'
    New-Item -Path $path -ItemType File -Force -ErrorAction SilentlyContinue | Out-Null
    return $path
}

$Global:LogFile = Initialize-Log

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
        Write-Host "SUCCESS: Created new user: $username" -ForegroundColor Green
        "SUCCESS: Created new local user account: $username" | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
    } 
    
    catch {
        Write-Host "FAIL: Unable to create user: $($_.Exception.Message)" -ForegroundColor Red
        "FAIL: Unable to create local user account: $($_.Exception.Message)" | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
    }
}

function Invoke-GroupPolicy {
    try {
        Write-Host "Running Policy Update..." -ForegroundColor Cyan
        gpupdate /target:computer | out-null
        Start-Sleep -Seconds 5
        Write-Host "SUCCESS: Computer Policy update has completed." -ForegroundColor Green
        "SUCCESS: Computer Policy update completed. Check Event Viewer for details." | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
    }

    catch {
        Write-Host "FAIL: Failed to update Computer Policy. Check Event Viewer for details." -ForegroundColor Yellow
        "FAIL: Unable to update Computer Policy." | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
        $($_.Exception.Message) | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
    }
}

function Execute-Actions {

    try {
        $ccmWMI = Get-WmiObject -Namespace "root\ccm" -Class SMS_Client -ErrorAction Stop
        if ($ccmWMI) {
            Write-Host "ConfigMgr client found (WMI verification)." -ForegroundColor Green
        }
    } 
    
    catch {
        Write-Warning  "ConfigMgr client not found (WMI verification)."
    }

    Add-Type -AssemblyName PresentationFramework

    # --- Configuration Manager client actions ---

    $actionsList = @(
        [PSCustomObject]@{ Name = "Machine policy retrieval cycle"; Guid = "{00000000-0000-0000-0000-000000000021}"; IsChecked = $false },
        [PSCustomObject]@{ Name = "Machine policy evaluation cycle"; Guid = "{00000000-0000-0000-0000-000000000022}"; IsChecked = $false },
        [PSCustomObject]@{ Name = "Hardware inventory cycle"; Guid = "{00000000-0000-0000-0000-000000000001}"; IsChecked = $false },
        [PSCustomObject]@{ Name = "Software inventory cycle"; Guid = "{00000000-0000-0000-0000-000000000002}"; IsChecked = $false },
        [PSCustomObject]@{ Name = "Discovery data collection cycle"; Guid = "{00000000-0000-0000-0000-000000000003}"; IsChecked = $false },
        [PSCustomObject]@{ Name = "Software updates scan cycle"; Guid = "{00000000-0000-0000-0000-000000000113}"; IsChecked = $false },
        [PSCustomObject]@{ Name = "Software updates deployment evaluation cycle"; Guid = "{00000000-0000-0000-0000-000000000114}"; IsChecked = $false },
        [PSCustomObject]@{ Name = "Software metering usage report cycle"; Guid = "{00000000-0000-0000-0000-000000000031}"; IsChecked = $false },
        [PSCustomObject]@{ Name = "Application deployment evaluation cycle"; Guid = "{00000000-0000-0000-0000-000000000121}"; IsChecked = $false },
        [PSCustomObject]@{ Name = "Windows installer source list update cycle"; Guid = "{00000000-0000-0000-0000-000000000032}"; IsChecked = $false },
        [PSCustomObject]@{ Name = "File collection"; Guid = "{00000000-0000-0000-0000-000000000010}"; IsChecked = $false }
    )

    # --- XAML for task selection GUI ---

$xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        Title='Configuration Manager Client Actions'
        Height='Auto' Width='420'
        SizeToContent='Height'
        WindowStartupLocation='CenterScreen'
        Background='#f2f5f7'
        FontFamily='Segoe UI'
        WindowStyle='SingleBorderWindow'
        ResizeMode='NoResize'>

    <Grid Margin='15'>
        <Grid.RowDefinitions>
            <RowDefinition Height='Auto' />    <!-- Title -->
            <RowDefinition Height='*' />       <!-- ItemsControl -->
            <RowDefinition Height='Auto' />    <!-- Buttons Panel -->
        </Grid.RowDefinitions>

        <!-- Title Section -->
        <StackPanel Grid.Row='0' Margin='0 0 0 15' HorizontalAlignment='Center'>
            <TextBlock Text='Configuration Manager Client Actions'
                       FontSize='16'
                       FontWeight='Bold'
                       Foreground='#0078d7'
                       HorizontalAlignment='Center'/>
            <TextBlock Text='Choose the actions you want to perform:'
                       FontSize='12'
                       FontStyle='Italic'
                       Foreground='#2b2b2b'
                       Margin='0 5 0 0'
                       HorizontalAlignment='Center'/>
        </StackPanel>

        <!-- ItemsControl inside Border -->
        <Border Grid.Row='1'
                Margin='10,0,10,0'
                Padding='10'
                Background='White'
                BorderBrush='#0078d7'
                BorderThickness='2'
                CornerRadius='4'>
            <ScrollViewer VerticalScrollBarVisibility='Auto' MaxHeight='180'>
                <ItemsControl Name='icActions'>
                    <ItemsControl.ItemTemplate>
                        <DataTemplate>
                            <CheckBox Content='{Binding Name}'
                                      IsChecked='{Binding IsChecked, Mode=TwoWay}'
                                      Margin='5,0,5,10'/>
                        </DataTemplate>
                    </ItemsControl.ItemTemplate>
                </ItemsControl>
            </ScrollViewer>
        </Border>

        <!-- Bottom Buttons Panel with Select All bottom-left, others bottom-right -->
        <Grid Grid.Row='2' Margin='0,20,0,0'>
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width='Auto' />    <!-- Select All -->
                <ColumnDefinition Width='*' />       <!-- Spacer -->
                <ColumnDefinition Width='Auto' />    <!-- Proceed / Cancel -->
            </Grid.ColumnDefinitions>

            <StackPanel Orientation='Horizontal' HorizontalAlignment='Left' Grid.Column='0'>
                <Button Name='btnSelectAll' Width='100' Height='28' Margin='5 0 5 0'
                        Background='#0078d7' Foreground='White' FontWeight='SemiBold' BorderBrush='#005a9e'>
                    Select All
                </Button>
            </StackPanel>

            <StackPanel Orientation='Horizontal' HorizontalAlignment='Right' Grid.Column='2'>
                <Button Name='btnOK' Width='90' Height='28' Margin='5'
                        IsDefault='True'
                        Background='#0078d7' Foreground='White' FontWeight='SemiBold' BorderBrush='#005a9e'>
                    Proceed
                </Button>
                <Button Width='90' Height='28' Margin='5' IsCancel='True'
                        Background='#cccccc' Foreground='Black' BorderBrush='#999999'>
                    Cancel
                </Button>
            </StackPanel>
        </Grid>
    </Grid>

</Window>
"@

    $reader = (New-Object System.Xml.XmlNodeReader ([xml]$xaml))
    $win = [Windows.Markup.XamlReader]::Load($reader)

    $ic = $win.FindName('icActions')
    $ic.ItemsSource = $actionsList

    $btnSelectAll = $win.FindName('btnSelectAll')
    $btnSelectAll.Add_Click({
        foreach ($item in $actionsList) { $item.IsChecked = $true }
        $ic.Items.Refresh()
    })

    $btnOK = $win.FindName('btnOK')
    $btnOK.Add_Click({
        $win.Tag = $actionsList | Where-Object { $_.IsChecked }
        $win.Close()
    })

    $win.Topmost = $true
    $win.ShowDialog() | Out-Null

    $chosen = $win.Tag
    if (-not $chosen) { return }

    # --- Invoke selected Configuration Manager client actions ---

    foreach ($action in $chosen) {
        try {
            Invoke-WmiMethod -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule -ArgumentList $action.Guid -ErrorAction Stop | Out-Null
            Write-Host "SUCCESS: $($action.Name)" -ForegroundColor Green
            "SUCCESS: $($action.Name)" | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
        } 
        
        catch {
            Write-Host "FAIL: $($action.Name) $($_.Exception.Message)" -ForegroundColor Red
            "FAIL: $($action.Name) $($_.Exception.Message)" | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
        }
        Start-Sleep -Seconds 2
    }
}

function Run-DellUpdates {
    Write-Host "Running System Updates..." -ForegroundColor Cyan
    $path = 'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe'
    if (Test-Path $path) {
        Start-Sleep -Seconds 2
        "Dell Command CLI application detected, starting updates..." | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
        & "$path" /applyUpdates -autoSuspendBitLocker=enable -forceupdate=enable -outputLog='C:\command.log'
    } 
    
    else {
        Write-Warning "Dell Command application not detected, skipping updates."
         "WARN: Dell Command CLI application not detected, skipping updates." | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
    }
}

function Disable-Sleep {
    Write-Host "Disabling Sleep and Lid Closure When Plugged In..." -ForegroundColor Cyan
    Start-Sleep 2
    powercfg /change standby-timeout-ac 0
    powercfg -setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 0
    Write-Host "SUCCESS: Sleep and Lid Closure action when plugged in is disabled." -ForegroundColor Green
    "SUCCESS: Sleep and Lid Closure action when plugged in has been disabled." | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
    Start-Sleep 2
}

function Remove-TempFiles {
    $temp = 'C:\Windows\Temp\'
    Write-Host "Removing temporary files..." -ForegroundColor Cyan
    $itemsremoved = (Get-ChildItem $temp | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue; $_ } catch {} }).Count
    Write-Host "SUCCESS: Removed $itemsremoved temporary files from $temp" -ForegroundColor Green

}

function Update-HostsFile {
    [CmdletBinding()] param(
        [Parameter(Mandatory)]
        [ValidatePattern('^(?:\d{1,3}\.){3}\d{1,3}$')] $IPAddress,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()] $Hostname
    )

    $hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
    $backup = "$hosts.$((Get-Date -f yyyyMMddHHmmss)).bak"

    Copy-Item $hosts $backup -Force

    $entry = "$IPAddress`t$Hostname"
    if (-not (Select-String $hosts -Pattern "^\s*$IPAddress\s+$Hostname\s*$" -SimpleMatch)) {
        Add-Content $hosts $entry
        "Added: $entry"
    }
    else {
        "Already exists: $entry"
    }
}

function Clear-MSTeams {
    # Stop Microsoft Teams processes
    Write-Host "Stopping Microsoft Teams processes..." -ForegroundColor Cyan
    Get-Process *teams* -ErrorAction SilentlyContinue | Stop-Process -Force

    # Prompt user to select profile(s)
    $users = Get-ChildItem C:\Users | Out-GridView -PassThru

    foreach ($user in $users) {
        $teamsCachePath = Join-Path -Path $user.FullName -ChildPath "AppData\Local\Packages\MSTeams_8wekyb3d8bbwe"

        if (Test-Path $teamsCachePath) {
            Remove-Item -Path $teamsCachePath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Cleared Teams cache for: $($user.Name)" -ForegroundColor Green
        } else {
            Write-Host "Teams cache not found for: $($user.Name)" -ForegroundColor Yellow
        }
    }

    # Download the Microsoft Teams offline installer
    $installerUrl = "https://go.microsoft.com/fwlink/?linkid=2196106"
    $user = (Get-Process explorer -IncludeUserName).UserName.Split("\")[-1]
    $installerPath = "C:\Users\$user\AppData\Local\Temp\MSTeams-x64.msix"

    Write-Host "Downloading Microsoft Teams installer..." -ForegroundColor Cyan

    # Disable progress rendering (MAJOR speed improvement)
    $oldProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    try {
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
        Write-Host "Download completed: $installerPath" -ForegroundColor Green
    } catch {
        Write-Host "Error downloading installer: $_" -ForegroundColor Red
        return
    } finally {
        # Restore original preference
        $ProgressPreference = $oldProgressPreference
    }

    # Launch the installer
    Write-Host "Launching installer..." -ForegroundColor Cyan
    Start-Process -FilePath $installerPath

    Write-Host "Microsoft Teams repair complete." -ForegroundColor Green
}

function Generate-AuditReport {
    [CmdletBinding()]
    param (
        [bool]$SortByInstallDate = $false,
        [string]$Global:LogFilePath = $null
    )

    # Get computer name once for subtitle
    $computerNameRaw = $env:COMPUTERNAME
    $computerName = [System.Web.HttpUtility]::HtmlEncode($computerNameRaw)  # Simple HTML encode

    # Get computer domain
    Try {
        $domainRaw = (Get-CimInstance Win32_ComputerSystem).Domain
        $domain = if ($domainRaw) { [System.Web.HttpUtility]::HtmlEncode($domainRaw) } else { "N/A" }
    } Catch {
        $domain = "N/A"
    }

    # Initialize ordered hashtable for report sections
    $report = [ordered]@{}

    # --- Collect System Information ---
    Try {
        $report["System Info"] = Get-ComputerInfo | Select-Object CsName, WindowsVersion, WindowsBuildLabEx, OsArchitecture, CsManufacturer, CsModel
    } Catch { Write-Warning "Failed to get system info: $_" }

    Try {
        $report["Local Users"] = Get-LocalUser | Select Name, FullName, Enabled, PasswordLastSet
    } Catch { Write-Warning "Failed to get local users: $_" }

    Try {
        $report["Printers"] = Get-Printer | Select Name, Type, DriverName, PortName, Shared
    } Catch { Write-Warning "Failed to get printers: $_" }

    Try {
        $report["SMB Shares"] = Get-SmbShare | Select Name, Path, Description, ShareState
    } Catch { Write-Warning "Failed to get SMB shares: $_" }

    Try {
        $excludedPublishers = @("Microsoft", "Advanced Micro Devices, Inc.", "Intel Corporation")

        $installedSoftware = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, `
                                              HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* `
                                              -ErrorAction SilentlyContinue |
            Where-Object { 
                $_.DisplayName -and 
                ($excludedPublishers -notcontains $_.Publisher)
            } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate

        # Safe install date parsing helper
        function Parse-InstallDate($date) {
            if ([string]::IsNullOrWhiteSpace($date)) { return [datetime]::MinValue }
            try {
                return [datetime]::ParseExact($date, 'yyyyMMdd', $null)
            } catch {
                return [datetime]::MinValue
            }
        }

        if ($SortByInstallDate) {
            $report["Installed Software"] = $installedSoftware | Sort-Object @{Expression = { Parse-InstallDate $_.InstallDate }}
        } else {
            $report["Installed Software"] = $installedSoftware | Sort-Object DisplayName
        }
    } Catch { Write-Warning "Failed to get installed software: $_" }

    Try {
        # Use Win32_LogicalDisk for disk usage info
        $report["Disk Usage"] = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object DeviceID,
            @{Name='Used(GB)';Expression={[math]::Round(($_.Size - $_.FreeSpace)/1GB,1)}},
            @{Name='Free(GB)';Expression={[math]::Round($_.FreeSpace/1GB,1)}}
    } Catch { Write-Warning "Failed to get disk usage: $_" }

    # FIXED Network Info section: Convert DNSServer addresses to comma-separated string safely
    Try {
        $report["Network Info"] = Get-NetIPConfiguration | ForEach-Object {
            [PSCustomObject]@{
                InterfaceAlias       = $_.InterfaceAlias
                IPv4                 = ($_.IPv4Address.IPAddress)
                IPv6                 = ($_.IPv6Address.IPAddress)
                DNSServer            = if ($_.DNSServer) { ($_.DNSServer.ServerAddresses -join ', ') } else { '' }
                InterfaceDescription = $_.InterfaceDescription
            }
        }
    } Catch { Write-Warning "Failed to get network info: $_" }

    Try {
        $report["C:\ Directory"] = Get-ChildItem C:\ -ErrorAction SilentlyContinue | Select LastWriteTime, Name, Attributes
    } Catch { Write-Warning "Failed to list C:\ directory: $_" }

    Try {
        $report["C:\Users Directory"] = Get-ChildItem C:\Users -ErrorAction SilentlyContinue | Select LastWriteTime, Name, Attributes
    } Catch { Write-Warning "Failed to list C:\Users directory: $_" }

    # Get last 5 installed Windows updates
    Try {
        $lastUpdates = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 5 |
                       Select-Object HotFixID, InstalledOn, Description
        $report["Last 5 Windows Updates"] = $lastUpdates
    } Catch { Write-Warning "Failed to get Windows updates: $_" }

    # Get environment variables
    Try {
        $envVars = Get-ChildItem Env: | Sort-Object Name | Select-Object Name, Value
        $report["Environment Variables"] = $envVars
    } Catch { Write-Warning "Failed to get environment variables: $_" }

    # --- Output Configuration ---

    if (-not $Global:LogFilePath) {
        $desktopPath = [Environment]::GetFolderPath('Desktop')
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
        $Global:LogFilePath = Join-Path -Path $desktopPath -ChildPath "System_Audit_Report_$timestamp.html"
    }

    # --- Build HTML Report ---

    $dateGenerated = Get-Date -Format "dddd, MMMM dd yyyy HH:mm"
    $htmlHeader = @"
<html>
<head>
    <title>System Audit Report</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background-color: #f4f7f9;
            margin: 30px auto;
            max-width: 1200px;
            color: #333;
        }
        .header-container {
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            margin-bottom: 20px;
            border-bottom: 1.5px solid #ccc;
            padding-bottom: 10px;
        }
        .left-block, .right-block {
            display: flex;
            flex-direction: column;
            justify-content: center;
        }
        .left-block {
            align-items: flex-start;
        }
        .right-block {
            align-items: flex-end;
            text-align: right;
        }
        h1 {
            font-size: 2.4em;
            color: #004d99;
            margin: 0 0 6px 0;
            font-weight: 600;
            line-height: 1.1;
        }
        .generated-date {
            font-size: 1em;
            color: #666;
            margin: 0;
            font-weight: 400;
        }
        h2.subtitle {
            font-size: 1.2em;
            font-weight: 500;
            color: #333;
            margin: 0 0 4px 0;
        }
        h3.domain {
            font-size: 1em;
            font-weight: 400;
            color: #666;
            margin: 0;
        }
        h2.section-title {
            color: #007acc;
            border-bottom: 3px solid #007acc;
            padding-bottom: 6px;
            margin-top: 40px;
        }
        .section {
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 6px rgba(0,0,0,0.1);
            padding: 0;
            max-height: 380px;
            overflow-y: auto;
            margin-bottom: 30px;
            position: relative;
            z-index: 0;
            overflow-anchor: none;
        }
        table {
            border-collapse: separate;
            border-spacing: 0;
            width: 100%;
            font-size: 0.9em;
            table-layout: fixed;
            word-wrap: break-word;
            background-color: white;
        }
        th, td {
            border: 1px solid #d1d9e6;
            padding: 12px 10px;
            text-align: left;
            vertical-align: top;
            background-clip: padding-box;
        }
        thead {
            background-color: #e1ecf9;
        }
        thead th {
            position: sticky;
            top: 0;
            z-index: 15;
            color: #004d99;
            box-shadow: 0 2px 2px -1px rgba(0,0,0,0.1);
            border-bottom: 2px solid #007acc;
        }
        tbody tr:nth-child(even) {
            background-color: #f9fbfd;
        }
    </style>
</head>
<body>
    <div class='header-container'>
        <div class='left-block'>
            <h1>System Audit Report</h1>
            <div class='generated-date'>Generated on $dateGenerated</div>
        </div>
        <div class='right-block'>
            <h2 class='subtitle'>Computer Name: $computerName</h2>
            <h3 class='domain'>Domain: $domain</h3>
        </div>
    </div>
"@

    $htmlBody = ""
    foreach ($section in $report.GetEnumerator()) {
        if ($section.Value -ne $null -and $section.Value.Count -gt 0) {
            $htmlBody += "<h2 class='section-title'>$($section.Key)</h2><div class='section'>"
            $htmlBody += ($section.Value | ConvertTo-Html -Fragment)
            $htmlBody += "</div>"
        }
    }

    $htmlFooter = @"
</body>
</html>
"@

    Try {
        ($htmlHeader + $htmlBody + $htmlFooter) | Out-File -FilePath $Global:LogFilePath -Encoding UTF8 -Force
        Write-Host "`nSystem audit report generated at:`n$Global:LogFilePath"
        Invoke-Item $Global:LogFilePath
    } Catch {
        Write-Error "Failed to write report: $_"
    }
}

# --- Begin Script Logic ---

Clear-Host

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Ensure Administrative Execution ---

$pspath = (Get-Process -Id $PID).Path

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process $pspath -Verb runAs -ArgumentList '-NoExit', '-ExecutionPolicy RemoteSigned', '-Command', "& {Invoke-WebRequest 'https://agho.me/dev' -UseBasicParsing | Invoke-Expression}"
    Stop-Process -Id $PID
}

$computer = $env:COMPUTERNAME
$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
$ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
$bootVolume = [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB, 2)
$bios = (Get-CimInstance Win32_BIOS).ReleaseDate.tostring('MM/dd/yyyy')

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
 BIOS: $bios

"@

$messageTasks = @"
 Actions Available:

 - Update Group Policy
 - Configuration Manager tasks
 - Install Dell system updates
 - Create a local user account
 - Disable sleep on AC
 - Remove temporary files

"@

$date = Get-Date

" Execution Date & Time: $date" | Out-File -FilePath $Global:LogFile -Encoding utf8

Write-Host $messageHeader -ForegroundColor Cyan
$messageHeader | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
Write-Host $messageDetails
$messageDetails | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
Write-Host $messageTasks

"Task Execution Logs:`n" | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append

# --- Retrieve user input and launch selection window upon explicit confirmation ---

while (($i = Read-Host " Press Y to continue or N to quit") -notmatch '^[YyNn]$') {}
if ($i -notmatch '^[Yy]$') { exit }

Add-Type -AssemblyName PresentationFramework

# --- Build XAML for task selection GUI ---

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Quick Utilities Script v1.0"
        Height="Auto" Width="420"
        SizeToContent="Height"
        WindowStartupLocation="CenterScreen"
        Background="#f2f5f7"
        FontFamily="Segoe UI"
        WindowStyle="SingleBorderWindow"
        ResizeMode="NoResize">

    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/> 
            <RowDefinition Height="*"/>    
            <RowDefinition Height="Auto"/> 
        </Grid.RowDefinitions>

        <!-- Title Section -->
        <StackPanel Grid.Row="0" Margin="0 0 0 15" HorizontalAlignment="Center">
            <TextBlock Text="System Actions Available"
                       FontSize="16"
                       FontWeight="Bold"
                       Foreground="#0078d7"
                       HorizontalAlignment="Center"
                       TextAlignment="Center"/>
            <TextBlock Text="Choose the actions you want to perform:"
                       FontSize="12"
                       FontStyle="Italic"
                       Foreground="#2b2b2b"
                       Margin="0 5 0 0"
                       HorizontalAlignment="Center"
                       TextAlignment="Center"/>
        </StackPanel>

        <!-- Options Section -->
        <Border Grid.Row="1"
                Margin="10,0,10,0"
                Padding="10"
                BorderBrush="#0078d7"
                BorderThickness="2"
                Background="White"
                CornerRadius="4">

            <StackPanel>
                <!-- Dynamic Items -->
                <ScrollViewer VerticalScrollBarVisibility="Auto" MaxHeight="180">
                    <ItemsControl Name="icActions">
                        <ItemsControl.ItemTemplate>
                            <DataTemplate>
                                <CheckBox IsChecked="{Binding IsChecked, Mode=TwoWay}" Margin="5 0 5 10">
                                    <StackPanel Orientation="Horizontal">
                                        <TextBlock FontFamily="Segoe MDL2 Assets"
                                                   FontSize="16"
                                                   Text="&#xE115;"
                                                   Margin="6,0,8,0"/>
                                        <TextBlock Text="{Binding Name}"/>
                                    </StackPanel>
                                </CheckBox>
                            </DataTemplate>
                        </ItemsControl.ItemTemplate>
                    </ItemsControl>
                </ScrollViewer>

                <!-- Static Checkboxes With Updated Icons -->
                <CheckBox Name="cbGP" Margin="5"
                          ToolTip="Run gpupdate to refresh computer policies.">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE923;" FontSize="16" Margin="6,0,8,0"/>
                        <TextBlock Text="Update Group Policy"/>
                    </StackPanel>
                </CheckBox>

                <CheckBox Name="cbCM" Margin="5"
                          ToolTip="Initiate software/hardware inventory and application deployments.">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE713;" FontSize="16" Margin="6,0,8,0"/>
                        <TextBlock Text="Configuration Manager tasks"/>
                    </StackPanel>
                </CheckBox>

                <CheckBox Name="cbDell" Margin="5"
                          ToolTip="Run Dell Command to check for BIOS, driver, and firmware updates.">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE895;" FontSize="16" Margin="6,0,8,0"/>
                        <TextBlock Text="Install Dell system updates"/>
                    </StackPanel>
                </CheckBox>

                <CheckBox Name="cbUser" Margin="5"
                          ToolTip="Add a new local account for non-domain access.">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE77B;" FontSize="16" Margin="6,0,8,0"/>
                        <TextBlock Text="Create a local user account"/>
                    </StackPanel>
                </CheckBox>

                <CheckBox Name="cbPowerSettings" Margin="5"
                          ToolTip="Prevent system from entering sleep mode while plugged in.">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE945;" FontSize="16" Margin="6,0,8,0"/>
                        <TextBlock Text="Disable sleep on AC power"/>
                    </StackPanel>
                </CheckBox>

                <CheckBox Name="cbTempFiles" Margin="5"
                          ToolTip="Clear temporary files from Windows directory.">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE74D;" FontSize="16" Margin="6,0,8,0"/>
                        <TextBlock Text="Remove temporary files"/>
                    </StackPanel>
                </CheckBox>

                <CheckBox Name="cbEditHosts" Margin="5"
                          ToolTip="Add local hosts file entry for DNS resolution.">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE211;" FontSize="16" Margin="6,0,8,0"/>
                        <TextBlock Text="Update local hosts file"/>
                    </StackPanel>
                </CheckBox>

                <CheckBox Name="cbClearTeams" Margin="5"
                          ToolTip="Clear Teams application cache and run offline MSIX installer.">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE78B;" FontSize="16" Margin="6,0,8,0"/>
                        <TextBlock Text="Repair Microsoft Teams"/>
                    </StackPanel>
                </CheckBox>

                <CheckBox Name="cbAuditReport" Margin="5"
                          ToolTip="Generate detailed system audit report for migration.">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE14C;" FontSize="16" Margin="6,0,8,0"/>
                        <TextBlock Text="Generate system report"/>
                    </StackPanel>
                </CheckBox>

            </StackPanel>
        </Border>

        <!-- Buttons -->
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,20,0,0">
            <Button Name="btnOK" Width="90" Height="28" Margin="5"
                    Background="#0078d7" Foreground="White"
                    FontWeight="SemiBold" BorderBrush="#005a9e"
                    IsDefault="True">Proceed</Button>

            <Button Width="90" Height="28" Margin="5"
                    Background="#cccccc" Foreground="Black"
                    BorderBrush="#999999" IsCancel="True">Cancel</Button>
        </StackPanel>

    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader ([xml]$xaml))
$win = [Windows.Markup.XamlReader]::Load($reader)

$btnOK = $win.FindName("btnOK")
$btnOK.Add_Click({
    $win.Tag = @{
        GroupPolicy  = $win.FindName("cbGP").IsChecked
        ConfigMgr    = $win.FindName("cbCM").IsChecked
        DellUpdates  = $win.FindName("cbDell").IsChecked
        CreateUser   = $win.FindName("cbUser").IsChecked
        PowerConfig  = $win.FindName("cbPowerSettings").IsChecked
        ClearTemp    = $win.FindName("cbTempFiles").IsChecked
        EditHosts    = $win.FindName("cbEditHosts").IsChecked
        ClearTeams   = $win.FindName("cbClearTeams").IsChecked
        AuditReport  = $win.FindName("cbAuditReport").IsChecked
    }
    $win.Close()
})

$win.Topmost = $true
$win.ShowDialog() | Out-Null
$sel = $win.Tag

Clear-Host

# --- Execute Tasks ---

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

if ($sel.PowerConfig) {
    Disable-Sleep
}

if ($sel.ClearTemp) {
    Remove-TempFiles
}

if ($sel.EditHosts) {
    Update-HostsFile
}

if ($sel.ClearTeams) {
    Clear-MSTeams
}

if ($sel.AuditReport) {
    Generate-AuditReport
}

"`nScript execution complete." | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append

Write-Host "Script execution complete. See:"
Write-Host "$Global:LogFile" -Foregroundcolor Gray

Start-Sleep 1
