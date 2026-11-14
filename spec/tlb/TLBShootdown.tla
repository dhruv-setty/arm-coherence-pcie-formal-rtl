------------------------- MODULE TLBShootdown -------------------------
(* Unmapping one page on a multicore system. The initiator clears the  *)
(* PTE, flushes its own TLB, sends invalidation IPIs and must wait for *)
(* every ack before the physical frame is freed. With SkipWait = TRUE  *)
(* the initiator frees early, and TLC finds a core still translating   *)
(* to a freed frame.                                                   *)
EXTENDS Naturals

CONSTANTS Cores, Initiator, SkipWait

ASSUME Initiator \in Cores

VARIABLES pte, tlb, pending, phase
vars == <<pte, tlb, pending, phase>>

Init ==
  /\ pte = TRUE
  /\ tlb = [c \in Cores |-> FALSE]
  /\ pending = [c \in Cores |-> FALSE]
  /\ phase = "idle"

\* Any core may walk the page table and cache the translation while it is present.
Fill(c) ==
  /\ pte /\ ~tlb[c]
  /\ tlb' = [tlb EXCEPT ![c] = TRUE]
  /\ UNCHANGED <<pte, pending, phase>>

Clear ==
  /\ phase = "idle"
  /\ pte' = FALSE
  /\ tlb' = [tlb EXCEPT ![Initiator] = FALSE]
  /\ phase' = "cleared"
  /\ UNCHANGED pending

SendIPIs ==
  /\ phase = "cleared"
  /\ pending' = [c \in Cores |-> c # Initiator]
  /\ phase' = "sent"
  /\ UNCHANGED <<pte, tlb>>

\* Remote core takes the IPI, invalidates the entry and acks.
Ack(c) ==
  /\ pending[c]
  /\ tlb' = [tlb EXCEPT ![c] = FALSE]
  /\ pending' = [pending EXCEPT ![c] = FALSE]
  /\ UNCHANGED <<pte, phase>>

Free ==
  /\ phase = "sent"
  /\ SkipWait \/ \A c \in Cores : ~pending[c]
  /\ phase' = "freed"
  /\ UNCHANGED <<pte, tlb, pending>>

Next == Clear \/ SendIPIs \/ Free \/ \E c \in Cores : Fill(c) \/ Ack(c)

Spec == Init /\ [][Next]_vars

TypeOK ==
  /\ pte \in BOOLEAN
  /\ tlb \in [Cores -> BOOLEAN]
  /\ pending \in [Cores -> BOOLEAN]
  /\ phase \in {"idle", "cleared", "sent", "freed"}

\* No core can reach a frame after it has been returned to the allocator.
NoStaleTranslation == phase = "freed" => \A c \in Cores : ~tlb[c]
=============================================================================
