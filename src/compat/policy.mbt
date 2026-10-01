///|
pub(all) enum Compatibility {
  Compatible
  Breaking
  Unknown
} derive(Eq, Debug)

///|
pub extend Compatibility with @debug.Debug::{to_repr}

///|
pub extend Compatibility with Eq::{not_equal, equal}

///|
pub(all) enum CompatibilityPolicy {
  Semantic
  Strict
} derive(Eq, Debug)

///|
pub extend CompatibilityPolicy with @debug.Debug::{to_repr}

///|
pub extend CompatibilityPolicy with Eq::{not_equal, equal}

///|
pub fn semantic_policy() -> CompatibilityPolicy {
  Semantic
}

///|
pub fn strict_policy() -> CompatibilityPolicy {
  Strict
}

///|
pub const MHA_EXPORT_ADDED : String = "MHA_EXPORT_ADDED"

///|
pub const MHA_IMPORT_REMOVED : String = "MHA_IMPORT_REMOVED"

///|
pub const MHA_SCHEMA_UNSUPPORTED : String = "MHA_SCHEMA_UNSUPPORTED"

///|
pub const MHA_FEATURE_UNSUPPORTED : String = "MHA_FEATURE_UNSUPPORTED"

///|
pub(all) struct AbiChange {
  classification : Compatibility
  code : String
  path : String
  message : String
} derive(Eq, Debug)

///|
pub extend AbiChange with @debug.Debug::{to_repr}

///|
pub extend AbiChange with Eq::{not_equal, equal}

///|
pub(all) struct CompatibilityReport {
  classification : Compatibility
  changes : Array[AbiChange]
} derive(Eq, Debug)

///|
pub extend CompatibilityReport with @debug.Debug::{to_repr}

///|
pub extend CompatibilityReport with Eq::{not_equal, equal}
