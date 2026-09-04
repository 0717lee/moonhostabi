///|
pub(all) enum FailureKind {
  Usage
  BreakingAbi
  InvalidArtifact
  AdapterMismatch
  RuntimeFailure
} derive(Eq, Debug)

///|
pub fn exit_code_for_failure(failure : FailureKind) -> Int {
  match failure {
    Usage => 1
    BreakingAbi => 2
    InvalidArtifact => 3
    AdapterMismatch => 4
    RuntimeFailure => 5
  }
}

///|
pub(all) struct CommandResult {
  exit_code : Int
  stdout : String
  stderr : String
} derive(Eq, Debug)

///|
pub(all) enum CliCommand {
  Inspect(String)
  Lock(String, String)
  Check(String, String)
} derive(Eq, Debug)

///|
const USAGE : String = "usage: moonhostabi inspect <artifact.wasm> --format json | lock <artifact.wasm> --out <lock.json> | check <artifact.wasm> --against <lock.json>"

///|
fn parse_command(args : Array[String]) -> CliCommand? {
  if args.length() == 4 &&
    args[0] == "inspect" &&
    !args[1].is_empty() &&
    args[2] == "--format" &&
    args[3] == "json" {
    Some(Inspect(args[1]))
  } else if args.length() == 4 &&
    args[0] == "lock" &&
    !args[1].is_empty() &&
    args[2] == "--out" &&
    !args[3].is_empty() {
    Some(Lock(args[1], args[3]))
  } else if args.length() == 4 &&
    args[0] == "check" &&
    !args[1].is_empty() &&
    args[2] == "--against" &&
    !args[3].is_empty() {
    Some(Check(args[1], args[3]))
  } else {
    None
  }
}

///|
fn json_string(value : String) -> String {
  Json::string(value).stringify()
}

///|
fn severity_text(severity : @model.DiagnosticSeverity) -> String {
  match severity {
    @model.Info => "info"
    @model.Warning => "warning"
    @model.Error => "error"
  }
}

///|
fn encode_diagnostic(diagnostic : @model.Diagnostic) -> String {
  let byte_offset = match diagnostic.byte_offset {
    Some(value) => "\{value}"
    None => "null"
  }
  "{\"code\":\{json_string(diagnostic.code)},\"severity\":\{json_string(severity_text(diagnostic.severity))},\"path\":\{json_string(diagnostic.path)},\"message\":\{json_string(diagnostic.message)},\"byteOffset\":\{byte_offset}}"
}

///|
fn encode_diagnostics(diagnostics : Array[@model.Diagnostic]) -> String {
  "{\"diagnostics\":[\{diagnostics.map(fn(value) { encode_diagnostic(value) }).join(",")}] }"
}

///|
fn compatibility_text(classification : @compat.Compatibility) -> String {
  match classification {
    @compat.Compatible => "compatible"
    @compat.Breaking => "breaking"
    @compat.Unknown => "unknown"
  }
}

///|
fn encode_change(change : @compat.AbiChange) -> String {
  "{\"classification\":\{json_string(compatibility_text(change.classification))},\"code\":\{json_string(change.code)},\"path\":\{json_string(change.path)},\"message\":\{json_string(change.message)}}"
}

///|
fn encode_report(report : @compat.CompatibilityReport) -> String {
  "{\"classification\":\{json_string(compatibility_text(report.classification))},\"changes\":[\{report.changes.map(fn(value) { encode_change(value) }).join(",")}] }"
}

///|
fn invalid_result(message : String) -> CommandResult {
  {
    exit_code: exit_code_for_failure(InvalidArtifact),
    stdout: "",
    stderr: "{\"code\":\{json_string(@model.MHA_PARSE_MALFORMED)},\"message\":\{json_string(message)}}",
  }
}

///|
fn unsupported_result(
  diagnostics : Array[@model.Diagnostic],
  stdout : String,
) -> CommandResult {
  {
    exit_code: exit_code_for_failure(InvalidArtifact),
    stdout,
    stderr: encode_diagnostics(diagnostics),
  }
}

///|
fn analyze_artifact(bytes : Bytes) -> @projector.ProjectionAnalysis raise {
  let wasm_module = @wasm_adapter.parse_artifact(bytes)
  @projector.analyze_host_abi(
    wasm_module,
    @projector.default_js_capability_policy(),
  )
}

///|
fn execute_command(command : CliCommand) -> CommandResult raise {
  match command {
    Inspect(artifact_path) => {
      let analysis = analyze_artifact(@fs.read_file_to_bytes(artifact_path))
      let encoded_abi = @lockfile.encode_canonical_abi(analysis.abi)
      if analysis.diagnostics.is_empty() {
        { exit_code: 0, stdout: encoded_abi, stderr: "" }
      } else {
        unsupported_result(analysis.diagnostics, encoded_abi)
      }
    }
    Lock(artifact_path, output_path) => {
      if @fs.path_exists(output_path) {
        return invalid_result("lock output already exists; choose a new path")
      }
      let artifact = @fs.read_file_to_bytes(artifact_path)
      let analysis = analyze_artifact(artifact)
      if !analysis.diagnostics.is_empty() {
        return unsupported_result(analysis.diagnostics, "")
      }
      let encoded = @lockfile.encode_lockfile(
        @lockfile.create_lockfile(analysis.abi, artifact),
      )
      @fs.write_bytes_to_file(output_path, @utf8.encode(encoded))
      {
        exit_code: 0,
        stdout: "{\"written\":\{json_string(output_path)}}",
        stderr: "",
      }
    }
    Check(artifact_path, baseline_path) => {
      let baseline_text = @utf8.decode(@fs.read_file_to_bytes(baseline_path)[:])
      let baseline = @lockfile.decode_lockfile(baseline_text)
      let current = analyze_artifact(@fs.read_file_to_bytes(artifact_path))
      let report = @compat.compare_host_abi_with_diagnostics(
        baseline.canonical_abi(),
        current.abi,
        current.diagnostics,
        @compat.semantic_policy(),
      )
      let exit_code = match report.classification {
        @compat.Compatible => 0
        @compat.Breaking => exit_code_for_failure(BreakingAbi)
        @compat.Unknown => exit_code_for_failure(InvalidArtifact)
      }
      { exit_code, stdout: encode_report(report), stderr: "" }
    }
  }
}

///|
pub fn dispatch(args : Array[String]) -> CommandResult {
  match parse_command(args) {
    None =>
      { exit_code: exit_code_for_failure(Usage), stdout: "", stderr: USAGE }
    Some(command) =>
      execute_command(command) catch {
        error => invalid_result(error.to_string())
      }
  }
}

///|
fn main {
  let process_args = @env.args()
  let args = if process_args.is_empty() {
    []
  } else {
    process_args[1:].to_owned()
  }
  let result = dispatch(args)
  if !result.stdout.is_empty() {
    println(result.stdout)
  }
  if !result.stderr.is_empty() {
    println(result.stderr)
  }
  @sys.exit(result.exit_code)
}
