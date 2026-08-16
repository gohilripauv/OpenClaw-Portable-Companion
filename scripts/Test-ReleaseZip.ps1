[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ZipPath,
    [string]$ChecksumPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$zip = [System.IO.Path]::GetFullPath($ZipPath)
if (-not (Test-Path -LiteralPath $zip -PathType Leaf)) {
    throw "Release ZIP does not exist: $zip"
}

$actualHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
if (-not [string]::IsNullOrWhiteSpace($ChecksumPath)) {
    $checksum = [System.IO.Path]::GetFullPath($ChecksumPath)
    $line = (Get-Content -LiteralPath $checksum -Raw).Trim()
    $expectedName = [System.IO.Path]::GetFileName($zip)
    if ($line -notmatch '^([0-9a-fA-F]{64})\s{2}(.+)$' -or
        $Matches[1].ToLowerInvariant() -ne $actualHash -or
        $Matches[2] -ne $expectedName) {
        throw 'The release checksum file does not match the ZIP.'
    }
}

$tar = Join-Path $env:SystemRoot 'System32\tar.exe'
$entries = @(& $tar -tf $zip)
if ($LASTEXITCODE -ne 0 -or $entries.Count -eq 0) {
    throw 'Could not list release ZIP contents.'
}
$unsafeEntries = @($entries | Where-Object {
    $_ -match '^(?:/|\\|[A-Za-z]:)' -or $_ -match '(^|[\\/])\.\.([\\/]|$)'
})
if ($unsafeEntries.Count -gt 0) {
    throw "Release ZIP contains unsafe paths: $($unsafeEntries -join ', ')"
}

$testParent = [System.IO.Path]::GetFullPath((Join-Path $env:TEMP 'openclaw-portable-release-tests'))
$testRoot = Join-Path $testParent ([guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testRoot -Force)
try {
    & $tar -xf $zip -C $testRoot
    if ($LASTEXITCODE -ne 0) {
        throw 'Release ZIP extraction failed.'
    }

    $bundleDirectories = @(Get-ChildItem -LiteralPath $testRoot -Directory)
    if ($bundleDirectories.Count -ne 1) {
        throw 'Release ZIP must contain exactly one top-level directory.'
    }
    $bundleRoot = $bundleDirectories[0].FullName

    $sbomPath = Join-Path $bundleRoot 'SBOM.cdx.json'
    if (-not (Test-Path -LiteralPath $sbomPath -PathType Leaf)) {
        throw 'Release ZIP does not contain SBOM.cdx.json.'
    }
    $sbom = Get-Content -LiteralPath $sbomPath -Raw | ConvertFrom-Json
    if ($sbom.bomFormat -ne 'CycloneDX' -or $null -eq $sbom.components) {
        throw 'Release ZIP contains an invalid or incomplete CycloneDX SBOM.'
    }

    & (Join-Path $PSScriptRoot 'Test-Portable.ps1') -BuiltBundle $bundleRoot
    & (Join-Path $PSScriptRoot 'Test-GatewayLifecycle.ps1') -BuiltBundle $bundleRoot

    Write-Host "Release ZIP checks passed: $actualHash" -ForegroundColor Green
}
finally {
    $candidate = [System.IO.Path]::GetFullPath($testRoot)
    $parentPrefix = $testParent.TrimEnd('\') + '\'
    if ($candidate.StartsWith($parentPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
        [System.IO.Directory]::Exists($candidate)) {
        [System.IO.Directory]::Delete($candidate, $true)
    }
}
