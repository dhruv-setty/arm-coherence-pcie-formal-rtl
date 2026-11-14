/* AArch64 TLBI by-VA operand (TLBI VAE1IS and friends), after ARM DDI 0487K,
   TLB maintenance instructions: Xt[63:48] ASID, Xt[47:44] TTL hint,
   Xt[43:0] VA[55:12]. Written for this repo, not copied from Arm's Sail model. */

default Order dec
$include <prelude.sail>

struct TLBIOperand = {
  asid : bits(16),
  ttl  : bits(4),
  va   : bits(56),
}

val decode_tlbi_va : bits(64) -> TLBIOperand
function decode_tlbi_va(xt) =
  struct { asid = xt[63 .. 48], ttl = xt[47 .. 44], va = xt[43 .. 0] @ 0x000 }

val encode_tlbi_va : (bits(16), bits(4), bits(56)) -> bits(64)
function encode_tlbi_va(asid, ttl, va) = asid @ ttl @ va[55 .. 12]

/* A TLB entry matches a by-VA invalidate when the page and ASID agree.
   Global entries match any ASID. 4 KiB granule only. */
struct TLBEntry = {
  vpn    : bits(44),
  asid   : bits(16),
  global : bool,
}

val tlbi_va_matches : (TLBEntry, TLBIOperand) -> bool
function tlbi_va_matches(e, op) =
  e.vpn == op.va[55 .. 12] & (e.global | e.asid == op.asid)
