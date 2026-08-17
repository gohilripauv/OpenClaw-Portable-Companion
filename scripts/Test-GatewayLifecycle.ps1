[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BuiltBundle
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'PortableEnvironment.ps1')

if (-not ('OpenClawPortable.Tests.ConsoleSignal' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Threading;

namespace OpenClawPortable.Tests
{
    public static class ConsoleSignal
    {
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool FreeConsole();

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool AttachConsole(UInt32 processId);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GenerateConsoleCtrlEvent(UInt32 ctrlEvent, UInt32 processGroupId);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetConsoleCtrlHandler(IntPtr handler, bool add);

        public static bool SendCtrlC(int processId)
        {
            const UInt32 CTRL_C_EVENT = 0;
            const UInt32 ATTACH_PARENT_PROCESS = UInt32.MaxValue;
            FreeConsole();
            if (!AttachConsole((UInt32)processId))
            {
                AttachConsole(ATTACH_PARENT_PROCESS);
                return false;
            }

            SetConsoleCtrlHandler(IntPtr.Zero, true);
            bool sent = GenerateConsoleCtrlEvent(CTRL_C_EVENT, 0);
            Thread.Sleep(300);
            FreeConsole();
            AttachConsole(ATTACH_PARENT_PROCESS);
            SetConsoleCtrlHandler(IntPtr.Zero, false);
            return sent;
        }
    }
}
"@
}

function Get-FreeTcpPort {
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally {
        $listener.Stop()
    }
}

function Wait-GatewayReady {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$StandardOutput,
        [Parameter(Mandatory = $true)][string]$StandardError
    )

    $deadline = (Get-Date).AddSeconds(75)
    while ((Get-Date) -lt $deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            $details = if (Test-Path -LiteralPath $StandardError) {
                (Get-Content -LiteralPath $StandardError -Tail 40) -join [Environment]::NewLine
            } else { 'No error log was produced.' }
            throw "Gateway exited before readiness.`n$details"
        }

        if (Test-TcpPortOpen -Port $Port -TimeoutMilliseconds 500) {
            # The socket opens shortly before plugins and startup migrations
            # finish. Give those hooks a small deterministic settling window;
            # the authenticated RPC check below is the final readiness proof.
            Start-Sleep -Seconds 3
            return
        }
        Start-Sleep -Milliseconds 400
    }
    throw 'Gateway did not report readiness within 75 seconds.'
}

function Wait-GatewayRpc {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)]$Paths
    )

    $deadline = (Get-Date).AddSeconds(90)
    $lastOutput = @('No RPC probe completed.')
    while ((Get-Date) -lt $deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw 'Gateway exited while waiting for its authenticated RPC endpoint.'
        }

        $savedPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $lastOutput = @(& $Paths.Node $Paths.OpenClawEntry gateway status --require-rpc --json 2>&1)
            $rpcExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $savedPreference
        }
        if ($rpcExitCode -eq 0) {
            return $lastOutput
        }
        Start-Sleep -Seconds 2
    }

    throw "Authenticated Gateway RPC did not become ready within 90 seconds: $($lastOutput -join [Environment]::NewLine)"
}

function Stop-GatewayGracefully {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)

    $Process.Refresh()
    if ($Process.HasExited) {
        return
    }
    if (-not [OpenClawPortable.Tests.ConsoleSignal]::SendCtrlC($Process.Id)) {
        throw 'Could not deliver CTRL_C_EVENT to the Gateway console.'
    }
    # Hosted Windows runners can take substantially longer than interactive
    # desktops to schedule the managed app-server cleanup after SIGINT. Keep
    # requiring a real graceful exit and the clean-shutdown log assertions
    # below, but allow enough time for native x64 and ARM64 CI hosts.
    if (-not $Process.WaitForExit(60000)) {
        throw 'Gateway did not exit within 60 seconds of SIGINT.'
    }
}

$bundleRoot = [System.IO.Path]::GetFullPath($BuiltBundle)
$paths = Get-PortablePaths -Root $bundleRoot
Assert-PortablePayload -Paths $paths

