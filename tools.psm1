function Remove-TempFiles {

    $temp = 'C:\Windows\Temp\'
    Write-Host "Removing temporary files from $temp..."
    $itemsremoved = (Get-ChildItem $temp | ForEach-Object { try { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue; $_ } catch {} }).Count
    Write-Host "Removed $itemsremoved temporary files."

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