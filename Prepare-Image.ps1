<#
.DESCRIPTION
  This script executes administrative tasks on a Windows system, including:
    - Updating Group Policy
    - Initiating Configuration Manager client actions
    - Installing Dell system updates
    - Creating a local user account

.NOTES
    - Requires administrative privileges.
    - Designed for interactive use with GUI-based action selection.    
    - Outputs log to C:\results.txt
    - Ensures administrative privileges.

.EXAMPLE
  .\Prepare-Image.ps1 -Verbose
#>

# --- Begin Function Definitions ---

function Initialize-Log {
    # --- Prefer OneDrive\Desktop if available, otherwise use local Desktop ---

    $desktop = [Environment]::GetFolderPath("Desktop")
    $output = if ($env:OneDrive -and (Test-Path $env:OneDrive)) {
    Join-Path $env:OneDrive "Desktop\results.txt"
    } 
    else {
    Join-Path $desktop "results.txt"
    }

    New-Item -Path (Split-Path $output) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    return $output

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
        "SUCCESS: Created new local user account: $username" | Out-File -FilePath $output -Encoding utf8 -Append
    } 
    
    catch {
        Write-Host "FAIL: Unable to create user: $($_.Exception.Message)" -ForegroundColor Red
        "FAIL: Unable to create local user account: $($_.Exception.Message)" | Out-File -FilePath $output -Encoding utf8 -Append
    }
}

function Invoke-GroupPolicy {
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

function Execute-Actions {
    Add-Type -AssemblyName PresentationFramework

    # --- Create Configuration Manager client actions as PSCustomObjects ---

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

    # --- Build XAML for Configuration Manager client selection GUI ---

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
            "SUCCESS: $($action.Name)" | Out-File -FilePath $output -Encoding utf8 -Append
        } 
        
        catch {
            Write-Host "FAIL: $($action.Name) $($_.Exception.Message)" -ForegroundColor Red
            "FAIL: $($action.Name) $($_.Exception.Message)" | Out-File -FilePath $output -Encoding utf8 -Append
        }
        Start-Sleep -Seconds 2
    }
}

function Run-DellUpdates {
    Write-Host "Running System Updates..." -ForegroundColor Cyan
    $path = 'C:\Program Files\Dell\CommandUpdate\dcu-cli.exe'
    if (Test-Path $path) {
        Start-Sleep -Seconds 3
        "Dell Command CLI application detected, starting updates..." | Out-File -FilePath $output -Encoding utf8 -Append
        & "$path" /applyUpdates -autoSuspendBitLocker=enable -forceupdate=enable -outputLog='C:\command.log'
    } 
    
    else {
        Write-Host "WARN: Dell Command application not detected, skipping updates."  -ForegroundColor Yellow
         "WARN: Dell Command CLI application not detected, skipping updates." | Out-File -FilePath $output -Encoding utf8 -Append
    }
}

function Disable-Sleep {
    Write-Host "Disabling Sleep When Plugged In..." -ForegroundColor Cyan
    Start-Sleep 2
    powercfg /change standby-timeout-ac 0
    powercfg -setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 0
    Write-Host "SUCCESS: Sleep and Lid Closure action when plugged in is disabled." -ForegroundColor Green
    "SUCCESS: Sleep and Lid Closure action when plugged in has been disabled." | Out-File -FilePath $output -Encoding utf8 -Append
    Start-Sleep 2
}

function Remove-TempFiles {
    $temp = 'C:\Windows\Temp\'
    Write-Host "Removing temporary files..." -ForegroundColor Cyan
    $itemsremoved = (Get-ChildItem $temp | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue; $_ } catch {} }).Count
    Write-Host "SUCCESS: Removed $itemsremoved temporary files from $temp" -ForegroundColor Green

}

function Update-HostsFile {
    # Prompt for hostname and IP address
    $hostname = Read-Host "Enter the hostname"
    $ip = Read-Host "Enter the IP address"

    # Path to the hosts file
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"

    # Create the entry
    $entry = "`n$ip`t$hostname"

    # Backup the original hosts file
    Copy-Item $hostsPath "$hostsPath.bak" -Force

    # Add the entry
    Add-Content -Path $hostsPath -Value $entry

    Write-Output "Entry added: $ip $hostname"

}

# --- Begin Script Logic ---

Clear-Host

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Check for elevated user session, elevate if needed and restart script execution ---

