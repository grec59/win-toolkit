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

    Write-Output "Creating Local User Account..." 

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
        Write-Output "SUCCESS: Created new user: $username" 
        "Created new local user account: $username" | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
    } 
    
    catch {
        Write-Warning "Unable to create user: $($_.Exception.Message)" 
        "Unable to create local user account: $($_.Exception.Message)" | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
    }
}

function Invoke-GroupPolicy {
    try {
        Write-Output "Running Policy Update..."
        gpupdate /target:computer | out-null
        Start-Sleep -Seconds 5
        Write-Output "SUCCESS: Computer Policy update has completed." 
        "Computer Policy update completed. Check Event Viewer for details." | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
    }

    catch {
        Write-Warning "Unable to update Computer Policy. Check Event Viewer for details."
        "Unable to update Computer Policy." | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
        $($_.Exception.Message) | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
    }
}

function Execute-Actions {

    try {
        $ccmWMI = Get-WmiObject -Namespace "root\ccm" -Class SMS_Client -ErrorAction Stop
        if ($ccmWMI) {
        Write-Output "Microsoft SCCM client installation found." 
	    "SUCCESS: Microsoft SCCM client found through WMI verification." | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
        }
    } 
    
    catch {
        Write-Warning  "Unable to locate Microsoft SCCM client."
	    "Unable to locate Microsoft SCCM client."."" | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
	    $($_.Exception.Message) | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
        return
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
            Write-Output "SUCCESS: $($action.Name)" 
            "SUCCESS: $($action.Name)" | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
        } 
        
        catch {
            Write-Warning "$($action.Name) $($_.Exception.Message)"
            "FAIL: $($action.Name) $($_.Exception.Message)" | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
        }
        Start-Sleep -Seconds 2
    }
}

function Run-DellUpdates {
    Write-Output "Running System Updates..."
    $path = 'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe'
    if (Test-Path $path) {
        Start-Sleep -Seconds 2
        "Dell Command CLI application detected, starting updates..." | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
        & "$path" /applyUpdates -autoSuspendBitLocker=enable -forceupdate=enable -outputLog='C:\command.log'
    } 
    
    else {
        Write-Warning "Dell Command application not detected, skipping updates."
         "Dell Command CLI application not detected, skipping updates." | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
    }
}

function Disable-Sleep {
    Write-Output "Disabling Sleep and Lid action when plugged in..."
    Start-Sleep 2
    powercfg /change standby-timeout-ac 0
    powercfg -setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 0
    Write-Output "Sleep and Lid action when plugged in has been disabled."
    "Sleep and Lid action when plugged in has been disabled." | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
    Start-Sleep 2
}

function Remove-TempFiles {
    $temp = 'C:\Windows\Temp\'
    $alttemp = 'C:\Users\*\AppData\Local\Temp'
  #  $ccm = Get-WmiObject -Namespace "root\ccm\SoftMgmtAgent" -Class CacheElement | ForEach-Object { $_.Delete() }
  #  $teams = C:\Users\*\AppData\Local\Packages\MSTeams_8wekyb3d8bbwe
  #  $chrome = C:\Users\*\AppData\Local\Google\Chrome\User Data\*\Cache
  #  $edge = C:\Users\*\AppData\Local\Microsoft\Edge\User Data\*\Cache
    Write-Output "Removing temporary files..."
    Get-ChildItem $alttemp | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {} }
    $itemsremoved = (Get-ChildItem $temp | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue; $_ } catch {} }).Count
    $altitemsremoved = (Get-ChildItem $alttemp | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue; $_ } catch     
    {} }).Count
    "Removed $itemsremoved item(s) from $temp and $altitemsremoved from $alttemp" | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
    Write-Output "Removed $itemsremoved temporary files from $temp and $altitemsremoved from $alttemp"
}

