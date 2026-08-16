Set-StrictMode -Version 2.0

function Get-PortableRoot {
    $candidate = Join-Path $PSScriptRoot '..'
    return [System.IO.Path]::GetFullPath($candidate)
}

function Get-PortablePaths {
    param([Parameter(Mandatory = $true)][string]$Root)

    $data = Join-Path $Root 'data'
    return [pscustomobject]@{
        Root             = $Root
        Data             = $data
        State            = Join-Path $data 'openclaw-state'
        ConfigDirectory  = Join-Path $data 'config'
        Config           = Join-Path $data 'config\openclaw.json'
        Companion        = Join-Path $data 'companion'
        CompanionSetup   = Join-Path $data 'companion-setup'
        Workspace        = Join-Path $data 'workspace'
        Secrets          = Join-Path $data 'secrets'
        Token            = Join-Path $data 'secrets\gateway-token.txt'
        GatewayId        = Join-Path $data 'secrets\gateway-id.txt'
        Runtime          = Join-Path $data 'runtime'
        Logs             = Join-Path $data 'logs'
        Temp             = Join-Path $data 'temp'
        NpmCache         = Join-Path $data 'npm-cache'
        Node             = Join-Path $Root 'runtime\node.exe'
        OpenClawEntry    = Join-Path $Root 'gateway\node_modules\openclaw\openclaw.mjs'
        CompanionExe     = Join-Path $Root 'app\OpenClaw.Tray.WinUI.exe'
        Versions         = Join-Path $Root 'versions.json'
        BundleManifest   = Join-Path $Root 'bundle-manifest.json'
        ConfiguredMarker = Join-Path $data 'config\openai-configured.marker'
    }
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Value, $encoding)
}

function Get-PortableFileSystem {
    param([Parameter(Mandatory = $true)][string]$Root)

    try {
        $driveRoot = [System.IO.Path]::GetPathRoot($Root)
        if ([string]::IsNullOrWhiteSpace($driveRoot)) {
            return 'Unknown'
        }
        $drive = New-Object System.IO.DriveInfo($driveRoot)
        return $drive.DriveFormat
    }
    catch {
        return 'Unknown'
    }
}

function Confirm-PortableFileSystemSafety {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [switch]$AllowInsecureFileSystem,
        [switch]$NonInteractive
    )

    $format = Get-PortableFileSystem -Root $Root
    if ($format -in @('NTFS', 'ReFS')) {
        return $format
    }

    $message = @"
The portable folder is on '$format'. That filesystem may not enforce Windows ACLs.
OpenClaw stores OAuth credentials and a local Gateway token inside the data folder.
Use an NTFS/ReFS volume, ideally protected with BitLocker To Go.
"@
    Write-Warning $message.Trim()

    if ($AllowInsecureFileSystem) {
        return $format
    }
    if ($NonInteractive) {
        throw 'Refusing to store credentials on a filesystem without enforceable Windows ACLs.'
    }

    $answer = Read-Host "Type ALLOW to continue anyway, or press Enter to stop"
    if ($answer -cne 'ALLOW') {
        throw 'Cancelled because the portable storage does not provide enforceable Windows ACLs.'
    }
    return $format
}

function Set-RestrictedAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$File
    )

    $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $icacls = Join-Path $env:SystemRoot 'System32\icacls.exe'

    # Reset first so a folder copied from another NTFS volume cannot retain an
    # unrelated explicit ACE. Then remove inheritance and write the complete
    # allow-list. icacls changes only the DACL, avoiding Set-Acl's attempt to
    # rewrite audit metadata (which requires SeSecurityPrivilege on reruns).
    $resetOutput = & $icacls $Path /reset 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Could not reset ACLs on $Path`: $($resetOutput -join [Environment]::NewLine)"
    }

    if ($File) {
        $grants = @(
            "*$($currentSid):F",
            '*S-1-5-18:F',
            '*S-1-5-32-544:F')
    }
    else {
        $grants = @(
            "*$($currentSid):(OI)(CI)F",
            '*S-1-5-18:(OI)(CI)F',
            '*S-1-5-32-544:(OI)(CI)F')
    }

    $grantOutput = & $icacls $Path /inheritance:r /grant:r @grants 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Could not restrict ACLs on $Path`: $($grantOutput -join [Environment]::NewLine)"
    }

    $result = Get-Acl -LiteralPath $Path
    if (-not $result.AreAccessRulesProtected -or @($result.Access).Count -ne 3) {
        throw "ACL verification failed for $Path."
    }
}

