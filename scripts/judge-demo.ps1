param(
  [string] $RepositoryRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([String]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = Join-Path $PSScriptRoot '..'
}
$repositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$tempParent = (Resolve-Path -LiteralPath ([IO.Path]::GetTempPath())).ProviderPath
$runLeaf = 'moonhostabi-judge-demo-' + [Guid]::NewGuid().ToString('N')
$runRoot = [IO.Path]::GetFullPath((Join-Path $tempParent $runLeaf))

function Invoke-Moon {
  param([Parameter(Mandatory)] [string[]] $Arguments)
  & moon @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "MoonHostABI demo command failed with exit code $LASTEXITCODE."
  }
}

function Assert-SafeRunRoot {
  $resolved = (Resolve-Path -LiteralPath $runRoot).ProviderPath
  $parent = (Resolve-Path -LiteralPath $tempParent).ProviderPath
  $normalized = [IO.Path]::GetFullPath($resolved).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  $normalizedParent = [IO.Path]::GetFullPath($parent).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  $prefix = $normalizedParent + [IO.Path]::DirectorySeparatorChar
  if (-not $normalized.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
      [IO.Path]::GetFileName($normalized) -cne $runLeaf) {
    throw "Refusing to remove unexpected demo path '$normalized'."
  }
}

try {
  [IO.Directory]::CreateDirectory($runRoot) | Out-Null
  Assert-SafeRunRoot
  Push-Location $repositoryRoot
  $artifact = 'fixtures/artifacts/externref.wasm'
  $contract = 'fixtures/contracts/externref.contract.json'
  $lock = Join-Path $runRoot 'host-abi.lock.json'
  $generated = Join-Path $runRoot 'generated'

  Write-Output '== 1. Inspect compiled Wasm host surface =='
  Invoke-Moon @('run', 'cmd/moonhostabi', '--target', 'native', 'inspect', $artifact, '--format', 'json')
  Write-Output '== 2. Create canonical ABI lockfile =='
  Invoke-Moon @('run', 'cmd/moonhostabi', '--target', 'native', 'lock', $artifact, '--out', $lock)
  Write-Output '== 3. Verify artifact and contract =='
  Invoke-Moon @('run', 'cmd/moonhostabi', '--target', 'native', 'verify', $artifact, '--against', $lock, '--contract', $contract, '--format', 'json')
  Write-Output '== 4. Generate strict TypeScript adapter =='
  Invoke-Moon @('run', 'cmd/moonhostabi', '--target', 'native', 'generate', $artifact, '--contract', $contract, '--out', $generated)
  Write-Output 'Generated files:'
  Get-ChildItem -LiteralPath $generated -File | Sort-Object Name | ForEach-Object { Write-Output "  $($_.Name)" }
  Write-Output 'MOONHOSTABI_JUDGE_DEMO_STATUS=GO'
}
finally {
  if ((Get-Location).Path -eq $repositoryRoot) { Pop-Location }
  if (Test-Path -LiteralPath $runRoot) {
    Assert-SafeRunRoot
    Remove-Item -LiteralPath $runRoot -Recurse -Force
  }
}
