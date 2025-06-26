$source = "D:\Files\13-10 Coding Projects\PreserveDateCreated"
$target = "D:\Files\13-10 Coding Projects\PreserveDateCreated\TestDestinationFiles"

$files = Get-ChildItem -Path $source -Recurse -File
$totalSize = ($files | Measure-Object Length -Sum).Sum
$bytesCopied = 0

foreach ($file in $files) {
    $relPath = $file.FullName.Substring($source.Length).TrimStart('\')
    $destPath = Join-Path $target $relPath

    robocopy (Split-Path $file.FullName) (Split-Path $destPath) $file.Name /NFL /NDL /NJH /NJS > $null
    $bytesCopied += $file.Length
    $percent = [math]::Round(($bytesCopied / $totalSize) * 100, 2)
    Write-Host "$percent% complete ($($file.Name))"
}

$outputCSV = "D:\Files\13-10 Coding Projects\PreserveDateCreated\creation_dates.csv"

Get-ChildItem -Path $source -Recurse -Force | ForEach-Object {
    [PSCustomObject]@{
        FullPath = $_.FullName
        CreationTime = $_.CreationTimeUtc
        IsDirectory = $_.PSIsContainer
    }
} | Export-Csv -Path $outputCSV -NoTypeInformation -Encoding UTF8



$errorLog = "D:\Files\13-10 Coding Projects\PreserveDateCreated\timestamp_restore_errors.log"

# Clear previous error log
if (Test-Path $errorLog) { Remove-Item $errorLog }

$timestampData = Import-Csv -Path $outputCSV

foreach ($entry in $timestampData) {
    try {
        # Adjust source path length dynamically
        $sourceRoot = Split-Path -Path $entry.FullPath -Parent
        $relativePath = $entry.FullPath.Substring($sourcePath.Length).TrimStart('\')
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