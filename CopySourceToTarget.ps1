param (
    [Parameter(Mandatory = $true)]
    [string]$JobListJsonPath
)

if (-not (Test-Path $JobListJsonPath)) {
    Write-Error "Job list JSON file not found: $JobListJsonPath"
    exit 1
}

# Read job list JSON (expecting array of objects with Source and Target strings)
$jobList = Get-Content -Path $JobListJsonPath -Raw | ConvertFrom-Json

if (-not $jobList -or $jobList.Count -eq 0) {
    Write-Error "Job list JSON is empty or invalid."
    exit 1
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
    ".mp4"   = "DarkYellow"; ".mkv" = "DarkYellow"
    ".html"  = "White"; ".css" = "White"; ".js" = "Yellow"
    ".json"  = "Yellow"; ".xml" = "DarkCyan"; ".dll" = "DarkMagenta"; ".sys" = "DarkRed"
}

function Get-ValidConsoleColor {
    param(
        [string]$color,
        [string]$fallback = "White"
    )
    if ([string]::IsNullOrWhiteSpace($color)) { return $fallback }
    if ([System.Enum]::GetNames([System.ConsoleColor]) -contains $color) { return $color }
    else { return $fallback }
}

function Show-ProgressBar {
    param(
        [int]$current,
        [int]$total,
        [string]$filename,
        [TimeSpan]$eta,
        [string]$fgColor = "White"
    )
    $percent = [math]::Round(($current / $total) * 100)
    $width = 30
    $filled = [int]($width * $percent / 100)
    $bar = ('#' * $filled).PadRight($width, '-')
    $shortName = [System.IO.Path]::GetFileName($filename)
    $etaStr = $eta.ToString("hh\:mm\:ss")
    Write-Host "`r[$bar] $percent% | $etaStr | $shortName".PadRight(100) -ForegroundColor $fgColor -NoNewline
}

function Get-Ext {
    param ($path)
    $ext = [System.IO.Path]::GetExtension($path)
    if (-not $ext) { $ext = "" }
    return $ext.ToLower()
}

# Initialize global stats hashtables
$totalByExtGlobal = @{}
$copiedByExtGlobal = @{}
$errorLogGlobal = Join-Path $env:TEMP "robocopy_all_errors.log"
$copiedLogGlobal = Join-Path $env:TEMP "robocopy_all_copied_files.log"

# Clear global logs
foreach ($log in @($errorLogGlobal, $copiedLogGlobal)) {
    if (Test-Path $log) { Remove-Item $log }
}

