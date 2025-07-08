param (
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$Target
)

Write-Host "`n`n📂 Copying from '$Source' to '$Target'..." -ForegroundColor DarkGreen

# === Logs ===
$errorLog  = Join-Path $Source "robocopy_errors.log"
$copiedLog = Join-Path $Source "robocopy_copied_files.log"
$tempLog   = Join-Path $env:TEMP "robocopy_temp.log"

foreach ($log in @($errorLog, $copiedLog, $tempLog)) {
    if (Test-Path $log) { Remove-Item $log -Force }
}

# === Color Map ===
$extColors = @{
    ".txt" = "Yellow"; ".ps1" = "Cyan"; ".exe" = "Magenta"
    ".jpg" = "Green"; ".png" = "Green"; ".zip" = "DarkYellow"
    ".pdf" = "Blue"; ".docx" = "DarkBlue"; ".json" = "Yellow"
    ".xml" = "DarkCyan"; ".dll" = "DarkMagenta"; ".mp4" = "Red"
}

function Get-ValidConsoleColor {
    param([string]$color, [string]$fallback = "White")
    if ([System.Enum]::IsDefined([System.ConsoleColor], $color)) { return $color } else { return $fallback }
}

function Show-ProgressBar {
    param([int]$current, [int]$total, [string]$filename, [TimeSpan]$eta, [string]$fgColor)
    $percent = [math]::Round(100 * $current / $total)
    $barLen = 30
    $filled = [int]($barLen * $percent / 100)
    $bar = ('#' * $filled).PadRight($barLen, '-')
    $etaStr = $eta.ToString("hh\:mm\:ss")
    Write-Host "`r[$bar] $percent% | $etaStr | $filename".PadRight(100) -ForegroundColor $fgColor -NoNewline
}

# === Scan folders ===
$directories = Get-ChildItem -Path $Source -Directory -Recurse -Force
$directories += Get-Item -LiteralPath $Source
$total = $directories.Count
if ($total -eq 0) {
    Write-Host "❌ No directories found to process." -ForegroundColor Red
    exit
}

$startTime = Get-Date
$done = 0

foreach ($dir in $directories) {
    $relPath = $dir.FullName.Substring($Source.Length).TrimStart('\')
    $destDir = Join-Path $Target $relPath

    try {
        # Run robocopy
        robocopy $dir.FullName $destDir /E /COPY:DAT /DCOPY:T /R:1 /W:1 /LOG:$tempLog /NFL /NDL /NJH /NJS /NP | Out-Null

        # Read log
        $lines = Get-Content $tempLog -ErrorAction SilentlyContinue
        $elapsed = (Get-Date) - $startTime
        $eta = [TimeSpan]::FromSeconds((($elapsed.TotalSeconds / ($done + 1)) * ($total - $done)))

        foreach ($line in $lines) {
            if ($line -match "^\s+(New File|Newer|Extra File)\s+(.*)") {
                $relFile = $matches[2].Trim()
                Add-Content -Path $copiedLog -Value $relFile

                $ext = [System.IO.Path]::GetExtension($relFile).ToLower()
                $fg = Get-ValidConsoleColor $extColors[$ext] "White"
                Show-ProgressBar -current $done -total $total -filename $relFile -eta $eta -fgColor $fg
            }
            elseif ($line -match "^\s+Older\s+(.*)") {
                $relFile = $matches[1].Trim()
                Show-ProgressBar -current $done -total $total -filename $relFile -eta $eta -fgColor "Gray"
            }
        }

        $done++
    } catch {
        Write-Host "`nError processing $($dir.FullName): $($_.Exception.Message)" -ForegroundColor Red
        Add-Content -Path $errorLog -Value "Failed folder: $($dir.FullName) - $($_.Exception.Message)"
    }
}

Remove-Item $tempLog -ErrorAction SilentlyContinue

Write-Host "`n`n✅ Robocopy completed!" -ForegroundColor Green
if (Test-Path $copiedLog) {
    Write-Host "📄 Copied files logged in: $copiedLog" -ForegroundColor Yellow
}
if (Test-Path $errorLog) {
    Write-Host "⚠️ Errors occurred. See: $errorLog" -ForegroundColor Red
}