$pspath = (Get-Process -Id $PID).Path

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process $pspath -Verb runAs -ArgumentList '-NoExit', '-ExecutionPolicy RemoteSigned', '-Command', "& {Invoke-WebRequest 'https://agho.me/provision' -UseBasicParsing | Invoke-Expression}"
    Stop-Process -Id $PID
}

$output = Initialize-Log

$computer = $env:COMPUTERNAME
$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
$ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
$bootVolume = [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB, 2)

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
 - Configuration Manager tasks
 - Install Dell system updates
 - Create a local user account
 - Disable sleep on AC
 - Remove temporary files

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

# --- Retrieve user input and launch selection window upon confirmation ---

while (($i = Read-Host " Press Y to continue or N to quit") -notmatch '^[YyNn]$') {}
if ($i -notmatch '^[Yy]$') { exit }

Add-Type -AssemblyName PresentationFramework

# --- Build XAML for task selection GUI ---

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Quick Utilities Script v1.0"
        Height="360" Width="420"
        Background="#f2f5f7"
        WindowStartupLocation="CenterScreen"
        WindowStyle="SingleBorderWindow"
        ResizeMode="NoResize"
        FontFamily="Segoe UI">

    <Grid Margin="15" >
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>    <!-- Title Section -->
            <RowDefinition Height="*"/>       <!-- Options Section -->
            <RowDefinition Height="Auto"/>    <!-- Button Controls -->
        </Grid.RowDefinitions>

        <!-- Title Section -->
        <StackPanel Grid.Row="0" Margin="0 0 0 15" HorizontalAlignment="Center">
            <TextBlock Text="Actions Available"
                       FontSize="16"
                       FontWeight="Bold"
                       Foreground="#0078d7"
                       HorizontalAlignment="Center"/>
            <TextBlock Text="Choose the actions you want to perform:"
                       FontSize="12"
                       FontStyle="Italic"
                       Foreground="#2b2b2b"
                       Margin="0 5 0 0"
                       HorizontalAlignment="Center"/>
        </StackPanel>

        <!-- Options inside Border box -->
        <Border Grid.Row="1"
                Margin="10,0,10,0"
                Padding="10"
                BorderBrush="#0078d7"
                BorderThickness="2"
                Background="White"
                CornerRadius="4">
            <StackPanel>
                <CheckBox Name="cbGP"
                          Content=" Update Group Policy"
                          Margin="5"
                          ToolTip="Run gpupdate to refresh computer policies."/>
                
                <CheckBox Name="cbCM"
                          Content=" Configuration Manager tasks"
                          Margin="5"
                          ToolTip="Initiate software/hardware inventory and application deployments."/>
         
                <CheckBox Name="cbDell"
                          Content=" Install Dell system updates"
                          Margin="5"
                          ToolTip="Run Dell Command to check for BIOS, driver, and firmware updates."/>
         
                <CheckBox Name="cbUser"
                          Content=" Create a local user account"
                          Margin="5"
                          ToolTip="Add a new local account for non-domain access."/>
                
                <CheckBox Name="cbPowerSettings"
                          Content=" Disable sleep on AC power"
                          Margin="5"
                          ToolTip="Prevent system from entering sleep mode while plugged in."/>

                <CheckBox Name="cbTempFiles"
                          Content=" Remove temporary files"
                          Margin="5"
                          ToolTip="Clear temporary files from Windows directory."/>
                <CheckBox Name="cbEditHosts"
                          Content=" Update local hosts file"
                          Margin="5"
                          ToolTip="Add local hosts file entry for DNS resolution."/>
            </StackPanel>
        </Border>

        <!-- Button Controls -->
        <StackPanel Grid.Row="2"
                    Orientation="Horizontal"
                    HorizontalAlignment="Right"
                    Margin="0,20,0,0">
            <Button Name="btnOK"
                    Width="90"
                    Height="28"
                    Margin="5"
                    IsDefault="True"
                    Background="#0078d7"
                    Foreground="White"
                    FontWeight="SemiBold"
                    BorderBrush="#005a9e">
                Proceed
            </Button>
            <Button Width="90"
                    Height="28"
                    Margin="5"
                    IsCancel="True"
                    Background="#cccccc"
                    Foreground="Black"
                    BorderBrush="#999999">
                Cancel
            </Button>
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

" " | Out-File -FilePath $output -Encoding utf8 -Append
"Script execution complete." | Out-File -FilePath $output -Encoding utf8 -Append
Write-Host "Script execution complete. See:"
Write-Host "$output" -Foregroundcolor Gray

Start-Sleep 1