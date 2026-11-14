// SPDX-License-Identifier: GPL-2.0
/*
 * Linux PCI driver for rtl/dma/dma_engine.sv behind rtl/pcie/cfg_space.sv.
 * Same register map and descriptor format as driver/dma_drv.c. BAR0 holds the
 * registers, the ring comes from dma_alloc_coherent(), and dma_wmb() orders
 * descriptor stores before OWN and before the TAIL doorbell.
 *
 * The vendor ID 0xABCD is a placeholder from cfg_space.sv, not a PCI-SIG
 * assignment, so this binds only to the model. With selftest=1 the probe
 * copies one buffer and checks it.
 */
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/interrupt.h>
#include <linux/dma-mapping.h>
#include <linux/completion.h>
#include <linux/io.h>
#include <linux/random.h>

#define DRV_NAME "iato_dma"

#define REG_CTRL      0x00
#define REG_STATUS    0x04
#define REG_RING_LO   0x08
#define REG_RING_HI   0x0C
#define REG_RING_SIZE 0x10
#define REG_TAIL      0x14
#define REG_HEAD      0x18
#define REG_DONE_CNT  0x1C

#define CTRL_EN       BIT(0)
#define CTRL_IRQ_EN   BIT(1)
#define STATUS_IRQ    BIT(1)

#define DESC_OWN      BIT_ULL(32)
#define DESC_IRQ      BIT_ULL(33)
#define DESC_DONE     BIT_ULL(0)

#define RING_SIZE     64

struct iato_desc {
	__le64 src;
	__le64 dst;
	__le64 ctl;
	__le64 status;
};

struct iato_dev {
	struct pci_dev *pdev;
	void __iomem *regs;
	struct iato_desc *ring;
	dma_addr_t ring_dma;
	u16 tail;
	u16 clean;
	spinlock_t lock;
	struct completion done;
};

static bool selftest;
module_param(selftest, bool, 0444);
MODULE_PARM_DESC(selftest, "Copy one buffer at probe and verify it");

static int iato_submit(struct iato_dev *d, dma_addr_t src, dma_addr_t dst, u32 len)
{
	struct iato_desc *x;
	unsigned long flags;

	if (len & 7)
		return -EINVAL;
	spin_lock_irqsave(&d->lock, flags);
	if ((u16)(d->tail - d->clean) >= RING_SIZE - 1) {
		spin_unlock_irqrestore(&d->lock, flags);
		return -EBUSY;
	}
	x = &d->ring[d->tail & (RING_SIZE - 1)];
	x->src = cpu_to_le64(src);
	x->dst = cpu_to_le64(dst);
	x->status = 0;
	dma_wmb();                         /* addresses before OWN */
	x->ctl = cpu_to_le64((u64)len | DESC_OWN | DESC_IRQ);
	d->tail++;
	dma_wmb();                         /* descriptor before doorbell */
	writel(d->tail, d->regs + REG_TAIL);
	spin_unlock_irqrestore(&d->lock, flags);
	return 0;
}

static int iato_reap(struct iato_dev *d)
{
	int n = 0;

	while (d->clean != d->tail) {
		struct iato_desc *x = &d->ring[d->clean & (RING_SIZE - 1)];

		if (!(le64_to_cpu(READ_ONCE(x->status)) & DESC_DONE) ||
		    (le64_to_cpu(READ_ONCE(x->ctl)) & DESC_OWN))
			break;
		dma_rmb();                 /* DONE before anything else in the slot */
		x->status = 0;
		d->clean++;
		n++;
	}
	return n;
}

static irqreturn_t iato_irq(int irq, void *arg)
{
	struct iato_dev *d = arg;
	u32 st = readl(d->regs + REG_STATUS);

	if (!(st & STATUS_IRQ))
		return IRQ_NONE;
	writel(STATUS_IRQ, d->regs + REG_STATUS);   /* write 1 to clear */
	spin_lock(&d->lock);
	if (iato_reap(d))
		complete(&d->done);
	spin_unlock(&d->lock);
	return IRQ_HANDLED;
}

