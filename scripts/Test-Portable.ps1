[CmdletBinding()]
param(
    [string]$BuiltBundle
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$sourceRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$failures = New-Object System.Collections.Generic.List[string]

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) {
        $failures.Add($Message)
    }
}

Write-Host 'Checking PowerShell syntax...'
Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'scripts') -Filter '*.ps1' | ForEach-Object {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $_.FullName,
        [ref]$tokens,
        [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) {
        $failures.Add("$($_.Name): $($parseError.Message)")
    }
}

Write-Host 'Checking version and dependency pins...'
$versions = Get-Content -LiteralPath (Join-Path $sourceRoot 'versions.json') -Raw | ConvertFrom-Json
Assert-True -Condition ([string]$versions.wrapperVersion -match '^\d+\.\d+\.\d+$') -Message 'wrapperVersion must be SemVer.'
Assert-True -Condition ([string]$versions.openClaw.version -match '^\d{4}\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') -Message 'OpenClaw must use an exact published version.'
foreach ($architecture in @('x64', 'arm64')) {
    $nodeInfo = $versions.node.architectures.$architecture
    $companionInfo = $versions.companion.architectures.$architecture
    Assert-True -Condition ($nodeInfo.url -match '^https://nodejs\.org/dist/') -Message "Unexpected Node.js host for $architecture."
    Assert-True -Condition ($companionInfo.url -match '^https://github\.com/openclaw/openclaw-windows-node/releases/download/') -Message "Unexpected Companion host for $architecture."
    Assert-True -Condition ($nodeInfo.sha256 -match '^[0-9a-f]{64}$') -Message "Invalid Node.js SHA-256 for $architecture."
    Assert-True -Condition ($companionInfo.sha256 -match '^[0-9a-f]{64}$') -Message "Invalid Companion SHA-256 for $architecture."
}

$package = Get-Content -LiteralPath (Join-Path $sourceRoot 'gateway\package.json') -Raw | ConvertFrom-Json
Assert-True `
    -Condition ([string]$package.dependencies.openclaw -eq [string]$versions.openClaw.version) `
    -Message 'gateway/package.json does not match the OpenClaw pin in versions.json.'

$lockText = Get-Content -LiteralPath (Join-Path $sourceRoot 'gateway\package-lock.json') -Raw
$openClawLockPattern = '(?s)"node_modules/openclaw"\s*:\s*\{.*?"version"\s*:\s*"' +
    [regex]::Escape([string]$versions.openClaw.version) + '".*?"integrity"\s*:\s*"' +
    [regex]::Escape([string]$versions.openClaw.npmIntegrity) + '"'
Assert-True -Condition ($lockText -match $openClawLockPattern) -Message 'package-lock.json does not match the recorded OpenClaw version and integrity.'

Write-Host 'Checking launcher security invariants...'
$launcherText = (Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'scripts') -Filter '*.ps1' |
    Where-Object { $_.Name -ne 'Test-Portable.ps1' } |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join [Environment]::NewLine
Assert-True -Condition ($launcherText -notmatch '(?i)--auth\s+["'']?none') -Message 'A launcher contains an unauthenticated Gateway mode.'
Assert-True -Condition ($launcherText -notmatch '(?i)openclaw@latest') -Message 'A launcher uses the mutable openclaw@latest specifier.'
Assert-True -Condition ($launcherText -notmatch '(?i)Invoke-Expression') -Message 'A launcher uses Invoke-Expression.'
Assert-True -Condition ($launcherText -notmatch '(?i)powershell(?:\.exe)?[^\r\n]+-Command') -Message 'A launcher builds a nested PowerShell -Command string.'
Assert-True -Condition ($launcherText -match '(?i)--bind'',\s*''loopback') -Message 'The Gateway launcher does not explicitly bind to loopback.'
Assert-True -Condition ($launcherText -match '(?i)--auth'',\s*''token') -Message 'The Gateway launcher does not explicitly require token authentication.'

foreach ($batchName in @('Start-OpenClaw.bat', 'Configure-OpenAI.bat', 'Configure-OpenAI-Device-Code.bat')) {
    $batchText = Get-Content -LiteralPath (Join-Path $sourceRoot $batchName) -Raw
    Assert-True `
        -Condition ($batchText -match '(?i)%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe') `
        -Message "$batchName does not select Windows PowerShell through an absolute trusted path."
    Assert-True `
        -Condition ($batchText -notmatch '(?im)^\s*powershell\.exe\s') `
        -Message "$batchName invokes powershell.exe through ambient executable search order."
}

. (Join-Path $sourceRoot 'scripts\PortableEnvironment.ps1')
$quoted = ConvertTo-WindowsCommandLineArgument -Argument "C:\Folder With Space\O'Brien\openclaw.mjs"
Assert-True -Condition ($quoted.StartsWith('"') -and $quoted.EndsWith('"')) -Message 'Windows argument quoting did not quote a spaced path.'
Assert-True -Condition ($quoted.Contains("O'Brien")) -Message 'Windows argument quoting corrupted an apostrophe.'

