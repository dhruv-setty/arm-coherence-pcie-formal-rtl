# References

Specifications are cited by title and section. Check the current revision before relying on a section number.

## Vendor and standards specifications

- Arm, *AMBA CHI Architecture Specification* (ARM IHI 0050). Cache state model, request and snoop transactions.
- PCI-SIG, *PCI Express Base Specification*. Transaction Layer chapter: TLP header formats and byte enable rules (2.2), Transaction Ordering and the Relaxed Ordering attribute (2.4).
- Arm, *Arm Architecture Reference Manual for A-profile architecture* (ARM DDI 0487). Memory model, translation and TLB maintenance.
- Intel, *Intel 64 and IA-32 Architectures Software Developer's Manual*, Volume 3A. Memory ordering and TLB invalidation.

## Coherence and consistency

- D. J. Sorin, M. D. Hill, D. A. Wood, *A Primer on Memory Consistency and Cache Coherence*. Source of the single writer, multiple reader and data value invariants used here.
- K. Gharachorloo et al., "Memory Consistency and Event Ordering in Scalable Shared-Memory Multiprocessors", ISCA 1990. Release Consistency.
- P. Sewell et al., "x86-TSO: A Rigorous and Usable Programmer's Model for x86 Multiprocessors", CACM 2010.
- J. Alglave, L. Maranget, M. Tautschnig, "Herding Cats", TOPLAS 2014. Litmus tests and axiomatic models.

## Formal methods

- L. Lamport, *Specifying Systems*. TLA+ and TLC.
- A. Armstrong et al., "ISA Semantics for ARMv8-A, RISC-V, and CHERI-MIPS", POPL 2019. Sail.
