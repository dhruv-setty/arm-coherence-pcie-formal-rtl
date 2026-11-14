val main : unit -> unit
function main() = {
  let xt : bits(64) = 0x0042_7_00000ABCDE1;
  let op = decode_tlbi_va(xt);
  assert(op.asid == 0x0042, "asid field");
  assert(op.ttl == 0x7, "ttl field");
  assert(op.va == 0x000_00ABCDE1_000, "va field");
  assert(encode_tlbi_va(op.asid, op.ttl, op.va) == xt, "round trip");

  let hit  : TLBEntry = struct { vpn = 0x000_00ABCDE1, asid = 0x0042, global = false };
  let miss : TLBEntry = struct { vpn = 0x000_00ABCDE1, asid = 0x0043, global = false };
  let glob : TLBEntry = struct { vpn = 0x000_00ABCDE1, asid = 0x0099, global = true };
  assert(tlbi_va_matches(hit, op), "same page, same asid");
  assert(not_bool(tlbi_va_matches(miss, op)), "other asid survives");
  assert(tlbi_va_matches(glob, op), "global entry matches any asid");

  let c = desc_post(0x00000040, true);
  assert(engine_may_process(c), "posted descriptor is device owned");
  assert(len_ok(c), "64 byte length is word aligned");
  assert(not_bool(driver_may_reap(c, false)), "driver cannot reap a posted slot");
  let d = desc_complete(c);
  assert(not_bool(engine_may_process(d)), "completed slot is driver owned");
  assert(d[LEN] == 0x00000040 & d[IRQ] == 0b1, "writeback keeps length and irq");
  assert(driver_may_reap(d, true), "driver reaps after DONE");
  assert(not_bool(len_ok(desc_post(0x00000041, false))), "unaligned length rejected");
  print_endline("PASS sail")
}
