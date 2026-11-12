#requires -Version 5.1
<#
.SYNOPSIS
    Builds the NVMe Slot Info executables with .NET 10 Native AOT.

.DESCRIPTION
    Produces native executables that do not require the .NET runtime on the
    target machine. The PowerShell script is embedded as a resource.

    Native AOT needs the MSVC linker and the Windows SDK import libraries.
    If the Windows SDK is not installed, this script downloads the Microsoft
    Windows SDK NuGet package once and caches the x64 libs under
    %LOCALAPPDATA%\NvmeSlotInfo.

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
$mainProject = Join-Path $root 'src\Launcher\NvmeSlots.csproj'
$reportProject = Join-Path $root 'src\Report\NvmeSlots-Report.csproj'
$script = Join-Path $root 'Get-NvmeSlots.ps1'

foreach ($required in @($mainProject, $reportProject, $script)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required file not found: $required"
    }
}

$WindowsSdkVersion = '10.0.22621.3233'
$WindowsSdkPackage = 'microsoft.windows.sdk.cpp.x64'
$WindowsSdkHash = 'F8475CF8654763DD5D5DB050B99788EF3CEAE4436A2FBA8FE4EA3B022C656E19'

function Get-DotNetPath {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'),
        (Join-Path $env:USERPROFILE '.dotnet\dotnet.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    $command = Get-Command dotnet.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    throw 'The .NET 10 SDK was not found. Install it from https://dotnet.microsoft.com/download/dotnet/10.0'
}

function Get-MsvcTools {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw 'Visual Studio Installer (vswhere.exe) was not found. Native AOT needs the MSVC C++ build tools.'
    }

    $installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ([string]::IsNullOrWhiteSpace($installPath)) {
        throw 'The MSVC C++ build tools were not found. Install the "Desktop development with C++" workload in Visual Studio.'
    }

    $versions = Get-ChildItem -LiteralPath (Join-Path $installPath 'VC\Tools\MSVC') -Directory |
        Sort-Object -Property { [version]$_.Name } -Descending
    if (-not $versions) {
        throw 'No MSVC toolset was found under Visual Studio.'
    }

    $msvc = $versions[0].FullName
    $bin = Join-Path $msvc 'bin\Hostx64\x64'
    $lib = Join-Path $msvc 'lib\x64'
    if (-not (Test-Path -LiteralPath (Join-Path $bin 'link.exe'))) {
        throw "link.exe was not found under $bin"
    }

    return [pscustomobject]@{ Bin = $bin; Lib = $lib }
}