$smokeParent = [System.IO.Path]::GetFullPath((Join-Path $env:TEMP 'openclaw-portable-gateway-tests'))
$smokeRoot = Join-Path $smokeParent ([guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $smokeRoot -Force)
$statePath = Join-Path $smokeRoot 'state'
$workspacePath = Join-Path $smokeRoot 'workspace'
$tempPath = Join-Path $smokeRoot 'temp'
[void](New-Item -ItemType Directory -Path $statePath, $workspacePath, $tempPath)
$configPath = Join-Path $smokeRoot 'openclaw.json'
$port = Get-FreeTcpPort
$token = 'portable-smoke-' + [guid]::NewGuid().ToString('N')
$first = $null
$second = $null

$environmentNames = @(
    'OPENCLAW_HOME',
    'OPENCLAW_STATE_DIR',
    'OPENCLAW_CONFIG_PATH',
    'OPENCLAW_PORTABLE_ROOT',
    'CODEX_HOME',
    'OPENCLAW_GATEWAY_TOKEN',
    'OPENCLAW_GATEWAY_PORT',
    'OPENAI_API_KEY',
    'CODEX_API_KEY',
    'TEMP',
    'TMP')
$savedEnvironment = @{}
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

try {
    $config = [ordered]@{
        gateway = [ordered]@{
            mode = 'local'
            port = $port
            bind = 'loopback'
            auth = [ordered]@{
                mode = 'token'
                token = '${OPENCLAW_GATEWAY_TOKEN}'
            }
        }
        agents = [ordered]@{
            defaults = [ordered]@{
                workspace = $workspacePath
                model = [ordered]@{ primary = 'openai/gpt-5.6-sol' }
                models = [ordered]@{
                    'openai/*' = [ordered]@{
                        agentRuntime = [ordered]@{ id = 'codex' }
                    }
                }
            }
        }
        plugins = [ordered]@{
            enabled = $true
            entries = [ordered]@{
                codex = [ordered]@{
                    enabled = $true
                    config = [ordered]@{
                        appServer = [ordered]@{
                            mode = 'guardian'
                            homeScope = 'agent'
                            clearEnv = @('OPENAI_API_KEY', 'CODEX_API_KEY')
                            defaultWorkspaceDir = $workspacePath
                        }
                    }
                }
            }
        }
    }
    Write-Utf8NoBom -Path $configPath -Value (($config | ConvertTo-Json -Depth 8) + [Environment]::NewLine)

    $env:OPENCLAW_HOME = $statePath
    $env:OPENCLAW_STATE_DIR = $statePath
    $env:OPENCLAW_CONFIG_PATH = $configPath
    $env:OPENCLAW_PORTABLE_ROOT = $bundleRoot
    $env:CODEX_HOME = Join-Path $statePath 'codex-home'
    [void](New-Item -ItemType Directory -Path $env:CODEX_HOME)
    $env:OPENCLAW_GATEWAY_TOKEN = $token
    $env:OPENCLAW_GATEWAY_PORT = [string]$port
    $env:TEMP = $tempPath
    $env:TMP = $tempPath
    [Environment]::SetEnvironmentVariable('OPENAI_API_KEY', $null, 'Process')
    [Environment]::SetEnvironmentVariable('CODEX_API_KEY', $null, 'Process')

    $managedCodexVersion = Assert-ManagedCodexRuntime -Paths $paths
    Write-Host "Verified bundled $managedCodexVersion." -ForegroundColor DarkGray

    $arguments = Join-WindowsCommandLine -ArgumentList @(
        $paths.OpenClawEntry,
        'gateway',
        '--port', [string]$port,
        '--bind', 'loopback',
        '--auth', 'token',
        '--verbose')

    $firstOut = Join-Path $smokeRoot 'first.stdout.log'
    $firstErr = Join-Path $smokeRoot 'first.stderr.log'
    $first = Start-Process `
        -FilePath $paths.Node `
        -ArgumentList $arguments `
        -WorkingDirectory $bundleRoot `
        -WindowStyle Hidden `
        -RedirectStandardOutput $firstOut `
        -RedirectStandardError $firstErr `
        -PassThru
    Wait-GatewayReady -Process $first -Port $port -StandardOutput $firstOut -StandardError $firstErr

    $pluginOutput = & $paths.Node $paths.OpenClawEntry plugins list --enabled --json
    if ($LASTEXITCODE -ne 0) {
        throw "Codex plugin inventory failed: $($pluginOutput -join [Environment]::NewLine)"
    }
    $pluginInventory = ($pluginOutput -join [Environment]::NewLine) | ConvertFrom-Json
    $codexPlugins = @($pluginInventory.plugins | Where-Object { $_.id -eq 'codex' -and $_.enabled -eq $true })
    if ($codexPlugins.Count -ne 1) {
        throw 'The bundled Codex plugin was not loaded and enabled exactly once.'
    }

    $authenticatedOutput = Wait-GatewayRpc -Process $first -Paths $paths

    $env:OPENCLAW_GATEWAY_TOKEN = 'wrong-' + [guid]::NewGuid().ToString('N')
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $wrongTokenOutput = & $paths.Node $paths.OpenClawEntry gateway status --require-rpc --json 2>&1
        $wrongTokenExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedPreference
    }
    if ($wrongTokenExitCode -eq 0) {
        throw "Gateway accepted an incorrect token: $($wrongTokenOutput -join [Environment]::NewLine)"
    }
    $env:OPENCLAW_GATEWAY_TOKEN = $token

    Stop-GatewayGracefully -Process $first
    if (Test-TcpPortOpen -Port $port -TimeoutMilliseconds 300) {
        throw 'Gateway port remained open after graceful shutdown.'
    }
    $firstLog = Get-Content -LiteralPath $firstOut -Raw
    if (-not $firstLog.Contains('signal SIGINT received') -or
        -not $firstLog.Contains('[shutdown] completed cleanly')) {
        throw 'Gateway logs did not confirm a clean SIGINT shutdown.'
    }
    if (-not $firstLog.Contains('Registered plugin command: /codex')) {
        throw 'Gateway logs did not confirm registration of the reserved /codex command.'
    }
    if ($firstLog.Contains('used external cli oauth bootstrap')) {
        throw 'Gateway startup imported OAuth from a non-portable Codex home.'
    }
    $firstErrorLog = Get-Content -LiteralPath $firstErr -Raw
    if ($firstErrorLog.Contains('only bundled plugins can claim reserved command ownership') -or
        $firstErrorLog.Contains("can't verify where this plugin came from")) {
        throw 'The Codex plugin loaded without the bundled official-plugin trust boundary.'
    }

    $secondOut = Join-Path $smokeRoot 'second.stdout.log'
    $secondErr = Join-Path $smokeRoot 'second.stderr.log'
    $second = Start-Process `
        -FilePath $paths.Node `
        -ArgumentList $arguments `
        -WorkingDirectory $bundleRoot `
        -WindowStyle Hidden `
        -RedirectStandardOutput $secondOut `
        -RedirectStandardError $secondErr `
        -PassThru
    Wait-GatewayReady -Process $second -Port $port -StandardOutput $secondOut -StandardError $secondErr
    [void](Wait-GatewayRpc -Process $second -Paths $paths)
    Stop-GatewayGracefully -Process $second

    Write-Host 'Gateway auth, graceful shutdown, and immediate restart checks passed.' -ForegroundColor Green
}
finally {
    $env:OPENCLAW_GATEWAY_TOKEN = $token
    foreach ($process in @($first, $second)) {
        if ($null -ne $process) {
            $process.Refresh()
            if (-not $process.HasExited) {
                $savedPreference = $ErrorActionPreference
                $ErrorActionPreference = 'SilentlyContinue'
                try {
                    & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F 2>$null | Out-Null
                }
                finally {
                    $ErrorActionPreference = $savedPreference
                }
                [void]$process.WaitForExit(5000)
            }
            $process.Dispose()
        }
    }

    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }

    $candidate = [System.IO.Path]::GetFullPath($smokeRoot)
    $parentPrefix = $smokeParent.TrimEnd('\') + '\'
    if ($candidate.StartsWith($parentPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
        [System.IO.Directory]::Exists($candidate)) {
        $lastDeleteError = $null
        for ($attempt = 1; $attempt -le 20; $attempt++) {
            try {
                [System.IO.Directory]::Delete($candidate, $true)
                $lastDeleteError = $null
                break
            }
            catch {
                $lastDeleteError = $_
                Start-Sleep -Seconds 1
            }
        }
        if ($null -ne $lastDeleteError) {
            throw $lastDeleteError
        }
    }
}
