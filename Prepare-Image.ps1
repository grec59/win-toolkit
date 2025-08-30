<#
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
        Write-Host "SUCCESS: Created new user: $username"
        "SUCCESS: Created new local user account: $username" | Out-File -FilePath $output -Encoding utf8 -Append
    } catch {
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

    # Define the actions as PSCustomObjects
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

    # Build XAML
    $xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' Title='Select ConfigMgr Actions' Height='Auto' Width='400' SizeToContent='Height' WindowStartupLocation='CenterScreen'>
  <StackPanel Margin='10'>
    <TextBlock FontWeight='Bold' Margin='0 0 0 10'>Choose actions to perform:</TextBlock>
    <Button Name='btnSelectAll' Width='100' Margin='0 0 0 10'>Select All</Button>
    <ItemsControl Name='icActions'>
      <ItemsControl.ItemTemplate>
        <DataTemplate>
          <CheckBox Content='{Binding Name}' IsChecked='{Binding IsChecked, Mode=TwoWay}' />
        </DataTemplate>
      </ItemsControl.ItemTemplate>
    </ItemsControl>
    <StackPanel Orientation='Horizontal' HorizontalAlignment='Right' Margin='0 15 0 0'>
      <Button Name='btnOK' Width='75' Margin='5' IsDefault='True'>Proceed</Button>
      <Button Width='75' Margin='5' IsCancel='True'>Cancel</Button>
    </StackPanel>
  </StackPanel>
</Window>
"@

    $reader = (New-Object System.Xml.XmlNodeReader ([xml]$xaml))
    $win = [Windows.Markup.XamlReader]::Load($reader)

    # Bind the actions
    $ic = $win.FindName('icActions')
    $ic.ItemsSource = $actionsList

    # Select All button
    $btnSelectAll = $win.FindName('btnSelectAll')
    $btnSelectAll.Add_Click({
        foreach ($item in $actionsList) { $item.IsChecked = $true }
        $ic.Items.Refresh()  # Refresh to show changes
    })

    # Proceed button
    $btnOK = $win.FindName('btnOK')
    $btnOK.Add_Click({
        $win.Tag = $actionsList | Where-Object { $_.IsChecked }
        $win.Close()
    })

    $win.Topmost = $true
    $win.ShowDialog() | Out-Null

    $chosen = $win.Tag
    if (-not $chosen) { return }

    # Execute selected actions
    foreach ($action in $chosen) {
        try {
            Invoke-WmiMethod -Namespace root\ccm -Class SMS_CLIENT -Name TriggerSchedule -ArgumentList $action.Guid -ErrorAction Stop | Out-Null
            Write-Host "SUCCESS: $($action.Name)" -ForegroundColor Green
            "SUCCESS: $($action.Name)" | Out-File -FilePath $output -Encoding utf8 -Append
        } catch {
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

while (($i = Read-Host " Press Y to continue or N to quit") -notmatch '^[YyNn]$') {}
if ($i -notmatch '^[Yy]$') { exit }

# --- Build GUI ---

Add-Type -AssemblyName PresentationFramework

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="System Maintenance Tool"
        Height="540" Width="550"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResize"
        MinWidth="550" MaxWidth="550"
        MinHeight="500" MaxHeight="720"
        Background="#f4f6f9"
        FontFamily="Segoe UI">
  <Window.Resources>
    <Style TargetType="ToolTip">
      <Setter Property="ToolTipService.InitialShowDelay" Value="400"/>
      <Setter Property="ToolTipService.BetweenShowDelay" Value="0"/>
      <Setter Property="ToolTipService.ShowDuration" Value="8000"/>
    </Style>
  </Window.Resources>
  <Grid Margin="15">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <!-- Header -->
    <StackPanel Grid.Row="0" Margin="0 0 0 15">
      <TextBlock Text="System Maintenance Actions" 
                 FontWeight="Bold" FontSize="16" 
                 Foreground="DarkBlue"
                 HorizontalAlignment="Center"/>
      <TextBlock Text="Select one or more actions to perform:" 
                 FontStyle="Italic"
                 Foreground="Gray"
                 HorizontalAlignment="Center"
                 Margin="0 5 0 0"/>
    </StackPanel>
    <!-- Options + Progress -->
    <StackPanel Grid.Row="1">
      <GroupBox Header="Available Actions" FontWeight="SemiBold" Margin="0 0 0 10">
        <StackPanel Margin="12">
          <CheckBox Name="cbGP" Content=" Update Group Policy" Margin="5"
                    ToolTip="Force a Group Policy update for computer and user settings."/>
          <CheckBox Name="cbCM" Content=" Run Configuration Manager Tasks" Margin="5"
                    ToolTip="Synchronize SCCM client actions like inventory and application scan."/>
          <CheckBox Name="cbDell" Content=" Install Dell System Updates" Margin="5"
                    ToolTip="Run Dell Command Update to install BIOS, driver, and firmware updates."/>
          <CheckBox Name="cbUser" Content=" Create Local User Account" Margin="5"
                    ToolTip="Create a new local user account for troubleshooting or configuration."/>
          <CheckBox Name="cbPowerSettings" Content=" Disable Sleep on AC Power" Margin="5"
                    ToolTip="Prevents the machine from entering sleep mode while plugged in."/>
        </StackPanel>
      </GroupBox>
      <!-- Progress Area -->
      <GroupBox Header="Execution Progress" FontWeight="SemiBold">
        <StackPanel Margin="12">
          <ProgressBar Name="pbProgress" Height="20" Minimum="0" Maximum="100" Foreground="#0078d7"/>
          <TextBlock Name="lblStatus" Text="Waiting for user input..." Margin="0 5 0 10" Foreground="DimGray"/>
          <TextBox Name="txtLog" Height="180" 
                   VerticalScrollBarVisibility="Auto" 
                   IsReadOnly="True"
                   Background="WhiteSmoke"
                   Foreground="Black"
                   FontFamily="Consolas"
                   TextWrapping="Wrap"/>
        </StackPanel>
      </GroupBox>
    </StackPanel>
    <!-- Buttons -->
    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0 15 0 5">
      <Button Name="btnOK" Width="90" Height="30" Margin="5" IsDefault="True" IsEnabled="False"
              Background="#0078d7" Foreground="White" FontWeight="SemiBold" BorderBrush="#005a9e">
        Proceed
      </Button>
      <Button Name="btnCancel" Width="90" Height="30" Margin="5" IsCancel="True"
              Background="#cccccc" Foreground="Black" BorderBrush="#999999">
        Cancel
      </Button>
    </StackPanel>
    <!-- Footer / Version Banner (bound dynamically later) -->
    <TextBlock Name="txtFooter" Grid.Row="3"
               HorizontalAlignment="Right"
               Foreground="Gray"
               FontSize="11"
               Margin="0,5,0,0"/>
  </Grid>
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
$win.Activate() | out-null
$win.ShowDialog() | out-null
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

if ($sel.PowerConfig) {
    Disable-Sleep
}

" " | Out-File -FilePath $output -Encoding utf8 -Append
"Script execution complete." | Out-File -FilePath $output -Encoding utf8 -Append
Write-Host "Script execution complete. See:"
Write-Host "$output" -Foregroundcolor Gray
Start-Sleep 2