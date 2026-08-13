[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Query,

    [ValidateRange(1, 100000)]
    [int]$MaxResults = 100,

    [ValidateSet('Auto', 'Dll', 'Es')]
    [string]$Backend = 'Auto',

    [string]$DllPath,
    [string]$EsPath,
    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'
$detectScript = Join-Path $PSScriptRoot 'detect_everything.ps1'

function Convert-FileTimeUtc {
    param([Int64]$Value)
    if ($Value -le 0) { return $null }
    try { return [DateTime]::FromFileTimeUtc($Value).ToString('o') } catch { return $null }
}

function Get-PathMetadata {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        return [ordered]@{
            path = $item.FullName
            name = $item.Name
            kind = if ($item.PSIsContainer) { 'folder' } else { 'file' }
            size = if ($item.PSIsContainer) { $null } else { [Int64]$item.Length }
            modified_utc = $item.LastWriteTimeUtc.ToString('o')
            attributes = $item.Attributes.ToString()
            exists = $true
        }
    } catch {
        return [ordered]@{
            path = $Path
            name = Split-Path -Leaf $Path
            kind = 'unknown'
            size = $null
            modified_utc = $null
            attributes = $null
            exists = $false
        }
    }
}

function Invoke-EsSearch {
    param([string]$Executable, [string]$SearchText, [int]$Limit)

    $lines = @(& $Executable -n $Limit $SearchText 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "es.exe failed with exit code $LASTEXITCODE`: $($lines -join [Environment]::NewLine)"
    }

    $items = foreach ($line in $lines) {
        $path = [string]$line
        if (-not [string]::IsNullOrWhiteSpace($path)) { Get-PathMetadata -Path $path }
    }

    return [ordered]@{
        backend = 'es'
        query = $SearchText
        max_results = $Limit
        result_count = @($items).Count
        total_results = $null
        truncated = $null
        truncation_known = $false
        results = @($items)
    }
}

