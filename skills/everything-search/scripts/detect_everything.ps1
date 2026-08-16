[CmdletBinding()]
param(
    [switch]$Pretty,
    [switch]$AsObject
)

$ErrorActionPreference = 'Stop'

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
    Add-CandidatePath $DllList (Join-Path $expanded 'Everything64.dll')
    Add-CandidatePath $DllList (Join-Path $expanded 'Everything32.dll')
    Add-CandidatePath $DllList (Join-Path $expanded 'EverythingARM64.dll')
    Add-CandidatePath $DllList (Join-Path $expanded 'EverythingARM.dll')
    Add-CandidatePath $EsList (Join-Path $expanded 'es.exe')
}

if ($env:OS -ne 'Windows_NT') {
    $notWindows = [ordered]@{
        platform = [ordered]@{ windows = $false; architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() }
        everything = [ordered]@{ installed = $false; running = $false; executable = $null }
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

foreach ($commandName in @('Everything.exe', 'Everything64.exe')) {
    $command = Get-Command $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { Add-CandidatePath $exeCandidates $command.Source }
}
$esCommand = Get-Command 'es.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($esCommand) { Add-CandidatePath $esCandidates $esCommand.Source }

foreach ($process in @(Get-Process -Name 'Everything', 'Everything64' -ErrorAction SilentlyContinue)) {
    try { Add-CandidatePath $exeCandidates $process.Path } catch { }
}

$standardDirs = @(
    (Join-Path $env:ProgramFiles 'Everything'),
    (Join-Path $env:ProgramFiles 'Everything 1.5a'),
    $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Everything' }),
    $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Everything 1.5a' }),
    (Join-Path $env:LOCALAPPDATA 'Everything'),
    (Join-Path $env:LOCALAPPDATA 'EverythingAgent\SDK\DLL'),
    (Join-Path $env:LOCALAPPDATA 'EverythingAgent\CLI'),
    $env:EVERYTHING_HOME,
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
$running = @(Get-Process -Name 'Everything', 'Everything64' -ErrorAction SilentlyContinue).Count -gt 0
$preferred = if ($dll) { 'dll' } elseif ($es) { 'es' } else { $null }

$installed = [bool]($exe -or $running)

$message = if (-not $installed) {
    'Everything was not detected. Install the full application from voidtools.'
} elseif (-not $running) {
    'Everything is installed but is not currently running.'
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
