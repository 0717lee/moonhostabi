$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$moduleRoot = [IO.Path]::GetFullPath(
  (Join-Path $repoRoot '.mooncakes/Milky2018/wasm_core')
)
$patchPath = [IO.Path]::GetFullPath(
  (Join-Path $repoRoot 'patches/wasm_core-0.14.0-singleton-rec.patch')
)
$moduleDirectory = '.mooncakes/Milky2018/wasm_core'
$versionPath = Join-Path $moduleRoot 'moon.mod'

if (-not (Test-Path -LiteralPath $versionPath)) {
  throw "Missing wasm_core dependency at '$moduleRoot'. Run 'moon update' first."
}
if (-not (Test-Path -LiteralPath $patchPath)) {
  throw "Missing dependency patch at '$patchPath'."
}
$moduleConfig = [IO.File]::ReadAllText($versionPath)
if ($moduleConfig -notmatch '(?m)^version\s*=\s*"0\.14\.0"\s*$') {
  throw 'The local wasm_core version is not 0.14.0; refusing to apply a stale patch.'
}

$gitCommand = Get-Command git -ErrorAction Stop
Push-Location $repoRoot
try {
  & $gitCommand.Source apply --reverse --check --directory=$moduleDirectory $patchPath 2>$null
  if ($LASTEXITCODE -eq 0) {
    Write-Output 'wasm_core 0.14.0 singleton-rec patch is already applied.'
    return
  }

  & $gitCommand.Source apply --check --directory=$moduleDirectory $patchPath
  if ($LASTEXITCODE -ne 0) {
    throw "wasm_core patch preflight failed with exit code $LASTEXITCODE"
  }
  & $gitCommand.Source apply --directory=$moduleDirectory $patchPath
  if ($LASTEXITCODE -ne 0) {
    throw "wasm_core patch application failed with exit code $LASTEXITCODE"
  }
  & $gitCommand.Source apply --reverse --check --directory=$moduleDirectory $patchPath
  if ($LASTEXITCODE -ne 0) {
    throw 'wasm_core patch postcondition failed.'
  }
  Write-Output 'Applied wasm_core 0.14.0 singleton-rec parser patch.'
} finally {
  Pop-Location
}