function Initialize-PortableDirectories {
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)][string]$FileSystem
    )

    if (-not (Test-Path -LiteralPath $Paths.Data -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $Paths.Data)
    }

    if ($FileSystem -in @('NTFS', 'ReFS')) {
        Set-RestrictedAcl -Path $Paths.Data
    }

    foreach ($directory in @(
        $Paths.State,
        $Paths.ConfigDirectory,
        $Paths.Companion,
        $Paths.CompanionSetup,
        $Paths.Workspace,
        $Paths.Secrets,
        $Paths.Runtime,
        $Paths.Logs,
        $Paths.Temp,
        $Paths.NpmCache)) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            [void](New-Item -ItemType Directory -Path $directory)
        }
    }
}

function Assert-PortablePayload {
    param([Parameter(Mandatory = $true)]$Paths)

    foreach ($required in @(
        $Paths.Node,
        $Paths.OpenClawEntry,
        $Paths.CompanionExe,
        $Paths.Versions)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "The portable payload is incomplete. Missing: $required"
        }
    }
}

function Test-BundleManifest {
    param([Parameter(Mandatory = $true)]$Paths)

    if (-not (Test-Path -LiteralPath $Paths.BundleManifest -PathType Leaf)) {
        Write-Warning 'bundle-manifest.json is missing; key-file integrity could not be checked.'
        return
    }

    $manifest = Get-Content -LiteralPath $Paths.BundleManifest -Raw | ConvertFrom-Json
    foreach ($entry in @($manifest.files)) {
        $candidate = [System.IO.Path]::GetFullPath((Join-Path $Paths.Root ([string]$entry.path)))
        $rootPrefix = $Paths.Root.TrimEnd('\') + '\'
        if (-not $candidate.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Manifest path escapes the portable root: $($entry.path)"
        }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Manifest file is missing: $($entry.path)"
        }
        $actual = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne ([string]$entry.sha256).ToLowerInvariant()) {
            throw "Integrity check failed for $($entry.path). Re-download the release ZIP."
        }
    }
}

function Test-CompanionSignature {
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [switch]$SkipSignatureCheck
    )

    if ($SkipSignatureCheck) {
        Write-Warning 'The OpenClaw Companion Authenticode check was explicitly skipped.'
        return
    }

    $versions = Get-Content -LiteralPath $Paths.Versions -Raw | ConvertFrom-Json
    $expectedSubject = [string]$versions.companion.signerSubjectContains
    $signature = Get-AuthenticodeSignature -LiteralPath $Paths.CompanionExe
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "The official Companion signature is not valid: $($signature.Status)."
    }
    if ($null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject.IndexOf($expectedSubject, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw 'The Companion signer does not match the publisher recorded in versions.json.'
    }
}

function Set-PortableEnvironment {
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][int]$GatewayPort
    )

    $env:OPENCLAW_HOME = $Paths.State
    $env:OPENCLAW_STATE_DIR = $Paths.State
    $env:OPENCLAW_CONFIG_PATH = $Paths.Config
    $env:OPENCLAW_GATEWAY_TOKEN = $Token
    $env:OPENCLAW_GATEWAY_PORT = [string]$GatewayPort
    $env:OPENCLAW_TRAY_DATA_DIR = $Paths.Companion
    $env:OPENCLAW_TRAY_LOCAL_DATA_DIR = $Paths.CompanionSetup
    $env:OPENCLAW_TRAY_LOCALAPPDATA_DIR = $Paths.CompanionSetup
    $env:OPENCLAW_SKIP_UPDATE_CHECK = '1'
    $env:NPM_CONFIG_CACHE = $Paths.NpmCache
    $env:TEMP = $Paths.Temp
    $env:TMP = $Paths.Temp
}

