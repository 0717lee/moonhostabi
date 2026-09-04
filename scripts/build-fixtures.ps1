$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixturesRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'fixtures'))
$projectsRoot = [IO.Path]::GetFullPath((Join-Path $fixturesRoot 'projects'))
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $fixturesRoot 'artifacts'))
$oracleRoot = [IO.Path]::GetFullPath((Join-Path $fixturesRoot 'oracle'))
$buildRoot = [IO.Path]::GetFullPath((Join-Path $fixturesRoot '.build'))
$toolsRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tools'))
$utf8NoBom = [Text.UTF8Encoding]::new($false)

function Assert-ChildPath {
  param(
    [Parameter(Mandatory)] [string] $Path,
    [Parameter(Mandatory)] [string] $Parent
  )
  $resolvedPath = [IO.Path]::GetFullPath($Path)
  $resolvedParent = [IO.Path]::GetFullPath($Parent).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
  )
  $prefix = $resolvedParent + [IO.Path]::DirectorySeparatorChar
  if (-not $resolvedPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Path escapes intended parent: '$resolvedPath' is not beneath '$resolvedParent'"
  }
}

foreach ($directory in @($artifactsRoot, $oracleRoot, $buildRoot)) {
  Assert-ChildPath -Path $directory -Parent $repoRoot
  [IO.Directory]::CreateDirectory($directory) | Out-Null
}

$moonCommand = Get-Command moon -ErrorAction Stop

$bundledTools = @()
if (Test-Path -LiteralPath (Join-Path $toolsRoot 'wasm-tools')) {
  $bundledTools = @(
    Get-ChildItem -LiteralPath (Join-Path $toolsRoot 'wasm-tools') -Recurse -File |
      Where-Object { $_.Name -in @('wasm-tools.exe', 'wasm-tools') }
  )
}
if ($bundledTools.Count -gt 1) {
  throw "Expected at most one bundled wasm-tools executable, found $($bundledTools.Count)"
}
if ($bundledTools.Count -eq 1) {
  $wasmTools = $bundledTools[0].FullName
} else {
  $wasmToolsCommand = Get-Command wasm-tools -ErrorAction Stop
  $wasmTools = $wasmToolsCommand.Source
}

$versionOutput = & $wasmTools --version
if ($LASTEXITCODE -ne 0) {
  throw "wasm-tools --version failed with exit code $LASTEXITCODE"
}
if (($versionOutput -join "`n") -notmatch '^wasm-tools 1\.258\.0(?:\s|$)') {
  throw "Expected wasm-tools 1.258.0, got '$($versionOutput -join ' ')'."
}

function Invoke-Checked {
  param(
    [Parameter(Mandatory)] [string] $FilePath,
    [Parameter(Mandatory)] [string[]] $Arguments,
    [Parameter(Mandatory)] [string] $Description
  )
  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$Description failed with exit code $LASTEXITCODE"
  }
}

function Get-PrintedWat {
  param([Parameter(Mandatory)] [string] $Artifact)
  $output = & $wasmTools print $Artifact
  if ($LASTEXITCODE -ne 0) {
    throw "wasm-tools print failed for '$Artifact' with exit code $LASTEXITCODE"
  }
  $output -join "`n"
}

function Assert-WatPattern {
  param(
    [Parameter(Mandatory)] [string] $Wat,
    [Parameter(Mandatory)] [string] $Pattern,
    [Parameter(Mandatory)] [string] $Fixture,
    [Parameter(Mandatory)] [string] $Description
  )
  if ($Wat -notmatch $Pattern) {
    throw "Oracle assertion failed for '$Fixture': missing $Description (pattern: $Pattern)"
  }
}

$runRoot = [IO.Path]::GetFullPath(
  (Join-Path $buildRoot ([Guid]::NewGuid().ToString('N')))
)
Assert-ChildPath -Path $runRoot -Parent $buildRoot
[IO.Directory]::CreateDirectory($runRoot) | Out-Null

