# === CONFIGURATION ===
$source = "D:\Files"
$target = "T:\10-19 Grace\13 Files"
$errorLog = Join-Path $source "timestamp_restore_errors.log"
$progressLog = Join-Path $env:TEMP "backup_progress.tmp"

# Define extension-to-color mapping (lowercase extensions)
$extColors = @{
    ".txt"   = "Yellow"
    ".ps1"   = "Cyan"
    ".exe"   = "Magenta"
    ".jpg"   = "Green"
    ".jpeg"  = "Green"
    ".png"   = "Green"
    ".gif"   = "DarkGreen"
    ".bmp"   = "DarkGreen"
    ".zip"   = "DarkYellow"
    ".rar"   = "DarkYellow"
    ".7z"    = "DarkYellow"
    ".pdf"   = "Blue"
    ".doc"   = "DarkBlue"
    ".docx"  = "DarkBlue"
    ".xls"   = "DarkCyan"
    ".xlsx"  = "DarkCyan"
    ".ppt"   = "DarkMagenta"
    ".pptx"  = "DarkMagenta"
    ".csv"   = "DarkGray"
    ".mp3"   = "Magenta"
    ".wav"   = "Magenta"
    ".mp4"   = "Red"
    ".mkv"   = "Red"
    ".html"  = "White"
    ".css"   = "White"
    ".js"    = "Yellow"
    ".json"  = "Yellow"
    ".xml"   = "DarkCyan"
    ".dll"   = "DarkMagenta"
    ".sys"   = "DarkRed"
}

function Show-ProgressBar {
    param(
        [int]$percent,
        [int]$width = 30
    )
    $filled = [int]($width * $percent / 100)
    $empty = $width - $filled
    $bar = ('#' * $filled) + ('-' * $empty)
    $text = "[${bar}] $percent% complete"
    Write-Host "`r$text" -NoNewline
}

# === CLEANUP PREVIOUS LOGS ===
if (Test-Path $errorLog) { Remove-Item $errorLog }
if (Test-Path $progressLog) { Remove-Item $progressLog }

# === GATHER FILES ===
$files = Get-ChildItem -Path $source -Recurse -File -Force
$totalFiles = $files.Count
$startTime = Get-Date
$filesCopied = 0

foreach ($file in $files) {
    try {
        $relPath = $file.FullName.Substring($source.Length).TrimStart('\')
        $destPath = Join-Path $target $relPath
        $destFolder = Split-Path $destPath -Parent

        if (!(Test-Path $destFolder)) {
            New-Item -ItemType Directory -Path $destFolder -Force | Out-Null
        }

        $shouldCopy = $true
        if (Test-Path $destPath) {
            $destItem = Get-Item -LiteralPath $destPath -Force
            if ($destItem.Length -eq $file.Length -and $destItem.LastWriteTimeUtc -eq $file.LastWriteTimeUtc) {
                $shouldCopy = $false
            }
        }

        if ($shouldCopy) {
            Copy-Item -LiteralPath $file.FullName -Destination $destPath -Force
            (Get-Item -LiteralPath $destPath -Force).CreationTimeUtc = $file.CreationTimeUtc
        }

        $filesCopied++
        Add-Content -Path $progressLog -Value $file.FullName

        # Foreground color based on extension
        $ext = [IO.Path]::GetExtension($file.Name).ToLower()
        if ($extColors.ContainsKey($ext)) {
            $fgColor = $extColors[$ext]
        } else {
            $fgColor = "White"
        }

        # Background color based on size
        $sizeMB = $file.Length / 1MB
        if ($sizeMB -lt 1) {
            $bgColor = "Black"
        } elseif ($sizeMB -lt 100) {
            $bgColor = "DarkGray"
        } else {
            $bgColor = "DarkRed"
        }

        $percent = [math]::Round(($filesCopied / $totalFiles) * 100)
        $elapsed = (Get-Date) - $startTime
        $avgTimePerFile = $elapsed.TotalSeconds / $filesCopied
        $remainingSeconds = ($totalFiles - $filesCopied) * $avgTimePerFile
        $timeRemaining = [TimeSpan]::FromSeconds($remainingSeconds)

        # Print status line with foreground & background colors
        # Fixed background for "Time left: ..."
         Write-Host " | Time left: $($timeRemaining.ToString('hh\:mm\:ss')) | " -ForegroundColor White -BackgroundColor DarkBlue -NoNewline

            # Dynamic colors for filename
        Write-Host $file.Name -ForegroundColor $fgColor -BackgroundColor $bgColor


        # Update progress bar at bottom
        Show-ProgressBar -percent $percent

    } catch {
        $msg = "Error copying $($file.FullName): $($_.Exception.Message)"
        Add-Content -Path $errorLog -Value $msg
        Write-Host $msg -ForegroundColor Red
    }
}

# Move to new line after progress bar completes
Write-Host ""

# === RESTORE DIRECTORY CREATION DATES ===
Write-Host "`nRestoring directory creation timestamps..."

$directories = Get-ChildItem -Path $source -Recurse -Directory -Force
foreach ($dir in $directories) {
    $relativePath = $dir.FullName.Substring($source.Length).TrimStart('\')
    $destDirPath = Join-Path $target $relativePath

    if (Test-Path $destDirPath) {
        try {
            (Get-Item -LiteralPath $destDirPath -Force).CreationTimeUtc = $dir.CreationTimeUtc
        } catch {
            $msg = "Failed to set creation time on directory: $destDirPath - $_"
            Add-Content -Path $errorLog -Value $msg
            Write-Host $msg -ForegroundColor Red
        }
    } else {
        $msg = "Directory missing after copy: $destDirPath"
        Add-Content -Path $errorLog -Value $msg
        Write-Host $msg -ForegroundColor Red
    }
}

# === SUMMARY ===
Write-Host "`n✅ Backup complete!" -ForegroundColor Green

if (Test-Path $errorLog) {
    Write-Host "⚠️ Some errors occurred. See log: $errorLog" -ForegroundColor Red
} else {
    Write-Host "🎉 No errors encountered." -ForegroundColor Green
}
