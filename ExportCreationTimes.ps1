$sourcePath = "C:\Source"
$outputCSV = "C:\BackupLogs\creation_dates.csv"

Get-ChildItem -Path $sourcePath -Recurse -Force | ForEach-Object {
    [PSCustomObject]@{
        FullPath = $_.FullName
        CreationTime = $_.CreationTimeUtc
        IsDirectory = $_.PSIsContainer
    }
} | Export-Csv -Path $outputCSV -NoTypeInformation -Encoding UTF8
