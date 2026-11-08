/*
 * W600D chain-load shim: started by the vendor U-Boot with `go <shim>` after
 * mainline U-Boot was loaded to TARGET. The vendor U-Boot runs with MMU and
 * caches on, mainline U-Boot expects them off (as after TF-A):
 *   mask IRQs, clean+invalidate D-cache, MMU/D-cache off, clean+invalidate
 *   again, invalidate I-cache + TLBs, jump to TARGET.
 * Position independent, no stack, no data: registers only.
 */
#ifndef TARGET
#define TARGET 0x00800000
#endif

	.text
	.globl	_start
_start:
	msr	daifset, #0xf
	movz	x20, #(TARGET >> 16), lsl #16
	movk	x20, #(TARGET & 0xffff)

	bl	dcache_clean_inv_all

	mrs	x0, CurrentEL
	cmp	x0, #0x8
	b.ne	1f
	mrs	x1, sctlr_el2
	bic	x1, x1, #(1 << 0)		/* M */
	bic	x1, x1, #(1 << 2)		/* C */
	msr	sctlr_el2, x1
	b	2f
1:	mrs	x1, sctlr_el1
	bic	x1, x1, #(1 << 0)
	bic	x1, x1, #(1 << 2)
	msr	sctlr_el1, x1
2:	isb

	bl	dcache_clean_inv_all

	ic	iallu
	mrs	x0, CurrentEL
	cmp	x0, #0x8
	b.ne	3f
	tlbi	alle2
	b	4f
3:	tlbi	vmalle1
4:	dsb	sy
	isb

	mov	x0, #0
	mov	x1, #0
	mov	x2, #0
	mov	x3, #0
	br	x20

/* clean + invalidate all data/unified cache levels up to LoC, by set/way */
dcache_clean_inv_all:
	dsb	sy
	mrs	x10, clidr_el1
	ubfx	x11, x10, #24, #3		/* LoC */
	cbz	x11, 9f
	mov	x12, #0				/* level << 1 */
5:	add	x13, x12, x12, lsr #1		/* level * 3 */
	lsr	x14, x10, x13
	and	x14, x14, #7			/* cache type at this level */
	cmp	x14, #2
	b.lt	8f				/* no D/unified cache */
	msr	csselr_el1, x12
	isb
	mrs	x14, ccsidr_el1
	and	x15, x14, #7
	add	x15, x15, #4			/* log2(line size) */
	ubfx	x16, x14, #3, #10		/* max way */
	ubfx	x17, x14, #13, #15		/* max set */
	clz	w18, w16			/* way shift */
6:	mov	x19, x17			/* set */
7:	lsl	x9, x16, x18
	orr	x9, x12, x9
	lsl	x8, x19, x15
	orr	x9, x9, x8
	dc	cisw, x9
	subs	x19, x19, #1
	b.ge	7b
	subs	x16, x16, #1
	b.ge	6b
8:	add	x12, x12, #2
	cmp	x11, x12, lsr #1
	b.gt	5b
9:	mov	x12, #0
	msr	csselr_el1, x12
	dsb	sy
	isb
	ret
