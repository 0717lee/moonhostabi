#requires -Version 7.0
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath
$tempParent = (Resolve-Path -LiteralPath ([IO.Path]::GetTempPath())).ProviderPath
$runId = [Guid]::NewGuid().ToString('N')
$tempLeaf = "moonhostabi-consumer-$runId"
$tempRoot = Join-Path $tempParent $tempLeaf
$buildRoot = Join-Path $repoRoot "_build/consumer-tools/$runId"
$outputRoot = Join-Path $buildRoot 'output'
$utf8 = [Text.UTF8Encoding]::new($false)

function Invoke-Checked {
  param(
    [string] $Executable,
    [string[]] $Arguments,
    [string] $Label,
    [int] $ExpectedExit = 0
  )
  $stdout = Join-Path $buildRoot "$Label.stdout.txt"
  $stderr = Join-Path $buildRoot "$Label.stderr.txt"
  & $Executable @Arguments 1> $stdout 2> $stderr
  $code = $LASTEXITCODE
  $out = [IO.File]::ReadAllText($stdout)
  $err = [IO.File]::ReadAllText($stderr)
  if ($code -ne $ExpectedExit) {
    throw "$Label exited $code (expected $ExpectedExit).`n$out`n$err"
  }
  Write-Host "CONSUMER_STEP=$Label EXIT=$code"
  return $out
}

function Assert-Marker([string] $Text, [string] $Marker) {
  if (($Text -split '\r?\n') -cnotcontains $Marker) {
    throw "Missing stdout marker: $Marker"
  }
  Write-Host $Marker
}

function Remove-ExactTempRun {
  $resolved = (Resolve-Path -LiteralPath $tempRoot).ProviderPath
  $resolvedParent = (Resolve-Path -LiteralPath $tempParent).ProviderPath
  $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
  $item = Get-Item -LiteralPath $resolved
  if (
    -not [string]::Equals([IO.Path]::GetDirectoryName($resolved), $resolvedParent.TrimEnd([IO.Path]::DirectorySeparatorChar), $comparison) -or
    [IO.Path]::GetFileName($resolved) -cne $tempLeaf -or
    $tempLeaf -cnotmatch '^moonhostabi-consumer-[0-9a-f]{32}$' -or
    ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
  ) {
    throw "Refusing cleanup of unexpected temporary path '$resolved'."
  }
  Remove-Item -LiteralPath $resolved -Recurse -Force
  Write-Host 'CONSUMER_TEMP_CLEANUP=GO'
}

