/// Total cents after a basis-point discount, rounded down to whole cents.
/// This small example uses nonnegative inputs whose intermediate product fits Int.

///|
#export_name("total_price")
pub fn total_price(unit_cents : Int, quantity : Int, discount_bps : Int) -> Int {
  unit_cents * quantity * (10000 - discount_bps) / 10000
}
