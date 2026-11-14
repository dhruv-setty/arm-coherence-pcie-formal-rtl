---------------------------- MODULE MOESI ----------------------------
(* MOESI on one line over an atomic bus. Owned lets a dirty line be     *)
(* shared without writing back, which is the case CHI's SharedDirty     *)
(* (SD) state also covers.                                              *)
EXTENDS Naturals, FiniteSets

CONSTANTS Caches, Values

VARIABLES state, cdata, mem, lastWrite
vars == <<state, cdata, mem, lastWrite>>

States == {"M", "O", "E", "S", "I"}

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
Dirty == {d \in Caches : state[d] \in {"M", "O"}}

Read(c) ==
  /\ state[c] = "I"
  /\ IF Dirty # {}
       THEN LET d == CHOOSE x \in Dirty : TRUE IN
            \* The dirty holder supplies data and keeps ownership: no writeback.
            /\ cdata' = [cdata EXCEPT ![c] = cdata[d]]
            /\ state' = [state EXCEPT ![c] = "S", ![d] = "O"]
            /\ mem' = mem
       ELSE /\ cdata' = [cdata EXCEPT ![c] = mem]
            /\ mem' = mem
            /\ IF \E d \in Others(c) : state[d] # "I"
                 THEN state' = [x \in Caches |->
                        IF x = c THEN "S"
                        ELSE IF state[x] = "E" THEN "S" ELSE state[x]]
                 ELSE state' = [state EXCEPT ![c] = "E"]
  /\ UNCHANGED lastWrite

Write(c, v) ==
  /\ IF state[c] \in {"M", "E"}
       THEN state' = [state EXCEPT ![c] = "M"]
       ELSE state' = [x \in Caches |-> IF x = c THEN "M" ELSE "I"]
  /\ cdata' = [cdata EXCEPT ![c] = v]
  /\ lastWrite' = v
  /\ UNCHANGED mem

Evict(c) ==
  /\ state[c] # "I"
  /\ mem' = IF state[c] \in {"M", "O"} THEN cdata[c] ELSE mem
  /\ state' = [state EXCEPT ![c] = "I"]
  /\ UNCHANGED <<cdata, lastWrite>>

Next == \E c \in Caches : Read(c) \/ Evict(c) \/ \E v \in Values : Write(c, v)

Spec == Init /\ [][Next]_vars

SWMR == \A c \in Caches : state[c] \in {"M", "E"} =>
          \A d \in Others(c) : state[d] = "I"

\* At most one owner, and an owner only coexists with sharers.
SingleOwner == \A c \in Caches : state[c] = "O" =>
          \A d \in Others(c) : state[d] \in {"S", "I"}

DataValue == \A c \in Caches : state[c] # "I" => cdata[c] = lastWrite

MemCurrent == Dirty = {} => mem = lastWrite
=============================================================================
