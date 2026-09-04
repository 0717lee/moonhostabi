param(
  [string] $RepositoryRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([String]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = Join-Path $PSScriptRoot '..'
}
$repositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$hostTempRoot = (Resolve-Path -LiteralPath ([IO.Path]::GetTempPath())).ProviderPath
$runLeaf = 'moonhostabi-txn-' + [Guid]::NewGuid().ToString('N')
$runRoot = [IO.Path]::GetFullPath((Join-Path $hostTempRoot $runLeaf))
$outputLeaf = 'concurrent-output'
$outputRoot = Join-Path $runRoot $outputLeaf
$pathComparison = if ($IsWindows) {
  [StringComparison]::OrdinalIgnoreCase
} else {
  [StringComparison]::Ordinal
}

function Assert-ExactTransactionTemp {
  $resolvedPath = (Resolve-Path -LiteralPath $script:runRoot).ProviderPath
  $resolvedParent = (Resolve-Path -LiteralPath $script:hostTempRoot).ProviderPath
  $normalizedPath = [IO.Path]::GetFullPath($resolvedPath).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
  )
  $normalizedParent = [IO.Path]::GetFullPath($resolvedParent).TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
  )
  $expectedPrefix = $normalizedParent + [IO.Path]::DirectorySeparatorChar
  if (
    -not $normalizedPath.StartsWith($expectedPrefix, $script:pathComparison) -or
    [IO.Path]::GetFileName($normalizedPath) -cne $script:runLeaf -or
    $script:runLeaf -notmatch '^moonhostabi-txn-[0-9a-f]{32}$'
  ) {
    throw "Refusing to remove unexpected transaction path '$normalizedPath'."
  }
}

function Start-CliProcess {
  param(
    [Parameter(Mandatory)] [string] $CliPath,
    [Parameter(Mandatory)] [string[]] $Arguments,
    [string] $Fault
  )

  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $CliPath
  $startInfo.WorkingDirectory = $script:repositoryRoot
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  if ([String]::IsNullOrWhiteSpace($Fault)) {
    [void]$startInfo.Environment.Remove('MOONHOSTABI_INTERNAL_TEST_ONLY_FAULT')
  } else {
    $startInfo.Environment['MOONHOSTABI_INTERNAL_TEST_ONLY_FAULT'] = $Fault
  }
  foreach ($argument in $Arguments) {
    $startInfo.ArgumentList.Add($argument)
  }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  if (-not $process.Start()) {
    throw 'Failed to start MoonHostABI transaction verifier process.'
  }
  [pscustomobject]@{
    Process = $process
    Stdout = $process.StandardOutput.ReadToEndAsync()
    Stderr = $process.StandardError.ReadToEndAsync()
  }
}

function Complete-CliProcess {
  param([Parameter(Mandatory)] $Running)

  $Running.Process.WaitForExit()
  [pscustomobject]@{
    ExitCode = $Running.Process.ExitCode
    Stdout = $Running.Stdout.GetAwaiter().GetResult()
    Stderr = $Running.Stderr.GetAwaiter().GetResult()
  }
}

function Get-GenerationFingerprint {
  param(
    [Parameter(Mandatory)] [string] $Directory,
    [Parameter(Mandatory)] [string[]] $Names
  )

  @(
    foreach ($name in $Names) {
      $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Directory $name)).Hash
      "$name=$($hash.ToLowerInvariant())"
    }
  )
}

function Assert-FingerprintEqual {
  param(
    [Parameter(Mandatory)] [string[]] $Expected,
    [Parameter(Mandatory)] [string[]] $Actual,
    [Parameter(Mandatory)] [string] $Description
  )

  if (
    [String]::Join([Environment]::NewLine, $Expected) -cne
    [String]::Join([Environment]::NewLine, $Actual)
  ) {
    throw "$Description changed the prior complete output."
  }
}

[IO.Directory]::CreateDirectory($runRoot) | Out-Null
Assert-ExactTransactionTemp

