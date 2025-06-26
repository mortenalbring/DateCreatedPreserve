# === CONFIGURATION ===
$source = "D:\Files\13-10 Coding Projects\PreserveDateCreated\TestSourceFiles\"
$target = "D:\Files\13-10 Coding Projects\PreserveDateCreated\TestDestinationFiles\"
$outputCSV = Join-Path $source "creation_dates.csv"
$errorLog = Join-Path $source "timestamp_restore_errors.log"

# === STEP 1: COPY FILES WITH PROGRESS ===
$files = Get-ChildItem -Path $source -Recurse -File
$totalSize = ($files | Measure-Object Length -Sum).Sum
$bytesCopied = 0

Write-Host "`n=== Copying files with progress tracking... ===`n"

foreach ($file in $files) {
    $relPath = $file.FullName.Substring($source.Length).TrimStart('\')
    $destPath = Join-Path $target $relPath

    # Ensure destination folder exists
    $destFolder = Split-Path $destPath -Parent
    if (!(Test-Path $destFolder)) {
        New-Item -ItemType Directory -Path $destFolder -Force | Out-Null
    }

    # Use robocopy to copy the individual file
    robocopy (Split-Path $file.FullName) $destFolder $file.Name /NFL /NDL /NJH /NJS > $null

    $bytesCopied += $file.Length
    $percent = [math]::Round(($bytesCopied / $totalSize) * 100, 2)
    Write-Host ("{0,6}% complete - {1}" -f $percent, $file.Name)
}

# === STEP 2: EXPORT ORIGINAL CREATION TIMES ===
Write-Host "`n=== Exporting original creation timestamps... ===`n"

Get-ChildItem -Path $source -Recurse -Force | ForEach-Object {
    [PSCustomObject]@{
        FullPath     = $_.FullName
        CreationTime = $_.CreationTimeUtc
        IsDirectory  = $_.PSIsContainer
    }
} | Export-Csv -Path $outputCSV -NoTypeInformation -Encoding UTF8

# === STEP 3: RESTORE CREATION TIMES ===
Write-Host "`n=== Restoring creation timestamps... ===`n"

# Clear old error log
if (Test-Path $errorLog) { Remove-Item $errorLog }

$timestampData = Import-Csv -Path $outputCSV

foreach ($entry in $timestampData) {
    try {
        $relativePath = $entry.FullPath.Substring($source.Length).TrimStart('\')
        $destPath = Join-Path $target $relativePath

        if (Test-Path $destPath) {
            $item = Get-Item -LiteralPath $destPath -Force
            $item.CreationTimeUtc = [datetime]::Parse($entry.CreationTime)
        } else {
            Add-Content -Path $errorLog -Value "Missing: $destPath"
        }
    } catch {
        Add-Content -Path $errorLog -Value "Error setting timestamp: $destPath - $_"
    }
}

# === STEP 4: RESTORE DIRECTORY CREATION TIMES ===
Write-Host "`n=== Restoring directory creation timestamps... ===`n"

$directories = $timestampData | Where-Object { $_.IsDirectory -eq 'True' }

foreach ($dirEntry in $directories) {
    try {
        $relativePath = $dirEntry.FullPath.Substring($source.Length).TrimStart('\')
        $destDirPath = Join-Path $target $relativePath

        if (Test-Path $destDirPath) {
            (Get-Item -LiteralPath $destDirPath -Force).CreationTimeUtc = [datetime]::Parse($dirEntry.CreationTime)
        } else {
            Add-Content -Path $errorLog -Value "Missing Directory: $destDirPath"
        }
    } catch {
        Add-Content -Path $errorLog -Value "Error restoring dir timestamp: $destDirPath - $_"
    }
}

# === DONE ===
Write-Host "`n✅ All done. If any errors occurred, check: $errorLog"
