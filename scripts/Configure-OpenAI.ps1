[CmdletBinding()]
param(
    [switch]$DeviceCode,
    [switch]$AllowInsecureFileSystem
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'PortableEnvironment.ps1')

try {
    $root = Get-PortableRoot
    $paths = Get-PortablePaths -Root $root
    Assert-PortablePayload -Paths $paths
    Test-BundleManifest -Paths $paths
    [void](Initialize-PortableState `
        -Paths $paths `
        -GatewayPort 18789 `
        -AllowInsecureFileSystem:$AllowInsecureFileSystem)

    Write-Host ''
    Write-Host 'OpenClaw will open the official ChatGPT/Codex sign-in flow.' -ForegroundColor Cyan
    Write-Host 'Credentials remain under this portable folder in data\openclaw-state.'
    Write-Host 'API-key authentication and usage-based API billing are disabled by this wrapper.'
    Write-Host ''

    $managedCodexVersion = Assert-ManagedCodexRuntime -Paths $paths
    Write-Host "Verified bundled $managedCodexVersion." -ForegroundColor DarkGray

    $profileId = 'openai:portable-oauth'
    $loginArguments = @(
        'models', 'auth', 'login',
        '--provider', 'openai',
        '--profile-id', $profileId,
        '--method', 'oauth')
    if ($DeviceCode) {
        $loginArguments[-1] = 'device-code'
    }

    $exitCode = Invoke-PortableOpenClaw -Paths $paths -ArgumentList $loginArguments
    if ($exitCode -ne 0) {
        throw "OpenAI sign-in failed with exit code $exitCode."
    }

    $exitCode = Invoke-PortableOpenClaw `
        -Paths $paths `
        -ArgumentList @('models', 'auth', 'order', 'set', '--provider', 'openai', $profileId)
    if ($exitCode -ne 0) {
        throw "Could not restrict OpenAI authentication to the portable OAuth profile (exit code $exitCode)."
    }

    $exitCode = Invoke-PortableOpenClaw `
        -Paths $paths `
        -ArgumentList @('config', 'set', 'agents.defaults.model.primary', 'openai/gpt-5.6-sol')
    if ($exitCode -ne 0) {
        throw "The model selection failed with exit code $exitCode."
    }

    Write-Utf8NoBom -Path $paths.ConfiguredMarker -Value ((Get-Date).ToUniversalTime().ToString('o') + [Environment]::NewLine)
    Write-Host ''
    Write-Host 'ChatGPT/Codex OAuth is configured. You can now run Start-OpenClaw.bat.' -ForegroundColor Green
}
catch {
    Write-Error $_
    throw
}