function Update-HostsFile {
    [CmdletBinding()]
    param(
        [string]$IPAddress,
        [string]$Hostname
    )

    # Prompt if blank or null
    if ([string]::IsNullOrWhiteSpace($IPAddress)) {
        $IPAddress = Read-Host "Enter IP Address (leave blank to skip)"
    }

    if ([string]::IsNullOrWhiteSpace($Hostname)) {
        $Hostname = Read-Host "Enter Hostname (leave blank to skip)"
    }

    # If either is still blank after prompt → skip
    if ([string]::IsNullOrWhiteSpace($IPAddress) -or
        [string]::IsNullOrWhiteSpace($Hostname)) {

        Write-Warning "IP address or hostname is blank. Skipping hosts file update."
        return
    }

    # Validate IPv4 address
    if (-not [System.Net.IPAddress]::TryParse($IPAddress, [ref]$null)) {
        Write-Warning "Invalid IPv4 address '$IPAddress'. Skipping hosts file update."
        return
    }

    $hosts  = "$env:SystemRoot\System32\drivers\etc\hosts"
    $backup = "$hosts.$((Get-Date -f yyyyMMddHHmmss)).bak"

    # Backup the hosts file
    Copy-Item $hosts $backup -Force

    $entry = "$IPAddress`t$Hostname"

    # Check if the entry already exists
    if (-not (Select-String -Path $hosts -Pattern "^\s*$IPAddress\s+$Hostname\s*$")) {
        Add-Content -Path $hosts -Value $entry
        Write-Output "Added: $entry"
        "SUCCESS: Added $entry to local system hosts file." | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
    }
    else {
        Write-Output "Already exists: $entry"
    }
}

function Clear-MSTeams {

    $installerUrl = "https://go.microsoft.com/fwlink/?linkid=2196106"

    # Stop Microsoft Teams processes
    Write-Output "Stopping Microsoft Teams processes..."
    Get-Process *teams* -ErrorAction SilentlyContinue | Stop-Process -Force

    # Clear Teams cache
    Get-ChildItem C:\Users -Directory | ForEach-Object {
        $userProfile = $_.FullName
        $paths = @(
            Join-Path $userProfile "AppData\Local\Packages\MSTeams_8wekyb3d8bbwe"
            Join-Path $userProfile "AppData\Roaming\Microsoft\Teams"
        )

        foreach ($path in $paths) {
            if (Test-Path $path) {
                Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                Write-Output "Cleared Teams cache for $($_.Name) at $path"
		"Cleared Teams cache for $($_.Name) at $path" | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
            }
        }
    }

    $installerPath = "C:\MSTeams-x64.msix"
    Write-Output "Downloading Microsoft Teams installer..." 

    # Disable progress rendering (MAJOR speed improvement)
    $oldProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    try {
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
        Write-Output "Download completed: $installerPath" 
	"Download completed: $installerPath" | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
    } 
    
    catch {
        Write-Error "Error downloading installer: $_"
	"Download error: $installerPath" | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
        return
    } 
    
    finally {
        # Restore original preference
        $ProgressPreference = $oldProgressPreference
    }

    # Launch the installer
    Start-Process -FilePath $installerPath
    Start-Sleep 3
    Write-Output "Microsoft Teams repair complete." 
    "Microsoft Teams repair complete." | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
}