[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
Write-Host "CONSUMER_EVIDENCE=$buildRoot"
try {
  foreach ($relative in @('examples/consumer/moon.mod', 'examples/consumer-app/v1/moon.mod', 'examples/consumer-app/v2/moon.mod')) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relative) -PathType Leaf)) {
      throw "Missing consumer template: $relative"
    }
  }
  $moon = (Get-Command moon -CommandType Application -ErrorAction Stop)[0].Source
  $node = (Get-Command node -CommandType Application -ErrorAction Stop)[0].Source
  $tsc = Join-Path $repoRoot 'runtime/node_modules/typescript/bin/tsc'
  if (-not (Test-Path -LiteralPath $tsc -PathType Leaf)) {
    throw 'Expected the existing runtime/node_modules TypeScript installation.'
  }
  $version = Invoke-Checked $moon @('version', '--all') 'toolchain'
  if ($version -notmatch '(?m)^moon 0\.1\.20260920 \(914d7da 2026-09-20\)' -or
      $version -notmatch '(?m)^moonc v0\.10\.14\+7d59c7ec9 \(2026-09-18\)') {
    throw "Expected the pinned MoonBit 0.10.14 toolchain.`n$version"
  }
  $null = Invoke-Checked $node @('--version') 'node-version'
  $null = Invoke-Checked $node @($tsc, '--version') 'typescript-version'

  $workspace = Join-Path $tempRoot 'workspace'
  [IO.Directory]::CreateDirectory($workspace) | Out-Null
  $consumer = Join-Path $workspace 'consumer'
  Copy-Item -LiteralPath (Join-Path $repoRoot 'examples/consumer') -Destination $consumer -Recurse
  Copy-Item -LiteralPath (Join-Path $repoRoot 'examples/consumer-app') -Destination (Join-Path $tempRoot 'app') -Recurse

  # No application sources or library implementation are synthesized here.
  foreach ($versionName in @('v1', 'v2')) {
    $app = Join-Path $tempRoot "app/$versionName"
    $target = Join-Path $buildRoot "app-$versionName"
    $null = Invoke-Checked $moon @('-C', $app, 'build', '--frozen', '--release', '--target', 'wasm-gc', '--target-dir', $target) "build-$versionName"
    $artifacts = @(Get-ChildItem -LiteralPath $target -Recurse -File -Filter '*.wasm')
    if ($artifacts.Count -ne 1) { throw "Expected one compiled $versionName artifact, got $($artifacts.Count)." }
    Copy-Item -LiteralPath $artifacts[0].FullName -Destination (Join-Path $outputRoot "$versionName.wasm")
  }

  $bundledRoot = Join-Path $repoRoot '.tools/wasm-tools'
  $wasmTools = @()
  if (Test-Path -LiteralPath $bundledRoot) {
    $toolName = if ($IsWindows) { 'wasm-tools.exe' } else { 'wasm-tools' }
    $wasmTools = @(Get-ChildItem -LiteralPath $bundledRoot -Recurse -File -Filter $toolName)
  }
  if ($wasmTools.Count -gt 1) { throw 'Expected at most one bundled wasm-tools executable.' }
  if ($wasmTools.Count -eq 1) {
    foreach ($versionName in @('v1', 'v2')) {
      $null = Invoke-Checked $wasmTools[0].FullName @('validate', (Join-Path $outputRoot "$versionName.wasm")) "validate-$versionName"
    }
    Write-Host 'CONSUMER_WASM_VALIDATE=GO'
  } else {
    Write-Host 'CONSUMER_WASM_VALIDATE=SKIP (optional bundled wasm-tools absent)'
  }

  # Moon's workspace override keeps the declared registry dependency intact.
  $members = @($repoRoot.Replace('\', '/'), $consumer.Replace('\', '/')) | ConvertTo-Json -Compress
  $workText = "members = $members`n"
  [IO.File]::WriteAllText((Join-Path $workspace 'moon.work'), $workText, $utf8)
  [IO.File]::WriteAllText((Join-Path $buildRoot 'moon.work'), $workText, $utf8)
  $sdkTarget = Join-Path $buildRoot 'sdk'
  $sdkBuild = @('-C', $workspace, 'build', $consumer, '--release', '--target', 'native', '--target-dir', $sdkTarget)
  $plan = Invoke-Checked $moon ($sdkBuild + '--dry-run') 'source-plan'
  $normalizedPlan = $plan.Replace('\', '/')
  foreach ($source in @('src/wasm_adapter/parse.mbt', 'src/verification/verify.mbt', 'src/generator/typescript.mbt')) {
    $expected = (Join-Path $repoRoot $source).Replace('\', '/')
    if (-not $normalizedPlan.Contains($expected)) {
      throw "Local workspace library resolution not proven for $source. Stopping; no published-package fallback."
    }
  }
  Write-Host "CONSUMER_LIBRARY_SOURCE=$repoRoot"
  Write-Host 'CONSUMER_SOURCE_WORKSPACE=GO'
  $null = Invoke-Checked $moon $sdkBuild 'build-sdk'
  $executables = @(Get-ChildItem -LiteralPath $sdkTarget -Recurse -File -Filter 'consumer.exe')
  if ($executables.Count -ne 1) { throw "Expected one consumer.exe, got $($executables.Count)." }
  $inputs = @((Join-Path $outputRoot 'v1.wasm'), (Join-Path $outputRoot 'v2.wasm'), $outputRoot)
  [IO.File]::WriteAllText((Join-Path $buildRoot 'inputs.json'), (ConvertTo-Json -InputObject $inputs), $utf8)
  $sdkOutput = Invoke-Checked $executables[0].FullName $inputs 'sdk'
  Assert-Marker $sdkOutput 'CONSUMER_V1_EXIT=0'
  Assert-Marker $sdkOutput 'CONSUMER_V2_EXIT=2'
  Assert-Marker $sdkOutput 'CONSUMER_SDK=GO'

  Copy-Item -LiteralPath (Join-Path $consumer 'host.ts') -Destination (Join-Path $outputRoot 'host.ts')
  [IO.File]::WriteAllText((Join-Path $outputRoot 'package.json'), '{"private":true,"type":"module"}', $utf8)
  $tsconfig = @{
    compilerOptions = @{
      target = 'ES2022'; module = 'NodeNext'; moduleResolution = 'NodeNext'
      lib = @('ES2022', 'DOM'); types = @('node'); strict = $true; noEmitOnError = $true
      typeRoots = @((Join-Path $repoRoot 'runtime/node_modules/@types'))
      rootDir = '.'; outDir = 'dist'
    }
    include = @('host.ts', 'generated/adapter.ts')
  } | ConvertTo-Json -Depth 5
  [IO.File]::WriteAllText((Join-Path $outputRoot 'tsconfig.json'), $tsconfig, $utf8)
  $null = Invoke-Checked $node @($tsc, '--project', (Join-Path $outputRoot 'tsconfig.json')) 'strict-typescript'
  Write-Host 'CONSUMER_TYPESCRIPT=GO'
  $hostProgram = Join-Path $outputRoot 'dist/host.js'
  $good = Invoke-Checked $node @($hostProgram, $inputs[0], (Join-Path $outputRoot 'v1.report.json')) 'host-v1'
  Assert-Marker $good 'CONSUMER_HOST_TOTAL_CENTS=3375'
  $blocked = Invoke-Checked $node @($hostProgram, $inputs[1], (Join-Path $outputRoot 'v2.report.json')) 'host-v2' 2
  Assert-Marker $blocked 'CONSUMER_HOST_BLOCKED=breaking'
  if ($blocked.Contains('CONSUMER_HOST_TOTAL_CENTS=')) { throw 'Breaking upgrade reached the pricing call.' }
} catch {
  Write-Host 'MOONHOSTABI_SOURCE_CONSUMER_STATUS=NO_GO'
  throw
} finally {
  if (Test-Path -LiteralPath $tempRoot) { Remove-ExactTempRun }
}
Write-Host 'MOONHOSTABI_SOURCE_CONSUMER_STATUS=GO'