function Get-OrCreateGatewayToken {
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)][string]$FileSystem
    )

    if (Test-Path -LiteralPath $Paths.Token -PathType Leaf) {
        $token = (Get-Content -LiteralPath $Paths.Token -Raw).Trim()
        if ($token -notmatch '^[A-Za-z0-9_-]{40,100}$') {
            throw 'The saved Gateway token is malformed. Remove data\secrets\gateway-token.txt to rotate it.'
        }
    }
    else {
        $bytes = New-Object byte[] 32
        $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $generator.GetBytes($bytes)
        }
        finally {
            $generator.Dispose()
        }
        $token = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        Write-Utf8NoBom -Path $Paths.Token -Value ($token + [Environment]::NewLine)
    }

    if ($FileSystem -in @('NTFS', 'ReFS')) {
        Set-RestrictedAcl -Path $Paths.Token -File
    }
    return $token
}

function Get-OrCreateGatewayId {
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)][string]$FileSystem
    )

    if (Test-Path -LiteralPath $Paths.GatewayId -PathType Leaf) {
        $id = (Get-Content -LiteralPath $Paths.GatewayId -Raw).Trim()
        $parsed = [guid]::Empty
        if (-not [guid]::TryParse($id, [ref]$parsed)) {
            throw 'The saved portable Gateway ID is malformed.'
        }
    }
    else {
        $id = [guid]::NewGuid().ToString('D')
        Write-Utf8NoBom -Path $Paths.GatewayId -Value ($id + [Environment]::NewLine)
    }

    if ($FileSystem -in @('NTFS', 'ReFS')) {
        Set-RestrictedAcl -Path $Paths.GatewayId -File
    }
    return $id
}

function Set-JsonProperty {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        $Value
    )

    if ($InputObject.PSObject.Properties.Name -contains $Name) {
        $InputObject.$Name = $Value
    }
    else {
        $InputObject | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Initialize-OpenClawConfig {
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)][int]$GatewayPort
    )

    if (Test-Path -LiteralPath $Paths.Config -PathType Leaf) {
        return
    }

    $config = [ordered]@{
        gateway = [ordered]@{
            mode = 'local'
            port = $GatewayPort
            bind = 'loopback'
            auth = [ordered]@{
                mode = 'token'
                token = '${OPENCLAW_GATEWAY_TOKEN}'
            }
        }
        agents = [ordered]@{
            defaults = [ordered]@{
                workspace = $Paths.Workspace
                model = [ordered]@{
                    primary = 'openai/gpt-5.6-sol'
                }
            }
        }
    }
    Write-Utf8NoBom -Path $Paths.Config -Value (($config | ConvertTo-Json -Depth 10) + [Environment]::NewLine)
}

function Initialize-CompanionRegistry {
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][string]$GatewayId,
        [Parameter(Mandatory = $true)][int]$GatewayPort
    )

    $registryPath = Join-Path $Paths.Companion 'gateways.json'
    $gatewayUrl = "ws://127.0.0.1:$GatewayPort"

    if (Test-Path -LiteralPath $registryPath -PathType Leaf) {
        try {
            $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
        }
        catch {
            throw "The Companion gateway registry is invalid JSON: $registryPath"
        }
    }
    else {
        $registry = [pscustomobject]@{ gateways = @(); activeId = $null }
    }

    if ($null -eq $registry) {
        $registry = [pscustomobject]@{ gateways = @(); activeId = $null }
    }
    if (-not ($registry.PSObject.Properties.Name -contains 'gateways')) {
        $registry | Add-Member -MemberType NoteProperty -Name gateways -Value @()
    }

    $gateways = @($registry.gateways)
    $record = $gateways | Where-Object { $_.id -eq $GatewayId } | Select-Object -First 1
    if ($null -eq $record) {
        $record = [pscustomobject]@{
            id = $GatewayId
            url = $gatewayUrl
            friendlyName = 'Portable local Gateway'
            sharedGatewayToken = $Token
            bootstrapToken = $null
            lastConnected = $null
            isLocal = $false
            requiresV2Signature = $false
            setupManagedDistroName = $null
            sshTunnel = $null
            browserControlPort = $null
        }
        $gateways += $record
    }
    else {
        Set-JsonProperty -InputObject $record -Name 'url' -Value $gatewayUrl
        Set-JsonProperty -InputObject $record -Name 'friendlyName' -Value 'Portable local Gateway'
        Set-JsonProperty -InputObject $record -Name 'sharedGatewayToken' -Value $Token
        Set-JsonProperty -InputObject $record -Name 'bootstrapToken' -Value $null
        Set-JsonProperty -InputObject $record -Name 'isLocal' -Value $false
        Set-JsonProperty -InputObject $record -Name 'setupManagedDistroName' -Value $null
    }

    Set-JsonProperty -InputObject $registry -Name 'gateways' -Value $gateways
    Set-JsonProperty -InputObject $registry -Name 'activeId' -Value $GatewayId
    Write-Utf8NoBom -Path $registryPath -Value (($registry | ConvertTo-Json -Depth 20) + [Environment]::NewLine)
}