function Invoke-DllSearch {
    param([string]$LibraryPath, [string]$SearchText, [int]$Limit)

    $dllName = Split-Path -Leaf $LibraryPath
    $processArchitecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    $expected = @{
        X64 = 'Everything64.dll'
        X86 = 'Everything32.dll'
        Arm64 = 'EverythingARM64.dll'
        Arm = 'EverythingARM.dll'
    }[$processArchitecture]
    if (-not $expected) { throw "Unsupported PowerShell process architecture: $processArchitecture" }
    if ($dllName -ne $expected) {
        throw "PowerShell process architecture requires $expected, but $dllName was selected."
    }

    $kernelSource = @'
using System;
using System.Runtime.InteropServices;
public static class EverythingKernel32 {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SetDllDirectory(string lpPathName);
}
'@
    if (-not ('EverythingKernel32' -as [type])) { Add-Type -TypeDefinition $kernelSource }
    if (-not [EverythingKernel32]::SetDllDirectory((Split-Path -Parent $LibraryPath))) {
        throw "Could not add the Everything SDK directory to the DLL search path. Win32 error: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }

    $interopSource = @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class EverythingSdk {
    [DllImport("$dllName", CharSet = CharSet.Unicode)] public static extern void Everything_SetSearchW(string search);
    [DllImport("$dllName")] public static extern void Everything_SetRequestFlags(UInt32 flags);
    [DllImport("$dllName")] public static extern void Everything_SetMax(UInt32 max);
    [DllImport("$dllName")] public static extern bool Everything_QueryW(bool wait);
    [DllImport("$dllName")] public static extern UInt32 Everything_GetLastError();
    [DllImport("$dllName")] public static extern UInt32 Everything_GetNumResults();
    [DllImport("$dllName")] public static extern UInt32 Everything_GetTotResults();
    [DllImport("$dllName", CharSet = CharSet.Unicode)] public static extern UInt32 Everything_GetResultFullPathNameW(UInt32 index, StringBuilder buffer, UInt32 size);
    [DllImport("$dllName")] public static extern bool Everything_GetResultSize(UInt32 index, out long size);
    [DllImport("$dllName")] public static extern bool Everything_GetResultDateModified(UInt32 index, out long fileTime);
    [DllImport("$dllName")] public static extern UInt32 Everything_GetResultAttributes(UInt32 index);
    [DllImport("$dllName")] public static extern bool Everything_IsFileResult(UInt32 index);
    [DllImport("$dllName")] public static extern bool Everything_IsFolderResult(UInt32 index);
    [DllImport("$dllName")] public static extern void Everything_Reset();
}
"@
    if (-not ('EverythingSdk' -as [type])) { Add-Type -TypeDefinition $interopSource }

    $requestFlags = 0x00000001 -bor 0x00000004 -bor 0x00000010 -bor 0x00000040 -bor 0x00000100

    [EverythingSdk]::Everything_Reset()
    [EverythingSdk]::Everything_SetSearchW($SearchText)
    [EverythingSdk]::Everything_SetMax([UInt32]$Limit)
    [EverythingSdk]::Everything_SetRequestFlags([UInt32]$requestFlags)

    if (-not [EverythingSdk]::Everything_QueryW($true)) {
        $errorCode = [EverythingSdk]::Everything_GetLastError()
        throw "Everything SDK query failed with error $errorCode. Confirm Everything is running in the same user session."
    }

    $count = [EverythingSdk]::Everything_GetNumResults()
    $total = [EverythingSdk]::Everything_GetTotResults()
    $items = [System.Collections.Generic.List[object]]::new()

    for ($i = 0; $i -lt $count; $i++) {
        $buffer = [Text.StringBuilder]::new(32768)
        [void][EverythingSdk]::Everything_GetResultFullPathNameW([UInt32]$i, $buffer, [UInt32]$buffer.Capacity)

        [Int64]$size = 0
        [Int64]$modified = 0
        $hasSize = [EverythingSdk]::Everything_GetResultSize([UInt32]$i, [ref]$size)
        $hasModified = [EverythingSdk]::Everything_GetResultDateModified([UInt32]$i, [ref]$modified)
        $attributesValue = [EverythingSdk]::Everything_GetResultAttributes([UInt32]$i)
        $kind = if ([EverythingSdk]::Everything_IsFolderResult([UInt32]$i)) { 'folder' } elseif ([EverythingSdk]::Everything_IsFileResult([UInt32]$i)) { 'file' } else { 'unknown' }
        $path = $buffer.ToString()

        $items.Add([pscustomobject][ordered]@{
            path = $path
            name = Split-Path -Leaf $path
            kind = $kind
            size = if ($hasSize -and $kind -eq 'file') { $size } else { $null }
            modified_utc = if ($hasModified) { Convert-FileTimeUtc $modified } else { $null }
            attributes = ([IO.FileAttributes]$attributesValue).ToString()
            exists = Test-Path -LiteralPath $path
        })
    }

    return [ordered]@{
        backend = 'dll'
        query = $SearchText
        max_results = $Limit
        result_count = $count
        total_results = $total
        truncated = $total -gt $count
        truncation_known = $true
        results = @($items)
    }
}

try {
    $detected = & $detectScript -AsObject
    if (-not $detected.platform.windows) { throw $detected.message }
    if (-not $detected.everything.installed) { throw $detected.message }
    if (-not $detected.everything.running) { throw $detected.message }

    if (-not $DllPath) { $DllPath = $detected.backend.dll }
    if (-not $EsPath) { $EsPath = $detected.backend.es }

    $selectedBackend = if ($Backend -eq 'Auto') {
        if ($DllPath) { 'Dll' } elseif ($EsPath) { 'Es' } else { $null }
    } else { $Backend }

    if (-not $selectedBackend) {
        throw 'No query backend was detected. Install the official Everything SDK DLL or es.exe.'
    }
    if ($selectedBackend -eq 'Dll' -and -not (Test-Path -LiteralPath $DllPath -PathType Leaf)) {
        throw "Everything SDK DLL not found: $DllPath"
    }
    if ($selectedBackend -eq 'Es' -and -not (Test-Path -LiteralPath $EsPath -PathType Leaf)) {
        throw "Everything CLI not found: $EsPath"
    }

    $payload = if ($selectedBackend -eq 'Dll') {
        Invoke-DllSearch -LibraryPath $DllPath -SearchText $Query -Limit $MaxResults
    } else {
        Invoke-EsSearch -Executable $EsPath -SearchText $Query -Limit $MaxResults
    }

    $payload | ConvertTo-Json -Depth 8 -Compress:(-not $Pretty)
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
