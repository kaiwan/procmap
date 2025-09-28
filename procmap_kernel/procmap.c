/*
 * procmap.c
 ***************************************************************
 * Brief Description:
 * This kernel module forms the kernel component of the 'procmap' project.
 *
 * The procmap project's intention is, given a process's PID, it will display
 * (in a CLI/console output format only for now) a complete 'memory map' of the
 * process VAS (virtual address space).
 *
 * Note:- BSD has a utility by the same name: procmap(1), this project isn't
 * the same, though (quite obviously) some aspects are similar.
 *
 * Works on both 32 and 64-bit systems of differing architectures (note: only
 * lightly tested on ARM and x86 32 and 64-bit systems).
 ***************************************************************
 * (c) Kaiwan N Billimoria, 2020
 * (c) kaiwanTECH
 * License: MIT
 */
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/sched.h>
#include <linux/mm.h>
#include <linux/highmem.h>
#include <linux/slab.h>
#include <linux/vmalloc.h>
#include <linux/debugfs.h>
#include <linux/version.h>
#include <asm/pgtable.h>
#include <asm/fixmap.h>
#include "convenient.h"

// TODO - rm this, use pr_fmt()
#define OURMODNAME   "procmap"

MODULE_AUTHOR("Kaiwan N Billimoria");
MODULE_DESCRIPTION("procmap: an LKM, the kernel component of the procmap project");
MODULE_LICENSE("Dual MIT/GPL");
MODULE_VERSION("0.2");

// For portability between 32 and 64-bit platforms
#if (BITS_PER_LONG == 32)
#define FMTSPC		"%08x"
#define FMTSPC_DEC	"%7d"
#define TYPECST		unsigned int
#elif(BITS_PER_LONG == 64)
#define FMTSPC		"%016lx"
#define FMTSPC_DEC	"%9ld"
#define TYPECST	    unsigned long
#endif

#define MAXLEN		2048
#define ELLPS "|                           [ . . . ]                         |\n"

static struct dentry *gparent;
DEFINE_MUTEX(mtx);

#include <linux/string.h>
/*
 * Try to use Red Hat’s version header if present.
 * Rocky/Alma sometimes don’t ship it, so we fall back.
 */
#ifdef CONFIG_RHEL_VERSION
#include <linux/rh_rhel_version.h>
#endif

/*
 * Unified helper to determine “effective RHEL release code”.
 * - On upstream kernels, returns 0 (unused).
 * - On RHEL/Rocky with rh_rhel_version.h, returns RHEL_RELEASE_CODE.
 * - Otherwise, tries to parse UTS_RELEASE string (e.g. "el8_10" → 810).
 */
static int using_rhel;
#include <generated/utsrelease.h>
static inline int effective_rhel_release_code(void)
{
#ifdef CONFIG_RHEL_VERSION
    return RHEL_RELEASE_CODE;
#else
    /* Fallback: check for "elX_Y" in the release string */
    if (strstr(UTS_RELEASE, "el8_10"))
        return 810;
    if (strstr(UTS_RELEASE, "el8_9"))
        return 809;
    if (strstr(UTS_RELEASE, "el8_8"))
        return 808;
    /* extend as needed for other releases */
    return 0; /* unknown or not RHEL-ish */
#endif
}

/*
 * query_kernelseg_details
 * Display kernel segment details as applicable to the architecture we're
 * currently running upon.
 * Format (for most of the details):
 *   start_kva,end_kva,<mode>,<name-of-region>
 *
 * CAREFUL: An ABI:
 * We depend on the <name-of-region> field (in the usermode scripts);
 * do NOT arbitrarily change it; if you Must, you'll need to update the
 * usermode scripts that depend on it.
 *
 * We try to order it by descending address (here, kva's) but this doesn't
 * always work out as ordering of regions differs by arch.
 *
 * An enhancement: this module is now part of our 'procmap' project.
 * Here, we display the kernel segment values in CSV format as follows:
 *   start_kva,end_kva,<mode>,<name-of-region>
 * f.e. on an x86_64 VM w/ 2047 MB RAM
 *   0xffff92dac0000000,0xffff92db3fff0000,rwx,lowmem region
 */