Write-Host 'Exercising isolated state creation...'
$testParent = [System.IO.Path]::GetFullPath((Join-Path $env:TEMP 'openclaw-portable-tests'))
$testRoot = Join-Path $testParent ([guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testRoot -Force)
$environmentNames = @(
    'OPENCLAW_HOME',
    'OPENCLAW_STATE_DIR',
    'OPENCLAW_CONFIG_PATH',
    'OPENCLAW_GATEWAY_TOKEN',
    'OPENCLAW_GATEWAY_PORT',
    'OPENCLAW_TRAY_DATA_DIR',
    'OPENCLAW_TRAY_LOCAL_DATA_DIR',
    'OPENCLAW_TRAY_LOCALAPPDATA_DIR',
    'OPENCLAW_SKIP_UPDATE_CHECK',
    'NPM_CONFIG_CACHE',
    'TEMP',
    'TMP')
$savedEnvironment = @{}
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    $testPaths = Get-PortablePaths -Root $testRoot
    $state = Initialize-PortableState -Paths $testPaths -GatewayPort 28491 -NonInteractive
    $aclProbe = Join-Path $testPaths.State 'acl-probe.txt'
    Write-Utf8NoBom -Path $aclProbe -Value 'ACL probe'
    if ($state.FileSystem -in @('NTFS', 'ReFS')) {
        $icacls = Join-Path $env:SystemRoot 'System32\icacls.exe'
        & $icacls $aclProbe /inheritance:r /grant:r '*S-1-1-0:R' | Out-Null
        Assert-True -Condition ($LASTEXITCODE -eq 0) -Message 'Could not prepare the copied-descendant ACL test.'
    }
    $secondState = Initialize-PortableState -Paths $testPaths -GatewayPort 28491 -NonInteractive
    Assert-True -Condition (Test-Path -LiteralPath $testPaths.Config -PathType Leaf) -Message 'State initialization did not create openclaw.json.'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $testPaths.Companion 'gateways.json') -PathType Leaf) -Message 'State initialization did not create gateways.json.'
    Assert-True -Condition ($state.Token -match '^[A-Za-z0-9_-]{43}$') -Message 'Generated Gateway token is not 256-bit base64url.'
    Assert-True -Condition ($secondState.Token -eq $state.Token) -Message 'A second launch did not preserve the Gateway token.'

    $config = Get-Content -LiteralPath $testPaths.Config -Raw | ConvertFrom-Json
    Assert-True -Condition ($config.gateway.bind -eq 'loopback') -Message 'Generated config is not loopback-only.'
    Assert-True -Condition ($config.gateway.auth.mode -eq 'token') -Message 'Generated config does not use token auth.'
    Assert-True -Condition ($config.gateway.auth.token -eq '${OPENCLAW_GATEWAY_TOKEN}') -Message 'Generated config embeds or misreferences the Gateway token.'

    $registry = Get-Content -LiteralPath (Join-Path $testPaths.Companion 'gateways.json') -Raw | ConvertFrom-Json
    Assert-True -Condition (@($registry.gateways).Count -eq 1) -Message 'Generated Companion registry has an unexpected Gateway count.'
    Assert-True -Condition ($registry.gateways[0].sharedGatewayToken -eq $state.Token) -Message 'Companion and Gateway tokens do not match.'
    Assert-True -Condition ($registry.gateways[0].isLocal -eq $false) -Message 'Portable Gateway must remain externally managed by the wrapper.'

    if ($state.FileSystem -in @('NTFS', 'ReFS')) {
        $acl = Get-Acl -LiteralPath $testPaths.Data
        Assert-True -Condition $acl.AreAccessRulesProtected -Message 'The portable data ACL still inherits ambient permissions.'
        $probeAcl = Get-Acl -LiteralPath $aclProbe
        $broadRules = @($probeAcl.Access | Where-Object {
            try {
                $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value -eq 'S-1-1-0'
            }
            catch { $false }
        })
        Assert-True -Condition (-not $probeAcl.AreAccessRulesProtected) -Message 'A copied descendant retained a protected ACL.'
        Assert-True -Condition ($broadRules.Count -eq 0) -Message 'A copied descendant retained an explicit Everyone ACL.'
    }
}
finally {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
    $candidate = [System.IO.Path]::GetFullPath($testRoot)
    $parentPrefix = $testParent.TrimEnd('\') + '\'
    if ($candidate.StartsWith($parentPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $candidate)) {
        Remove-Item -LiteralPath $candidate -Recurse -Force
    }
}

if (-not [string]::IsNullOrWhiteSpace($BuiltBundle)) {
    Write-Host 'Checking built bundle...'
    $bundleRoot = [System.IO.Path]::GetFullPath($BuiltBundle)
    $bundlePaths = Get-PortablePaths -Root $bundleRoot
    try {
        Assert-PortablePayload -Paths $bundlePaths
        Test-BundleManifest -Paths $bundlePaths
        Test-CompanionSignature -Paths $bundlePaths
    }
    catch {
        $failures.Add($_.Exception.Message)
    }
}

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host 'Portable checks failed:' -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host " - $failure" -ForegroundColor Red
    }
    throw 'Portable checks failed.'
}

Write-Host ''
Write-Host 'All portable checks passed.' -ForegroundColor Green