static int iato_selftest(struct iato_dev *d)
{
	struct device *dev = &d->pdev->dev;
	const size_t len = 4096;
	dma_addr_t s_dma, t_dma;
	u8 *s, *t;
	int ret;

	s = dma_alloc_coherent(dev, len, &s_dma, GFP_KERNEL);
	t = dma_alloc_coherent(dev, len, &t_dma, GFP_KERNEL);
	if (!s || !t) {
		ret = -ENOMEM;
		goto out;
	}
	get_random_bytes(s, len);
	memset(t, 0, len);
	reinit_completion(&d->done);
	ret = iato_submit(d, s_dma, t_dma, len);
	if (ret)
		goto out;
	if (!wait_for_completion_timeout(&d->done, msecs_to_jiffies(1000))) {
		ret = -ETIMEDOUT;
		goto out;
	}
	ret = memcmp(s, t, len) ? -EIO : 0;
	dev_info(dev, "selftest %s (done_cnt %u)\n", ret ? "FAILED" : "passed",
		 readl(d->regs + REG_DONE_CNT));
out:
	if (s)
		dma_free_coherent(dev, len, s, s_dma);
	if (t)
		dma_free_coherent(dev, len, t, t_dma);
	return ret;
}

static int iato_probe(struct pci_dev *pdev, const struct pci_device_id *id)
{
	struct device *dev = &pdev->dev;
	struct iato_dev *d;
	int ret;

	d = devm_kzalloc(dev, sizeof(*d), GFP_KERNEL);
	if (!d)
		return -ENOMEM;
	d->pdev = pdev;
	spin_lock_init(&d->lock);
	init_completion(&d->done);

	ret = pcim_enable_device(pdev);
	if (ret)
		return ret;
	d->regs = pcim_iomap_region(pdev, 0, DRV_NAME);
	if (IS_ERR(d->regs))
		return PTR_ERR(d->regs);
	ret = dma_set_mask_and_coherent(dev, DMA_BIT_MASK(64));
	if (ret)
		return ret;
	pci_set_master(pdev);

	d->ring = dmam_alloc_coherent(dev, RING_SIZE * sizeof(*d->ring), &d->ring_dma, GFP_KERNEL);
	if (!d->ring)
		return -ENOMEM;

	ret = pci_alloc_irq_vectors(pdev, 1, 1, PCI_IRQ_MSI | PCI_IRQ_INTX);
	if (ret < 0)
		return ret;
	ret = devm_request_irq(dev, pci_irq_vector(pdev, 0), iato_irq, IRQF_SHARED, DRV_NAME, d);
	if (ret)
		goto free_vec;

	writel(0, d->regs + REG_CTRL);
	writel(lower_32_bits(d->ring_dma), d->regs + REG_RING_LO);
	writel(upper_32_bits(d->ring_dma), d->regs + REG_RING_HI);
	writel(RING_SIZE, d->regs + REG_RING_SIZE);
	writel(0, d->regs + REG_TAIL);
	writel(CTRL_EN | CTRL_IRQ_EN, d->regs + REG_CTRL);
	pci_set_drvdata(pdev, d);

	if (selftest) {
		ret = iato_selftest(d);
		if (ret)
			goto disable;
	}
	return 0;

disable:
	writel(0, d->regs + REG_CTRL);
	devm_free_irq(dev, pci_irq_vector(pdev, 0), d);
free_vec:
	pci_free_irq_vectors(pdev);
	return ret;
}

static void iato_remove(struct pci_dev *pdev)
{
	struct iato_dev *d = pci_get_drvdata(pdev);

	writel(0, d->regs + REG_CTRL);
	devm_free_irq(&pdev->dev, pci_irq_vector(pdev, 0), d);
	pci_free_irq_vectors(pdev);
}

static const struct pci_device_id iato_ids[] = {
	{ PCI_DEVICE(0xABCD, 0x0001) },
	{ }
};
MODULE_DEVICE_TABLE(pci, iato_ids);

static struct pci_driver iato_driver = {
	.name     = DRV_NAME,
	.id_table = iato_ids,
	.probe    = iato_probe,
	.remove   = iato_remove,
};
module_pci_driver(iato_driver);

MODULE_DESCRIPTION("IATO descriptor ring DMA engine (model)");
MODULE_LICENSE("GPL");
