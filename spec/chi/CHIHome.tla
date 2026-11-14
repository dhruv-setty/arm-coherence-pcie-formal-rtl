------------------------------ MODULE CHIHome ------------------------------
(* A subset of AMBA CHI (ARM IHI 0050) for one cache line: request nodes   *)
(* (RN-F) with the five stable states I, UC, UD, SC, SD and a home node    *)
(* (HN-F) that serialises ReadShared and ReadUnique. Each snoop is its own *)
(* step, so requests, snoops and clean evictions interleave, unlike the    *)
(* atomic bus models in ../coherence. Dirty data passes to the requester   *)
(* through the home's buffer (SnpRespData), not through memory.            *)
(* Not modelled: partial states (UCE, UDP), DMT and DCT, CompAck timing,   *)
(* retries, and the channel ordering CHI leaves unordered.                 *)
EXTENDS Naturals, FiniteSets

CONSTANTS RN, Values, NONE

VARIABLES st, data, mem, last, want, hn
vars == <<st, data, mem, last, want, hn>>

States == {"I", "UC", "UD", "SC", "SD"}
Valid(s) == s # "I"
Unique(s) == s \in {"UC", "UD"}
Dirty(s) == s \in {"UD", "SD"}

HnIdle == [phase |-> "idle", req |-> NONE, op |-> "none", snp |-> {}, buf |-> NONE, dirty |-> FALSE]

Init ==
  /\ st = [r \in RN |-> "I"]
  /\ data \in [RN -> Values]
  /\ mem \in Values
  /\ last = mem
  /\ want = [r \in RN |-> "none"]
  /\ hn = HnIdle

\* RN-F issues a request; it waits until the home completes it.
ReqShared(r) ==
  /\ st[r] = "I" /\ want[r] = "none"
  /\ want' = [want EXCEPT ![r] = "ReadShared"]
  /\ UNCHANGED <<st, data, mem, last, hn>>

ReqUnique(r) ==
  /\ st[r] \in {"I", "SC"} /\ want[r] = "none"
  /\ want' = [want EXCEPT ![r] = "ReadUnique"]
  /\ UNCHANGED <<st, data, mem, last, hn>>

\* HN-F accepts one request and works out which peers to snoop.
Accept(r) ==
  /\ hn.phase = "idle" /\ want[r] # "none"
  /\ LET op == want[r]
         peers == RN \ {r}
         targets == IF op = "ReadShared"
                      THEN {p \in peers : Unique(st[p]) \/ Dirty(st[p])}
                      ELSE {p \in peers : Valid(st[p])}
     IN hn' = [phase |-> "snoop", req |-> r, op |-> op, snp |-> targets, buf |-> NONE, dirty |-> FALSE]
  /\ UNCHANGED <<st, data, mem, last, want>>

\* One snooped RN-F responds. SnpShared keeps a dirty copy as SD; SnpUnique invalidates.
Snoop(p) ==
  /\ hn.phase = "snoop" /\ p \in hn.snp
  /\ LET s == st[p]
         ns == IF hn.op = "ReadShared"
                 THEN (IF Dirty(s) THEN "SD" ELSE IF s = "I" THEN "I" ELSE "SC")
                 ELSE "I"
         gotData == Valid(s)
     IN /\ st' = [st EXCEPT ![p] = ns]
        /\ hn' = [hn EXCEPT !.snp = @ \ {p},
                            !.buf = IF gotData THEN data[p] ELSE @,
                            !.dirty = @ \/ (Dirty(s) /\ hn.op = "ReadUnique")]
  /\ UNCHANGED <<data, mem, last, want>>

\* CompData to the requester once every snoop has answered.
Comp ==
  /\ hn.phase = "snoop" /\ hn.snp = {}
  /\ LET r == hn.req
         d == IF hn.buf = NONE THEN mem ELSE hn.buf
         othersValid == \E p \in RN \ {r} : Valid(st[p])
         ns == IF hn.op = "ReadShared"
                 THEN (IF othersValid THEN "SC" ELSE "UC")
                 ELSE (IF hn.dirty THEN "UD" ELSE "UC")
     IN /\ st' = [st EXCEPT ![r] = ns]
        /\ data' = [data EXCEPT ![r] = d]
        /\ want' = [want EXCEPT ![r] = "none"]
  /\ hn' = HnIdle
  /\ UNCHANGED <<mem, last>>

\* A store hits only in a unique state; UC upgrades to UD silently.
Store(r, v) ==
  /\ Unique(st[r]) /\ want[r] = "none"
  /\ st' = [st EXCEPT ![r] = "UD"]
  /\ data' = [data EXCEPT ![r] = v]
  /\ last' = v
  /\ UNCHANGED <<mem, want, hn>>

\* Clean lines may be dropped silently (Evict); a later snoop finds I.
EvictClean(r) ==
  /\ st[r] \in {"UC", "SC"} /\ want[r] = "none"
  /\ st' = [st EXCEPT ![r] = "I"]
  /\ UNCHANGED <<data, mem, last, want, hn>>

\* WriteBackFull is serialised at the home like any other request.
WriteBack(r) ==
  /\ Dirty(st[r]) /\ hn.phase = "idle" /\ want[r] = "none"
  /\ mem' = data[r]
  /\ st' = [st EXCEPT ![r] = "I"]
  /\ UNCHANGED <<data, last, want, hn>>

Next ==
  \/ Comp
  \/ \E r \in RN : ReqShared(r) \/ ReqUnique(r) \/ Accept(r) \/ Snoop(r)
                   \/ EvictClean(r) \/ WriteBack(r) \/ \E v \in Values : Store(r, v)

Spec == Init /\ [][Next]_vars

\* Unique states exclude every other valid copy.
SWMR == \A r \in RN : Unique(st[r]) => \A p \in RN \ {r} : st[p] = "I"
\* At most one dirty copy, and an SD copy only coexists with SC.
OneDirty == \A r, p \in RN : r # p /\ Dirty(st[r]) => ~Dirty(st[p]) /\ ~Unique(st[p])
DataValue == \A r \in RN : Valid(st[r]) => data[r] = last
MemCurrent == (\A r \in RN : ~Dirty(st[r])) /\ ~hn.dirty => mem = last
\* Every request is eventually completed (checked as a liveness property).
Progress == \A r \in RN : want[r] # "none" ~> want[r] = "none"

\* Weak fairness on the home's arbiter is not enough: TLC finds a requester
\* starved by the others taking turns. Real homes need a fair arbiter (CHI
\* uses retry with protocol credits); strong fairness models that.
WeakSpec == Spec /\ WF_vars(Comp) /\ \A r \in RN : WF_vars(Accept(r)) /\ WF_vars(Snoop(r))
FairSpec == Spec /\ WF_vars(Comp) /\ \A r \in RN : SF_vars(Accept(r)) /\ WF_vars(Snoop(r))
=============================================================================
