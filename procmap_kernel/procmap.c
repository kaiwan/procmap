/*
 * procmap.c
 ***************************************************************
 * Brief Description:
 * This kernel module forms the kernel component of the 'procmap' project.

 The procmap project's intention is, given a process's PID, it will display
 (in a CLI/console output format only for now) a complete 'memory map' of the
 process VAS (virtual address space). 

 Note:- BSD has a utility by the same name: procmap(1), this project isn't
 the same, though (quite obviously) some aspects are similar.

 * Works on both 32 and 64-bit systems of differing architectures (note: only
 * lightly tested on ARM and x86 32 and 64-bit systems).
 *
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
#include <asm/pgtable.h>
#include "convenient.h"

#define OURMODNAME   "procmap"

MODULE_AUTHOR("Kaiwan N Billimoria");
MODULE_DESCRIPTION(
	"procmap: an LKM, the kernel component of the procmap project");
MODULE_LICENSE("Dual MIT/GPL");
MODULE_VERSION("0.1");

// For portability between 32 and 64-bit platforms
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

static struct dentry *gparent;

/* We use a mutex lock; details in Ch 15 and Ch 16 */
DEFINE_MUTEX(mtx);

/* 
 * query_kernelseg_details
 * Display kernel segment details as applicable to the architecture we're
 * currently running upon.
 * Format (for most of the details):
 *   start_kva,end_kva,<mode>,<name-of-region>
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

#ifdef ARM
	memset(tmpbuf, 0, TMPMAX);
	snprintf(tmpbuf, TMPMAX,
	FMTSPC "," FMTSPC ",r--,vector table\n",
	(TYPECST)VECTORS_BASE, (TYPECST)VECTORS_BASE+PAGE_SIZE);
	strncat(buf, tmpbuf, strlen(tmpbuf));
#endif

	/* kernel fixmap region */
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
                //SHOW_DELTA_M((TYPECST)FIXADDR_START, (TYPECST)FIXADDR_END));
#else
#include <asm/fixmap.h>
	 // seems to work fine on x86
	memset(tmpbuf, 0, TMPMAX);
	snprintf(tmpbuf, TMPMAX,
		FMTSPC "," FMTSPC ",r--,fixmap region\n",
		(TYPECST)FIXADDR_START, (TYPECST)FIXADDR_START+FIXADDR_SIZE);
	strncat(buf, tmpbuf, strlen(tmpbuf));
#endif

	/* kernel module region
	 * For the modules region, it's high in the kernel segment on typical 64-bit
	 * systems, but the other way around on many 32-bit systems (particularly
	 * ARM-32); so we rearrange the order in which it's shown depending on the
	 * arch, thus trying to maintain a 'by descending address' ordering.
	 */
#if(BITS_PER_LONG == 64)
	memset(tmpbuf, 0, TMPMAX);
	snprintf(tmpbuf, TMPMAX,
		FMTSPC "," FMTSPC ",rwx,module region\n",
		(TYPECST)MODULES_VADDR, (TYPECST)MODULES_END);
	strncat(buf, tmpbuf, strlen(tmpbuf));
#endif

#ifdef CONFIG_KASAN  // KASAN region: Kernel Address SANitizer
	memset(tmpbuf, 0, TMPMAX);
	snprintf(tmpbuf, TMPMAX,
	FMTSPC "," FMTSPC ",rw-,KASAN shadow\n",
	(TYPECST)KASAN_SHADOW_START, (TYPECST)KASAN_SHADOW_END);
	strncat(buf, tmpbuf, strlen(tmpbuf));
#endif

	/* vmalloc region */
	memset(tmpbuf, 0, TMPMAX);
	snprintf(tmpbuf, TMPMAX,
		FMTSPC "," FMTSPC ",rw-,vmalloc region\n",
		(TYPECST)VMALLOC_START, (TYPECST)VMALLOC_END);
	strncat(buf, tmpbuf, strlen(tmpbuf));

	/* lowmem region */
	memset(tmpbuf, 0, TMPMAX);
	snprintf(tmpbuf, TMPMAX,
		FMTSPC "," FMTSPC ",rwx,lowmem region\n",
		(TYPECST)PAGE_OFFSET, (TYPECST)high_memory);
	strncat(buf, tmpbuf, strlen(tmpbuf));

	/* (possible) highmem region;  may be present on some 32-bit systems */
#ifdef CONFIG_HIGHMEM
	memset(tmpbuf, 0, TMPMAX);
	snprintf(tmpbuf, TMPMAX,
	FMTSPC "," FMTSPC ",rwx,HIGHMEM region\n",
	(TYPECST)PKMAP_BASE, (TYPECST)(PKMAP_BASE)+(LAST_PKMAP*PAGE_SIZE));
	strncat(buf, tmpbuf, strlen(tmpbuf));
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
	memset(tmpbuf, 0, TMPMAX);
	snprintf(tmpbuf, TMPMAX,
		FMTSPC "," FMTSPC ",rwx,module region:\n",
		(TYPECST)MODULES_VADDR, (TYPECST)MODULES_END);
	strncat(buf, tmpbuf, strlen(tmpbuf));
#endif

	memset(tmpbuf, 0, TMPMAX);
	snprintf(tmpbuf, TMPMAX,
		"PAGE_OFFSET," FMTSPC "\n"
		"high_memory," FMTSPC "\n",
		(TYPECST)PAGE_OFFSET, (TYPECST)high_memory);
	strncat(buf, tmpbuf, strlen(tmpbuf));
}

/* Our debugfs file 1's read callback function */
static ssize_t dbgfs_show_kernelseg(struct file *filp, char __user *ubuf,
				 size_t count, loff_t *fpos)
{
#define MAXLEN 2048
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

	ret = simple_read_from_buffer(ubuf, MAXLEN, fpos, kbuf,
				       strlen(kbuf));
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

	/* Create a dir under the debugfs mount point, whose name is the
	 * module name */
	gparent = debugfs_create_dir(OURMODNAME, NULL);
	if (!gparent) {
		pr_info("%s: debugfs_create_dir failed, aborting...\n",
			OURMODNAME);
		stat = PTR_ERR(gparent);
		goto out_fail_1;
	}

	/* Create a generic debugfs file */
#define DBGFS_FILE1	"disp_kernelseg_details"
	file1 =
	    debugfs_create_file(DBGFS_FILE1, 0444, gparent, (void *)NULL,
				&dbgfs_fops);
	if (!file1) {
		pr_info("%s: debugfs_create_file failed, aborting...\n",
			OURMODNAME);
		stat = PTR_ERR(file1);
		goto out_fail_2;
	}
	pr_debug("%s: debugfs file 1 <debugfs_mountpt>/%s/%s created\n",
		 OURMODNAME, OURMODNAME, DBGFS_FILE1);

	return 0;	/* success */

out_fail_2:
	debugfs_remove_recursive(gparent);
out_fail_1:
	return stat;
}

static int __init procmap_init(void)
{
	int ret = 0;

	pr_info("%s: inserted\n", OURMODNAME);
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