function Generate-AuditReport {

    Write-Output "Generating audit report..."
    Add-Type -AssemblyName System.Web
    $safe = { param($v) if ($null -eq $v) { "" } else { [System.Web.HttpUtility]::HtmlEncode($v.ToString()) } }

    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue

    $dateGenerated = "Generated on $(Get-Date -f 'dddd, MMMM dd, yyyy hh:mm tt') $((Get-TimeZone).StandardName)"
    $computerName = &$safe $env:COMPUTERNAME
    $domain       = &$safe $cs.Domain
    $installDate  = if ($os.InstallDate) { $os.InstallDate.ToLocalTime() } else { "N/A" }

    $diskMap = @{}
    Get-Disk -ErrorAction SilentlyContinue | ForEach-Object {
        $diskMap[$_.Number] = if ($_.FriendlyName) { $_.FriendlyName } else { $_.Model }
    }

    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue |
        ForEach-Object {
            $letter    = $_.DeviceID.TrimEnd(':')
            $partition = Get-Partition -DriveLetter $letter -ErrorAction SilentlyContinue
            [pscustomobject]@{
                Drive = $_.DeviceID
                Model = if ($partition -and $diskMap.ContainsKey($partition.DiskNumber)) { $diskMap[$partition.DiskNumber] } else { 'Not Available' }
                Used  = [math]::Round(($_.Size - $_.FreeSpace)/1GB,1)
                Free  = [math]::Round($_.FreeSpace/1GB,1)
            }
        }

    $sidToString = {
        param($sid)
        if ($sid -is [System.Security.Principal.SecurityIdentifier]) { $sid.Value }
        elseif ($sid -is [byte[]]) { (New-Object System.Security.Principal.SecurityIdentifier($sid,0)).Value }
        else { [string]$sid }
    }

    $adminSidStrings = @()
    try {
        $adminSidStrings = Get-LocalGroupMember Administrators -ErrorAction Stop |
            Where-Object ObjectClass -eq 'User' |
            ForEach-Object { & $sidToString $_.SID }
    } catch {
        $admins = [ADSI]"WinNT://./Administrators,group"
        $admins.Invoke("Members") | ForEach-Object { $adminSidStrings += & $sidToString $_.objectSID }
    }

    $localUsers = Get-LocalUser -ErrorAction SilentlyContinue |
        ForEach-Object {
            $sidValue = & $sidToString $_.SID
            $type     = if ($adminSidStrings -contains $sidValue) { 'Administrator' } else { 'Standard' }

            [pscustomobject]@{
                Name            = $_.Name
                Enabled         = $_.Enabled
                LastLogon       = $_.LastLogon
                PasswordExpires = $_.PasswordExpires
                Type            = $type
            }
        }

    $networks   = Get-NetIPConfiguration -ErrorAction SilentlyContinue
    $shares     = Get-SmbShare -ErrorAction SilentlyContinue
    $printers   = Get-Printer -ErrorAction SilentlyContinue

    $displays = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Sort-Object { if ($_.Name -match "Intel") { 1 } else { 0 } }

    $updates = Get-CimInstance Win32_QuickFixEngineering -ErrorAction SilentlyContinue |
        Sort-Object InstalledOn -Descending |
        Select-Object -First 5

    $excludeEnv = 'ALLUSERSPROFILE','ComSpec','CommonProgramFiles','CommonProgramFiles(x86)',
                  'CommonProgramW6432','HOMEDRIVE','HOMEPATH','LOCALAPPDATA','LOGONSERVER',
                  'NUMBER_OF_PROCESSORS','OS','Path','PATHEXT','PROCESSOR_ARCHITECTURE',
                  'PROCESSOR_IDENTIFIER','PROCESSOR_LEVEL','PROCESSOR_REVISION',
                  'ProgramData','ProgramFiles','ProgramFiles(x86)','ProgramW6432',
                  'PUBLIC','SystemDrive','SystemRoot','TEMP','TMP','USERDOMAIN',
                  'USERNAME','USERPROFILE','windir'

    $envVars = Get-ChildItem Env: | Where-Object { $excludeEnv -notcontains $_.Name } | Sort Name

    $software = @(
        Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue
        Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue
    ) | Where-Object { $_.DisplayName } |
      Select-Object DisplayName, Publisher |
      Sort-Object DisplayName -Unique

    $printers = $printers | Sort-Object @(
        @{ Expression = { if ($_.Shared -or $_.PortName -match 'IP|WSD|DOT4|USB|LPT') { 0 } else { 1 } }; Ascending = $true },
        @{ Expression = { $_.Name }; Ascending = $true }
    )

    $softwareHtml = $software | ForEach-Object {
        $pub = if ($_.Publisher) { " - $(& $safe $_.Publisher)" } else { "" }
        "<div class='software-item'><strong>$(& $safe $_.DisplayName)</strong>$pub</div>"
    } | Out-String

    $renderList = {
        param($items, $template)
        $items | ForEach-Object { & $template $_ } | Out-String
    }

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>System Audit Report</title>
<style>
@page{size:letter;margin:.25in}
body{font-family:'Segoe UI',Arial;font-size:10px;margin:.25in}
.header{display:flex;justify-content:space-between;border-bottom:2px solid #004d99;padding-bottom:4px}
h1{color:#004d99;margin:0;font-size:18px}
.section{margin-top:10px}
.section h2{font-size:11px;color:#004d99;border-bottom:1px solid #ccc;margin-bottom:4px;text-transform:uppercase}
.summary-grid{display:grid;grid-template-columns:1fr 1fr;gap:2px 20px;margin-top:4px}
.columns-2{columns:2;column-gap:14px}
.columns-2 li{break-inside:avoid-column;-webkit-column-break-inside:avoid;page-break-inside:avoid}
ul{margin:0;padding-left:18px}
li{margin-bottom:4px;line-height:1.25;word-break:break-word;overflow-wrap:anywhere}
table{width:100%;border-collapse:collapse}
td{padding:2px 4px;border-bottom:1px solid #eee;vertical-align:top;word-break:break-word;overflow-wrap:anywhere}
.small table{font-size:9px;table-layout:fixed}
.env-list{margin:0;padding-left:18px;list-style:disc;columns:2;column-gap:14px}
.env-list li{margin-bottom:4px;break-inside:avoid-column}
.env-value{word-break:break-word;overflow-wrap:anywhere}
.software-table{columns:2;column-gap:14px;font-size:9px}
.software-table .software-item{padding:2px 4px;break-inside:avoid-column}
.software-table .software-item:nth-child(odd){background:#f6f6f6}
.header-right{text-align:right}
</style>
</head>
<body>

<div class="header">
  <div>
    <h1>System Audit Report</h1>
    <div>$(& $safe $dateGenerated)</div>
  </div>
  <div class="header-right">
    <div><strong>Computer:</strong> $(& $safe $computerName)</div>
    <div><strong>Domain:</strong> $(& $safe $domain)</div>
  </div>
</div>

<div class="section">
  <h2>System Summary</h2>
  <div class='summary-grid'>
    <div><strong>Model:</strong> $(& $safe $cs.Model)</div>
    <div><strong>Manufacturer:</strong> $(& $safe $cs.Manufacturer)</div>
    <div><strong>Operating System:</strong> $(& $safe $os.Caption) ($(& $safe $os.OSArchitecture))</div>
    <div><strong>Install Date:</strong> $(& $safe $installDate)</div>
  </div>
</div>

<div class="section">
  <h2>Local Users</h2>
  <ul class="columns-2">
$($renderList.Invoke($localUsers, { param($u)
  "<li><strong>$(& $safe $u.Name)</strong><br>Type: $(& $safe $u.Type)<br>Enabled: $(& $safe $u.Enabled)<br>Last Logon: $(& $safe $u.LastLogon)<br>Password Expires: $(& $safe $u.PasswordExpires)</li>"
}))
  </ul>
</div>

<div class="section">
  <h2>Disks</h2>
  <ul class="columns-2">
$($renderList.Invoke($disks, { param($d)
  "<li><strong>$(& $safe $d.Drive)</strong> - $(& $safe $d.Model)<br>Used: $(& $safe $d.Used) GB | Free: $(& $safe $d.Free) GB</li>"
}))
  </ul>
</div>

<div class="section">
  <h2>Networks</h2>
  <ul class="columns-2">
$($renderList.Invoke($networks, { param($n)
  "<li><strong>$(& $safe $n.InterfaceAlias)</strong><br>Description: $(& $safe $n.InterfaceDescription)<br>IPv4: $(& $safe ($n.IPv4Address.IPAddress -join ', '))<br>IPv6: $(& $safe ($n.IPv6Address.IPAddress -join ', '))<br>DNS: $(& $safe ($n.DNSServer.ServerAddresses -join ', '))</li>"
}))
  </ul>
</div>

<div class="section">
  <h2>Display Devices</h2>
  <ul class="columns-2">
$($renderList.Invoke($displays, { param($d)
  "<li><strong>$(& $safe $d.Name)</strong><br>Driver Version: $(& $safe $d.DriverVersion)</li>"
}))
  </ul>
</div>

<div class="section">
  <h2>Latest Windows Updates</h2>
  <ul class="columns-2">
$($renderList.Invoke($updates, { param($u)
  $date = if ($u.InstalledOn) { (Get-Date $u.InstalledOn).ToString('MM/dd/yyyy') } else { 'Unknown' }
  "<li><strong>$(& $safe $u.HotFixID)</strong><br>Type: $(& $safe $u.Description)<br>Installed On: $(& $safe $date)</li>"
}))
  </ul>
</div>

<div class="section">
  <h2>Local Shares</h2>
  <ul class="columns-2">
$($renderList.Invoke($shares, { param($s)
  "<li><strong>$(& $safe $s.Name)</strong><br>Path: $(& $safe $s.Path)<br>Description: $(& $safe $s.Description)<br>Status: $(& $safe $s.ShareState)</li>"
}))
  </ul>
</div>

<div class="section">
  <h2>Printers</h2>
  <ul class="columns-2">
$($renderList.Invoke($printers, { param($p)
  "<li><strong>$(& $safe $p.Name)</strong><br>Driver: $(& $safe $p.DriverName)<br>Type: $(& $safe $p.Type)<br>Shared: $(& $safe $p.Shared)<br>Port: $(& $safe $p.PortName)</li>"
}))
  </ul>
</div>

<div class="section">
  <h2>Environment Variables</h2>
  <ul class="env-list">
$($renderList.Invoke($envVars, { param($e)
  "<li><strong>$(& $safe $e.Name)</strong><br><span class='env-value'>Value: $(& $safe $e.Value)</span></li>"
}))
  </ul>
</div>

<div class="section small">
  <h2>Win32 Applications</h2>
  <div class="software-table">
$softwareHtml
  </div>
</div>

</body>
</html>
"@

    $html | Out-File 'C:\audit.html'
    Write-Output "Audit report generated at C:\audit.html"
    "Audit report generated at C:\audit.html" | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
    Invoke-Item 'C:\audit.html'
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
$InstallDate = (gcim Win32_OperatingSystem).InstallDate.ToString()
$tpmversion = ((Get-CimInstance -Namespace "root/cimv2/security/microsofttpm" -ClassName Win32_Tpm).SpecVersion -split ',')[0].Trim()
$secboot =  Confirm-SecureBootUEFI
$ip = (Get-NetIPConfiguration | ? IPv4DefaultGateway).IPv4Address.IPAddress

$messageHeader = @"

 ==========================================
 Welcome to the Quick Utilities Script v1.0
 ==========================================

"@

$messageDetails = @"
 System Summary:

 Install Date: $InstallDate
 Hostname: $computer

 CPU: $cpu
 RAM: $ram GB
 OS Free Space: $bootVolume GB
 IP Address: $ip

 Secure Boot: $secboot
 TPM Version: $tpmversion
 UEFI: $bios

"@

$messageTasks = @"
 Actions Available:

 - Update Group Policy
 - Configuration Manager tasks
 - Install Dell system updates
 - Create a local user account
 - Disable sleep on AC
 - and much more

"@

$date = Get-Date

" Execution Date & Time: $date" | Out-File -FilePath $Global:LogFile -Encoding utf8

Write-Output $messageHeader 
$messageHeader | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
Write-Output $messageDetails
$messageDetails | Out-File -FilePath $Global:LogFile -Encoding utf8 -Append
Write-Output $messageTasks

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
                          ToolTip="Refresh computer policies for current domain.">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE923;" FontSize="16" Margin="6,0,8,0"/>
                        <TextBlock Text="Update computer policy"/>
                    </StackPanel>
                </CheckBox>

                <CheckBox Name="cbCM" Margin="5"
                          ToolTip="Microsoft Endpoint Configuration Manager">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE713;" FontSize="16" Margin="6,0,8,0"/>
                        <TextBlock Text="Config Manager actions"/>
                    </StackPanel>
                </CheckBox>

                <CheckBox Name="cbDell" Margin="5"
                          ToolTip="Run Dell Command to install driver and firmware updates.">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE895;" FontSize="16" Margin="6,0,8,0"/>
                        <TextBlock Text="Install Dell system updates"/>
                    </StackPanel>
                </CheckBox>

                <CheckBox Name="cbUser" Margin="5"
                          ToolTip="Add a new local user for non-domain account access.">
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
                          ToolTip="Clear system files to free disk space.">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE74D;" FontSize="16" Margin="6,0,8,0"/>
                        <TextBlock Text="Remove temporary files"/>
                    </StackPanel>
                </CheckBox>

                <CheckBox Name="cbEditHosts" Margin="5"
                          ToolTip="Edit local hosts file for hostname IP mapping.">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE211;" FontSize="16" Margin="6,0,8,0"/>
                        <TextBlock Text="Add system hosts entry"/>
                    </StackPanel>
                </CheckBox>

                <CheckBox Name="cbClearTeams" Margin="5"
                          ToolTip="Clear Teams cache and run offline installer.">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE78B;" FontSize="16" Margin="6,0,8,0"/>
                        <TextBlock Text="Update Microsoft Teams"/>
                    </StackPanel>
                </CheckBox>

                <CheckBox Name="cbAuditReport" Margin="5"
                          ToolTip="Output system information HTML report.">
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

Write-Output "Script execution complete. See log for details.`
Generated logfile: $Global:LogFile"
Start-Sleep 3
