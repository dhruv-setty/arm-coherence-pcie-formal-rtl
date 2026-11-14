/* Descriptor control word of rtl/dma/dma_engine.sv, and the ownership
   handoff the engine and driver/dma_drv.c rely on. */

bitfield DescCtl : bits(64) = {
  IRQ : 33,
  OWN : 32,
  LEN : 31 .. 0,
}

val desc_post : (bits(32), bool) -> DescCtl
function desc_post(len, irq) =
  Mk_DescCtl(0x0000000 @ 0b00 @ (if irq then 0b1 else 0b0) @ 0b1 @ len)

val engine_may_process : DescCtl -> bool
function engine_may_process(c) = c[OWN] == 0b1

val len_ok : DescCtl -> bool
function len_ok(c) = c[LEN][2 .. 0] == 0b000

/* Engine writeback: OWN cleared, length and IRQ kept. */
val desc_complete : DescCtl -> DescCtl
function desc_complete(c) = [c with OWN = 0b0]

/* Driver may reclaim only after the engine has given the slot back. */
val driver_may_reap : (DescCtl, bool) -> bool
function driver_may_reap(c, done) = done & c[OWN] == 0b0
