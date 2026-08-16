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
    Write-Host ''

    $loginArguments = @('models', 'auth', 'login', '--provider', 'openai')
    if ($DeviceCode) {
        $loginArguments += '--device-code'
    }

    $exitCode = Invoke-PortableOpenClaw -Paths $paths -ArgumentList $loginArguments
    if ($exitCode -ne 0) {
        throw "OpenAI sign-in failed with exit code $exitCode."
    }

    $exitCode = Invoke-PortableOpenClaw `
        -Paths $paths `
        -ArgumentList @('config', 'set', 'agents.defaults.model.primary', 'openai/gpt-5.6-sol')
    if ($exitCode -ne 0) {
        throw "The model selection failed with exit code $exitCode."
    }

    Write-Utf8NoBom -Path $paths.ConfiguredMarker -Value ((Get-Date).ToUniversalTime().ToString('o') + [Environment]::NewLine)
    Write-Host ''
    Write-Host 'OpenAI sign-in is configured. You can now run Start-OpenClaw.bat.' -ForegroundColor Green
}
catch {
    Write-Error $_
    throw
}
