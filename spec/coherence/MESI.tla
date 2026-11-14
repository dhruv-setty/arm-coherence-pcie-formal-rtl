---------------------------- MODULE MESI ----------------------------
(* Snooping MESI on one cache line over an atomic bus.                  *)
(* Each step is one bus transaction, so the model checks the protocol's *)
(* state logic, not transient states or interconnect races.             *)
EXTENDS Naturals, FiniteSets

CONSTANTS Caches, Values

VARIABLES state, cdata, mem, lastWrite
vars == <<state, cdata, mem, lastWrite>>

States == {"M", "E", "S", "I"}

TypeOK ==
  /\ state \in [Caches -> States]
  /\ cdata \in [Caches -> Values]
  /\ mem \in Values
  /\ lastWrite \in Values

Init ==
  /\ state = [c \in Caches |-> "I"]
  /\ cdata \in [Caches -> Values]
  /\ mem \in Values
  /\ lastWrite = mem

Others(c) == Caches \ {c}
Owner == {d \in Caches : state[d] = "M"}

\* BusRd: read miss from c.
Read(c) ==
  /\ state[c] = "I"
  /\ IF Owner # {}
       THEN LET d == CHOOSE x \in Owner : TRUE IN
            /\ mem' = cdata[d]
            /\ cdata' = [cdata EXCEPT ![c] = cdata[d]]
            /\ state' = [state EXCEPT ![c] = "S", ![d] = "S"]
       ELSE /\ mem' = mem
            /\ cdata' = [cdata EXCEPT ![c] = mem]
            /\ IF \E d \in Others(c) : state[d] # "I"
                 THEN state' = [x \in Caches |->
                        IF x = c THEN "S"
                        ELSE IF state[x] = "E" THEN "S" ELSE state[x]]
                 ELSE state' = [state EXCEPT ![c] = "E"]
  /\ UNCHANGED lastWrite

\* Full-line write by c. BusRdX or BusUpgr from S or I invalidates peers.
Write(c, v) ==
  /\ IF state[c] \in {"M", "E"}
       THEN state' = [state EXCEPT ![c] = "M"]
       ELSE state' = [x \in Caches |-> IF x = c THEN "M" ELSE "I"]
  /\ cdata' = [cdata EXCEPT ![c] = v]
  /\ lastWrite' = v
  /\ UNCHANGED mem

Evict(c) ==
  /\ state[c] # "I"
  /\ mem' = IF state[c] = "M" THEN cdata[c] ELSE mem
  /\ state' = [state EXCEPT ![c] = "I"]
  /\ UNCHANGED <<cdata, lastWrite>>

Next == \E c \in Caches : Read(c) \/ Evict(c) \/ \E v \in Values : Write(c, v)

Spec == Init /\ [][Next]_vars

\* Single writer, multiple readers.
SWMR == \A c \in Caches : state[c] \in {"M", "E"} =>
          \A d \in Others(c) : state[d] = "I"

\* Every valid copy holds the latest write.
DataValue == \A c \in Caches : state[c] # "I" => cdata[c] = lastWrite

\* With no dirty owner, memory is current.
MemCurrent == Owner = {} => mem = lastWrite
=============================================================================
