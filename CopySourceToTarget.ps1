param (
    [Parameter(Mandatory=$true)]
    [Array]$JobList
)

# Global breakdown for summary
$globalTotalByExt = @{}
$globalCopiedByExt = @{}

function Get-ValidConsoleColor {
    param(
        [string]$color,
        [string]$fallback = "White"
    )
    if ([string]::IsNullOrWhiteSpace($color)) { return $fallback }
    if ([System.Enum]::GetNames([System.ConsoleColor]) -contains $color) { return $color }
    return $fallback
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
    Write-Host "`r[$bar] $percent% | $etaStr | $shortName".PadRight(100) -ForegroundColor $fgColor
}

function Get-Ext($path) {
    $ext = [System.IO.Path]::GetExtension($path)
    if (-not $ext) { $ext = "" }
    return $ext.ToLower()
}

$extColors = @{
    ".txt" = "Yellow"; ".ps1" = "Cyan"; ".exe" = "Magenta"
    ".jpg" = "Green"; ".jpeg" = "Green"; ".png" = "Green"
    ".gif" = "DarkGreen"; ".bmp" = "DarkGreen"
    ".zip" = "DarkYellow"; ".rar" = "DarkYellow"; ".7z" = "DarkYellow"
    ".pdf" = "Blue"; ".doc" = "DarkBlue"; ".docx" = "DarkBlue"
    ".xls" = "DarkCyan"; ".xlsx" = "DarkCyan"
    ".ppt" = "DarkMagenta"; ".pptx" = "DarkMagenta"
    ".csv" = "DarkGray"; ".mp3" = "Magenta"; ".wav" = "Magenta"
    ".mp4" = "DarkYellow"; ".mkv" = "DarkYellow"
    ".html" = "White"; ".css" = "White"; ".js" = "Yellow"
    ".json" = "Yellow"; ".xml" = "DarkCyan"; ".dll" = "DarkMagenta"; ".sys" = "DarkRed"
}

foreach ($job in $JobList) {
    $Source = $job.Source
    $Target = $job.Target

    Write-Host "`n`n🚀 Copying: $Source → $Target" -ForegroundColor DarkGreen

    $errorLog = Join-Path $Source "robocopy_errors.log"
    $copiedLog = Join-Path $Source "robocopy_copied_files.log"
    $tempLog = Join-Path $env:TEMP "robocopy_temp.log"

    foreach ($log in @($errorLog, $copiedLog, $tempLog)) {
        if (Test-Path $log) { Remove-Item $log }
    }

    $directories = Get-ChildItem -Path $Source -Directory -Recurse
    $total = $directories.Count
    $startTime = Get-Date
    $done = 0

    foreach ($dir in $directories) {
        $relPath = $dir.FullName.Substring($Source.Length).TrimStart('\')
        $destDir = Join-Path $Target $relPath

        try {
            robocopy $dir.FullName $destDir /E /COPYALL /DCOPY:T /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /LOG:$tempLog > $null

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

            $done++
            $elapsed = (Get-Date) - $startTime
            $eta = [TimeSpan]::FromSeconds((($elapsed.TotalSeconds / $done) * ($total - $done)))
            $anyFile = Get-ChildItem -Path $dir.FullName -File -ErrorAction SilentlyContinue | Select-Object -First 1
            $ext = if ($anyFile) { [System.IO.Path]::GetExtension($anyFile.Name).ToLower() } else { "" }
            $fg = Get-ValidConsoleColor $extColors[$ext] "White"
            $displayName = if ($anyFile) { $anyFile.Name } else { $relPath }

            Show-ProgressBar -current $done -total $total -filename $displayName -eta $eta -fgColor $fg
        } catch {
            Add-Content -Path $errorLog -Value "Error copying $($dir.FullName): $($_.Exception.Message)"
            Write-Host "`nError copying $relPath" -ForegroundColor Red
            Write-Host "$($_.Exception.Message)"
        }
    }

    Remove-Item $tempLog -ErrorAction SilentlyContinue

    # === Breakdown ===
    $allSourceFiles = Get-ChildItem -Path $Source -Recurse -File -Force
    $totalByExt = @{}
    foreach ($file in $allSourceFiles) {
        $ext = Get-Ext $file.Name
        if ($totalByExt.ContainsKey($ext)) {
            $totalByExt[$ext] += 1
        } else {
            $totalByExt[$ext] = 1
        }
        if ($globalTotalByExt.ContainsKey($ext)) {
            $globalTotalByExt[$ext] += 1
        } else {
            $globalTotalByExt[$ext] = 1
        }
    }

    $copiedByExt = @{}
    if (Test-Path $copiedLog) {
        Get-Content -Path $copiedLog | ForEach-Object {
            $ext = Get-Ext $_
            if ($copiedByExt.ContainsKey($ext)) {
                $copiedByExt[$ext] += 1
            } else {
                $copiedByExt[$ext] = 1
            }
            if ($globalCopiedByExt.ContainsKey($ext)) {
                $globalCopiedByExt[$ext] += 1
            } else {
                $globalCopiedByExt[$ext] = 1
            }
        }
    }

    Write-Host "`n✅ Robocopy completed for: $Source" -ForegroundColor Green
    if (Test-Path $copiedLog) {
        Write-Host "📄 Copied files: $copiedLog" -ForegroundColor Yellow
    }
    if (Test-Path $errorLog) {
        Write-Host "⚠️ Errors: $errorLog" -ForegroundColor Red
    }
}

# === Global Summary ===
Write-Host "`n📊 Combined Extension Summary:" -ForegroundColor Cyan
$allExts = ($globalTotalByExt.Keys + $globalCopiedByExt.Keys) | Sort-Object -Unique
foreach ($ext in $allExts) {
    $copied = if ($globalCopiedByExt.ContainsKey($ext)) { $globalCopiedByExt[$ext] } else { 0 }
    $total = if ($globalTotalByExt.ContainsKey($ext)) { $globalTotalByExt[$ext] } else { 0 }
    $skipped = $total - $copied
    $label = if ($ext -ne "") { $ext } else { "[no ext]" }

    $line = "{0,-10} Copied: {1,6}    Skipped: {2,6}" -f $label, $copied, $skipped
    Write-Host " - $line" -ForegroundColor Gray
}

Write-Host "`n🎉 All backup jobs completed!" -ForegroundColor Green
