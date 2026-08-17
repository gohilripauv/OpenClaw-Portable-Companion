[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)][int]$GatewayPort = 18789,
    [switch]$AllowInsecureFileSystem,
    [switch]$SkipSignatureCheck,
    [switch]$SkipOnboarding
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'PortableEnvironment.ps1')

$gatewayProcess = $null
$companionProcess = $null
$jobHandle = [IntPtr]::Zero

function Initialize-KillOnCloseJob {
    if (-not ('OpenClawPortable.NativeJob' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace OpenClawPortable
{
    public static class NativeJob
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct IO_COUNTERS
        {
            public UInt64 ReadOperationCount;
            public UInt64 WriteOperationCount;
            public UInt64 OtherOperationCount;
            public UInt64 ReadTransferCount;
            public UInt64 WriteTransferCount;
            public UInt64 OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_BASIC_LIMIT_INFORMATION
        {
            public Int64 PerProcessUserTimeLimit;
            public Int64 PerJobUserTimeLimit;
            public UInt32 LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public UInt32 ActiveProcessLimit;
            public UIntPtr Affinity;
            public UInt32 PriorityClass;
            public UInt32 SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        {
            public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
            public IO_COUNTERS IoInfo;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryUsed;
            public UIntPtr PeakJobMemoryUsed;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr CreateJobObject(IntPtr attributes, string name);

        [DllImport("kernel32.dll")]
        private static extern bool SetInformationJobObject(
            IntPtr job,
            int informationClass,
            IntPtr information,
            UInt32 informationLength);

        [DllImport("kernel32.dll")]
        public static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

        [DllImport("kernel32.dll")]
        public static extern bool CloseHandle(IntPtr handle);

        public static IntPtr CreateKillOnCloseJob()
        {
            const UInt32 JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;
            const int JobObjectExtendedLimitInformation = 9;

            IntPtr job = CreateJobObject(IntPtr.Zero, null);
            if (job == IntPtr.Zero)
                return IntPtr.Zero;

            JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
            info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            int length = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
            IntPtr pointer = Marshal.AllocHGlobal(length);
            try
            {
                Marshal.StructureToPtr(info, pointer, false);
                if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, pointer, (UInt32)length))
                {
                    CloseHandle(job);
                    return IntPtr.Zero;
                }
                return job;
            }
            finally
            {
                Marshal.FreeHGlobal(pointer);
            }
        }
    }

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

            // Ignore the event in this launcher while broadcasting it to the
            // Gateway's dedicated hidden console. Node maps it to SIGINT.
            SetConsoleCtrlHandler(IntPtr.Zero, true);
            bool sent = GenerateConsoleCtrlEvent(CTRL_C_EVENT, 0);
            System.Threading.Thread.Sleep(300);
            FreeConsole();
            AttachConsole(ATTACH_PARENT_PROCESS);
            SetConsoleCtrlHandler(IntPtr.Zero, false);
            return sent;
        }
    }
}
"@
    }
    return [OpenClawPortable.NativeJob]::CreateKillOnCloseJob()
}

function Stop-ExactProcessTree {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)

    try {
        $Process.Refresh()
        if ($Process.HasExited) {
            return
        }

        if ([OpenClawPortable.ConsoleSignal]::SendCtrlC($Process.Id)) {
            if ($Process.WaitForExit(20000)) {
                return
            }
            Write-Warning 'The Gateway did not finish graceful SIGINT cleanup within 20 seconds; forcing its exact process tree to stop.'
        }
        else {
            Write-Warning 'Could not deliver graceful SIGINT to the Gateway; forcing its exact process tree to stop.'
        }

        $savedPreference = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        try {
            & "$env:SystemRoot\System32\taskkill.exe" /PID $Process.Id /T /F 2>$null | Out-Null
        }
        finally {
            $ErrorActionPreference = $savedPreference
        }
    }
    catch {
        Write-Warning "Could not stop Gateway PID $($Process.Id): $($_.Exception.Message)"
    }
}

