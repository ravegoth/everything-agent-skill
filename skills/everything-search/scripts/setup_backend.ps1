[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Sdk', 'Es')]
    [string]$Component = 'Sdk',

    [string]$Destination = (Join-Path $env:LOCALAPPDATA 'EverythingAgent'),
    [switch]$Force,
    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') { throw 'This setup script supports Windows only.' }

$architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
if ($architecture -notin @('X64', 'X86', 'Arm64', 'Arm')) {
    throw "Unsupported Windows architecture: $architecture"
}

$spec = if ($Component -eq 'Sdk') {
    [ordered]@{
        url = 'https://www.voidtools.com/Everything-SDK.zip'
        target = Join-Path $Destination 'SDK'
    }
} else {
    $suffix = @{ X64 = 'x64'; X86 = 'x86'; Arm64 = 'ARM64'; Arm = 'ARM' }[$architecture]
    [ordered]@{
        url = "https://www.voidtools.com/ES-1.1.0.37.$suffix.zip"
        target = Join-Path $Destination 'CLI'
    }
}

if ((Test-Path -LiteralPath $spec.target) -and -not $Force) {
    throw "Target already exists: $($spec.target). Use -Force to replace files."
}

if (-not $PSCmdlet.ShouldProcess($spec.target, "Download and extract official Everything $Component from $($spec.url)")) {
    return
}

New-Item -ItemType Directory -Path $Destination -Force | Out-Null
$tempZip = Join-Path ([IO.Path]::GetTempPath()) ("everything-{0}.zip" -f [Guid]::NewGuid().ToString('N'))
$tempExtract = Join-Path ([IO.Path]::GetTempPath()) ("everything-{0}" -f [Guid]::NewGuid().ToString('N'))

try {
    Invoke-WebRequest -Uri $spec.url -OutFile $tempZip -UseBasicParsing
    Expand-Archive -LiteralPath $tempZip -DestinationPath $tempExtract -Force
    New-Item -ItemType Directory -Path $spec.target -Force | Out-Null
    Copy-Item -Path (Join-Path $tempExtract '*') -Destination $spec.target -Recurse -Force
} finally {
    Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
}

$detectScript = Join-Path $PSScriptRoot 'detect_everything.ps1'
& $detectScript -Pretty:$Pretty
