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

# Emit UTF-8 no matter what code page the host console uses. A legacy console
# code page transcodes non-ASCII characters in paths, and some of them become
# raw control bytes that make the JSON unparseable: U+2022 is byte 0x07 in
# CP437, for example. Written without a BOM so the output stays clean JSON.
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

$detectScript = Join-Path $PSScriptRoot 'detect_everything.ps1'

function Convert-FileTimeUtc {
    param([Int64]$Value)
    if ($Value -le 0) { return $null }
    try { return [DateTime]::FromFileTimeUtc($Value).ToString('o') } catch { return $null }
}

# Casting a raw attribute mask to [IO.FileAttributes] throws whenever it carries
# a bit the running .NET does not define, such as the cloud placeholder flag
# 0x400000 that OneDrive sets. Decode bit by bit instead and keep any unknown
# remainder as hex so a search never fails on an unfamiliar attribute.
function Convert-FileAttribute {
    param([UInt32]$Value)

    # 0xFFFFFFFF is INVALID_FILE_ATTRIBUTES. Written as [UInt32]::MaxValue
    # because PowerShell parses the 0xFFFFFFFF literal as -1.
    if ($Value -eq 0 -or $Value -eq [UInt32]::MaxValue) { return $null }

    $names = [System.Collections.Generic.List[string]]::new()
    $remaining = $Value
    foreach ($name in [Enum]::GetNames([IO.FileAttributes])) {
        $bit = [UInt32][IO.FileAttributes]::$name
        if ($bit -ne 0 -and ($remaining -band $bit) -eq $bit) {
            [void]$names.Add($name)
            $remaining = $remaining -band (-bnot $bit)
        }
    }
    if ($remaining -ne 0) { [void]$names.Add('0x{0:X}' -f $remaining) }
    if ($names.Count -eq 0) { return $null }

    return ($names -join ', ')
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

# es.exe treats one argument containing spaces as a single literal phrase, so a
# whole query passed as one argument matches nothing. Split it into terms on
# unquoted whitespace and keep the quotes, which es.exe needs to see for phrases.
function Split-EsQueryTerm {
    param([string]$Text)

    $terms = [System.Collections.Generic.List[string]]::new()
    $current = [Text.StringBuilder]::new()
    $inQuotes = $false

    foreach ($character in $Text.ToCharArray()) {
        if ($character -eq '"') {
            $inQuotes = -not $inQuotes
            [void]$current.Append($character)
            continue
        }
        if (-not $inQuotes -and [char]::IsWhiteSpace($character)) {
            if ($current.Length -gt 0) {
                [void]$terms.Add($current.ToString())
                [void]$current.Clear()
            }
            continue
        }
        [void]$current.Append($character)
    }
    if ($current.Length -gt 0) { [void]$terms.Add($current.ToString()) }

    return $terms
}

function Invoke-EsSearch {
    param([string]$Executable, [string]$SearchText, [int]$Limit)

    $terms = Split-EsQueryTerm -Text $SearchText
    if ($terms.Count -eq 0) { throw 'The query contains no search terms.' }

    # Ask for one more result than requested so an exact-limit result set is not
    # misreported as truncated.
    $probe = if ($Limit -lt [int]::MaxValue) { $Limit + 1 } else { $Limit }

    # es.exe emits UTF-8 only when the console output code page is 65001.
    $previousEncoding = $null
    try { $previousEncoding = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

    # A native command writing to stderr raises NativeCommandError while
    # ErrorActionPreference is 'Stop', even when it exits successfully.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $esArguments = @('-n', $probe) + $terms
        $lines = @(& $Executable @esArguments 2>$null)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
        if ($previousEncoding) { try { [Console]::OutputEncoding = $previousEncoding } catch { } }
    }

    if ($exitCode -ne 0) {
        throw "es.exe exited with code $exitCode. Confirm Everything is running in the same interactive user session as this shell, then retry. Run detect_everything.ps1 -Pretty to re-check the backend."
    }

    $paths = @($lines | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $truncated = $paths.Count -gt $Limit
    if ($truncated) { $paths = @($paths | Select-Object -First $Limit) }

    $items = @(foreach ($path in $paths) { Get-PathMetadata -Path $path })

    return [ordered]@{
        backend = 'es'
        query = $SearchText
        max_results = $Limit
        result_count = $items.Count
        total_results = $null
        truncated = $truncated
        truncation_known = $true
        results = $items
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
        $attributes = Convert-FileAttribute -Value $attributesValue
        $kind = if ([EverythingSdk]::Everything_IsFolderResult([UInt32]$i)) { 'folder' } elseif ([EverythingSdk]::Everything_IsFileResult([UInt32]$i)) { 'file' } else { 'unknown' }
        $path = $buffer.ToString()

        $items.Add([pscustomobject][ordered]@{
            path = $path
            name = Split-Path -Leaf $path
            kind = $kind
            size = if ($hasSize -and $kind -eq 'file') { $size } else { $null }
            modified_utc = if ($hasModified) { Convert-FileTimeUtc $modified } else { $null }
            attributes = $attributes
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
        throw 'No query backend was detected. Install the official Everything SDK DLL or es.exe, for example with setup_backend.ps1 -Component Sdk.'
    }
    if ($selectedBackend -eq 'Dll') {
        if ([string]::IsNullOrWhiteSpace($DllPath)) {
            throw 'Backend Dll was requested, but no Everything SDK DLL was detected. Pass -DllPath, run setup_backend.ps1 -Component Sdk, or use -Backend Auto.'
        }
        if (-not (Test-Path -LiteralPath $DllPath -PathType Leaf)) {
            throw "Everything SDK DLL not found: $DllPath"
        }
    }
    if ($selectedBackend -eq 'Es') {
        if ([string]::IsNullOrWhiteSpace($EsPath)) {
            throw 'Backend Es was requested, but es.exe was not detected. Pass -EsPath, run setup_backend.ps1 -Component Es, or use -Backend Auto.'
        }
        if (-not (Test-Path -LiteralPath $EsPath -PathType Leaf)) {
            throw "Everything CLI not found: $EsPath"
        }
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
