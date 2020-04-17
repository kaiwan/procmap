/*
 * ch7/procmap/procmap.c
 ***************************************************************
 * This program is part of the source code released for the book
 *  "Learn Linux Kernel Development"
 *  (c) Author: Kaiwan N Billimoria
 *  Publisher:  Packt
 *  GitHub repository:
 *  https://github.com/PacktPublishing/Learn-Linux-Kernel-Development
 *
 * From: Ch 7: Kernel and Memory Management Internals Essentials
 ****************************************************************
 * Brief Description:
 * This kernel module forms the kernel component of the 'procmap' project.

 The procmap project's intention is, given a process's PID, it will display
 (in a CLI/console output format only for now) a complete 'memory map' of the
 process VAS (virtual address space). 

 Note:- BSD has a utility by the same name: procmap(1), this project isn't
 the same, though (quite obviously) some aspects are similar.

 * A kernel module to show us some relevant details wrt the layout of the
 * kernel segment, IOW, the kernel VAS (Virtual Address Space). In effect,
 * this shows a simple memory map of the kernel. Works on both 32 and 64-bit
 * systems of differing architectures (note: only lightly tested on ARM and
 * x86 32 and 64-bit systems).
 *
 * For details, please refer the book, Ch 7.
 */
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/sched.h>
#include <linux/mm.h>
#include <linux/highmem.h>
#include <linux/slab.h>
#include <linux/vmalloc.h>
#include <asm/pgtable.h>
#include "../../klib_llkd.h"
#include "../../convenient.h"

#define OURMODNAME   "procmap"

MODULE_AUTHOR("Kaiwan N Billimoria");
MODULE_DESCRIPTION(
	"LLKD book:ch7/procmap: display some kernel segment details");
MODULE_LICENSE("Dual MIT/GPL");
MODULE_VERSION("0.1");

/* Module parameters */
static int show_procmap_style;
module_param(show_procmap_style, int, 0660);
MODULE_PARM_DESC(show_procmap_style,
        "Show kernel segment details in CSV format appropriate for the userland"
	" procmap code (default=0, no)");

// For protability between 32 and 64-bit platforms
#if(BITS_PER_LONG == 32)
	#define FMTSPC		"%08x"
	#define FMTSPC_DEC	"%7d"
	#define TYPECST		unsigned int
#elif(BITS_PER_LONG == 64)
	#define FMTSPC		"%016lx"
	#define FMTSPC_DEC	"%9ld"
	#define TYPECST	    unsigned long
#endif

#define ELLPS "|                           [ . . . ]                         |\n"

/* 
 * show_kernelseg_info
 * Display kernel segment details as applicable to the architecture we're
 * currently running upon.
 * Format (for most of the details):
 *  |<name of region>:   start_kva - end_kva        | [ size in KB/MB/GB]
 * f.e. on an x86_64 VM w/ 2047 MB RAM
 *  |lowmem region:   0xffff92dac0000000 - 0xffff92db3fff0000 | [ 2047 MB = 1 GB]
 *
 * We try to order it by descending address (here, kva's) but this doesn't
 * always work out as ordering of regions differs by arch.
 *
 * An enhancement: this module is now part of our 'procmap' project. In this
 * respect, the module parameter show_procmap_style wll be 1. If so, we shall
 * display the kernel segment values in CSV format as follows:
 *   start_kva,end_kva,<mode>,<name-of-region>
 * f.e. on an x86_64 VM w/ 2047 MB RAM
 *   <modname>,0xffff92dac0000000,0xffff92db3fff0000,rwx,lowmem region
 */
static void show_kernelseg_info(void)
{
	pr_info("\nSome Kernel Details [by decreasing address]\n"
	"+-------------------------------------------------------------+\n");
#ifdef ARM
	if (show_procmap_style == 0)
		pr_info(
		"|vector table:       "
		" 0x" FMTSPC " - 0x" FMTSPC " | [" FMTSPC_DEC " KB]  |\n",
		SHOW_DELTA_K((TYPECST)VECTORS_BASE, (TYPECST)VECTORS_BASE+PAGE_SIZE));
	else
		pr_info(
		"%s,0x" FMTSPC ",0x" FMTSPC ",r--,vector table\n",
		OURMODNAME, (TYPECST)VECTORS_BASE, (TYPECST)VECTORS_BASE+PAGE_SIZE);
#endif

	/* kernel fixmap region */
	if (show_procmap_style == 0)
		pr_info(
		ELLPS
		"|fixmap region:      "
		" 0x" FMTSPC " - 0x" FMTSPC " | [" FMTSPC_DEC " MB]  |\n",
#ifdef CONFIG_ARM
	/* RELOOK: We seem to have an issue on ARM; the compile fails with:
	 *  "./include/asm-generic/fixmap.h:29:38: error: invalid storage
	 *   class for function ‘fix_to_virt’"
	 * ### So, okay, as a *really silly and ugly* workaround am simply
	 * copying in the required macros from the
	 * arch/arm/include/asm/fixmap.h header manually here ###
	 */
#define FIXADDR_START   0xffc00000UL
#define FIXADDR_END     0xfff00000UL
                SHOW_DELTA_M((TYPECST)FIXADDR_START, (TYPECST)FIXADDR_END));
#else
#include <asm/fixmap.h>
	 // seems to work fine on x86
                SHOW_DELTA_M((TYPECST)FIXADDR_START, (TYPECST)FIXADDR_START+FIXADDR_SIZE));
	else
		pr_info(
		"%s,0x" FMTSPC ",0x" FMTSPC ",r--,fixmap region\n",
		OURMODNAME, (TYPECST)FIXADDR_START, (TYPECST)FIXADDR_START+FIXADDR_SIZE);
