# IĀTŌ

**Intent to Auditable Trust Object.** The monolith of the series: one repo where hardware behaviour is written down as something a machine can check.

This series covers the layer underneath the operating system: how caches agree on a value, how a page stops being reachable after it is unmapped, how PCIe orders the writes a device posts, and what a load is allowed to return under a given memory model. Each piece is a small, executable model with an invariant, and each claim in this README is backed by a check that runs in CI.

## What is here

| Area | Artefact | What it checks | Status |
|---|---|---|---|
| Cache coherence | `spec/coherence/MESI.tla` | Single writer, multiple readers; every valid copy holds the latest write; memory is current when no cache is dirty | TLC passes, 3 caches, 2 values, 120 states |
| Cache coherence | `spec/coherence/MOESI.tla` | As MESI, plus a single Owned holder that only coexists with sharers | TLC passes, 3 caches, 2 values, 216 states |
| Virtual memory | `spec/tlb/TLBShootdown.tla` | No core holds a translation to a frame after it is freed | TLC passes; the `SkipWait` variant fails with a counterexample |
| PCIe ordering | `spec/pcie/TLPOrdering.tla` | A consumer that sees the flag also sees the data | TLC passes with strict posted ordering; setting Relaxed Ordering on the flag write fails |
| Memory models | `memory-models/litmus.py` | SB, SB+fences, MP, MP+rel+acq and LB under SC, x86 TSO and a simplified relaxed model | All 15 expected allow or forbid results hold |
| RTL | `rtl/tlp_hdr_decode.sv` | Decodes Fmt, Type, TC, Attr, Length, Requester ID, Tag, byte enables and address for 3DW and 4DW memory requests and completions; flags byte enable violations | Verilator lint clean, Icarus testbench passes |
| RTL | `rtl/tlb.sv` | Fully associative TLB with fill, invalidate by VPN and invalidate all; never holds two valid entries for one VPN | Verilator lint clean, Icarus testbench passes |

Run everything with:

```
./scripts/check.sh
```

It needs Java 11 or later, Python 3, Icarus Verilog and Verilator. The script downloads `tla2tools.jar` on first run.

## Design choices

**Small models, honest bounds.** Every TLA+ model is checked exhaustively at a small size (three caches, three cores, one line, one page). That proves the invariant for that configuration, not for every size. The bounds are in each `.cfg` file.

**Atomic bus.** The coherence models treat each bus transaction as one step. They check the stable state protocol, not transient states, so they say nothing yet about races in a directory or a CHI style interconnect. Transient states are the next step.

**Failing variants on purpose.** The `_bug.cfg` configs are expected to fail. A model that can never fail checks nothing, so each safety property ships with the one change that breaks it.

**The relaxed model is a teaching model.** It allows any reordering of independent accesses unless a fence, an acquire or a release forbids it. It ignores dependencies and multi copy atomicity, so it is close to Release Consistency in spirit and is not the Arm or RISC-V axiomatic model. Those belong in herd7 or Sail, which this repo does not use yet.

## Coherence states and AMBA CHI

CHI names its cache states by validity, uniqueness and dirtiness. The MOESI model maps onto the CHI stable states like this:

| MOESI | CHI | Meaning |
|---|---|---|
| M | UD (Unique Dirty) | Only copy, modified |
| E | UC (Unique Clean) | Only copy, matches memory |
| S | SC (Shared Clean) | One of several copies; this copy is not responsible for writeback |
| O | SD (Shared Dirty) | Shared, and this copy is responsible for writeback |
| I | I (Invalid) | No copy |

CHI also defines UCE and UDP for partial lines, which these models do not cover.

## Layout

```
spec/
  coherence/   MESI.tla, MOESI.tla
  tlb/         TLBShootdown.tla (+ _bug variant)
  pcie/        TLPOrdering.tla (+ _bug variant)
memory-models/ litmus.py
rtl/           tlp_hdr_decode.sv, tlb.sv, tb/
scripts/       check.sh
docs/          references.md
```

## Roadmap

1. Transient states and a directory for the coherence models, then a CHI request and snoop subset.
2. PCIe completion ordering: a read completion must not pass posted writes headed the same way.
3. SystemVerilog assertions on the TLB checked with a formal tool, not only simulated.
4. Arm Stage 2 translation and TLBI semantics, cross checked against Sail.

## History

The earlier IĀTŌ material (observation induced equivalence and notes on Arm EL2, Stage 2 isolation, KVM and SVE2) is preserved at the tag `archive/v1`.

## References

See [`docs/references.md`](docs/references.md). Vendor specifications are cited by document and section; no specification text is reproduced here.

## License

Apache 2.0. See `LICENSE`.
