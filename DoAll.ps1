# === CONFIGURATION ===
$source = "D:\Files"
$target = "T:\10-19 Grace\13 Files"
$errorLog = Join-Path $source "timestamp_restore_errors.log"

# Clear previous error log
if (Test-Path $errorLog) { Remove-Item $errorLog }

# === STEP 1: COPY FILES AND PRESERVE TIMESTAMPS ===
$files = Get-ChildItem -Path $source -Recurse -File -Force
$totalFiles = $files.Count
$filesCopied = 0
$startTime = Get-Date

Write-Host "`n=== Copying files with inline creation timestamp restoration (ETA by file count)... ===`n"

foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($source.Length).TrimStart('\')
    $destPath = Join-Path $target $relativePath
    $destFolder = Split-Path $destPath -Parent

    if (!(Test-Path $destFolder)) {
        New-Item -ItemType Directory -Path $destFolder -Force | Out-Null
    }

    $originalCreationTime = $file.CreationTimeUtc

    # Copy file using robocopy
    robocopy (Split-Path $file.FullName) $destFolder $file.Name /NFL /NDL /NJH /NJS > $null

    if (Test-Path $destPath) {
        try {
            (Get-Item -LiteralPath $destPath -Force).CreationTimeUtc = $originalCreationTime
        } catch {
            Add-Content -Path $errorLog -Value "Failed to set creation time on file: $destPath - $_"
        }
    } else {
        Add-Content -Path $errorLog -Value "File missing after copy: $destPath"
    }

    $filesCopied++
    $percent = [math]::Round(($filesCopied / $totalFiles) * 100, 2)

    # ETA calculation by file count
    $elapsed = (Get-Date) - $startTime
    $avgTimePerFile = $elapsed.TotalSeconds / $filesCopied
    $remainingSeconds = ($totalFiles - $filesCopied) * $avgTimePerFile
    $eta = [TimeSpan]::FromSeconds($remainingSeconds)

    Write-Host ("{0,6}% complete - {1} | ETA: {2}" -f $percent, $file.Name, $eta.ToString("hh\:mm\:ss"))
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
