[CmdletBinding()]
param(
    [ValidateSet('x64', 'arm64')][string]$Architecture = 'x64',
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'),
    [string]$CacheDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) '.cache'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$sourceRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$cacheRoot = [System.IO.Path]::GetFullPath($CacheDirectory)
$versionsPath = Join-Path $sourceRoot 'versions.json'
$versions = Get-Content -LiteralPath $versionsPath -Raw | ConvertFrom-Json
$wrapperVersion = [string]$versions.wrapperVersion
$bundleName = "OpenClaw-Portable-Companion-$wrapperVersion-win-$Architecture"
$zipPath = Join-Path $outputRoot ($bundleName + '.zip')
$sbomArtifactPath = Join-Path $outputRoot ("SBOM-$bundleName.cdx.json")
$stagingRoot = Join-Path $outputRoot ('.staging-' + [guid]::NewGuid().ToString('N'))
$bundleRoot = Join-Path $stagingRoot $bundleName

function Assert-ChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Candidate
    )

    $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    $candidateFull = [System.IO.Path]::GetFullPath($Candidate)
    if (-not $candidateFull.StartsWith($parentFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to operate outside $Parent`: $Candidate"
    }
}

function Remove-SafeTree {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Candidate
    )

    Assert-ChildPath -Parent $Parent -Candidate $Candidate
    if (Test-Path -LiteralPath $Candidate) {
        Remove-Item -LiteralPath $Candidate -Recurse -Force
    }
}

function Get-VerifiedDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Sha256,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        $existingHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($existingHash -eq $Sha256.ToLowerInvariant()) {
            Write-Host "Using verified cache: $Destination"
            return
        }
        throw "Cached file hash mismatch: $Destination. Remove the file and retry."
    }

    $temporary = $Destination + '.' + [guid]::NewGuid().ToString('N') + '.download'
    try {
        Write-Host "Downloading $Url"
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $temporary
        $actualHash = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $Sha256.ToLowerInvariant()) {
            throw "SHA-256 mismatch for $Url. Expected $Sha256, received $actualHash."
        }
        Move-Item -LiteralPath $temporary -Destination $Destination
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Assert-ChildPath -Parent $cacheRoot -Candidate $temporary
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Copy-DistributionSources {
    param([Parameter(Mandatory = $true)][string]$Destination)

    foreach ($file in @(
        '.gitattributes',
        'LICENSE',
        'README.md',
        'SECURITY.md',
        'THIRD_PARTY_NOTICES.md',
        'Start-OpenClaw.bat',
        'Configure-OpenAI.bat',
        'Configure-OpenAI-Device-Code.bat',
        'versions.json')) {
        Copy-Item -LiteralPath (Join-Path $sourceRoot $file) -Destination (Join-Path $Destination $file)
    }

    Copy-Item -LiteralPath (Join-Path $sourceRoot 'licenses') -Destination (Join-Path $Destination 'licenses') -Recurse
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'docs') -Destination (Join-Path $Destination 'docs') -Recurse
    [void](New-Item -ItemType Directory -Path (Join-Path $Destination 'scripts'))
    foreach ($script in @('PortableEnvironment.ps1', 'Configure-OpenAI.ps1', 'Start-OpenClaw.ps1')) {
        Copy-Item -LiteralPath (Join-Path $sourceRoot "scripts\$script") -Destination (Join-Path $Destination "scripts\$script")
    }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[void](New-Item -ItemType Directory -Path $outputRoot -Force)
[void](New-Item -ItemType Directory -Path $cacheRoot -Force)

if (Test-Path -LiteralPath $zipPath) {
    if (-not $Force) {
        throw "Output already exists: $zipPath. Use -Force to replace this exact artifact."
    }
    Assert-ChildPath -Parent $outputRoot -Candidate $zipPath
    Remove-Item -LiteralPath $zipPath -Force
}
if (Test-Path -LiteralPath $sbomArtifactPath) {
    if (-not $Force) {
        throw "Output already exists: $sbomArtifactPath. Use -Force to replace this exact artifact."
    }
    Assert-ChildPath -Parent $outputRoot -Candidate $sbomArtifactPath
    Remove-Item -LiteralPath $sbomArtifactPath -Force
}

try {
    [void](New-Item -ItemType Directory -Path $bundleRoot)
    Copy-DistributionSources -Destination $bundleRoot

    $companionInfo = $versions.companion.architectures.$Architecture
    $nodeInfo = $versions.node.architectures.$Architecture
    if ($null -eq $companionInfo -or $null -eq $nodeInfo) {
        throw "versions.json has no complete pin set for $Architecture."
    }

    $companionArchive = Join-Path $cacheRoot "OpenClawTray-$($versions.companion.version)-win-$Architecture.zip"
    $nodeArchive = Join-Path $cacheRoot "node-v$($versions.node.version)-win-$Architecture.zip"
    Get-VerifiedDownload -Url $companionInfo.url -Sha256 $companionInfo.sha256 -Destination $companionArchive
    Get-VerifiedDownload -Url $nodeInfo.url -Sha256 $nodeInfo.sha256 -Destination $nodeArchive

    $appDestination = Join-Path $bundleRoot 'app'
    [void](New-Item -ItemType Directory -Path $appDestination)
    Expand-Archive -LiteralPath $companionArchive -DestinationPath $appDestination

    $companionExe = Join-Path $appDestination 'OpenClaw.Tray.WinUI.exe'
    if (-not (Test-Path -LiteralPath $companionExe -PathType Leaf)) {
        throw 'The official Companion archive did not contain OpenClaw.Tray.WinUI.exe at its expected path.'
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $companionExe
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
        $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject.IndexOf(
            [string]$versions.companion.signerSubjectContains,
            [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "The extracted Companion does not have the expected valid Authenticode signature: $($signature.Status)."
    }

    $nodeExtract = Join-Path $stagingRoot 'node-extract'
    [void](New-Item -ItemType Directory -Path $nodeExtract)
    Expand-Archive -LiteralPath $nodeArchive -DestinationPath $nodeExtract
    $nodeSource = @(Get-ChildItem -LiteralPath $nodeExtract -Directory)
    if ($nodeSource.Count -ne 1) {
        throw 'The Node.js archive layout was not recognized.'
    }
    $runtimeDestination = Join-Path $bundleRoot 'runtime'
    [void](New-Item -ItemType Directory -Path $runtimeDestination)
    Copy-Item -Path (Join-Path $nodeSource[0].FullName '*') -Destination $runtimeDestination -Recurse

    $runtimeNode = Join-Path $runtimeDestination 'node.exe'
    try {
        $reportedNodeVersion = (& $runtimeNode --version).Trim()
    }
    catch {
        throw "The $Architecture Node.js runtime cannot execute on this build runner. Use a matching Windows runner."
    }
    if ($reportedNodeVersion -ne "v$($versions.node.version)") {
        throw "Node.js version mismatch after extraction: $reportedNodeVersion"
    }

    $gatewayDestination = Join-Path $bundleRoot 'gateway'
    [void](New-Item -ItemType Directory -Path $gatewayDestination)
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'gateway\package.json') -Destination $gatewayDestination
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'gateway\package-lock.json') -Destination $gatewayDestination

    $npm = Join-Path $runtimeDestination 'npm.cmd'
    $previousNpmCache = $env:NPM_CONFIG_CACHE
    $env:NPM_CONFIG_CACHE = Join-Path $cacheRoot 'npm'
    try {
        Push-Location $gatewayDestination
        try {
            & $npm ci --omit=dev --no-audit --no-fund
            if ($LASTEXITCODE -ne 0) {
                throw "npm ci failed with exit code $LASTEXITCODE."
            }

            & $npm audit --omit=dev --audit-level=moderate --no-fund
            if ($LASTEXITCODE -ne 0) {
                throw "npm audit found a moderate-or-higher production dependency advisory."
            }

            $sbomOutput = @(& $npm sbom --sbom-format cyclonedx)
            if ($LASTEXITCODE -ne 0 -or $sbomOutput.Count -eq 0) {
                throw "npm could not generate the CycloneDX SBOM."
            }
            [System.IO.File]::WriteAllText(
                (Join-Path $bundleRoot 'SBOM.cdx.json'),
                (($sbomOutput -join [Environment]::NewLine) + [Environment]::NewLine),
                (New-Object System.Text.UTF8Encoding($false)))
        }
        finally {
            Pop-Location
        }
    }
    finally {
        $env:NPM_CONFIG_CACHE = $previousNpmCache
    }

    $openClawEntry = Join-Path $gatewayDestination 'node_modules\openclaw\openclaw.mjs'
    if (-not (Test-Path -LiteralPath $openClawEntry -PathType Leaf)) {
        throw 'The pinned OpenClaw package did not install its CLI entry point.'
    }
    $reportedOpenClawVersion = (& $runtimeNode $openClawEntry --version).Trim()
    if ($LASTEXITCODE -ne 0 -or $reportedOpenClawVersion -notmatch [regex]::Escape([string]$versions.openClaw.version)) {
        throw "OpenClaw CLI smoke test failed: $reportedOpenClawVersion"
    }

    $sourceCommit = 'uncommitted'
    try {
        $candidateCommit = (& git -C $sourceRoot rev-parse HEAD 2>$null).Trim()
        if ($LASTEXITCODE -eq 0 -and $candidateCommit -match '^[0-9a-f]{40}$') {
            $sourceCommit = $candidateCommit
        }
    }
    catch { }

    $buildInfo = [ordered]@{
        wrapperVersion = $wrapperVersion
        architecture = $Architecture
        companionVersion = [string]$versions.companion.version
        nodeVersion = [string]$versions.node.version
        openClawVersion = [string]$versions.openClaw.version
        sourceCommit = $sourceCommit
        builtAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText(
        (Join-Path $bundleRoot 'BUILD-INFO.json'),
        (($buildInfo | ConvertTo-Json -Depth 5) + [Environment]::NewLine),
        $utf8NoBom)

    $bundlePrefix = $bundleRoot.TrimEnd('\') + '\'
    $bundleItems = @(Get-ChildItem -LiteralPath $bundleRoot -Force -Recurse)
    $reparsePoints = @($bundleItems | Where-Object {
        ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
    })
    if ($reparsePoints.Count -gt 0) {
        throw "Release staging contains an unexpected reparse point: $($reparsePoints[0].FullName)"
    }

    $manifestEntries = foreach ($file in @($bundleItems | Where-Object { -not $_.PSIsContainer } | Sort-Object FullName)) {
        $relativePath = $file.FullName.Substring($bundlePrefix.Length).Replace('\', '/')
        [ordered]@{
            path = $relativePath
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            size = $file.Length
        }
    }
    $bundleManifest = [ordered]@{
        algorithm = 'SHA-256'
        catalogMode = 'all-files-except-data-and-manifest'
        files = @($manifestEntries)
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $bundleRoot 'bundle-manifest.json'),
        (($bundleManifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine),
        $utf8NoBom)

    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (-not (Test-Path -LiteralPath $tar -PathType Leaf)) {
        throw 'Windows tar.exe is required to create the release ZIP.'
    }
    & $tar -a -c -f $zipPath -C $stagingRoot $bundleName
    if ($LASTEXITCODE -ne 0) {
        throw "tar.exe failed to create the release ZIP (exit code $LASTEXITCODE)."
    }
    $zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksumLine = "$zipHash  $([System.IO.Path]::GetFileName($zipPath))"
    $checksumPath = Join-Path $outputRoot "SHA256SUMS-$Architecture.txt"
    [System.IO.File]::WriteAllText($checksumPath, $checksumLine + [Environment]::NewLine, $utf8NoBom)
    Copy-Item -LiteralPath (Join-Path $bundleRoot 'SBOM.cdx.json') -Destination $sbomArtifactPath

    Write-Host ''
    Write-Host "Built: $zipPath" -ForegroundColor Green
    Write-Host "SHA-256: $zipHash"
    Write-Host "SBOM: $sbomArtifactPath"
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-SafeTree -Parent $outputRoot -Candidate $stagingRoot
    }
}
