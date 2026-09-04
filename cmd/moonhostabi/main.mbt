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
pub(all) enum GenerateMode {
  Fresh
  Update
  DryRun
} derive(Eq, Debug)

///|
pub(all) enum CliCommand {
  Inspect(String)
  Lock(String, String)
  Check(String, String)
  Generate(String, String?, String, GenerateMode)
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
const MHA_OUTPUT_UNOWNED : String = "MHA_OUTPUT_UNOWNED"

///|
const MHA_LOCKFILE_INVALID : String = "MHA_LOCKFILE_INVALID"

///|
const MHA_CONTRACT_INVALID : String = "MHA_CONTRACT_INVALID"

///|
const USAGE : String = "usage: moonhostabi inspect <artifact.wasm> --format json | lock <artifact.wasm> --out <lock.json> | check <artifact.wasm> --against <lock.json> | generate <artifact.wasm> --out <directory> [--update | --dry-run] | generate <artifact.wasm> --contract <contract.json> --out <directory>"

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
    Some(Generate(args[1], None, args[3], Fresh))
  } else if args.length() == 6 &&
    args[0] == "generate" &&
    !args[1].is_empty() &&
    args[2] == "--contract" &&
    !args[3].is_empty() &&
    args[4] == "--out" &&
    !args[5].is_empty() {
    Some(Generate(args[1], Some(args[3]), args[5], Fresh))
  } else if args.length() == 5 &&
    args[0] == "generate" &&
    !args[1].is_empty() &&
    args[2] == "--out" &&
    !args[3].is_empty() &&
    args[4] == "--update" {
    Some(Generate(args[1], None, args[3], Update))
  } else if args.length() == 5 &&
    args[0] == "generate" &&
    !args[1].is_empty() &&
    args[2] == "--out" &&
    !args[3].is_empty() &&
    args[4] == "--dry-run" {
    Some(Generate(args[1], None, args[3], DryRun))
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
#borrow(source, destination)
extern "C" fn rename_directory_noreplace_ffi(
  source : NativePath,
  destination : NativePath,
) -> Int = "moonhostabi_rename_directory_noreplace"

///|
fn rename_directory_noreplace(source : String, destination : String) -> Int {
  rename_directory_noreplace_ffi(
    NativePath::from_string(source),
    NativePath::from_string(destination),
  )
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
  contract_text : String?,
) -> @generator.GenerationResult raise CliExecutionError {
  let contract = try {
    match contract_text {
      Some(text) => @contract.decode_contract(abi, text)
      None => @contract.create_contract_draft(abi)
    }
  } catch {
    error =>
      raise CliExecutionError(MHA_CONTRACT_INVALID, Show::to_string(error))
  }
  @generator.generate_typescript_adapter(abi, contract) catch {
    error =>
      raise CliExecutionError(MHA_CONTRACT_INVALID, Show::to_string(error))
  }
}

///|
priv enum GenerationFault {
  FailSecondWrite
  FailAfterBackup
  RetainStaging
} derive(Eq)

///|
priv struct OwnedGenerationDirectory(String)

///|
fn generation_file_names() -> Array[String] {
  ["adapter.ts", "moonhostabi.contract.json", "moonhostabi.manifest.json"]
}

///|
/// Internal, failure-only seam used by real-process transaction tests.
fn generation_fault_from_environment() -> GenerationFault? raise CliExecutionError {
  match @env.get_env_var("MOONHOSTABI_INTERNAL_TEST_ONLY_FAULT") {
    None => None
    Some("second-write") => Some(FailSecondWrite)
    Some("after-backup") => Some(FailAfterBackup)
    Some("retain-staging") => Some(RetainStaging)
    Some(_) =>
      raise CliExecutionError(
        MHA_OUTPUT_IO,
        "unsupported internal generation fault",
      )
  }
}

///|
fn generation_file_path(directory : String, name : String) -> String {
  let root : @path.Path = directory
  let child : @path.Path = name
  root.join(child).to_string()
}

///|
fn transaction_sibling_path(
  directory : String,
  role : String,
) -> String raise CliExecutionError {
  let normalized : @path.Path = directory
  let normalized = normalized.normalize()
  let leaf = normalized.basename().to_owned()
  if leaf.is_empty() || leaf == "." || leaf == ".." {
    raise CliExecutionError(
      MHA_OUTPUT_IO,
      "output directory must have a concrete final path component",
    )
  }
  let random = match @env.rand(16) {
    Some(bytes) => @lockfile.sha256_hex(bytes)
    None =>
      raise CliExecutionError(
        MHA_OUTPUT_IO,
        "platform entropy is unavailable for generation transaction",
      )
  }
  let sibling : @path.Path = "\{leaf}.moonhostabi-\{role}-\{random}"
  normalized.dirname().join(sibling).to_string()
}

///|
fn create_staging_directory(
  directory : String,
) -> OwnedGenerationDirectory raise CliExecutionError {
  for _ in 0..<8 {
    let candidate = transaction_sibling_path(directory, "stage")
    let created = try {
      @fs.create_dir(candidate)
      true
    } catch {
      _ => false
    }
    if created {
      return OwnedGenerationDirectory(candidate)
    }
  }
  raise CliExecutionError(
    MHA_OUTPUT_IO,
    "failed to create a unique sibling staging directory",
  )
}

///|
fn cleanup_owned_generation_directory(
  directory : OwnedGenerationDirectory,
) -> Bool {
  let OwnedGenerationDirectory(path) = directory
  let entries = @fs.read_dir(path) catch { _ => return false }
  for name in entries {
    if !generation_file_names().contains(name) {
      return false
    }
    let child = generation_file_path(path, name)
    let is_file = @fs.is_file(child) catch { _ => false }
    if !is_file {
      return false
    }
  }
  for name in entries {
    @fs.remove_file(generation_file_path(path, name)) catch {
      _ => return false
    }
  }
  try {
    @fs.remove_dir(path)
    true
  } catch {
    _ => false
  }
}

///|
fn[T] fail_with_staging_cleanup(
  code : String,
  message : String,
  staging : OwnedGenerationDirectory,
) -> T raise CliExecutionError {
  let OwnedGenerationDirectory(path) = staging
  if cleanup_owned_generation_directory(staging) {
    raise CliExecutionError(code, message)
  }
  raise CliExecutionError(code, "\{message}; retained staging path: \{path}")
}

///|
fn validate_owned_generation_directory(
  directory : String,
  expected_abi_sha256 : String,
) -> String raise CliExecutionError {
  let entries = @fs.read_dir(directory) catch {
    _ =>
      raise CliExecutionError(
        MHA_OUTPUT_UNOWNED,
        "output directory is missing or unreadable",
      )
  }
  entries.sort_by(fn(left, right) { left.compare(right) })
  if entries != generation_file_names() {
    raise CliExecutionError(
      MHA_OUTPUT_UNOWNED,
      "output directory contains missing or unknown files",
    )
  }
  let manifest_path = generation_file_path(
    directory, "moonhostabi.manifest.json",
  )
  let manifest_text = @utf8.decode(@fs.read_file_to_bytes(manifest_path)[:]) catch {
    _ =>
      raise CliExecutionError(
        MHA_OUTPUT_UNOWNED,
        "generation manifest is missing, unreadable, or not UTF-8",
      )
  }
  let manifest = @generator.decode_generation_manifest(manifest_text) catch {
    error => raise CliExecutionError(MHA_OUTPUT_UNOWNED, Show::to_string(error))
  }
  if manifest.abi_fingerprint() != expected_abi_sha256 {
    raise CliExecutionError(
      MHA_OUTPUT_UNOWNED,
      "generation manifest ABI does not match artifact",
    )
  }
  for name in manifest.owned_file_names() {
    let bytes = @fs.read_file_to_bytes(generation_file_path(directory, name)) catch {
      _ =>
        raise CliExecutionError(
          MHA_OUTPUT_UNOWNED,
          "owned output file is missing or unreadable: \{name}",
        )
    }
    if manifest.file_sha256(name) != Some(@lockfile.sha256_hex(bytes)) {
      raise CliExecutionError(
        MHA_OUTPUT_UNOWNED,
        "owned output file hash does not match manifest: \{name}",
      )
    }
  }
  @utf8.decode(
    @fs.read_file_to_bytes(
      generation_file_path(directory, "moonhostabi.contract.json"),
    )[:],
  ) catch {
    _ =>
      raise CliExecutionError(
        MHA_OUTPUT_UNOWNED,
        "owned contract is not valid UTF-8",
      )
  }
}

///|
fn write_staged_generation(
  staging : OwnedGenerationDirectory,
  generated : @generator.GenerationResult,
  fault : GenerationFault?,
) -> Unit raise CliExecutionError {
  let OwnedGenerationDirectory(path) = staging
  write_new_file(
    generation_file_path(path, "moonhostabi.contract.json"),
    @utf8.encode(generated.contract),
  )
  if fault == Some(RetainStaging) {
    write_new_file(
      generation_file_path(path, "interruption.marker"),
      b"retained for cleanup evidence",
    )
    raise CliExecutionError(MHA_OUTPUT_IO, "injected cleanup interruption")
  }
  let adapter_path = generation_file_path(path, "adapter.ts")
  if fault == Some(FailSecondWrite) {
    @fs.create_dir(adapter_path) catch {
      @fs.IOError(message) =>
        raise CliExecutionError(
          MHA_OUTPUT_IO,
          "failed to inject second-file OS error: \{message}",
        )
    }
    let observed = try
      write_new_file(adapter_path, @utf8.encode(generated.typescript))
    catch {
      CliExecutionError(_, message) => message
    } noraise {
      _ => ""
    }
    let obstruction_removed = try {
      @fs.remove_dir(adapter_path)
      true
    } catch {
      _ => false
    }
    if observed.is_empty() {
      raise CliExecutionError(
        MHA_OUTPUT_IO,
        "second-file OS fault injection did not fail",
      )
    }
    if !obstruction_removed {
      raise CliExecutionError(
        MHA_OUTPUT_IO,
        "\{observed}; retained injected obstruction path: \{adapter_path}",
      )
    }
    raise CliExecutionError(
      MHA_OUTPUT_IO,
      "injected second-file OS write failure: \{observed}",
    )
  }
  write_new_file(adapter_path, @utf8.encode(generated.typescript))
  write_new_file(
    generation_file_path(path, "moonhostabi.manifest.json"),
    @utf8.encode(generated.manifest),
  )
}

///|
fn move_output_to_unique_backup(
  directory : String,
) -> OwnedGenerationDirectory raise CliExecutionError {
  for _ in 0..<8 {
    let backup = transaction_sibling_path(directory, "backup")
    match rename_directory_noreplace(directory, backup) {
      0 => return OwnedGenerationDirectory(backup)
      1 => ()
      _ =>
        raise CliExecutionError(
          MHA_OUTPUT_IO,
          "failed to preserve prior output directory",
        )
    }
  }
  raise CliExecutionError(
    MHA_OUTPUT_IO,
    "failed to allocate a unique sibling backup path",
  )
}

///|
fn publish_fresh_generation(
  directory : String,
  staging : OwnedGenerationDirectory,
) -> Unit raise CliExecutionError {
  let OwnedGenerationDirectory(staging_path) = staging
  match rename_directory_noreplace(staging_path, directory) {
    0 => ()
    1 =>
      fail_with_staging_cleanup(
        MHA_OUTPUT_EXISTS,
        "output directory already exists; choose a new path",
        staging,
      )
    _ =>
      fail_with_staging_cleanup(
        MHA_OUTPUT_IO,
        "failed to publish complete output directory",
        staging,
      )
  }
}

///|
fn restore_backup_after_failure(
  directory : String,
  staging : OwnedGenerationDirectory,
  backup : OwnedGenerationDirectory,
  code : String,
  message : String,
) -> Unit raise CliExecutionError {
  let OwnedGenerationDirectory(staging_path) = staging
  let OwnedGenerationDirectory(backup_path) = backup
  let restored = rename_directory_noreplace(backup_path, directory) == 0
  let staging_cleaned = cleanup_owned_generation_directory(staging)
  let mut detail = message
  if !restored {
    detail = "\{detail}; retained backup path: \{backup_path}"
  }
  if !staging_cleaned {
    detail = "\{detail}; retained staging path: \{staging_path}"
  }
  raise CliExecutionError(code, detail)
}

///|
fn publish_updated_generation(
  directory : String,
  staging : OwnedGenerationDirectory,
  expected_abi_sha256 : String,
  fault : GenerationFault?,
) -> Unit raise CliExecutionError {
  ignore(validate_owned_generation_directory(directory, expected_abi_sha256))
  let backup = move_output_to_unique_backup(directory)
  if fault == Some(FailAfterBackup) {
    restore_backup_after_failure(
      directory,
      staging,
      backup,
      MHA_OUTPUT_IO,
      "injected publication failure after backup",
    )
  }
  let OwnedGenerationDirectory(staging_path) = staging
  match rename_directory_noreplace(staging_path, directory) {
    0 =>
      if !cleanup_owned_generation_directory(backup) {
        let OwnedGenerationDirectory(backup_path) = backup
        raise CliExecutionError(
          MHA_OUTPUT_IO,
          "new output was committed; retained backup path: \{backup_path}",
        )
      }
    1 =>
      restore_backup_after_failure(
        directory,
        staging,
        backup,
        MHA_OUTPUT_EXISTS,
        "another writer created the output directory during update",
      )
    _ =>
      restore_backup_after_failure(
        directory,
        staging,
        backup,
        MHA_OUTPUT_IO,
        "failed to publish updated output directory",
      )
  }
}

///|
fn publish_generated_directory(
  directory : String,
  generated : @generator.GenerationResult,
  mode : GenerateMode,
  fault : GenerationFault?,
) -> Unit raise CliExecutionError {
  if mode == DryRun {
    raise CliExecutionError(
      MHA_OUTPUT_IO,
      "internal error: dry-run cannot publish output",
    )
  }
  if mode == Fresh && @fs.path_exists(directory) {
    raise CliExecutionError(
      MHA_OUTPUT_EXISTS,
      "output directory already exists; choose a new path",
    )
  }
  if mode == Update {
    ignore(validate_owned_generation_directory(directory, generated.abi_sha256))
  }
  let staging = create_staging_directory(directory)
  let write_result : Result[Unit, (String, String)] = try {
    write_staged_generation(staging, generated, fault)
    Ok(())
  } catch {
    CliExecutionError(code, message) => Err((code, message))
  }
  match write_result {
    Err((code, message)) => fail_with_staging_cleanup(code, message, staging)
    Ok(_) =>
      match mode {
        Fresh => publish_fresh_generation(directory, staging)
        Update =>
          publish_updated_generation(
            directory,
            staging,
            generated.abi_sha256,
            fault,
          )
        DryRun => ()
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
    Generate(artifact_path, contract_path, output_directory, mode) => {
      let analysis = analyze_artifact(read_bytes(artifact_path))
      if !analysis.diagnostics.is_empty() {
        return unsupported_result(analysis.diagnostics, "")
      }
      let contract = match mode {
        Update =>
          Some(
            validate_owned_generation_directory(
              output_directory,
              @lockfile.host_abi_sha256(analysis.abi),
            ),
          )
        Fresh | DryRun =>
          match contract_path {
            Some(path) => Some(decode_contract_file(path))
            None => None
          }
      }
      let generated = generate_adapter(analysis.abi, contract)
      if !generated.diagnostics.is_empty() {
        return unsupported_result(generated.diagnostics, "")
      }
      match mode {
        DryRun =>
          if @fs.path_exists(output_directory) {
            raise CliExecutionError(
              MHA_OUTPUT_EXISTS,
              "output directory already exists; choose a new path",
            )
          }
        Fresh | Update =>
          publish_generated_directory(
            output_directory,
            generated,
            mode,
            generation_fault_from_environment(),
          )
      }
      {
        exit_code: 0,
        stdout: "{\"abiSha256\":\{json_string(generated.abi_sha256)},\"files\":[\"adapter.ts\",\"moonhostabi.contract.json\",\"moonhostabi.manifest.json\"]}",
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