function Get-WindowsSdkLibs {
    $cache = Join-Path $env:LOCALAPPDATA 'NvmeSlotInfo\cache'
    $sdkRoot = Join-Path $env:LOCALAPPDATA "NvmeSlotInfo\winsdk\$WindowsSdkVersion"
    $umLib = Join-Path $sdkRoot 'um\x64'
    $ucrtLib = Join-Path $sdkRoot 'ucrt\x64'

    if ((Test-Path -LiteralPath (Join-Path $umLib 'kernel32.lib')) -and
        (Test-Path -LiteralPath (Join-Path $ucrtLib 'ucrt.lib')) -and
        (Test-Path -LiteralPath (Join-Path $sdkRoot '.complete'))) {
        return [pscustomobject]@{ Um = $umLib; Ucrt = $ucrtLib }
    }

    if (-not (Test-Path -LiteralPath $cache)) {
        [void](New-Item -ItemType Directory -Path $cache -Force)
    }

    $packagePath = Join-Path $cache "$WindowsSdkPackage.$WindowsSdkVersion.nupkg"
    if (-not (Test-Path -LiteralPath $packagePath)) {
        $url = "https://api.nuget.org/v3-flatcontainer/$WindowsSdkPackage/$WindowsSdkVersion/$WindowsSdkPackage.$WindowsSdkVersion.nupkg"
        Write-Host "Downloading Windows SDK import libraries ($WindowsSdkPackage $WindowsSdkVersion)..."
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $packagePath -TimeoutSec 900
    }

    $hash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
    if ($hash -ne $WindowsSdkHash) {
        Remove-Item -LiteralPath $packagePath -Force
        throw "Checksum mismatch for $packagePath. The download was removed; run the build again."
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
    try {
        foreach ($entry in $zip.Entries) {
            $prefix = $null
            $target = $null
            if ($entry.FullName.StartsWith('c/um/x64/')) {
                $prefix = 'c/um/x64/'
                $target = $umLib
            } elseif ($entry.FullName.StartsWith('c/ucrt/x64/')) {
                $prefix = 'c/ucrt/x64/'
                $target = $ucrtLib
            }

            if (-not $prefix -or $entry.FullName.EndsWith('/')) {
                continue
            }

            $relative = $entry.FullName.Substring($prefix.Length)
            $destination = Join-Path $target $relative
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent)) {
                [void](New-Item -ItemType Directory -Path $parent -Force)
            }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination, $true)
        }
    } finally {
        $zip.Dispose()
    }

    if (-not (Test-Path -LiteralPath (Join-Path $umLib 'kernel32.lib')) -or
        -not (Test-Path -LiteralPath (Join-Path $ucrtLib 'ucrt.lib'))) {
        throw "The Windows SDK package did not contain the expected x64 import libraries."
    }

    Set-Content -LiteralPath (Join-Path $sdkRoot '.complete') -Value $WindowsSdkVersion -Encoding ASCII
    return [pscustomobject]@{ Um = $umLib; Ucrt = $ucrtLib }
}

function Invoke-Publish {
    param(
        [string]$DotNet,
        [string]$Project,
        [string]$Destination
    )

    & $DotNet publish $Project -c Release -r win-x64 -o $Destination -p:IlcUseEnvironmentalTools=true --nologo
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed for $Project (exit code $LASTEXITCODE)."
    }
}

$dotnet = Get-DotNetPath
$msvc = Get-MsvcTools
$sdk = Get-WindowsSdkLibs

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    [void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
}
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path

Get-ChildItem -LiteralPath $OutputDirectory -Filter 'NvmeSlots*.exe' -File -ErrorAction SilentlyContinue |
    Remove-Item -Force
Get-ChildItem -LiteralPath $OutputDirectory -Filter 'NvmeSlots*.pdb' -File -ErrorAction SilentlyContinue |
    Remove-Item -Force

$originalPath = $env:PATH
$originalLib = $env:LIB
try {
    $env:PATH = $msvc.Bin + ';' + $originalPath
    $env:LIB = $msvc.Lib + ';' + $sdk.Um + ';' + $sdk.Ucrt
    $env:DOTNET_NOLOGO = '1'
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'

    Write-Host 'Publishing NvmeSlots.exe (Native AOT)...'
    Invoke-Publish -DotNet $dotnet -Project $mainProject -Destination $OutputDirectory

    Write-Host 'Publishing NvmeSlots-Report.exe (Native AOT)...'
    Invoke-Publish -DotNet $dotnet -Project $reportProject -Destination $OutputDirectory
} finally {
    $env:PATH = $originalPath
    if ($null -eq $originalLib) {
        Remove-Item Env:\LIB -ErrorAction SilentlyContinue
    } else {
        $env:LIB = $originalLib
    }
}

$built = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter 'NvmeSlots*.exe' -File)
foreach ($exe in $built) {
    if ($exe.Length -lt 500KB) {
        throw "Build output looks wrong: $($exe.FullName) is only $($exe.Length) bytes."
    }
}

$built |
    Sort-Object Name |
    Select-Object Name, @{ Name = 'SizeKB'; Expression = { [Math]::Round($_.Length / 1KB, 1) } }, LastWriteTime |
    Format-Table -AutoSize

Write-Host ('Build complete: ' + $OutputDirectory) -ForegroundColor Green
Write-Host 'These are native executables; the .NET runtime is not required on the target machine.'
