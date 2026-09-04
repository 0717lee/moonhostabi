///|
#external
pub type HostToken

///|
fn host_echo(token : HostToken) -> HostToken = "host" "echo"

///|
#export_name("roundtrip")
pub fn roundtrip(token : HostToken) -> HostToken {
  host_echo(token)
}