try {
  $moon = @(Get-Command moon -CommandType Application -ErrorAction Stop)[0].Source
  & $moon -C $repositoryRoot build cmd/moonhostabi --target native
  if ($LASTEXITCODE -ne 0) {
    throw "MoonHostABI build failed with exit code $LASTEXITCODE."
  }

  $executableName = if ($IsWindows) { 'moonhostabi.exe' } else { 'moonhostabi' }
  $cliPath = Join-Path $repositoryRoot "_build/native/debug/build/cmd/moonhostabi/$executableName"
  if (-not (Test-Path -LiteralPath $cliPath -PathType Leaf)) {
    throw "Built MoonHostABI executable was not found at '$cliPath'."
  }

  $artifact = Join-Path $repositoryRoot 'fixtures/artifacts/externref.wasm'
  $contract = Join-Path $repositoryRoot 'fixtures/contracts/externref.contract.json'
  $freshArguments = @(
    'generate', $artifact, '--contract', $contract, '--out', $outputRoot
  )
  $first = Start-CliProcess -CliPath $cliPath -Arguments $freshArguments
  $second = Start-CliProcess -CliPath $cliPath -Arguments $freshArguments
  $results = @(
    (Complete-CliProcess -Running $first),
    (Complete-CliProcess -Running $second)
  )
  $exitCodes = @($results.ExitCode | Sort-Object)
  if ($exitCodes.Count -ne 2 -or $exitCodes[0] -ne 0 -or $exitCodes[1] -ne 3) {
    throw "Concurrent generate exit codes must be 0 and 3; received $($exitCodes -join ', ')."
  }
  $loser = @($results | Where-Object ExitCode -eq 3)
  if ($loser.Count -ne 1) {
    throw 'Expected exactly one losing concurrent writer.'
  }
  $failure = $loser[0].Stderr | ConvertFrom-Json
  if ($failure.code -cne 'MHA_OUTPUT_EXISTS') {
    throw "Losing writer must report MHA_OUTPUT_EXISTS; received '$($failure.code)'."
  }

  $expectedFiles = @(
    'adapter.ts',
    'moonhostabi.contract.json',
    'moonhostabi.manifest.json'
  )
  $actualFiles = @(
    Get-ChildItem -LiteralPath $outputRoot -Force |
      Sort-Object Name |
      ForEach-Object Name
  )
  if (
    [String]::Join([Environment]::NewLine, $actualFiles) -cne
    [String]::Join([Environment]::NewLine, $expectedFiles)
  ) {
    throw "Published output has an unexpected file set: $($actualFiles -join ', ')."
  }
  $manifestPath = Join-Path $outputRoot 'moonhostabi.manifest.json'
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  if (
    $manifest.schemaVersion -ne 1 -or
    $manifest.generatorVersion -cne '0.1.0' -or
    [String]::IsNullOrWhiteSpace($manifest.files.'adapter.ts') -or
    [String]::IsNullOrWhiteSpace($manifest.files.'moonhostabi.contract.json')
  ) {
    throw 'Published generation manifest is incomplete.'
  }
  $adapterHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $outputRoot 'adapter.ts')).Hash.ToLowerInvariant()
  $contractHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $outputRoot 'moonhostabi.contract.json')).Hash.ToLowerInvariant()
  if (
    $manifest.files.'adapter.ts' -cne $adapterHash -or
    $manifest.files.'moonhostabi.contract.json' -cne $contractHash -or
    $manifest.contractSha256 -cne $contractHash
  ) {
    throw 'Published generation manifest hashes do not match output bytes.'
  }

  $transactionPrefix = "$outputLeaf.moonhostabi-"
  $beforeFaults = Get-GenerationFingerprint -Directory $outputRoot -Names $expectedFiles
  $updateArguments = @(
    'generate', $artifact, '--out', $outputRoot, '--update'
  )
  foreach ($fault in @('second-write', 'after-backup')) {
    $faultRun = Start-CliProcess -CliPath $cliPath -Arguments $updateArguments -Fault $fault
    $faultResult = Complete-CliProcess -Running $faultRun
    if ($faultResult.ExitCode -ne 3) {
      throw "Fault '$fault' must exit 3; received $($faultResult.ExitCode)."
    }
    $faultFailure = $faultResult.Stderr | ConvertFrom-Json
    if ($faultFailure.code -cne 'MHA_OUTPUT_IO') {
      throw "Fault '$fault' must report MHA_OUTPUT_IO; received '$($faultFailure.code)'."
    }
    $afterFault = Get-GenerationFingerprint -Directory $outputRoot -Names $expectedFiles
    Assert-FingerprintEqual -Expected $beforeFaults -Actual $afterFault -Description "Fault '$fault'"
    $faultResiduals = @(
      Get-ChildItem -LiteralPath $runRoot -Force |
        Where-Object {
          $_.Name.StartsWith($transactionPrefix, [StringComparison]::Ordinal)
        }
    )
    if ($faultResiduals.Count -ne 0) {
      throw "Fault '$fault' retained unexpected transaction paths: $($faultResiduals.Name -join ', ')."
    }
  }

  $retainedLeaf = 'retained-output'
  $retainedOutput = Join-Path $runRoot $retainedLeaf
  $retainedArguments = @(
    'generate', $artifact, '--contract', $contract, '--out', $retainedOutput
  )
  $retainedRun = Start-CliProcess -CliPath $cliPath -Arguments $retainedArguments -Fault 'retain-staging'
  $retainedResult = Complete-CliProcess -Running $retainedRun
  if ($retainedResult.ExitCode -ne 3 -or (Test-Path -LiteralPath $retainedOutput)) {
    throw 'Retained-staging fault must fail before publishing the target.'
  }
  $retainedFailure = $retainedResult.Stderr | ConvertFrom-Json
  if (
    $retainedFailure.code -cne 'MHA_OUTPUT_IO' -or
    $retainedFailure.message -notmatch 'retained staging path: (?<path>.+)$'
  ) {
    throw 'Retained-staging fault did not report its retained path.'
  }
  $reportedPath = [IO.Path]::GetFullPath($Matches.path)
  $retainedPrefix = "$retainedLeaf.moonhostabi-stage-"
  $retainedResiduals = @(
    Get-ChildItem -LiteralPath $runRoot -Force |
      Where-Object {
        $_.Name.StartsWith($retainedPrefix, [StringComparison]::Ordinal)
      }
  )
  if (
    $retainedResiduals.Count -ne 1 -or
    [IO.Path]::GetFullPath($retainedResiduals[0].FullName) -cne $reportedPath -or
    -not (Test-Path -LiteralPath (Join-Path $reportedPath 'interruption.marker') -PathType Leaf)
  ) {
    throw 'Reported staging path does not match the safely retained directory.'
  }
  Write-Output 'MOONHOSTABI_TRANSACTION_STATUS=GO'
}
finally {
  if (Test-Path -LiteralPath $runRoot) {
    Assert-ExactTransactionTemp
    Remove-Item -LiteralPath $runRoot -Recurse -Force
  }
}