foreach ($jobIndex in 0..($jobList.Count - 1)) {
    $job = $jobList[$jobIndex]

    if (-not $job.Source -or -not $job.Target) {
        Write-Warning "Job #$($jobIndex + 1) missing Source or Target, skipping."
        continue
    }

    Write-Host "`n=== Job $($jobIndex + 1) of $($jobList.Count): Copying from '$($job.Source)' to '$($job.Target)' ===`n" -ForegroundColor DarkGreen

    # Per-job logs (in source folder)
    $errorLog = Join-Path $job.Source "robocopy_errors.log"
    $copiedLog = Join-Path $job.Source "robocopy_copied_files.log"
    $tempLog = Join-Path $env:TEMP "robocopy_temp.log"

    # Clear per-job logs
    foreach ($log in @($errorLog, $copiedLog, $tempLog)) {
        if (Test-Path $log) { Remove-Item $log }
    }

    # Get all directories in source recursively
    $directories = Get-ChildItem -Path $job.Source -Directory -Recurse -ErrorAction SilentlyContinue
    $total = $directories.Count
    if ($total -eq 0) {
        Write-Warning "No directories found in source: $($job.Source)"
        continue
    }

    $startTime = Get-Date
    $done = 0

    foreach ($dir in $directories) {
        $relPath = $dir.FullName.Substring($job.Source.Length).TrimStart('\')
        $destDir = Join-Path $job.Target $relPath

        try {
            robocopy $dir.FullName $destDir /E /COPYALL /DCOPY:T /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /LOG:$tempLog > $null

            # Parse copied files from robocopy temp log
            $copiedLines = Select-String -Path $tempLog -Pattern '^\s+(New File|Newer|Extra File)' | ForEach-Object { $_.Line.Trim() }

            foreach ($line in $copiedLines) {
                try {
                    $relFile = $line -replace "^\s*(New File|Newer|Extra File)\s+", ''
                    $srcFile = Join-Path $dir.FullName $relFile
                    $dstFile = Join-Path $destDir $relFile

                    if (Test-Path $srcFile -PathType Leaf -and Test-Path $dstFile -PathType Leaf) {
                        $src = Get-Item -LiteralPath $srcFile -Force
                        $dst = Get-Item -LiteralPath $dstFile -Force
                        $dst.CreationTimeUtc = $src.CreationTimeUtc
                    }

                    Add-Content -Path $copiedLog -Value $relFile
                } catch {
                    Add-Content -Path $errorLog -Value "Failed to set creation time: $relFile - $($_.Exception.Message)"
                }
            }

            # Sync folder creation times
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

            # Progress output
            $done++
            $elapsed = (Get-Date) - $startTime
            $eta = [TimeSpan]::FromSeconds((($elapsed.TotalSeconds / $done) * ($total - $done)))

            $anyFile = Get-ChildItem -Path $dir.FullName -File -ErrorAction SilentlyContinue | Select-Object -First 1
            $ext = if ($anyFile) { [System.IO.Path]::GetExtension($anyFile.Name).ToLower() } else { "" }
            $fg = Get-ValidConsoleColor $extColors[$ext] "White"
            $displayName = if ($anyFile) { $anyFile.Name } else { $relPath }

            Show-ProgressBar -current $done -total $total -filename $displayName -eta $eta -fgColor $fg
        }
        catch {
            Add-Content -Path $errorLog -Value "Error copying $($dir.FullName): $($_.Exception.Message)"
            Write-Host "`nError copying $relPath" -ForegroundColor Red
            Write-Host "$($_.Exception.Message)"
        }
    }

    Remove-Item $tempLog -ErrorAction SilentlyContinue

    # Merge per-job copied log into global log
    if (Test-Path $copiedLog) {
        Get-Content $copiedLog | Add-Content -Path $copiedLogGlobal
    }
    # Merge per-job error log into global log
    if (Test-Path $errorLog) {
        Get-Content $errorLog | Add-Content -Path $errorLogGlobal
    }

    # Update global stats from source files
    $allSourceFiles = Get-ChildItem -Path $job.Source -Recurse -File -Force -ErrorAction SilentlyContinue
    foreach ($file in $allSourceFiles) {
        $ext = Get-Ext $file.Name
        if ($totalByExtGlobal.ContainsKey($ext)) {
            $totalByExtGlobal[$ext]++
        } else {
            $totalByExtGlobal[$ext] = 1
        }
    }

    # Update global stats from copied files (per job)
    if (Test-Path $copiedLog) {
        Get-Content -Path $copiedLog | ForEach-Object {
            $ext = Get-Ext $_
            if ($copiedByExtGlobal.ContainsKey($ext)) {
                $copiedByExtGlobal[$ext]++
            } else {
                $copiedByExtGlobal[$ext] = 1
            }
        }
    }

    Write-Host "`nCompleted job $($jobIndex + 1) of $($jobList.Count).`n"
}

# Output global summary breakdown
Write-Host "`n📂 Overall breakdown by extension:" -ForegroundColor Cyan
$allExtsGlobal = ($totalByExtGlobal.Keys + $copiedByExtGlobal.Keys) | Sort-Object -Unique
foreach ($ext in $allExtsGlobal) {
    $copied = if ($copiedByExtGlobal.ContainsKey($ext)) { $copiedByExtGlobal[$ext] } else { 0 }
    $total = if ($totalByExtGlobal.ContainsKey($ext)) { $totalByExtGlobal[$ext] } else { 0 }
    $skipped = $total - $copied
    $label = if ($ext -ne "") { $ext } else { "[no ext]" }

    $line = "{0,-10} Copied: {1,7}    Skipped: {2,7}" -f $label, $copied, $skipped
    Write-Host " - $line" -ForegroundColor Gray
}

Write-Host "`n`n✅ All robocopy jobs complete!" -ForegroundColor Green
if (Test-Path $copiedLogGlobal) {
    Write-Host "📄 All copied files logged in: $copiedLogGlobal" -ForegroundColor Yellow
}
if (Test-Path $errorLogGlobal) {
    Write-Host "⚠️ Errors occurred. See: $errorLogGlobal" -ForegroundColor Red
}
