$ErrorActionPreference = 'Stop'

$Organization = "moonlight-stream"
$PrebuiltRepo = "moonlight-qt-deps"
$TargetDir = Join-Path $PSScriptRoot "libs\windows"
$Assets = @("windows-x64.zip", "windows-ARM64.zip")
$Tag = "v19"

# SHA-256 of each prebuilt archive. Release assets can be replaced after they're published, so a
# download that doesn't match isn't used. Add the hashes here when changing $Tag.
$Sha256 = @{
    "v19/windows-x64.zip" = "65ff1bd439222e1e2750054f960dcd6fac46190027da16db7403e345c295f10f"
    "v19/windows-ARM64.zip" = "ac606be421c8bf14e94128ea2116d3257a425c3d6fa102cd92bbd017f56647e2"
}

if (Test-Path $TargetDir) {
    Write-Host "Cleaning target directory..." -ForegroundColor Cyan
    Remove-Item -Path "$TargetDir\*" -Recurse -Force
} else {
    New-Item -ItemType Directory -Path $TargetDir | Out-Null
}

foreach ($AssetName in $Assets) {
    $Url = "https://github.com/$Organization/$PrebuiltRepo/releases/download/$Tag/$AssetName"
    $ArchivePath = Join-Path $env:TEMP $AssetName
    $Expected = $Sha256["$Tag/$AssetName"]
    if (-not $Expected) {
        Write-Host "No SHA-256 for $AssetName at $Tag; add it to `$Sha256 in setup-deps.ps1" -ForegroundColor Red
        exit 1
    }

    Write-Host "Downloading $AssetName..." -ForegroundColor Cyan
    curl.exe -s -L -f -o "$ArchivePath" "$Url"
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    $Actual = (Get-FileHash -Algorithm SHA256 $ArchivePath).Hash.ToLowerInvariant()
    if ($Actual -ne $Expected) {
        Remove-Item $ArchivePath
        Write-Host "$AssetName has SHA-256 $Actual, expected $Expected" -ForegroundColor Red
        exit 1
    }

    Write-Host "Extracting $AssetName..." -ForegroundColor Cyan
    Expand-Archive -Path $ArchivePath -DestinationPath $TargetDir -Force
    Remove-Item $ArchivePath
}

Write-Host "Dependencies successfully deployed" -ForegroundColor Green