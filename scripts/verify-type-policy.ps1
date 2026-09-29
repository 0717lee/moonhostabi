#requires -Version 7.0
param(
  [Parameter(Mandatory)] [string] $CliPath,
  [Parameter(Mandatory)] [string] $WasmToolsPath,
  [string] $ArtifactPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false
$repository = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath
$cli = (Resolve-Path -LiteralPath $CliPath).ProviderPath
$validator = (Resolve-Path -LiteralPath $WasmToolsPath).ProviderPath
if (-not $ArtifactPath) {
  $ArtifactPath = Join-Path $repository '_build/wasm-gc/debug/test/src/resource/resource.whitebox_test.wasm'
}
$artifact = (Resolve-Path -LiteralPath $ArtifactPath).ProviderPath
$evidence = Join-Path $repository ('_build/type-policy-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($evidence) | Out-Null
Write-Output "TYPE_POLICY_EVIDENCE=$evidence"

& $validator validate $artifact
if ($LASTEXITCODE -ne 0) { throw 'The compiled type-policy probe is not valid Wasm.' }
$layout = (& $validator objdump $artifact) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Could not read the compiled probe section inventory.' }
$counts = [regex]::Match($layout, '(?m)^\s*types\s*\|[^\r\n]*\|\s*(\d+) count\s*$')
if (-not $counts.Success -or [int]$counts.Groups[1].Value -le 1024) {
  throw 'The compiled probe must contain more than 1024 type groups; recalibrate this fixture if its compiler layout changes.'
}
# Each group has at least one actual type. objdump's count is not the flattened
# type count, but this lower bound proves the old 1024 policy would reject it.
Write-Output "TYPE_POLICY_GROUP_LOWER_BOUND=$($counts.Groups[1].Value)"
Write-Output "TYPE_POLICY_ARTIFACT_BYTES=$((Get-Item -LiteralPath $artifact).Length)"
Write-Output "TYPE_POLICY_ARTIFACT_SHA256=$((Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant())"

$inspectOut = Join-Path $evidence 'inspect.stdout.json'
$inspectErr = Join-Path $evidence 'inspect.stderr.json'
& $cli inspect $artifact --format json 1> $inspectOut 2> $inspectErr
if ($LASTEXITCODE -ne 3) { throw 'The function-only inspect policy must retain its unsupported tag exit 3.' }
$abiText = Get-Content -Raw -LiteralPath $inspectOut
$diagnosticText = Get-Content -Raw -LiteralPath $inspectErr
if ([string]::IsNullOrWhiteSpace($abiText)) {
  throw "Checked parsing rejected the compiled probe before projection: $diagnosticText"
}
$abi = $abiText | ConvertFrom-Json
$diagnostics = $diagnosticText | ConvertFrom-Json
if (@($abi.imports).Count -eq 0 -or @($abi.exports).Count -eq 0 -or @($abi.types).Count -ne 0) {
  throw 'Expected the compiled test driver scalar/externref function surface.'
}
if (@($diagnostics.diagnostics).Count -ne 1 -or
    $diagnostics.diagnostics[0].code -cne 'MHA_PROJECT_UNSUPPORTED_ITEM' -or
    $diagnostics.diagnostics[0].path -cne 'imports[exception.tag]') {
  throw 'Type-policy probe did not retain the expected public tag capability diagnostic.'
}

$lock = Join-Path $evidence 'resource.lock.json'
& $cli resource-lock-v4 $artifact --out $lock 1> (Join-Path $evidence 'lock.stdout.json') 2> (Join-Path $evidence 'lock.stderr.txt')
if ($LASTEXITCODE -ne 0) { throw 'Large compiled probe resource lock creation failed.' }
& $cli resource-verify $artifact --against $lock --format json 1> (Join-Path $evidence 'verify.stdout.json') 2> (Join-Path $evidence 'verify.stderr.txt')
if ($LASTEXITCODE -ne 0) { throw 'Large compiled probe resource verification failed.' }
$report = Get-Content -Raw -LiteralPath (Join-Path $evidence 'verify.stdout.json') | ConvertFrom-Json
if ($report.classification -cne 'compatible' -or -not $report.compatible -or
    $report.exitCode -ne 0 -or @($report.changes).Count -ne 0) {
  throw 'Large compiled probe resource report is not compatible.'
}
foreach ($name in @('lock.stderr.txt','verify.stderr.txt')) {
  if (-not [string]::IsNullOrWhiteSpace((Get-Content -Raw -LiteralPath (Join-Path $evidence $name)))) {
    throw "Unexpected diagnostic output in $name."
  }
}
Write-Output 'MOONHOSTABI_TYPE_POLICY_STATUS=GO'
