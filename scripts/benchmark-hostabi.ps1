param(
  [Parameter(Mandatory)] [string] $CliPath,
  [string] $BaselineCliPath,
  [string[]] $Case,
  [string] $WasmToolsPath,
  [string] $ArtifactPath,
  [string] $OutputDirectory,
  [ValidateRange(0, 1000)] [int] $Warmups = 3,
  [ValidateRange(1, 10000)] [int] $Samples = 20,
  [ValidateRange(0.001, 30)] [double] $TimeoutSeconds = 30,
  [string] $PythonPath = 'python'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$cli = (Resolve-Path -LiteralPath $CliPath).ProviderPath
if (-not (Test-Path -LiteralPath $cli -PathType Leaf)) {
  throw 'CliPath must identify an already-built native MoonHostABI executable.'
}
$arguments = @(
  '-B', (Join-Path $PSScriptRoot 'benchmark_corpus.py'), 'run',
  '--cli-path', $cli, '--warmups', [string] $Warmups, '--samples', [string] $Samples,
  '--timeout-seconds', $TimeoutSeconds.ToString([Globalization.CultureInfo]::InvariantCulture)
)
if ($WasmToolsPath) { $arguments += @('--wasm-tools-path', (Resolve-Path -LiteralPath $WasmToolsPath).ProviderPath) }
if ($BaselineCliPath) { $arguments += @('--baseline-cli-path', (Resolve-Path -LiteralPath $BaselineCliPath).ProviderPath) }
foreach ($caseName in $Case) { $arguments += @('--case', $caseName) }
if ($ArtifactPath) { $arguments += @('--artifact-path', (Resolve-Path -LiteralPath $ArtifactPath).ProviderPath) }
if ($OutputDirectory) { $arguments += @('--output-directory', $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)) }
& $PythonPath @arguments
if ($LASTEXITCODE -ne 0) { throw "Native CLI benchmark failed with exit code $LASTEXITCODE." }