static void query_kernelseg_details(char *buf)
{
#define TMPMAX	256
	char tmpbuf[TMPMAX];
	unsigned long ram_size;

	// RHEL: Rocky/Alma/...
	if (using_rhel)
		ram_size = totalram_pages() * PAGE_SIZE;
	else {
		if (LINUX_VERSION_CODE >= KERNEL_VERSION(5, 0, 0))
			ram_size = totalram_pages() * PAGE_SIZE;
		else { // totalram_pages() undefined on the BeagleBone running an older 4.19 kernel..
#if defined(CONFIG_ARM)
		// TODO: test on ARM
			ram_size = totalram_pages * PAGE_SIZE;
#endif
		}
	}

#if defined(CONFIG_ARM64)
	pr_info("%s:VA_BITS (CONFIG_ARM64_VA_BITS) = %d\n", KBUILD_MODNAME, VA_BITS);
	if (VA_BITS > 48 && PAGE_SIZE == (64*1024)) // typically 52 bits and 64K pages
		pr_warn("%s:*** >= ARMv8.2 with LPA? (YMMV, not supported here) ***\n", KBUILD_MODNAME);
#endif

#ifdef ARM
	/* On ARM, the definition of VECTORS_BASE turns up only in kernels >= 4.11 */
#if LINUX_VERSION_CODE > KERNEL_VERSION(4, 11, 0)
	memset(tmpbuf, 0, TMPMAX);
	snprintf(tmpbuf, TMPMAX,
		 "%08x,%08lx,r--,vector table\n",
		 //FMTSPC "," FMTSPC ",r--,vector table\n",
		 (TYPECST) VECTORS_BASE, (TYPECST) VECTORS_BASE + PAGE_SIZE);
	strlcat(buf, tmpbuf, MAXLEN);
#endif
#endif

	/* kernel fixmap region */
	memset(tmpbuf, 0, TMPMAX);
	snprintf(tmpbuf, TMPMAX,
		 FMTSPC "," FMTSPC ",r--,fixmap region\n",
#ifdef CONFIG_ARM
	/* On ARM, the FIXADDR_START macro's only defined from 5.11!
	 * For earlier kernels, as a really silly and ugly workaround am simply
	 * copying it in here...
	 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 11, 0)
#define FIXADDR_START 0xffc00000UL
#endif
		 (TYPECST) FIXADDR_START, (TYPECST) FIXADDR_END
#else
		 (TYPECST) FIXADDR_START, (TYPECST) FIXADDR_START + FIXADDR_SIZE
#endif
	);
	strlcat(buf, tmpbuf, MAXLEN);

	/* kernel module region
	 * For the modules region, it's high in the kernel segment on typical 64-bit
	 * systems, but the other way around on many 32-bit systems (particularly
	 * ARM-32); so we rearrange the order in which it's shown depending on the
	 * arch, thus trying to maintain a 'by descending address' ordering.
	 */
#if (BITS_PER_LONG == 64)
	memset(tmpbuf, 0, TMPMAX);
	snprintf(tmpbuf, TMPMAX,
		 FMTSPC "," FMTSPC ",rwx,module region\n",
		 (TYPECST) MODULES_VADDR, (TYPECST) MODULES_END);
	strlcat(buf, tmpbuf, MAXLEN);
#endif

#ifdef CONFIG_KASAN		// KASAN region: Kernel Address SANitizer
	memset(tmpbuf, 0, TMPMAX);
	snprintf(tmpbuf, TMPMAX,
		 FMTSPC "," FMTSPC ",rw-,KASAN shadow\n",
		 (TYPECST) KASAN_SHADOW_START, (TYPECST) KASAN_SHADOW_END);
	strlcat(buf, tmpbuf, MAXLEN);
#endif

	/* TODO - sparsemem model; vmemmap region */

	/* vmalloc region */
	memset(tmpbuf, 0, TMPMAX);
	snprintf(tmpbuf, TMPMAX,
		 FMTSPC "," FMTSPC ",rw-,vmalloc region\n",
		 (TYPECST) VMALLOC_START, (TYPECST) VMALLOC_END);
	strlcat(buf, tmpbuf, MAXLEN);

	/* lowmem region: spans from PAGE_OFFSET for size of platform RAM */
	memset(tmpbuf, 0, TMPMAX);
	snprintf(tmpbuf, TMPMAX,
		 FMTSPC "," FMTSPC ",rwx,lowmem region\n",
		 (TYPECST)PAGE_OFFSET, (TYPECST)(PAGE_OFFSET + ram_size));
	strlcat(buf, tmpbuf, MAXLEN);

	pr_debug("high_memory = 0x%016lx\n", high_memory);

	/* (possible) highmem region;  may be present on some 32-bit systems */
#if defined(CONFIG_HIGHMEM)  && (BITS_PER_LONG==32)
	memset(tmpbuf, 0, TMPMAX);
	snprintf(tmpbuf, TMPMAX,
		 FMTSPC "," FMTSPC ",rwx,HIGHMEM region\n",
		 (TYPECST) PKMAP_BASE, (TYPECST) (PKMAP_BASE) + (LAST_PKMAP * PAGE_SIZE));
	strlcat(buf, tmpbuf, MAXLEN);
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

#if (BITS_PER_LONG == 32)	/* modules region: see the comment above reg this */
	memset(tmpbuf, 0, TMPMAX);
	snprintf(tmpbuf, TMPMAX,
		 FMTSPC "," FMTSPC ",rwx,module region:\n",
		 (TYPECST)MODULES_VADDR, (TYPECST)MODULES_END);
	strlcat(buf, tmpbuf, MAXLEN);
#endif

#include <asm/processor.h>
	/* Enhancement: also pass along other key kernel vars */
	memset(tmpbuf, 0, TMPMAX);
	snprintf(tmpbuf, TMPMAX,
		 "PAGE_SIZE," FMTSPC "\n"
		 "TASK_SIZE," FMTSPC "\n",
//		"high_memory," FMTSPC "\n",
		 (TYPECST) PAGE_SIZE, (TYPECST) TASK_SIZE); //, high_memory);
	strlcat(buf, tmpbuf, MAXLEN);
}

/* Our debugfs file 1's read callback function */
static ssize_t dbgfs_show_kernelseg(struct file *filp, char __user *ubuf,
				    size_t count, loff_t *fpos)
{
	char *kbuf;
	ssize_t ret = 0;

	if (mutex_lock_interruptible(&mtx))
		return -ERESTARTSYS;

	kbuf = kzalloc(MAXLEN, GFP_KERNEL);
	if (unlikely(!kbuf)) {
		mutex_unlock(&mtx);
		return -ENOMEM;
	}

	query_kernelseg_details(kbuf);

	ret = simple_read_from_buffer(ubuf, MAXLEN, fpos, kbuf, strlen(kbuf));
	//MSG("ret = %ld\n", ret);
	kfree(kbuf);
	mutex_unlock(&mtx);

	return ret;
}

static const struct file_operations dbgfs_fops = {
	.read = dbgfs_show_kernelseg,
};

static int setup_debugfs_file(void)
{
	struct dentry *file1;
	int stat = 0;

	if (!IS_ENABLED(CONFIG_DEBUG_FS)) {
		pr_warn("%s: debugfs unsupported! Aborting ...\n", OURMODNAME);
		return -EINVAL;
	}

	/* Create a dir under the debugfs mount point, whose name is the module name */
	gparent = debugfs_create_dir(OURMODNAME, NULL);
	if (!gparent) {
		pr_info("%s: debugfs_create_dir failed, aborting...\n", OURMODNAME);
		stat = PTR_ERR(gparent);
		goto out_fail_1;
	}

	/* Create a generic debugfs file */
#define DBGFS_FILE1	"disp_kernelseg_details"
	file1 = debugfs_create_file(DBGFS_FILE1, 0444, gparent, (void *)NULL, &dbgfs_fops);
	if (!file1) {
		pr_info("%s: debugfs_create_file failed, aborting...\n", OURMODNAME);
		stat = PTR_ERR(file1);
		goto out_fail_2;
	}
	pr_debug("%s: debugfs file 1 <debugfs_mountpt>/%s/%s created\n",
		 OURMODNAME, OURMODNAME, DBGFS_FILE1);

	return 0;		/* success */

 out_fail_2:
	debugfs_remove_recursive(gparent);
 out_fail_1:
	return stat;
}

static int __init procmap_init(void)
{
	int ret = 0;

	pr_info("%s: inserted\n", OURMODNAME);
	if (effective_rhel_release_code() >= 808) {
		using_rhel = 1;
		pr_info("fyi, RHEL release = %d\n", effective_rhel_release_code());
	}

	ret = setup_debugfs_file();
	return ret;
}

static void __exit procmap_exit(void)
{
	debugfs_remove_recursive(gparent);
	pr_info("%s: removed\n", OURMODNAME);
}

module_init(procmap_init);
module_exit(procmap_exit);
