"""Exhaustive litmus-test enumerator for three operational memory models.

SC:      every interleaving of program order.
TSO:     x86-style per-thread FIFO store buffers with store-to-load forwarding.
         MFENCE drains the thread's buffer.
RELAXED: a simplified weak model in the spirit of Release Consistency and
         Arm-style ordering. Two accesses in one thread keep program order only
         if they touch the same address, either is a full fence, the earlier is
         an acquire, or the later is a release. No dependency ordering and no
         multi-copy-atomicity subtleties, so it is a teaching approximation,
         not the Arm or RVWMO axiomatic model.

Run: python3 memory-models/litmus.py   (exits non-zero if an expectation fails)
"""
from itertools import permutations
import sys

# Instruction forms: ("st", addr, val, ann), ("ld", addr, reg, ann), ("fence",)
# ann is None, "acq" or "rel".
def st(a, v, ann=None): return ("st", a, v, ann)
def ld(a, r, ann=None): return ("ld", a, r, ann)
FENCE = ("fence",)


def interleavings(threads):
    """Yield sequences of (tid, instr) preserving each thread's given order."""
    idx = [0] * len(threads)
    out = []
    def rec():
        if all(idx[t] == len(threads[t]) for t in range(len(threads))):
            yield list(out); return
        for t in range(len(threads)):
            if idx[t] < len(threads[t]):
                out.append((t, threads[t][idx[t]])); idx[t] += 1
                yield from rec()
                idx[t] -= 1; out.pop()
    yield from rec()


def run_sc(threads):
    res = set()
    for seq in interleavings(threads):
        mem, regs = {}, {}
        for _, ins in seq:
            if ins[0] == "st": mem[ins[1]] = ins[2]
            elif ins[0] == "ld": regs[ins[2]] = mem.get(ins[1], 0)
        res.add(tuple(sorted(regs.items())))
    return res


def must_keep(a, b):
    """True if program-ordered a, b may not be reordered under RELAXED."""
    if a == FENCE or b == FENCE: return True
    if a[1] == b[1]: return True
    if a[3] == "acq" or b[3] == "rel": return True
    return False


def run_relaxed(threads):
    res = set()
    def orders(th):
        seen = set()
        for p in permutations(range(len(th))):
            pos = {i: k for k, i in enumerate(p)}
            ok = all(pos[i] < pos[j] for i in range(len(th)) for j in range(i + 1, len(th))
                     if must_keep(th[i], th[j]))
            if ok and p not in seen:
                seen.add(p); yield [th[i] for i in p]
    def rec(t, acc):
        if t == len(threads):
            res.update(run_sc(acc)); return
        for o in orders(threads[t]):
            rec(t + 1, acc + [o])
    rec(0, [])
    return res


def run_tso(threads):
    res = set()
    n = len(threads)
    def rec(pc, bufs, mem, regs):
        progressed = False
        for t in range(n):
            # Drain the oldest buffered store to memory.
            if bufs[t]:
                a, v = bufs[t][0]
                nb = list(bufs); nb[t] = bufs[t][1:]
                m = dict(mem); m[a] = v
                rec(pc, tuple(nb), m, regs); progressed = True
            if pc[t] < len(threads[t]):
                ins = threads[t][pc[t]]
                np_ = list(pc); np_[t] += 1
                if ins[0] == "st":
                    nb = list(bufs); nb[t] = bufs[t] + ((ins[1], ins[2]),)
                    rec(tuple(np_), tuple(nb), mem, regs); progressed = True
                elif ins[0] == "ld":
                    fwd = [v for a, v in bufs[t] if a == ins[1]]
                    val = fwd[-1] if fwd else mem.get(ins[1], 0)
                    r = dict(regs); r[ins[2]] = val
                    rec(tuple(np_), bufs, mem, r); progressed = True
                elif ins == FENCE and not bufs[t]:
                    rec(tuple(np_), bufs, mem, regs); progressed = True
        if not progressed:
            res.add(tuple(sorted(regs.items())))
    rec(tuple([0] * n), tuple(() for _ in range(n)), {}, {})
    return res


TESTS = {
    # name: (threads, outcome of interest, {model: allowed?})
    "SB": ([[st("x", 1), ld("y", "r0")], [st("y", 1), ld("x", "r1")]],
           {"r0": 0, "r1": 0}, {"SC": False, "TSO": True, "RELAXED": True}),
    "SB+fences": ([[st("x", 1), FENCE, ld("y", "r0")], [st("y", 1), FENCE, ld("x", "r1")]],
                  {"r0": 0, "r1": 0}, {"SC": False, "TSO": False, "RELAXED": False}),
    "MP": ([[st("d", 1), st("f", 1)], [ld("f", "r0"), ld("d", "r1")]],
           {"r0": 1, "r1": 0}, {"SC": False, "TSO": False, "RELAXED": True}),
    "MP+rel+acq": ([[st("d", 1), st("f", 1, "rel")], [ld("f", "r0", "acq"), ld("d", "r1")]],
                   {"r0": 1, "r1": 0}, {"SC": False, "TSO": False, "RELAXED": False}),
    "LB": ([[ld("x", "r0"), st("y", 1)], [ld("y", "r1"), st("x", 1)]],
           {"r0": 1, "r1": 1}, {"SC": False, "TSO": False, "RELAXED": True}),
}

MODELS = {"SC": run_sc, "TSO": run_tso, "RELAXED": run_relaxed}


def main():
    fail = 0
    print(f"{'test':<12} {'outcome':<14} " + " ".join(f"{m:<8}" for m in MODELS))
    for name, (threads, outcome, expect) in TESTS.items():
        key = tuple(sorted(outcome.items()))
        cells = []
        for m, fn in MODELS.items():
            allowed = key in fn(threads)
            cells.append(f"{'allow' if allowed else 'forbid':<8}")
            if allowed != expect[m]:
                fail += 1; cells[-1] = cells[-1].strip() + "!"
        o = ",".join(f"{k}={v}" for k, v in outcome.items())
        print(f"{name:<12} {o:<14} " + " ".join(cells))
    if fail:
        print(f"{fail} expectation(s) failed"); sys.exit(1)
    print("all expectations hold")


if __name__ == "__main__":
    main()
