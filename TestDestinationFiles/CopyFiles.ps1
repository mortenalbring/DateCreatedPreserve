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