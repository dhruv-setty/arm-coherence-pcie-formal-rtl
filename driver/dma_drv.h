// Driver for rtl/dma/dma_engine.sv. Written against an ops table so the same
// code runs over the Verilator model here and over a real BAR mapping later.
// In a Linux PCI driver the ops map to readl/writel on the pci_iomap()ed BAR0,
// the ring comes from dma_alloc_coherent(), and dma_wmb() orders descriptor
// writes before the doorbell.
#ifndef DMA_DRV_H
#define DMA_DRV_H
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define DMA_CTRL      0x00
#define DMA_STATUS    0x04
#define DMA_RING_LO   0x08
#define DMA_RING_HI   0x0C
#define DMA_RING_SIZE 0x10
#define DMA_TAIL      0x14
#define DMA_HEAD      0x18
#define DMA_DONE_CNT  0x1C

#define DESC_OWN  (1ull << 32)
#define DESC_IRQ  (1ull << 33)
#define DESC_DONE 1ull

struct dma_desc { uint64_t src, dst, ctl, status; };

struct dma_ops {
  uint32_t (*rd32)(void *ctx, uint32_t off);
  void     (*wr32)(void *ctx, uint32_t off, uint32_t val);
  void     (*wmb)(void *ctx);   // order descriptor stores before the doorbell
};

struct dma_dev {
  const struct dma_ops *ops;
  void *ctx;
  struct dma_desc *ring;        // CPU view of the ring
  uint64_t ring_pa;             // device view (bus address)
  uint16_t size;                // power of two
  uint16_t tail;                // next slot the driver fills
  uint16_t clean;               // next slot the driver reaps
};

int  dma_init(struct dma_dev *d, const struct dma_ops *ops, void *ctx,
              struct dma_desc *ring, uint64_t ring_pa, uint16_t size, int irq_en);
int  dma_submit(struct dma_dev *d, uint64_t src, uint64_t dst, uint32_t len, int irq);
void dma_kick(struct dma_dev *d);
int  dma_reap(struct dma_dev *d);
int  dma_inflight(const struct dma_dev *d);
#ifdef __cplusplus
}
#endif
#endif
