# procmap
***procmap* is designed to be a console/CLI utility to visualize the complete memory map of a Linux process, in effect, to visualize the memory mappings of both the kernel and usermode Virtual Address Space (VAS).**

It outputs a simple visualization of the complete memory map of a given process in a vertically-tiled format **ordered by descending virtual address** (see **screenshots** below). The script has the intelligence to show kernel and userspace mappings as well as calculate and show the sparse memory regions that will be present. Also, each segment or mapping is (very approximately) scaled by relative size and color-coded for readability. On 64-bit systems, it also shows the so-called non-canonical sparse region or 'hole' (typically close to a whopping 16,384 PB on the x86_64).

***Hey, be sure to see the [Examples](https://github.com/kaiwan/procmap#examples) section !***

***Usage:***

    $ ./procmap
    Usage: procmap [options] --pid=PID-of-process-to-show-memory-map-of
    Options:
     --only-user     : show ONLY the usermode mappings or segments (not kernel VAS)
     --only-kernel   : show ONLY the kernel-space mappings or segments (not user VAS)
            [default is to show BOTH]
     --locate=<start-vaddr>,<length_KB> : locate a given region within the process VAS
       start-vaddr : a virtual address in hexadecimal
       length : length of the region to locate in KB
     --export-maps=filename
         write all map information gleaned to the file you specify in CSV (note that it overwrites the file)
     --export-kernel=filename
         write kernel information gleaned to the file you specify in CSV (note that it overwrites the file)
     --verbose       : verbose mode (try it! see below for details)
     --debug         : run in debug mode
     --version|--ver : display version info.
    ...
    $

## Platforms that procmap has been tested upon:

- x86_64 (Ubuntu, Fedora distros)
- AArch32
    - Raspberry Pi Zero W
    - TI BBB (BeagleBone Black) [some work's pending here though]
- AArch64
    - Raspberry Pi 3B, 4 Model B
    - TI BGP (BeaglePlay)


## IMPORTANT: Running procmap on systems other than x86_64

On systems other than x86_64 (like AArch32/AArch64/etc), we don't know for sure if the *kernel module component* can be compiled and built while executing on
the target system; it may be possible to, it may not. Technically, to build a kernel module on the target system, you will require it to have a kernel development environment setup; this boils down to having the compiler, make and - key here - the 'kernel headers' package installed *for the kernel version it's currently running upon*. This can be a big ask... f.e., am running a *custom* 5.4 kernel on my Raspberry Pi; everything works fine, but as the kernel source tree for 5.4 isn't present (nor is there any kernel headers package), building kernel modules on it fails (while it works with the stock Raspbian kernel).
So: **you will have to cross-compile the kernel module**; to do so:

1. On your x86_64 *host* system:
2. Ensure you have an appropriate x86_64-to-ARM (or whatever) cross compiler installed. Then:

3. `git clone` the procmap project
4. `cd procmap/procmap_kernel`
5. `make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-`

(assuming the cross-compiler prefix is `arm-linux-gnueabihf-` (as is the case for the Raspberry Pi 32-bit)

6. Now verify that the procmap.ko kernel module is successfully built
7. If all okay, transfer it (scp or otherwise) to your target; place it (within the procmap source tree on the target device) in the *procmap/procmap_kernel* directory
8. run *procmap* - it should now work.


## How does procmap work?

### In a nutshell, in kernel-space:

The kernel memory map is garnered via the kernel component of this project - a *Loadable Kernel Module*. It collates all required information and makes that info available to userspace via a common interfacing technique - a debugfs (pseudo) file. Particulars:

Assuming the debugfs filesystem is mounted at /sys/kernel/debug, the kernel module sets up a debugfs file here:
` /sys/kernel/debug/procmap/disp_kernelseg_details`

Reading this file generates the required kernel information, which the scripts interpret and display.

### In a nutshell, in userspace:

The userspace memory map is collated and displayed by iterating over the `/proc/PID/maps` pseudo-file of the given process.

For both kernel and userspace, the procmap script color-codes and shows the following details (comma separated) for each segment (or mapping):

  * the start user virtual address (uva) to the right extreme of the line seperator
 - the segment name
 - it's size (appropriately, in KB/MB/GB/TB)
 - it's mode (permissions; highlights if null or .WX for security)
 - the type of mapping (p=private, s=shared) (only userspace)
 - if a file mapping, the offset from the beginning of the file (0x0 for anonymous or starts at BOF) (only userspace)

To aid with visualization of the process VAS, we show the relative vertical "length" of a segment or mapping via it's height (of course, it's a highly approximate measure).

The script works on both 32 and 64-bit Linux OS (lightly tested, I request more testing, on more platforms, and bug/issue reports please!).

## Requirements:

Kernel:

- Linux kernel 3.0 or later (technically, >= 2.6.12 should work)
- debugfs must be supported and mounted
- proc fs must be supported and mounted
- You should have the rights to build and insmod(8) a third-party (us!) kernel module on your box; in effect, you must have root (sudo)

User utils:

- bash(1)
- bc(1)
- smem(8)
- build system (make, gcc, binutils, etc)
- common utils typically always installed on a Linux system (grep, ps, cut, cat, getopts, etc)
- dtc (device tree compiler) on ARM-based platforms

Also of course, you require *root* access (to install the kernel module (or the CAP_SYS_MODULE capability), and get the details of any process from /proc/PID/<...>).

## Examples
### 1. Running procmap on an x86_64 Ubuntu 24.04 LTS box (with PID set to 1)
[![asciicast](https://asciinema.org/a/700116.svg)](https://asciinema.org/a/700116) 

In case you can't see or play the above (quite fantastic!) '*asciinema*' widget, pl visit this link to see the ASCII screencast:
https://asciinema.org/a/700116 

### 2. Running procmap on the TI BeagleBone Black (BBB) ARM-32 board (with PID set to a 'bash' process)
[![asciicast](https://asciinema.org/a/700143.svg)](https://asciinema.org/a/700143)


## A Note on the (optional) statistics display

We optionally show some **statistics** when done. The stats display is set to Off by default; to turn them On, set the `config:SHOW_STATS` variable to `1`. Once on, these stats show up:

 - Total sizes of kernel and user VAS's (bytes to TB range)
 - Total RAM reported by the system

 - If the process user virtual address space (VAS) memory is displayed, the stats also show, for that process:
   - The total number of VMA (Virtual Memory Area) objects the kernel currently maintains for it, and how many are 'sparse' regions
   - The amount and percentage of memory in it's userspace VAS that is just 'sparse' (empty; on 64-bit systems it can be very high!) vs the actually used memory amount and percentage
   - Memory usage statistics for this process via:
     - ps(1)
     - smem(8)

As a bonus, the output is logged - appended - to the file `log_procmap.txt`. Look it up when done.

### Exporting the output ###
- Use the --export-maps=filename option to write all map information gleaned to the file filename (writes in CSV format).
- If you just want the output (with color info), simply use output redirection:

  `procmap -p 12345 > procmap_saved.txt`

 It contains the ANSI color sequence codes within it; this is good, as to see it with color, simply 'cat' the file!
    - If you want to strip out the ANSI color sequence, do this:

  `sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g' procmap_saved.txt`


[End doc]
