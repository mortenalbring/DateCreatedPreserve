param (
    [Parameter(Mandatory=$true)]
    [string]$JobFile
)

# === Load jobs ===
$jobs = Get-Content $JobFile | ConvertFrom-Json

# === Setup color map ===
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

function Get-ValidConsoleColor {
    param([string]$color, [string]$fallback = "White")
    if ([System.Enum]::GetNames([System.ConsoleColor]) -contains $color) { return $color }
    return $fallback
}

function Get-Ext($path) {
    try {
        return [System.IO.Path]::GetExtension($path).ToLower()
    } catch {
        return ""
    }
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
    $bar = ('#' * ($percent / 3)).PadRight(33, '-')
    $etaStr = $eta.ToString("hh\:mm\:ss")
    $shortName = [System.IO.Path]::GetFileName($filename)
    Write-Host "`r[$bar] $percent% | $etaStr | $shortName".PadRight(100) -ForegroundColor $fgColor -NoNewline
}

$totalByExt = @{}
$copiedByExt = @{}

foreach ($job in $jobs) {
    $Source = $job.Source
    $Target = $job.Target
    Write-Host "`n▶ Copying from `"$Source`" to `"$Target`"" -ForegroundColor Cyan

    $errorLog = Join-Path $Source "robocopy_errors.log"
    $copiedLog = Join-Path $Source "robocopy_copied_files.log"
    $tempLog = Join-Path $env:TEMP "robocopy_temp.log"

    foreach ($log in @($errorLog, $copiedLog, $tempLog)) {
        if (Test-Path $log) { Remove-Item $log }
    }

    # Include root and all subdirs
    $directories = @()
    $directories += Get-Item -Path $Source
    $directories += Get-ChildItem -Path $Source -Directory -Recurse -Force
    $total = $directories.Count
    $startTime = Get-Date
    $done = 0

    foreach ($dir in $directories) {
        $relPath = $dir.FullName.Substring($Source.Length).TrimStart('\')
        $destDir = if ($relPath) { Join-Path $Target $relPath } else { $Target }
        if (-not (Test-Path $destDir)) { New-Item -Path $destDir -ItemType Directory -Force | Out-Null }

        try {
            robocopy $dir.FullName $destDir /E /COPYALL /DCOPY:T /R:1 /W:1 /NDL /NJH /NJS /NP /LOG:$tempLog > $null
            $copiedLines = Select-String -Path $tempLog -Pattern '^\s+(New File|Newer|Extra File)' | ForEach-Object { $_.Line.Trim() }

            foreach ($line in $copiedLines) {
                $relFile = $line -replace "^\s*(New File|Newer|Extra File)\s+", ''
                $srcFile = Join-Path $dir.FullName $relFile
                $dstFile = Join-Path $destDir $relFile

                if (Test-Path $srcFile -PathType Leaf -and Test-Path $dstFile -PathType Leaf) {
                    $src = Get-Item -LiteralPath $srcFile -Force
                    $dst = Get-Item -LiteralPath $dstFile -Force
                    $dst.CreationTimeUtc = $src.CreationTimeUtc
                }

                Add-Content -Path $copiedLog -Value $relFile
                $ext = Get-Ext $relFile
                $copiedByExt[$ext] = 1 + ($copiedByExt[$ext] | ForEach-Object { $_ } | Where-Object { $_ -ne $null } | Measure-Object -Sum).Sum
            }

            $sourceFolders = Get-ChildItem -Path $dir.FullName -Directory -Recurse -Force
            foreach ($sf in $sourceFolders) {
                $relative = $sf.FullName.Substring($dir.FullName.Length).TrimStart('\')
                $dfPath = Join-Path $destDir $relative
                if (Test-Path $dfPath) {
                    try {
                        (Get-Item -LiteralPath $dfPath -Force).CreationTimeUtc = $sf.CreationTimeUtc
                    } catch {
                        Add-Content -Path $errorLog -Value "Failed to set folder time: $dfPath - $($_.Exception.Message)"
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
            Add-Content -Path $errorLog -Value "Error in $($dir.FullName): $($_.Exception.Message)"
            Write-Host "`nError copying $relPath" -ForegroundColor Red
        }
    }

    Remove-Item $tempLog -ErrorAction SilentlyContinue

    # Count all files in this job for total
    $allFiles = Get-ChildItem -Path $Source -Recurse -File -Force
    foreach ($file in $allFiles) {
        $ext = Get-Ext $file.Name
        $totalByExt[$ext] = 1 + ($totalByExt[$ext] | ForEach-Object { $_ } | Where-Object { $_ -ne $null } | Measure-Object -Sum).Sum
    }

    Write-Host "`n✅ Completed job: $Source" -ForegroundColor Green
}

# === Summary ===
Write-Host "`n📂 Final Summary by Extension:" -ForegroundColor Cyan
$allExts = $copiedByExt.Keys | Sort-Object -Unique
foreach ($ext in $allExts) {
    $copied = $copiedByExt[$ext]
    $label = if ($ext -ne "") { $ext } else { "[no ext]" }
    $line = "{0,-10} Copied: {1,6}" -f $label, $copied
    Write-Host " - $line" -ForegroundColor Gray
}

