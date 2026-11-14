#include "dma_drv.h"
#include <errno.h>
#include <string.h>

int dma_init(struct dma_dev *d, const struct dma_ops *ops, void *ctx,
             struct dma_desc *ring, uint64_t ring_pa, uint16_t size, int irq_en) {
  if (size == 0 || (size & (size - 1)) || (ring_pa & 31)) return -EINVAL;
  d->ops = ops; d->ctx = ctx; d->ring = ring; d->ring_pa = ring_pa;
  d->size = size; d->tail = 0; d->clean = 0;
  memset(ring, 0, sizeof(*ring) * size);
  ops->wr32(ctx, DMA_CTRL, 0);
  ops->wr32(ctx, DMA_RING_LO, (uint32_t)ring_pa);
  ops->wr32(ctx, DMA_RING_HI, (uint32_t)(ring_pa >> 32));
  ops->wr32(ctx, DMA_RING_SIZE, size);
  ops->wr32(ctx, DMA_TAIL, 0);
  ops->wr32(ctx, DMA_CTRL, 1u | (irq_en ? 2u : 0u));
  return 0;
}

int dma_inflight(const struct dma_dev *d) {
  return (uint16_t)(d->tail - d->clean);
}

int dma_submit(struct dma_dev *d, uint64_t src, uint64_t dst, uint32_t len, int irq) {
  if (len & 7) return -EINVAL;
  // Keep one slot free so a full ring is never mistaken for an empty one.
  if (dma_inflight(d) >= d->size - 1) return -EBUSY;
  struct dma_desc *x = &d->ring[d->tail & (d->size - 1)];
  x->src = src;
  x->dst = dst;
  x->status = 0;
  // OWN goes in last, in the same store as the length, after the addresses.
  d->ops->wmb(d->ctx);
  x->ctl = (uint64_t)len | DESC_OWN | (irq ? DESC_IRQ : 0);
  d->tail++;
  return 0;
}

void dma_kick(struct dma_dev *d) {
  d->ops->wmb(d->ctx);          // descriptors visible before the doorbell
  d->ops->wr32(d->ctx, DMA_TAIL, d->tail);
}

// Reclaims finished descriptors in order by reading DONE from memory, so the
// common path never reads a device register.
int dma_reap(struct dma_dev *d) {
  int n = 0;
  while (d->clean != d->tail) {
    struct dma_desc *x = &d->ring[d->clean & (d->size - 1)];
    if (!(x->status & DESC_DONE) || (x->ctl & DESC_OWN)) break;
    x->status = 0;
    d->clean++;
    n++;
  }
  return n;
}