$projects = @(
  @{ Name = 'scalar'; Patterns = @(
      @{ Regex = '\(export "add"'; Description = 'add export' },
      @{ Regex = '\(export "answer"'; Description = 'answer export' },
      @{ Regex = '\(type \(;\d+;\) \(func \(param i32 i32\) \(result i32\)\)\)'; Description = 'i32 add signature' },
      @{ Regex = '\(type \(;\d+;\) \(func \(result i64\)\)\)'; Description = 'i64 answer signature' }
    ) },
  @{ Name = 'externref'; Patterns = @(
      @{ Regex = '\(import "host" "echo"'; Description = 'host.echo import' },
      @{ Regex = '\(export "roundtrip"'; Description = 'roundtrip export' },
      @{ Regex = '\(param externref\) \(result externref\)'; Description = 'externref signature' }
    ) },
  @{ Name = 'recursive'; Patterns = @(
      @{ Regex = '\(type \(;(?<recursiveId>\d+);\) \(struct .*\(ref null \k<recursiveId>\)'; Description = 'self-recursive struct type' },
      @{ Regex = '\(ref null (?:\$[A-Za-z][A-Za-z0-9_-]*|\d+)\)'; Description = 'nullable typed reference' },
      @{ Regex = '\(field \(mut \(ref null \d+\)\)\)'; Description = 'mutable recursive field' },
      @{ Regex = '\(export "new_node"'; Description = 'new_node export' },
      @{ Regex = '\(export "node_value"'; Description = 'node_value export' }
    ) },
  @{ Name = 'breaking_v1'; Patterns = @(
      @{ Regex = '\(export "add"'; Description = 'add export' },
      @{ Regex = '\(param i32 i32\) \(result i32\)'; Description = 'v1 add signature' }
    ) },
  @{ Name = 'breaking_v2'; Patterns = @(
      @{ Regex = '\(export "add"'; Description = 'add export' },
      @{ Regex = '\(param i32\) \(result i32\)'; Description = 'v2 add signature' }
    ) }
)

$successfulArtifacts = [Collections.Generic.List[string]]::new()
foreach ($project in $projects) {
  $name = [string] $project.Name
  $projectRoot = [IO.Path]::GetFullPath((Join-Path $projectsRoot $name))
  Assert-ChildPath -Path $projectRoot -Parent $projectsRoot
  if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'moon.mod'))) {
    throw "Missing fixture module: $projectRoot"
  }
  $targetDir = [IO.Path]::GetFullPath((Join-Path $runRoot $name))
  Assert-ChildPath -Path $targetDir -Parent $runRoot

  Push-Location $projectRoot
  try {
    Invoke-Checked -FilePath $moonCommand.Source -Arguments @(
      'build', '--release', '--target', 'wasm-gc', '--target-dir', $targetDir
    ) -Description "MoonBit build for $name"
  } finally {
    Pop-Location
  }

  $matches = @(
    Get-ChildItem -LiteralPath $targetDir -Recurse -File -Filter "$name.wasm"
  )
  if ($matches.Count -ne 1) {
    throw "Expected exactly one $name.wasm under '$targetDir', found $($matches.Count)"
  }
  $destination = [IO.Path]::GetFullPath((Join-Path $artifactsRoot "$name.wasm"))
  Assert-ChildPath -Path $destination -Parent $artifactsRoot
  Copy-Item -LiteralPath $matches[0].FullName -Destination $destination -Force

  Invoke-Checked -FilePath $wasmTools -Arguments @('validate', $destination) -Description "validation for $name"
  $wat = Get-PrintedWat -Artifact $destination
  foreach ($expectation in $project.Patterns) {
    Assert-WatPattern -Wat $wat -Pattern $expectation.Regex -Fixture $name -Description $expectation.Description
  }
  $oraclePath = [IO.Path]::GetFullPath((Join-Path $oracleRoot "$name.wat"))
  Assert-ChildPath -Path $oraclePath -Parent $oracleRoot
  [IO.File]::WriteAllText($oraclePath, $wat + "`n", $utf8NoBom)
  $successfulArtifacts.Add($destination)
}

$watFixtures = @('rec-a', 'rec-reindexed')
foreach ($name in $watFixtures) {
  $source = [IO.Path]::GetFullPath((Join-Path $fixturesRoot "wat/$name.wat"))
  $destination = [IO.Path]::GetFullPath((Join-Path $artifactsRoot "$name.wasm"))
  Assert-ChildPath -Path $source -Parent (Join-Path $fixturesRoot 'wat')
  Assert-ChildPath -Path $destination -Parent $artifactsRoot
  Invoke-Checked -FilePath $wasmTools -Arguments @('parse', $source, '-o', $destination) -Description "WAT parse for $name"
  Invoke-Checked -FilePath $wasmTools -Arguments @('validate', $destination) -Description "validation for $name"
  $wat = Get-PrintedWat -Artifact $destination
  foreach ($expectation in @(
      @{ Regex = '\(rec'; Description = 'recursive type group' },
      @{ Regex = '\(ref null (?:\$[A-Za-z][A-Za-z0-9_-]*|\d+)\)'; Description = 'nullable typed reference' },
      @{ Regex = '\(mut i16\)'; Description = 'packed mutable i16 field' },
      @{ Regex = '\(export "node-null"'; Description = 'node-null export' }
    )) {
    Assert-WatPattern -Wat $wat -Pattern $expectation.Regex -Fixture $name -Description $expectation.Description
  }
  $oraclePath = [IO.Path]::GetFullPath((Join-Path $oracleRoot "$name.wat"))
  Assert-ChildPath -Path $oraclePath -Parent $oracleRoot
  [IO.File]::WriteAllText($oraclePath, $wat + "`n", $utf8NoBom)
  $successfulArtifacts.Add($destination)
}

Write-Output "Validated fixture artifacts:"
foreach ($artifact in $successfulArtifacts) {
  Write-Output "- $artifact"
}
