"""Render a VCD capture as a logic analyser style PNG.

Usage: python3 vcd_view.py dma.vcd out.png [first_cycle] [last_cycle]
Reads only the signals listed in SIGNALS from the dma_engine scope.
"""
import sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

SIGNALS = ["reg_valid", "state", "mem_req_valid", "mem_req_we", "mem_req_addr",
           "mem_rsp_valid", "outstanding", "head"]
STATES = ["IDLE", "FETCH", "FWAIT", "CHECK", "COPY", "WB2", "WB3"]


def parse(path):
    ids, width, scope = {}, {}, []
    changes = {}
    t = 0
    with open(path) as f:
        for line in f:
            p = line.split()
            if not p:
                continue
            if p[0] == "$scope":
                scope.append(p[2])
            elif p[0] == "$upscope":
                scope.pop()
            elif p[0] == "$var":
                name = p[4]
                if scope and scope[-1] == "dma_engine" and name in SIGNALS:
                    ids.setdefault(p[3], []).append(name)
                    width[name] = int(p[2])
            elif p[0].startswith("#"):
                t = int(p[0][1:])
            elif p[0][0] in "01xz" and len(p) == 1:
                for n in ids.get(p[0][1:], []):
                    changes.setdefault(n, []).append((t, int(p[0][0]) if p[0][0] in "01" else 0))
            elif p[0][0] == "b":
                v = p[0][1:]
                val = int(v, 2) if set(v) <= {"0", "1"} else 0
                for n in ids.get(p[1], []):
                    changes.setdefault(n, []).append((t, val))
    return changes, width, t


def main():
    path, out = sys.argv[1], sys.argv[2]
    c0 = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    c1 = int(sys.argv[4]) if len(sys.argv) > 4 else None
    changes, width, tend = parse(path)
    t0, t1 = 2 * c0, 2 * c1 if c1 else tend
    fig, ax = plt.subplots(figsize=(14, 0.62 * len(SIGNALS) + 0.8))
    for row, name in enumerate(SIGNALS):
        y = len(SIGNALS) - 1 - row
        ev = changes.get(name, [(0, 0)])
        segs = []
        for i, (t, v) in enumerate(ev):
            te = ev[i + 1][0] if i + 1 < len(ev) else tend
            if te < t0 or t > t1:
                continue
            segs.append((max(t, t0), min(te, t1), v))
        if width.get(name, 1) == 1:
            xs, ys = [], []
            for a, b, v in segs:
                xs += [a / 2, b / 2]; ys += [y + 0.1 + 0.6 * v] * 2
            ax.plot(xs, ys, color="#e8590c", lw=1.4, drawstyle="steps-post")
        else:
            for a, b, v in segs:
                ax.plot([a / 2, b / 2], [y + 0.1, y + 0.1], color="#222", lw=0.8)
                ax.plot([a / 2, b / 2], [y + 0.7, y + 0.7], color="#222", lw=0.8)
                ax.plot([a / 2, a / 2], [y + 0.1, y + 0.7], color="#222", lw=0.8)
                if name == "state":
                    label = STATES[v] if v < len(STATES) else str(v)
                elif name == "mem_req_addr":
                    label = f"{v:x}"
                else:
                    label = str(v)
                if (b - a) / 2 >= 2:
                    ax.text((a + b) / 4, y + 0.4, label, ha="center", va="center", fontsize=7)
        ax.text(t0 / 2 - 0.5, y + 0.4, name, ha="right", va="center", fontsize=9, family="monospace")
    ax.set_xlim(t0 / 2, t1 / 2)
    ax.set_ylim(-0.2, len(SIGNALS))
    ax.set_yticks([])
    ax.set_xlabel("cycle")
    for s in ["top", "right", "left"]:
        ax.spines[s].set_visible(False)
    ax.set_title("dma_engine: two 64 B descriptors, memory latency 4 cycles", fontsize=10, loc="left")
    fig.tight_layout()
    fig.savefig(out, dpi=150)


if __name__ == "__main__":
    main()
