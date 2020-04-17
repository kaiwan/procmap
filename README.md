# vasu_grapher
*VASU = Virtual Address Space Usermode*. **A simple console/CLI utility to "graph" (visualize) the Linux user mode process VAS, in effect, the userspace memory map**.

A simple visualization (in a vertically-tiled format) of the userspace memory map of a given process. It works by iterating over the /proc/PID/maps pseudo-file of a given process. It color-codes and shows the following details (comma separated) for each segment (or mapping):
 - the start user virtual address (uva) to the right extreme of the line seperator
 - the segment name
 - it's size (appropriately, in KB/MB/GB)
 - it's mode (permissions; highlights if null or .WX for security)
 - the type of mapping (p=private, s=shared)
 - if a file mapping, the offset from thebeginning of the file (0x0 for anonymous or starts at BOF)

To aid with visualization of the process VAS, we show the relative "length" of a segment (or mapping) via it's height. The script works on both 32 and 64-bit Linux OS (lightly tested, request more testing and bug/issue reports please).

As an example, below, we run our script on process PID 1 on an x86_64 Ubuntu 18.04 Linux box, and
display partial screenshots of the beginning and end of the output:

![screenshot 1 of 2 of vasu_grapher run](scrshot1.png)

[...]

![screenshot 2 of 2 of vasu_grapher run](scrshot2.png)

**Note-**
- As of now, we also show some statistics when done- the amount and percentage of memory in the total VAS that is just 'sparse' (empty; on 64-bit systems it can be very high!) vs the actually used memory amount and percentage.

- Currently, at the end of the 'graph', the memory above the usermode addr space is shown as a 'sparse' region; in reality, on 32-bit systems, this is the kernel VAS! ... and on 64-bit systems, this _is_ sparse space (huge), followed by the kernel VAS. I shall work on updating this as such..

- As a bonus, the output is logged - appended - to the file log_vasu.txt. Look up this log when done.

[End doc]
