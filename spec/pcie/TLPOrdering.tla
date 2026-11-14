-------------------------- MODULE TLPOrdering --------------------------
(* Producer and consumer across PCIe. A device posts a data write and  *)
(* then a flag write; the CPU polls the flag and then reads the data.  *)
(* PCIe ordering: a posted request must not pass an earlier posted     *)
(* request unless the later one sets Relaxed Ordering (RO). With       *)
(* FlagRO = TRUE the flag may overtake the data, and TLC shows the     *)
(* consumer reading stale data.                                        *)
EXTENDS Naturals, Sequences

CONSTANTS FlagRO

VARIABLES q, mem, dev, cpu, got
vars == <<q, mem, dev, cpu, got>>

Init ==
  /\ q = <<>>
  /\ mem = [data |-> 0, flag |-> 0]
  /\ dev = "data"
  /\ cpu = "poll"
  /\ got = 0

PostData ==
  /\ dev = "data"
  /\ q' = Append(q, [addr |-> "data", ro |-> FALSE])
  /\ dev' = "flag"
  /\ UNCHANGED <<mem, cpu, got>>

PostFlag ==
  /\ dev = "flag"
  /\ q' = Append(q, [addr |-> "flag", ro |-> FlagRO])
  /\ dev' = "done"
  /\ UNCHANGED <<mem, cpu, got>>

RemoveAt(s, i) == SubSeq(s, 1, i - 1) \o SubSeq(s, i + 1, Len(s))

\* The fabric delivers the head, or a later TLP that is allowed to pass.
Deliver ==
  \E i \in 1..Len(q) :
    /\ i = 1 \/ q[i].ro
    /\ mem' = [mem EXCEPT ![q[i].addr] = 1]
    /\ q' = RemoveAt(q, i)
    /\ UNCHANGED <<dev, cpu, got>>

Poll ==
  /\ cpu = "poll" /\ mem.flag = 1
  /\ cpu' = "read"
  /\ UNCHANGED <<q, mem, dev, got>>

ReadData ==
  /\ cpu = "read"
  /\ got' = mem.data
  /\ cpu' = "done"
  /\ UNCHANGED <<q, mem, dev>>

Next == PostData \/ PostFlag \/ Deliver \/ Poll \/ ReadData

Spec == Init /\ [][Next]_vars

\* Seeing the flag implies seeing the data.
ConsumerSeesData == cpu = "done" => got = 1
=============================================================================
