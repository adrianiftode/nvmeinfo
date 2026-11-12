#requires -Version 5.1
<#
.SYNOPSIS
    Builds the NVMe Slot Info executables.

.DESCRIPTION
    Compiles src\NvmeSlotsLauncher.cs with the C# compiler that ships with the
    .NET Framework. The PowerShell script is embedded as a resource, so the
    resulting executables work without any additional files.

    Two executables are produced:
      NvmeSlots.exe         console report, accepts the script's normal options
      NvmeSlots-Report.exe  writes NvmeSlotReport.html and opens it by default

.PARAMETER OutputDirectory
    Destination for the executables. Defaults to dist\.
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot 'dist'
}

$root = $PSScriptRoot
$source = Join-Path $root 'src\NvmeSlotsLauncher.cs'
$script = Join-Path $root 'Get-NvmeSlots.ps1'

foreach ($required in @($source, $script)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required file not found: $required"
    }
}

$frameworkRoot = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$csc = Join-Path $frameworkRoot 'csc.exe'
if (-not (Test-Path -LiteralPath $csc)) {
    $frameworkRoot = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319'
    $csc = Join-Path $frameworkRoot 'csc.exe'
}
if (-not (Test-Path -LiteralPath $csc)) {
    throw 'The .NET Framework C# compiler (csc.exe) was not found. Windows 10 normally includes it.'
}

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    [void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
}
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path

function Invoke-Compiler {
    param(
        [string]$OutputPath,
        [string[]]$Defines
    )

    $arguments = New-Object System.Collections.Generic.List[string]
    $arguments.Add('/nologo')
    $arguments.Add('/target:exe')
    $arguments.Add('/platform:anycpu')
    $arguments.Add('/optimize+')
    $arguments.Add('/warn:4')
    $arguments.Add(('/out:' + $OutputPath))
    $arguments.Add(('/resource:' + $script + ',NvmeSlots.Script.ps1'))
    foreach ($define in $Defines) {
        $arguments.Add('/define:' + $define)
    }
    $arguments.Add($source)

    Write-Verbose ("csc " + ($arguments -join ' '))
    & $csc $arguments.ToArray()
    if ($LASTEXITCODE -ne 0) {
        throw "Compilation failed with exit code $LASTEXITCODE."
    }
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        throw "Compiler did not produce $OutputPath"
    }
}

Write-Host 'Building NvmeSlots.exe...'
Invoke-Compiler -OutputPath (Join-Path $OutputDirectory 'NvmeSlots.exe') -Defines @()

Write-Host 'Building NvmeSlots-Report.exe...'
Invoke-Compiler -OutputPath (Join-Path $OutputDirectory 'NvmeSlots-Report.exe') -Defines @('REPORT_MODE')

Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.exe' |
    Sort-Object Name |
    Select-Object Name, @{ Name = 'SizeKB'; Expression = { [Math]::Round($_.Length / 1KB, 1) } }, LastWriteTime |
    Format-Table -AutoSize

Write-Host ('Build complete: ' + $OutputDirectory) -ForegroundColor Green