#endif

	/* kernel module region
	 * For the modules region, it's high in the kernel segment on typical 64-bit
	 * systems, but the other way around on many 32-bit systems (particularly
	 * ARM-32); so we rearrange the order in which it's shown depending on the
	 * arch, thus trying to maintain a 'by descending address' ordering.
	 */
#if(BITS_PER_LONG == 64)
	if (show_procmap_style == 0)
		pr_info(
		"|module region:      "
		" 0x" FMTSPC " - 0x" FMTSPC " | [" FMTSPC_DEC " MB]  |\n",
		SHOW_DELTA_M((TYPECST)MODULES_VADDR, (TYPECST)MODULES_END));
	else
		pr_info(
		"%s,0x" FMTSPC ",0x" FMTSPC ",rw-,module region\n",
		OURMODNAME, (TYPECST)MODULES_VADDR, (TYPECST)MODULES_END);
#endif

#ifdef CONFIG_KASAN  // KASAN region: Kernel Address SANitizer
	if (show_procmap_style == 0)
		pr_info(
		"|KASAN shadow:       "
		" 0x" FMTSPC " - 0x" FMTSPC " | [" FMTSPC_DEC " GB]\n",
		SHOW_DELTA_G((TYPECST)KASAN_SHADOW_START, (TYPECST)KASAN_SHADOW_END));
	else
		pr_info(
		"%s,0x" FMTSPC ",0x" FMTSPC ",rw-,KASAN shadow\n",
		OURMODNAME, (TYPECST)KASAN_SHADOW_START, (TYPECST)KASAN_SHADOW_END);
#endif

	/* vmalloc region */
	if (show_procmap_style == 0)
		pr_info(
		"|vmalloc region:     "
		" 0x" FMTSPC " - 0x" FMTSPC " | [" FMTSPC_DEC " MB = " FMTSPC_DEC " GB]\n",
		SHOW_DELTA_MG((TYPECST)VMALLOC_START, (TYPECST)VMALLOC_END));
	else
		pr_info(
		"%s,0x" FMTSPC ",0x" FMTSPC ",rw-,vmalloc region\n",
		OURMODNAME, (TYPECST)VMALLOC_START, (TYPECST)VMALLOC_END);

	/* lowmem region */
	if (show_procmap_style == 0)
		pr_info(
		"|lowmem region:      "
		" 0x" FMTSPC " - 0x" FMTSPC " | [" FMTSPC_DEC " MB = " FMTSPC_DEC " GB]"
#if(BITS_PER_LONG == 32)
		"\n|             (above:PAGE_OFFSET - highmem)                   |\n",
#else
		"\n|                  (above:PAGE_OFFSET    -      highmem)      |\n",
#endif
		SHOW_DELTA_MG((TYPECST)PAGE_OFFSET, (TYPECST)high_memory));
	else
		pr_info(
		"%s,0x" FMTSPC ",0x" FMTSPC ",rwx,lowmem region\n",
		OURMODNAME, (TYPECST)PAGE_OFFSET, (TYPECST)high_memory);

	/* (possible) highmem region;  may be present on some 32-bit systems */
#ifdef CONFIG_HIGHMEM
	if (show_procmap_style == 0)
		pr_info(
		"|HIGHMEM region:     "
		" 0x" FMTSPC " - 0x" FMTSPC " | [" FMTSPC_DEC " MB]\n",
		SHOW_DELTA_M((TYPECST)PKMAP_BASE,
			     (TYPECST)(PKMAP_BASE)+(LAST_PKMAP*PAGE_SIZE)));
	else
		pr_info(
		"%s,0x" FMTSPC ",0x" FMTSPC ",rwx,HIGHMEM region\n",
		OURMODNAME, (TYPECST)PKMAP_BASE, (TYPECST)(PKMAP_BASE)+(LAST_PKMAP*PAGE_SIZE));
#endif

	/*
	 * Symbols for kernel:
	 *   text begin/end (_text/_etext)
	 *   init begin/end (__init_begin, __init_end)
	 *   data begin/end (_sdata, _edata)
	 *   bss begin/end (__bss_start, __bss_stop)
	 * are only defined *within* the kernel (in-tree) and aren't available
	 * for modules; thus we don't attempt to print them.
	 */

#if(BITS_PER_LONG == 32)  /* modules region: see the comment above reg this */
	if (show_procmap_style == 0)
		pr_info(
		"|module region:      "
		" 0x" FMTSPC " - 0x" FMTSPC " | [" FMTSPC_DEC " MB]  |\n",
		SHOW_DELTA_M((TYPECST)MODULES_VADDR, (TYPECST)MODULES_END));
	else
		pr_info(
		"%s,0x" FMTSPC "0x" FMTSPC ",rwx,module region:\n",
		OURMODNAME, (TYPECST)MODULES_VADDR, (TYPECST)MODULES_END);
#endif
	if (show_procmap_style == 0)
		pr_info(ELLPS);
}

static int __init kernel_seg_init(void)
{
	pr_info("%s: inserted\n", OURMODNAME);
	show_kernelseg_info();
	return 0;	/* success */
}

static void __exit kernel_seg_exit(void)
{
	pr_info("%s: removed\n", OURMODNAME);
}

module_init(kernel_seg_init);
module_exit(kernel_seg_exit);
