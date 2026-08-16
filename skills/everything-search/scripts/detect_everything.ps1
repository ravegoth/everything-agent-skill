[CmdletBinding()]
param(
    [switch]$Pretty,
    [switch]$AsObject
)

$ErrorActionPreference = 'Stop'

# Detected paths can contain non-ASCII characters, so emit UTF-8 regardless of
# the host console code page. See search_everything.ps1 for the failure mode.
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

function Add-CandidatePath {
    param(
        [System.Collections.Generic.List[string]]$List,
        [AllowNull()][string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if ((Test-Path -LiteralPath $expanded -PathType Leaf) -and -not $List.Contains($expanded)) {
        $List.Add((Resolve-Path -LiteralPath $expanded).Path)
    }
}

function Add-DirectoryCandidates {
    param(
        [System.Collections.Generic.List[string]]$ExeList,
        [System.Collections.Generic.List[string]]$DllList,
        [System.Collections.Generic.List[string]]$EsList,
        [AllowNull()][string]$Directory
    )

    if ([string]::IsNullOrWhiteSpace($Directory)) { return }
    $expanded = [Environment]::ExpandEnvironmentVariables($Directory.Trim().Trim('"'))
    Add-CandidatePath $ExeList (Join-Path $expanded 'Everything.exe')
    Add-CandidatePath $ExeList (Join-Path $expanded 'Everything64.exe')
    Add-CandidatePath $ExeList (Join-Path $expanded 'Everything32.exe')
    Add-CandidatePath $DllList (Join-Path $expanded 'Everything64.dll')
    Add-CandidatePath $DllList (Join-Path $expanded 'Everything32.dll')
    Add-CandidatePath $DllList (Join-Path $expanded 'EverythingARM64.dll')
    Add-CandidatePath $DllList (Join-Path $expanded 'EverythingARM.dll')
    Add-CandidatePath $EsList (Join-Path $expanded 'es.exe')
}

# Everything answers queries through a local IPC window. Looking for that window
# detects installed, portable, and renamed instances alike, which a search for
# known executable names cannot do.
function Test-EverythingIpcWindow {
    try {
        $source = @'
using System;
using System.Runtime.InteropServices;
public static class EverythingIpcProbe {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr FindWindowW(string className, string windowName);
}
'@
        if (-not ('EverythingIpcProbe' -as [type])) { Add-Type -TypeDefinition $source }
        return [EverythingIpcProbe]::FindWindowW('EVERYTHING_TASKBAR_NOTIFICATION', $null) -ne [IntPtr]::Zero
    } catch {
        return $false
    }
}

if ($env:OS -ne 'Windows_NT') {
    $notWindows = [ordered]@{
        platform = [ordered]@{ windows = $false; architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() }
        everything = [ordered]@{ installed = $false; running = $false; ipc = $false; executable = $null }
        backend = [ordered]@{ ready = $false; preferred = $null; dll = $null; es = $null }
        message = 'Everything Search is supported only on Windows.'
    }
    if ($AsObject) { return [pscustomobject]$notWindows }
    $notWindows | ConvertTo-Json -Depth 6 -Compress:(-not $Pretty)
    exit 2
}

$exeCandidates = [System.Collections.Generic.List[string]]::new()
$dllCandidates = [System.Collections.Generic.List[string]]::new()
$esCandidates = [System.Collections.Generic.List[string]]::new()

foreach ($commandName in @('Everything.exe', 'Everything64.exe', 'Everything32.exe')) {
    $command = Get-Command $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { Add-CandidatePath $exeCandidates $command.Source }
}
$esCommand = Get-Command 'es.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($esCommand) { Add-CandidatePath $esCandidates $esCommand.Source }

foreach ($process in @(Get-Process -Name 'Everything', 'Everything64', 'Everything32' -ErrorAction SilentlyContinue)) {
    try { Add-CandidatePath $exeCandidates $process.Path } catch { }
}

$programRoots = @(
    $env:ProgramFiles,
    ${env:ProgramFiles(x86)},
    $env:ProgramW6432,
    $env:LOCALAPPDATA,
    $env:APPDATA,
    $env:ProgramData
) | Where-Object { $_ } | Select-Object -Unique

$standardDirs = @(
    foreach ($root in $programRoots) {
        Join-Path $root 'Everything'
        Join-Path $root 'Everything 1.5a'
    }
    (Join-Path $env:LOCALAPPDATA 'EverythingAgent\SDK\DLL')
    (Join-Path $env:LOCALAPPDATA 'EverythingAgent\CLI')
    $env:EVERYTHING_HOME
    $env:EVERYTHING_SDK
) | Where-Object { $_ }

foreach ($directory in $standardDirs) {
    Add-DirectoryCandidates $exeCandidates $dllCandidates $esCandidates $directory
    Add-DirectoryCandidates $exeCandidates $dllCandidates $esCandidates (Join-Path $directory 'DLL')
}

$managedBackendRoot = Join-Path $env:LOCALAPPDATA 'EverythingAgent'
if (Test-Path -LiteralPath $managedBackendRoot -PathType Container) {
    foreach ($backendFile in @(Get-ChildItem -LiteralPath $managedBackendRoot -File -Recurse -ErrorAction SilentlyContinue)) {
        switch -Regex ($backendFile.Name) {
            '^Everything(32|64|ARM|ARM64)\.dll$' { Add-CandidatePath $dllCandidates $backendFile.FullName; continue }
            '^es\.exe$' { Add-CandidatePath $esCandidates $backendFile.FullName }
        }
    }
}

$registryRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

foreach ($root in $registryRoots) {
    foreach ($entry in @(Get-ItemProperty $root -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'Everything*' })) {
        Add-DirectoryCandidates $exeCandidates $dllCandidates $esCandidates $entry.InstallLocation
        if ($entry.DisplayIcon) {
            $iconPath = ($entry.DisplayIcon -replace ',\d+$', '').Trim('"')
            Add-CandidatePath $exeCandidates $iconPath
            Add-DirectoryCandidates $exeCandidates $dllCandidates $esCandidates (Split-Path -Parent $iconPath)
        }
    }
}

$appPathKeys = foreach ($hive in @('HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node', 'HKCU:\SOFTWARE')) {
    foreach ($exeName in @('Everything.exe', 'Everything64.exe', 'Everything32.exe')) {
        "$hive\Microsoft\Windows\CurrentVersion\App Paths\$exeName"
    }
}

foreach ($appPathKey in $appPathKeys) {
    $entry = Get-ItemProperty -LiteralPath $appPathKey -ErrorAction SilentlyContinue
    if (-not $entry) { continue }
    $registeredExe = $entry.'(default)'
    if ($registeredExe) {
        $registeredExe = $registeredExe.Trim().Trim('"')
        Add-CandidatePath $exeCandidates $registeredExe
        Add-DirectoryCandidates $exeCandidates $dllCandidates $esCandidates (Split-Path -Parent $registeredExe)
    }
    if ($entry.Path) {
        Add-DirectoryCandidates $exeCandidates $dllCandidates $esCandidates $entry.Path
    }
}

foreach ($exePath in @($exeCandidates)) {
    Add-DirectoryCandidates $exeCandidates $dllCandidates $esCandidates (Split-Path -Parent $exePath)
}

$processArchitecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
$expectedDll = @{
    X64 = 'Everything64.dll'
    X86 = 'Everything32.dll'
    Arm64 = 'EverythingARM64.dll'
    Arm = 'EverythingARM.dll'
}[$processArchitecture]
$dll = @($dllCandidates | Where-Object { (Split-Path -Leaf $_) -eq $expectedDll } | Select-Object -First 1)[0]

$exe = @($exeCandidates | Select-Object -First 1)[0]
$es = @($esCandidates | Select-Object -First 1)[0]
$ipcAvailable = Test-EverythingIpcWindow
$processRunning = @(Get-Process -Name 'Everything', 'Everything64', 'Everything32' -ErrorAction SilentlyContinue).Count -gt 0
$running = [bool]($ipcAvailable -or $processRunning)
$preferred = if ($dll) { 'dll' } elseif ($es) { 'es' } else { $null }

$installed = [bool]($exe -or $running)

$message = if (-not $installed) {
    'Everything was not detected. Install the full application from voidtools.'
} elseif (-not $running) {
    'Everything is installed but is not currently running.'
} elseif (-not $ipcAvailable) {
    'Everything is running, but its IPC window was not found. Run Everything and this shell in the same interactive user session; a service-only instance cannot answer queries.'
} elseif (-not $preferred) {
    'Everything is running, but neither the SDK DLL nor es.exe was detected.'
} else {
    "Everything is ready through the $preferred backend."
}

$result = [ordered]@{
    platform = [ordered]@{
        windows = $true
        process_bitness = if ([Environment]::Is64BitProcess) { 64 } else { 32 }
        process_architecture = $processArchitecture
        architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    }
    everything = [ordered]@{
        installed = $installed
        running = $running
        ipc = $ipcAvailable
        executable = $exe
        candidates = @($exeCandidates)
    }
    backend = [ordered]@{
        ready = [bool]($running -and $preferred)
        preferred = $preferred
        dll = $dll
        dll_candidates = @($dllCandidates)
        es = $es
        es_candidates = @($esCandidates)
    }
    message = $message
}

if ($AsObject) { return [pscustomobject]$result }
$result | ConvertTo-Json -Depth 6 -Compress:(-not $Pretty)
