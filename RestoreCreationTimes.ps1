$destinationRoot = "D:\Files\13-10 Coding Projects\PreserveDateCreated\TestDestinationFiles"
$inputCSV = "D:\Files\13-10 Coding Projects\PreserveDateCreated\creation_dates.csv"
$errorLog = "D:\Files\13-10 Coding Projects\PreserveDateCreated\timestamp_restore_errors.log"

# Clear previous error log
if (Test-Path $errorLog) { Remove-Item $errorLog }

$timestampData = Import-Csv -Path $inputCSV

foreach ($entry in $timestampData) {
    try {
        # Adjust source path length dynamically
        $sourceRoot = Split-Path -Path $entry.FullPath -Parent
        $relativePath = $entry.FullPath.Substring($sourcePath.Length).TrimStart('\')
        $destPath = Join-Path $destinationRoot $relativePath

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