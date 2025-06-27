# === CONFIGURATION ===
$source = "D:\Files"
$target = "T:\10-19 Grace\13 Files"
$errorLog = Join-Path $source "timestamp_restore_errors.log"

# Clear previous error log
if (Test-Path $errorLog) { Remove-Item $errorLog }

# === STEP 1: COPY FILES AND PRESERVE CREATION TIME ===
$files = Get-ChildItem -Path $source -Recurse -File -Force
$totalFiles = $files.Count
$filesCopied = 0
$startTime = Get-Date

Write-Host "`n=== Copying files with Copy-Item and restoring creation timestamps... ===`n"

foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($source.Length).TrimStart('\')
    $destPath = Join-Path $target $relativePath
    $destFolder = Split-Path $destPath -Parent

    if (Test-Path $destPath) {
        $destItem = Get-Item -LiteralPath $destPath -Force
        if ($destItem.Length -eq $file.Length -and $destItem.LastWriteTimeUtc -eq $file.LastWriteTimeUtc) {
            # Skip the file (already exists, same size and last modified)
            $filesCopied++
            $percent = [math]::Round(($filesCopied / $totalFiles) * 100, 2)

            $elapsed = (Get-Date) - $startTime
            $avgTimePerFile = $elapsed.TotalSeconds / $filesCopied
            $remainingSeconds = ($totalFiles - $filesCopied) * $avgTimePerFile
            $timeRemaining = [TimeSpan]::FromSeconds($remainingSeconds)

            Write-Host ("{0,6}% complete | Time remaining: {1} | Skipped: {2}" -f $percent, $timeRemaining.ToString("hh\:mm\:ss"), $file.Name)
            continue
        }
    }

    if (!(Test-Path $destFolder)) {
        New-Item -ItemType Directory -Path $destFolder -Force | Out-Null
    }

    try {
        Copy-Item -LiteralPath $file.FullName -Destination $destPath -Force
        (Get-Item -LiteralPath $destPath -Force).CreationTimeUtc = $file.CreationTimeUtc
    } catch {
        Add-Content -Path $errorLog -Value "Copy or timestamp error: $destPath - $_"
    }

    # Progress tracking
    $filesCopied++
    $percent = [math]::Round(($filesCopied / $totalFiles) * 100, 2)

    $elapsed = (Get-Date) - $startTime
    $avgTimePerFile = $elapsed.TotalSeconds / $filesCopied
    $remainingSeconds = ($totalFiles - $filesCopied) * $avgTimePerFile
    $timeRemaining = [TimeSpan]::FromSeconds($remainingSeconds)

    Write-Host ("{0,6}% complete | Time remaining: {1} | {2}" -f $percent, $timeRemaining.ToString("hh\:mm\:ss"), $file.Name)
}

# === STEP 2: RESTORE DIRECTORY CREATION TIMESTAMPS ===
Write-Host "`n=== Restoring directory creation timestamps... ===`n"

$directories = Get-ChildItem -Path $source -Recurse -Directory -Force

foreach ($dir in $directories) {
    $relativePath = $dir.FullName.Substring($source.Length).TrimStart('\')
    $destDirPath = Join-Path $target $relativePath

    if (Test-Path $destDirPath) {
        try {
            (Get-Item -LiteralPath $destDirPath -Force).CreationTimeUtc = $dir.CreationTimeUtc
        } catch {
            Add-Content -Path $errorLog -Value "Failed to set creation time on directory: $destDirPath - $_"
        }
    } else {
        Add-Content -Path $errorLog -Value "Directory missing after copy: $destDirPath"
    }
}

# === DONE ===
Write-Host "`n✅ All done!"
if (Test-Path $errorLog) {
    Write-Host "⚠️ Errors were logged to: $errorLog"
} else {
    Write-Host "🎉 No errors encountered."
}
