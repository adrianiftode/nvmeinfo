#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot 'Get-NvmeSlots.ps1'

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    $messages = @($parseErrors | ForEach-Object { $_.Message })
    throw ("Get-NvmeSlots.ps1 failed to parse: " + ($messages -join '; '))
}

$functionAst = $ast.Find({
    param($node)
    return ($node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Test-IsM2SlotType')
}, $true)

if ($null -eq $functionAst) {
    throw 'Test-IsM2SlotType was not found in Get-NvmeSlots.ps1.'
}

# Load only the pure classification function. Dot-sourcing the full script
# would enumerate hardware and is intentionally avoided in this test.
. ([scriptblock]::Create($functionAst.Extent.Text))

foreach ($typeCode in @(0x14, 0x15, 0x16, 0x17)) {
    if (-not (Test-IsM2SlotType -TypeCode $typeCode)) {
        throw ('Expected SMBIOS slot type 0x{0:X2} to be classified as M.2.' -f $typeCode)
    }
}

foreach ($typeCode in @(0x01, 0x02, 0x03, 0x09, 0x0A, 0x0B, 0x0C, 0x35, 0x36, 0x3A)) {
    if (Test-IsM2SlotType -TypeCode $typeCode) {
        throw ('Expected SMBIOS slot type 0x{0:X2} not to be classified as M.2.' -f $typeCode)
    }
}

Write-Host 'PowerShell compatibility and SMBIOS slot classification checks passed.'
