[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Destination
)

$ErrorActionPreference = "Stop"
$assets = Join-Path $Destination "Assets"
New-Item -ItemType Directory -Path $assets -Force | Out-Null

# A neutral 1x1 PNG is sufficient for this diagnostic package's required logo entries.
$png = [Convert]::FromBase64String(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)
foreach ($name in @("StoreLogo.png", "Logo.png", "AppList.png")) {
    [System.IO.File]::WriteAllBytes((Join-Path $assets $name), $png)
}

