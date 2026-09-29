/// A deliberately incompatible API: the caller now supplies a precomputed total.

///|
#export_name("total_price")
pub fn total_price(subtotal_cents : Int) -> Int {
  subtotal_cents
}
