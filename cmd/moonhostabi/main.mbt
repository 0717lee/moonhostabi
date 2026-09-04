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
  Generate(String, String?, String)
} derive(Eq, Debug)

///|
suberror CliExecutionError {
  CliExecutionError(String, String)
} derive(Debug)

///|
pub impl Show for CliExecutionError with fn output(self, logger) {
  match self {
    CliExecutionError(_, message) => logger.write_string(message)
  }
}

///|
const MHA_INPUT_IO : String = "MHA_INPUT_IO"

///|
const MHA_OUTPUT_IO : String = "MHA_OUTPUT_IO"

///|
const MHA_OUTPUT_EXISTS : String = "MHA_OUTPUT_EXISTS"

///|
const MHA_LOCKFILE_INVALID : String = "MHA_LOCKFILE_INVALID"

///|
const MHA_CONTRACT_INVALID : String = "MHA_CONTRACT_INVALID"

///|
const USAGE : String = "usage: moonhostabi inspect <artifact.wasm> --format json | lock <artifact.wasm> --out <lock.json> | check <artifact.wasm> --against <lock.json> | generate <artifact.wasm> [--contract <contract.json>] --out <directory>"

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
  } else if args.length() == 4 &&
    args[0] == "generate" &&
    !args[1].is_empty() &&
    args[2] == "--out" &&
    !args[3].is_empty() {
    Some(Generate(args[1], None, args[3]))
  } else if args.length() == 6 &&
    args[0] == "generate" &&
    !args[1].is_empty() &&
    args[2] == "--contract" &&
    !args[3].is_empty() &&
    args[4] == "--out" &&
    !args[5].is_empty() {
    Some(Generate(args[1], Some(args[3]), args[5]))
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
fn invalid_result(code : String, message : String) -> CommandResult {
  {
    exit_code: exit_code_for_failure(InvalidArtifact),
    stdout: "",
    stderr: "{\"code\":\{json_string(code)},\"message\":\{json_string(message)}}",
  }
}

///|
fn unexpected_result(message : String) -> CommandResult {
  {
    exit_code: exit_code_for_failure(RuntimeFailure),
    stdout: "",
    stderr: "{\"code\":\{json_string(@model.MHA_RUNTIME_FAILURE)},\"message\":\{json_string(message)}}",
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
fn read_bytes(path : String) -> Bytes raise CliExecutionError {
  @fs.read_file_to_bytes(path) catch {
    @fs.IOError(message) => raise CliExecutionError(MHA_INPUT_IO, message)
  }
}

///|
fn analyze_artifact(
  bytes : Bytes,
) -> @projector.ProjectionAnalysis raise CliExecutionError {
  let wasm_module = @wasm_adapter.parse_artifact(bytes) catch {
    error =>
      raise CliExecutionError(@model.MHA_PARSE_MALFORMED, error.to_string())
  }
  @projector.analyze_host_abi(
    wasm_module,
    @projector.default_js_capability_policy(),
  )
}

///|
#cfg(platform="windows")
priv struct NativePath(String)

///|
#cfg(not(platform="windows"))
priv struct NativePath(Bytes)

///|
#cfg(platform="windows")
fn NativePath::from_string(path : String) -> NativePath {
  NativePath(path)
}

///|
#cfg(not(platform="windows"))
fn NativePath::from_string(path : String) -> NativePath {
  NativePath(@utf8.encode(path) + b"\x00")
}

///|
#borrow(path, bytes)
extern "C" fn write_new_file_ffi(
  path : NativePath,
  bytes : Bytes,
  length : Int,
) -> Int = "moonhostabi_write_new_file"

///|
fn write_new_file(path : String, bytes : Bytes) -> Unit raise CliExecutionError {
  match
    write_new_file_ffi(NativePath::from_string(path), bytes, bytes.length()) {
    0 => ()
    1 =>
      raise CliExecutionError(
        MHA_OUTPUT_EXISTS,
        "output already exists; choose a new path",
      )
    _ =>
      raise CliExecutionError(
        MHA_OUTPUT_IO,
        "failed to create complete output file",
      )
  }
}

///|
fn decode_baseline(
  bytes : Bytes,
) -> @lockfile.AbiLockfile raise CliExecutionError {
  @lockfile.decode_lockfile(@utf8.decode(bytes[:])) catch {
    error => raise CliExecutionError(MHA_LOCKFILE_INVALID, error.to_string())
  }
}

///|
fn decode_contract_file(path : String) -> String raise CliExecutionError {
  @utf8.decode(read_bytes(path)[:]) catch {
    _ =>
      raise CliExecutionError(
        MHA_CONTRACT_INVALID,
        "contract is not valid UTF-8",
      )
  }
}

///|
fn generate_adapter(
  abi : @model.HostAbi,
  contract : String?,
) -> @generator.GenerationResult raise CliExecutionError {
  @generator.generate_typescript_adapter(abi, contract) catch {
    @generator.InvalidContract(message) =>
      raise CliExecutionError(MHA_CONTRACT_INVALID, message)
  }
}

///|
fn cleanup_generated_directory(directory : String) -> Unit {
  for name in ["adapter.ts", "moonhostabi.contract.json"] {
    let path = "\{directory}/\{name}"
    if @fs.path_exists(path) {
      @fs.remove_file(path) catch {
        _ => ()
      }
    }
  }
  if @fs.path_exists(directory) {
    @fs.remove_dir(directory) catch {
      _ => ()
    }
  }
}

///|
fn write_generated_directory(
  directory : String,
  generated : @generator.GenerationResult,
) -> Unit raise CliExecutionError {
  if @fs.path_exists(directory) {
    raise CliExecutionError(
      MHA_OUTPUT_EXISTS,
      "output directory already exists; choose a new path",
    )
  }
  @fs.create_dir(directory) catch {
    @fs.IOError(message) => raise CliExecutionError(MHA_OUTPUT_IO, message)
  }
  let write_result : Result[Unit, (String, String)] = try {
    write_new_file(
      "\{directory}/adapter.ts",
      @utf8.encode(generated.typescript),
    )
    write_new_file(
      "\{directory}/moonhostabi.contract.json",
      @utf8.encode(generated.contract),
    )
    Ok(())
  } catch {
    CliExecutionError(code, message) => Err((code, message))
  }
  match write_result {
    Ok(_) => ()
    Err((code, message)) => {
      cleanup_generated_directory(directory)
      raise CliExecutionError(code, message)
    }
  }
}

///|
fn execute_command(command : CliCommand) -> CommandResult raise {
  match command {
    Inspect(artifact_path) => {
      let analysis = analyze_artifact(read_bytes(artifact_path))
      let encoded_abi = @lockfile.encode_canonical_abi(analysis.abi)
      if analysis.diagnostics.is_empty() {
        { exit_code: 0, stdout: encoded_abi, stderr: "" }
      } else {
        unsupported_result(analysis.diagnostics, encoded_abi)
      }
    }
    Lock(artifact_path, output_path) => {
      let artifact = read_bytes(artifact_path)
      let analysis = analyze_artifact(artifact)
      if !analysis.diagnostics.is_empty() {
        return unsupported_result(analysis.diagnostics, "")
      }
      let encoded = @lockfile.encode_lockfile(
        @lockfile.create_lockfile(analysis.abi, artifact),
      )
      write_new_file(output_path, @utf8.encode(encoded))
      {
        exit_code: 0,
        stdout: "{\"written\":\{json_string(output_path)}}",
        stderr: "",
      }
    }
    Check(artifact_path, baseline_path) => {
      let baseline = decode_baseline(read_bytes(baseline_path))
      let current = analyze_artifact(read_bytes(artifact_path))
      // artifactSha256 records where the baseline came from. Compatibility is
      // intentionally semantic, so different bytes with the same ABI pass.
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
    Generate(artifact_path, contract_path, output_directory) => {
      let analysis = analyze_artifact(read_bytes(artifact_path))
      if !analysis.diagnostics.is_empty() {
        return unsupported_result(analysis.diagnostics, "")
      }
      let contract = match contract_path {
        Some(path) => Some(decode_contract_file(path))
        None => None
      }
      let generated = generate_adapter(analysis.abi, contract)
      if !generated.diagnostics.is_empty() {
        return unsupported_result(generated.diagnostics, "")
      }
      write_generated_directory(output_directory, generated)
      {
        exit_code: 0,
        stdout: "{\"abiSha256\":\{json_string(generated.abi_sha256)},\"files\":[\"adapter.ts\",\"moonhostabi.contract.json\"]}",
        stderr: "",
      }
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
        CliExecutionError(code, message) => invalid_result(code, message)
        error => unexpected_result(error.to_string())
      }
  }
}

///|
#borrow(bytes)
extern "C" fn write_stderr_bytes(bytes : Bytes, length : Int) -> Int = "moonhostabi_write_stderr"

///|
fn write_stderr(text : String) -> Unit {
  let bytes = @utf8.encode(text + "\n")
  ignore(write_stderr_bytes(bytes, bytes.length()))
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
    write_stderr(result.stderr)
  }
  @sys.exit(result.exit_code)
}