function Initialize-CompanionSettings {
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)][string]$GatewayId,
        [Parameter(Mandatory = $true)][int]$GatewayPort
    )

    $settingsPath = Join-Path $Paths.Companion 'settings.json'
    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        return
    }

    $settings = [ordered]@{
        settingsSchemaVersion = 1
        gatewayUrl = "ws://127.0.0.1:$GatewayPort"
        useSshTunnel = $false
        autoStart = $false
        globalHotkeyEnabled = $false
        enableNodeMode = $false
        nodeCanvasEnabled = $false
        nodeScreenEnabled = $false
        nodeCameraEnabled = $false
        nodeLocationEnabled = $false
        nodeBrowserProxyEnabled = $false
        nodeSystemRunEnabled = $false
        enableMcpServer = $false
        enableManagedLocalGatewayAutoRepair = $false
        preferredGatewayId = $GatewayId
        openTelemetryEndpoint = $null
    }
    Write-Utf8NoBom -Path $settingsPath -Value (($settings | ConvertTo-Json -Depth 10) + [Environment]::NewLine)
}

function Initialize-PortableState {
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)][int]$GatewayPort,
        [switch]$AllowInsecureFileSystem,
        [switch]$NonInteractive
    )

    $fileSystem = Confirm-PortableFileSystemSafety `
        -Root $Paths.Root `
        -AllowInsecureFileSystem:$AllowInsecureFileSystem `
        -NonInteractive:$NonInteractive
    Initialize-PortableDirectories -Paths $Paths -FileSystem $fileSystem
    $token = Get-OrCreateGatewayToken -Paths $Paths -FileSystem $fileSystem
    $gatewayId = Get-OrCreateGatewayId -Paths $Paths -FileSystem $fileSystem
    Set-PortableEnvironment -Paths $Paths -Token $token -GatewayPort $GatewayPort
    Initialize-OpenClawConfig -Paths $Paths -GatewayPort $GatewayPort
    Initialize-CompanionRegistry -Paths $Paths -Token $token -GatewayId $gatewayId -GatewayPort $GatewayPort
    Initialize-CompanionSettings -Paths $Paths -GatewayId $gatewayId -GatewayPort $GatewayPort
    return [pscustomobject]@{ FileSystem = $fileSystem; Token = $token; GatewayId = $gatewayId }
}

function Test-TcpPortOpen {
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutMilliseconds = 250
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync('127.0.0.1', $Port)
        return $task.Wait($TimeoutMilliseconds) -and $client.Connected
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

function ConvertTo-WindowsCommandLineArgument {
    param([AllowEmptyString()][string]$Argument)

    if ($Argument.Length -gt 0 -and $Argument -notmatch '[\s"]') {
        return $Argument
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) {
        [void]$builder.Append(('\' * ($backslashes * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Join-WindowsCommandLine {
    param([Parameter(Mandatory = $true)][string[]]$ArgumentList)
    return (($ArgumentList | ForEach-Object { ConvertTo-WindowsCommandLineArgument -Argument $_ }) -join ' ')
}

function Invoke-PortableOpenClaw {
    param(
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList
    )

    & $Paths.Node $Paths.OpenClawEntry @ArgumentList | Out-Host
    return $LASTEXITCODE
}
