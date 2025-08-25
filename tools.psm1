function Remove-TempFiles {

    $temp = 'C:\Windows\Temp\'
    Write-Host "Removing temporary Files from $temp"
    $itemsremoved = (Get-ChildItem $temp | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue; $_ } catch {} }).Count
    Write-Host "Removed $itemsremoved temporary file(s) from $temp"

}

function Schedule-DiskCheck {

    $drives = Get-Disk | ForEach-Object { $partition=Get-Partition -DiskNumber $_.Number | Where-Object IsBoot; if($partition){$partition.DriveLetter} }
    if ($drives) {
        Write-Host "Schedule CHKDSK on $($drives -join ', ')?"
        while(($i = Read-Host "Press Y to continue or N to quit") -notmatch '^[YyNn]$') {}
        if ($i -match '^[Yy]$') {
            foreach ($d in $drives) {
                chkdsk "${d}:" /F /R /X
            }
        } else { Write-Host "Operation cancelled." }
    } else { Write-Host "No boot disks found." }

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
            Write-Log "Triggered ConfigMgr action: $($action.Name)" -Level SUCCESS
        } catch {
            Write-Log "Failed ConfigMgr action: $($action.Name) -> $($_.Exception.Message)" -Level FAIL
        }
        Start-Sleep -Seconds 2
    }
}