try {
    $root = Get-PortableRoot
    $paths = Get-PortablePaths -Root $root
    Assert-PortablePayload -Paths $paths
    Test-BundleManifest -Paths $paths
    Test-CompanionSignature -Paths $paths -SkipSignatureCheck:$SkipSignatureCheck

    [void](Initialize-PortableState `
        -Paths $paths `
        -GatewayPort $GatewayPort `
        -AllowInsecureFileSystem:$AllowInsecureFileSystem)

    if (-not $SkipOnboarding -and -not (Test-Path -LiteralPath $paths.ConfiguredMarker -PathType Leaf)) {
        Write-Host ''
        Write-Host 'First run: ChatGPT/Codex OAuth has not been completed.' -ForegroundColor Yellow
        $answer = Read-Host 'Sign in now? [Y/n]'
        if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^[Yy]') {
            & (Join-Path $PSScriptRoot 'Configure-OpenAI.ps1') `
                -AllowInsecureFileSystem:$AllowInsecureFileSystem
        }
        else {
            Write-Warning 'Continuing without sign-in. The Companion can open, but Codex chats will remain unavailable; there is no API-key fallback.'
        }
    }

    if (Test-TcpPortOpen -Port $GatewayPort) {
        throw "TCP port $GatewayPort is already in use. This launcher will not stop or reuse an unidentified process."
    }

    $standardOutput = Join-Path $paths.Logs 'gateway.stdout.log'
    $standardError = Join-Path $paths.Logs 'gateway.stderr.log'
    $arguments = Join-WindowsCommandLine -ArgumentList @(
        $paths.OpenClawEntry,
        'gateway',
        '--port', [string]$GatewayPort,
        '--bind', 'loopback',
        '--auth', 'token')

    $jobHandle = Initialize-KillOnCloseJob
    if ($jobHandle -eq [IntPtr]::Zero) {
        throw 'Could not create the required kill-on-close job. The Gateway was not started.'
    }

    Write-Host ''
    Write-Host "Starting authenticated Gateway on 127.0.0.1:$GatewayPort..." -ForegroundColor Cyan
    $gatewayProcess = Start-Process `
        -FilePath $paths.Node `
        -ArgumentList $arguments `
        -WorkingDirectory $root `
        -WindowStyle Hidden `
        -RedirectStandardOutput $standardOutput `
        -RedirectStandardError $standardError `
        -PassThru

    if (-not [OpenClawPortable.NativeJob]::AssignProcessToJobObject($jobHandle, $gatewayProcess.Handle)) {
        throw 'Could not attach the Gateway to the required kill-on-close job.'
    }

    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Date) -lt $deadline) {
        $gatewayProcess.Refresh()
        if ($gatewayProcess.HasExited) {
            $details = if (Test-Path -LiteralPath $standardError) {
                (Get-Content -LiteralPath $standardError -Tail 30) -join [Environment]::NewLine
            } else { 'No Gateway error log was produced.' }
            throw "The Gateway exited before becoming ready.`n$details"
        }
        if (Test-TcpPortOpen -Port $GatewayPort -TimeoutMilliseconds 500) {
            break
        }
        Start-Sleep -Milliseconds 400
    }
    if (-not (Test-TcpPortOpen -Port $GatewayPort -TimeoutMilliseconds 500)) {
        throw "The Gateway did not become ready within 45 seconds. See $standardError"
    }

    Write-Host 'Starting the official signed OpenClaw Companion...' -ForegroundColor Cyan
    Write-Host 'Use Exit from the tray icon when finished; the portable Gateway will then stop.'
    $companionProcess = Start-Process `
        -FilePath $paths.CompanionExe `
        -WorkingDirectory (Split-Path -Parent $paths.CompanionExe) `
        -PassThru
    Wait-Process -Id $companionProcess.Id
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
finally {
    if ($null -ne $gatewayProcess) {
        Stop-ExactProcessTree -Process $gatewayProcess
    }
    if ($jobHandle -ne [IntPtr]::Zero) {
        [void][OpenClawPortable.NativeJob]::CloseHandle($jobHandle)
    }
}
