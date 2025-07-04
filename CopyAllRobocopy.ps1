# === CONFIGURATION ===
$source = "D:\Files"
$target = "T:\10-19 Grace\13 Files"
$errorLog = Join-Path $source "robocopy_errors.log"
$copiedLog = Join-Path $source "robocopy_copied_files.log"
$tempLog = Join-Path $env:TEMP "robocopy_temp.log"

# Clear logs
foreach ($log in @($errorLog, $copiedLog, $tempLog)) {
    if (Test-Path $log) { Remove-Item $log }
}

# Extension to foreground color map
$extColors = @{
    ".txt"   = "Yellow"; ".ps1"  = "Cyan"; ".exe"  = "Magenta"
    ".jpg"   = "Green";  ".jpeg" = "Green"; ".png"  = "Green"
    ".gif"   = "DarkGreen"; ".bmp" = "DarkGreen"
    ".zip"   = "DarkYellow"; ".rar" = "DarkYellow"; ".7z" = "DarkYellow"
    ".pdf"   = "Blue";   ".doc" = "DarkBlue"; ".docx" = "DarkBlue"
    ".xls"   = "DarkCyan"; ".xlsx" = "DarkCyan"
    ".ppt"   = "DarkMagenta"; ".pptx" = "DarkMagenta"
    ".csv"   = "DarkGray"; ".mp3" = "Magenta"; ".wav" = "Magenta"
    ".mp4"   = "Red"; ".mkv" = "Red"
    ".html"  = "White"; ".css" = "White"; ".js" = "Yellow"
    ".json"  = "Yellow"; ".xml" = "DarkCyan"; ".dll" = "DarkMagenta"; ".sys" = "DarkRed"
}

function Show-ProgressBar {
    param([int]$current, [int]$total)
    $percent = [math]::Round(($current / $total) * 100)
    $width = 30
    $filled = [int]($width * $percent / 100)
    $bar = ('#' * $filled).PadRight($width, '-')
    Write-Host "`r[$bar] $percent% complete" -NoNewline
}

# === GET FOLDERS ===
$directories = Get-ChildItem -Path $source -Directory -Recurse
$total = $directories.Count
$startTime = Get-Date
$done = 0

foreach ($dir in $directories) {
    $relPath = $dir.FullName.Substring($source.Length).TrimStart('\')
    $destDir = Join-Path $target $relPath

    try {
        # Run robocopy and log output to temp log
        robocopy $dir.FullName $destDir /E /COPYALL /DCOPY:T /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /LOG:$tempLog > $null

        # Parse copied files from log
        $copiedLines = Select-String -Path $tempLog -Pattern '^\s+New File|\s+Newer|\s+Extra File' | ForEach-Object { $_.Line.Trim() }

        foreach ($line in $copiedLines) {
            try {
                # Extract relative path
                $relFile = $line -replace "^\s*(New File|Newer|Extra File)\s+", ''
                $srcFile = Join-Path $dir.FullName $relFile
                $dstFile = Join-Path $destDir $relFile

                # Set DateCreated to match original
                if (Test-Path $srcFile -and Test-Path $dstFile) {
                    $src = Get-Item -LiteralPath $srcFile -Force
                    $dst = Get-Item -LiteralPath $dstFile -Force
                    $dst.CreationTimeUtc = $src.CreationTimeUtc
                }

                # Log copied file
                Add-Content -Path $copiedLog -Value $relFile
            } catch {
                Add-Content -Path $errorLog -Value "Failed to set creation time: $relFile - $($_.Exception.Message)"
            }
        }

        # After copying files, sync folder creation times
        $sourceFolders = Get-ChildItem -Path $dir.FullName -Directory -Recurse -Force
        foreach ($sf in $sourceFolders) {
            $relative = $sf.FullName.Substring($dir.FullName.Length).TrimStart('\')
            $dfPath = Join-Path $destDir $relative

            if (Test-Path $dfPath) {
                try {
                    $destFolder = Get-Item -LiteralPath $dfPath -Force
                    $destFolder.CreationTimeUtc = $sf.CreationTimeUtc
                } catch {
                    Add-Content -Path $errorLog -Value "Failed to set creation time on folder: $dfPath - $($_.Exception.Message)"
                }
            }
        }

        # Visual output
        $done++
        $elapsed = (Get-Date) - $startTime
        $eta = [TimeSpan]::FromSeconds((($elapsed.TotalSeconds / $done) * ($total - $done)))

        $anyFile = Get-ChildItem -Path $dir.FullName -File -ErrorAction SilentlyContinue | Select-Object -First 1
        $fg = if ($anyFile) {
            $ext = [System.IO.Path]::GetExtension($anyFile.Name).ToLower()
            $extColors[$ext] ?? "White"
        } else {
            "White"
        }

        Write-Host "`nTime left: $($eta.ToString('hh\:mm\:ss')) | " -ForegroundColor White -BackgroundColor DarkBlue -NoNewline
        Write-Host $relPath -ForegroundColor $fg
        Show-ProgressBar -current $done -total $total
    }
    catch {
        Add-Content -Path $errorLog -Value "Error copying $($dir.FullName): $($_.Exception.Message)"
        Write-Host "`nError copying $relPath" -ForegroundColor Red
    }
}

Remove-Item $tempLog -ErrorAction SilentlyContinue

Write-Host "`n✅ Robocopy batch complete!" -ForegroundColor Green
if (Test-Path $copiedLog) {
    Write-Host "📄 Copied files logged in: $copiedLog" -ForegroundColor Yellow
}
if (Test-Path $errorLog) {
    Write-Host "⚠️ Errors occurred. See: $errorLog" -ForegroundColor Red
}
