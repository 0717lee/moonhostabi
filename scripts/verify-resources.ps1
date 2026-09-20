param(
  [string] $RepositoryRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([String]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = Join-Path $PSScriptRoot '..'
}
$repositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$runtimeRoot = Join-Path $repositoryRoot 'runtime'
$hostTempRoot = (Resolve-Path -LiteralPath ([IO.Path]::GetTempPath())).ProviderPath
$runLeaf = 'moonhostabi-resources-' + [Guid]::NewGuid().ToString('N')
$runRoot = [IO.Path]::GetFullPath((Join-Path $hostTempRoot $runLeaf))
$fixtureRoot = Join-Path $runRoot 'fixtures with spaces'
$compiledRoot = Join-Path $runRoot 'compiled'
$pathComparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }

function Assert-ExactTempChild {
  $resolvedRun = (Resolve-Path -LiteralPath $script:runRoot).ProviderPath
  $resolvedParent = (Resolve-Path -LiteralPath $script:hostTempRoot).ProviderPath
  $expected = [IO.Path]::GetFullPath((Join-Path $resolvedParent $script:runLeaf))
  if (
    -not [String]::Equals([IO.Path]::GetFullPath($resolvedRun), $expected, $script:pathComparison) -or
    $script:runLeaf -notmatch '^moonhostabi-resources-[0-9a-f]{32}$' -or
    (Get-Item -LiteralPath $script:runRoot).Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)
  ) {
    throw "Refusing to remove unexpected resource verification path '$resolvedRun'."
  }
}

function Resolve-Application {
  param([Parameter(Mandatory)] [string] $Name)
  @(Get-Command $Name -CommandType Application -ErrorAction Stop)[0].Source
}

function Invoke-Checked {
  param(
    [Parameter(Mandatory)] [string] $FilePath,
    [Parameter(Mandatory)] [string[]] $Arguments
  )
  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "'$FilePath $($Arguments -join ' ')' failed with exit code $LASTEXITCODE."
  }
}

function Invoke-Cli {
  param(
    [Parameter(Mandatory)] [string[]] $Arguments,
    [int] $ExpectedExit = 0,
    [switch] $TextOutput
  )
  $stdoutPath = Join-Path $script:runRoot 'cli.stdout'
  $stderrPath = Join-Path $script:runRoot 'cli.stderr'
  & $script:cliPath @Arguments 1> $stdoutPath 2> $stderrPath
  $exitCode = $LASTEXITCODE
  $stdout = [IO.File]::ReadAllText($stdoutPath)
  $stderr = [IO.File]::ReadAllText($stderrPath)
  if ($exitCode -ne $ExpectedExit) {
    throw "'$($Arguments -join ' ')' expected exit $ExpectedExit, received $exitCode. stdout=$stdout stderr=$stderr"
  }
  if ($ExpectedExit -eq 0 -and -not [String]::IsNullOrWhiteSpace($stderr)) {
    throw "Successful resource command emitted stderr: $stderr"
  }
  if ($TextOutput) { return $stdout }
  # Parse the actual wire output. A literal interpolation placeholder must fail here.
  $stdout | ConvertFrom-Json -Depth 100
}

function Assert-Report {
  param(
    [Parameter(Mandatory)] $Report,
    [Parameter(Mandatory)] [string] $Classification,
    [Parameter(Mandatory)] [int] $ExitCode
  )
  if (
    $Report.schemaVersion -ne 1 -or $Report.classification -cne $Classification -or
    $Report.exitCode -ne $ExitCode -or $Report.compatible -ne ($ExitCode -eq 0)
  ) {
    throw "Invalid resource report: $($Report | ConvertTo-Json -Depth 100 -Compress)"
  }
}

function Assert-Change {
  param(
    [Parameter(Mandatory)] $Report,
    [Parameter(Mandatory)] [string] $Kind,
    [Parameter(Mandatory)] [string] $Field,
    [Parameter(Mandatory)] [string] $Before,
    [Parameter(Mandatory)] [string] $After
  )
  $matches = @($Report.changes | Where-Object {
    $_.path.StartsWith("$Kind[") -and $_.path.EndsWith(".$Field")
  })
  if ($matches.Count -ne 1) {
    throw "Expected exactly one $Kind.$Field change, received $($matches.Count)."
  }
  $change = $matches[0]
  if (
    $change.before -cne $Before -or $change.after -cne $After -or
    $change.classification -cne 'breaking' -or [String]::IsNullOrWhiteSpace($change.recommendation)
  ) {
    throw "Unexpected $Kind.$Field change: $($change | ConvertTo-Json -Compress)"
  }
  # The before/after payloads must themselves be JSON values, not informal summaries.
  $null = $change.before | ConvertFrom-Json -Depth 100
  $null = $change.after | ConvertFrom-Json -Depth 100
}

[IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
Assert-ExactTempChild
$pushedLocation = $false
try {
  Push-Location $repositoryRoot
  $pushedLocation = $true
  $moon = Resolve-Application 'moon'
  $node = Resolve-Application 'node'
  $wasmToolsCommands = @(Get-Command wasm-tools -CommandType Application -ErrorAction SilentlyContinue)
  if ($wasmToolsCommands.Count -gt 0) {
    $wasmTools = $wasmToolsCommands[0].Source
  } else {
    $executableName = if ($IsWindows) { 'wasm-tools.exe' } else { 'wasm-tools' }
    $bundledRoot = Join-Path $repositoryRoot '.tools/wasm-tools'
    $bundled = @(Get-ChildItem -LiteralPath $bundledRoot -Recurse -File | Where-Object { $_.Name -ceq $executableName })
    if ($bundled.Count -ne 1) { throw 'Install wasm-tools or provide exactly one bundled executable under .tools/wasm-tools.' }
    $wasmTools = $bundled[0].FullName
  }
  $tsc = Join-Path $runtimeRoot 'node_modules/typescript/bin/tsc'
  if (-not (Test-Path -LiteralPath $tsc -PathType Leaf)) {
    throw 'Run npm --prefix runtime ci before the resource E2E verification.'
  }

  Invoke-Checked $moon @('build', 'cmd/moonhostabi', '--target', 'native')
  $cliCandidates = @(
    (Join-Path $repositoryRoot '_build/native/debug/build/cmd/moonhostabi/moonhostabi.exe'),
    (Join-Path $repositoryRoot '_build/native/debug/build/cmd/moonhostabi/moonhostabi')
  )
  $existingCli = @($cliCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
  if ($existingCli.Count -ne 1) { throw 'Could not resolve the freshly built native MoonHostABI executable.' }
  $cliPath = $existingCli[0]

  foreach ($wat in Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'fixtures/wat') -Filter 'resources*.wat' -File) {
    $artifact = Join-Path $fixtureRoot ($wat.BaseName + '.wasm')
    Invoke-Checked $wasmTools @('parse', $wat.FullName, '-o', $artifact)
    Invoke-Checked $wasmTools @('validate', $artifact)
    $tracked = Join-Path $repositoryRoot "fixtures/artifacts/$($wat.BaseName).wasm"
    if (
      -not (Test-Path -LiteralPath $tracked -PathType Leaf) -or
      (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $tracked -Algorithm SHA256).Hash
    ) {
      throw "Tracked resource fixture differs from reproducible WAT build: $($wat.Name)."
    }
  }

  $baseline = Join-Path $fixtureRoot 'resources.wasm'
  $lock = Join-Path $runRoot 'resources.lock.json'
  $null = Invoke-Cli @('resource-lock-v4', $baseline, '--out', $lock)
  $lockDocument = Get-Content -LiteralPath $lock -Raw | ConvertFrom-Json -Depth 100
  if ($lockDocument.lockfileVersion -ne 4 -or $lockDocument.abi.schemaVersion -ne 4) {
    throw 'Expected resource lock v4 and resource surface v4.'
  }
  if (
    $lockDocument.abi.tables[0].elementType -cne 'externref' -or
    $lockDocument.abi.tables[0].minimumElements -ne 2 -or $lockDocument.abi.tables[0].maximumElements -ne 4 -or
    $lockDocument.abi.globals[0].valueType -cne 'i32' -or $lockDocument.abi.globals[0].mutable -ne $true -or
    @($lockDocument.abi.tags[0].params).Count -ne 1 -or $lockDocument.abi.tags[0].params[0] -cne 'i32'
  ) {
    throw 'Resource lock lost actual exported table/global/tag metadata.'
  }
  $same = Invoke-Cli @('resource-verify', $baseline, '--against', $lock, '--format', 'json')
  Assert-Report $same 'compatible' 0
  if (@($same.changes).Count -ne 0) { throw 'Unchanged resource ABI produced changes.' }
  $reindexed = Invoke-Cli @('resource-verify', (Join-Path $fixtureRoot 'resources-reindexed.wasm'), '--against', $lock, '--format', 'json')
  Assert-Report $reindexed 'compatible' 0

  $cases = @(
    @{ Name = 'resources-table-type-changed'; Kind = 'tables'; Field = 'elementType'; Before = '"externref"'; After = '"funcref"' },
    @{ Name = 'resources-global-type-changed'; Kind = 'globals'; Field = 'valueType'; Before = '"i32"'; After = '"i64"' },
    @{ Name = 'resources-tag-signature-changed'; Kind = 'tags'; Field = 'params'; Before = '["i32"]'; After = '["i64"]' }
  )
  foreach ($case in $cases) {
    $report = Invoke-Cli @('resource-verify', (Join-Path $fixtureRoot ($case.Name + '.wasm')), '--against', $lock, '--format', 'json') -ExpectedExit 2
    Assert-Report $report 'breaking' 2
    Assert-Change $report $case.Kind $case.Field $case.Before $case.After
  }
  $changedArtifact = Join-Path $fixtureRoot 'resources-changed.wasm'
  $changed = Invoke-Cli @('resource-verify', $changedArtifact, '--against', $lock, '--format', 'json') -ExpectedExit 2
  Assert-Report $changed 'breaking' 2
  Assert-Change $changed 'memories' 'minimumPages' '1' '2'
  Assert-Change $changed 'memories' 'maximumPages' '3' '4'
  Assert-Change $changed 'tables' 'minimumElements' '2' '3'
  Assert-Change $changed 'tables' 'maximumElements' '4' '5'
  Assert-Change $changed 'globals' 'mutable' 'true' 'false'
  Assert-Change $changed 'tags' 'params' '["i32"]' '["i64","i32"]'
  foreach ($format in @('text', 'markdown')) {
    $formatted = Invoke-Cli @('resource-verify', $changedArtifact, '--against', $lock, '--format', $format) -ExpectedExit 2 -TextOutput
    if ($formatted -notmatch 'breaking' -or $formatted -notmatch 'minimumPages') {
      throw "$format report omitted the breaking resource details."
    }
  }

  $legacyLock = Join-Path $runRoot 'resources-v3.lock.json'
  $null = Invoke-Cli @('resource-lock-v3', $baseline, '--out', $legacyLock)
  $null = Get-Content -LiteralPath $legacyLock -Raw | ConvertFrom-Json -Depth 100
  $legacyReport = Invoke-Cli @('resource-verify', $baseline, '--against', $legacyLock, '--format', 'json') -ExpectedExit 3
  Assert-Report $legacyReport 'unknown' 3
  $escaped = Join-Path $fixtureRoot 'resources-escaped.wasm'
  $escapedLock = Join-Path $runRoot 'escaped-v3.lock.json'
  $null = Invoke-Cli @('resource-lock-v3', $escaped, '--out', $escapedLock)
  $escapedDocument = Get-Content -LiteralPath $escapedLock -Raw | ConvertFrom-Json -Depth 100
  if (
    $escapedDocument.abi.memories[0].name -cne "memory`"quoted`nname" -or
    $escapedDocument.abi.tables[0].name -cne 'table\name'
  ) {
    throw 'Resource JSON did not preserve quoted, newline, and backslash names.'
  }
  $escapedReport = Invoke-Cli @('resource-verify', $escaped, '--against', $escapedLock, '--format', 'json')
  Assert-Report $escapedReport 'compatible' 0

  $contracts = @{}
  [IO.Directory]::CreateDirectory((Join-Path $runRoot 'generated')) | Out-Null
  foreach ($name in @('resources', 'resources-imports', 'resources-escaped')) {
    $artifact = Join-Path $fixtureRoot "$name.wasm"
    $contract = Join-Path $runRoot "$name.contract.json"
    $null = Invoke-Cli @('resource-contract', $artifact, '--out', $contract)
    $contractDocument = Get-Content -LiteralPath $contract -Raw | ConvertFrom-Json -Depth 100
    if ($contractDocument.schemaVersion -ne 5) { throw 'Expected resource contract schema version 5.' }
    $contracts[$name] = $contract
    $generated = Join-Path $runRoot "generated/$name"
    $null = Invoke-Cli @('generate', $artifact, '--resource-contract', $contract, '--out', $generated)
    foreach ($json in Get-ChildItem -LiteralPath $generated -Filter '*.json' -File) {
      $null = Get-Content -LiteralPath $json.FullName -Raw | ConvertFrom-Json -Depth 100
    }
    Invoke-Checked $node @(
      $tsc, '--strict', '--noImplicitAny', '--target', 'ES2022', '--module', 'ES2022',
      '--moduleResolution', 'Bundler', '--lib', 'ES2022,DOM', '--outDir', (Join-Path $compiledRoot $name),
      (Join-Path $generated 'adapter.ts')
    )
  }
  [IO.File]::WriteAllText((Join-Path $compiledRoot 'package.json'), '{"type":"module"}')
  Invoke-Checked $node @((Join-Path $runtimeRoot 'node/resource-adapter-e2e.mjs'), $compiledRoot, $fixtureRoot)

  $invalidContract = Join-Path $runRoot 'invalid.contract.json'
  [IO.File]::WriteAllText($invalidContract, '{"schemaVersion":5}')
  foreach ($case in @(
    @{ Name = 'invalid'; Artifact = $baseline; Contract = $invalidContract },
    @{ Name = 'mismatch'; Artifact = $changedArtifact; Contract = $contracts['resources'] }
  )) {
    $outputDirectory = Join-Path $runRoot "rejected-$($case.Name)"
    $null = Invoke-Cli @('generate', $case.Artifact, '--resource-contract', $case.Contract, '--out', $outputDirectory) -ExpectedExit 3 -TextOutput
    if (Test-Path -LiteralPath $outputDirectory) {
      throw "Rejected $($case.Name) resource contract created output files."
    }
  }
  Write-Output 'MOONHOSTABI_RESOURCE_E2E_STATUS=GO'
}
finally {
  if ($pushedLocation) { Pop-Location }
  if (Test-Path -LiteralPath $runRoot) {
    Assert-ExactTempChild
    Remove-Item -LiteralPath $runRoot -Recurse -Force
  }
}
