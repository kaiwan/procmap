#!/bin/bash
# do_vgraph.sh
#
# Quick Description:
# Support script for the procmap project. Handles the user VAS population
# into our array data structure.
# Don't invoke this directly, run the 'procmap' wrapper instead.
# "Draw" out, (somewhat) to scale, ranges of numbers in a vertically tiled 
# format. For eg.: the output of /proc/iomem, /proc/vmalloc, 
# /proc/<pid>/maps, etc etc
# 
# We EXPECT as input a file (the job of the mapsfile_prep.sh script is to
# generate this file); the file must be in CSV format with 3 columns;
# col 1 and col 2 are ASSuMEd to be in hexadecimal.
# (as of this very early ver at least). 
# FORMAT ::
#   [...]
# field1,field2,field3
# field1,field2,field3
#   [...]
#
# field1: integer value (often an address of some sort)
# field2: integer value (often an address of some sort)
# field3: string: descriptive
#
# Our mapsfile_prep.sh script is invoked via the procmap wrapper to do
# precisely this.
#
# Created      : 17Apr2020
# Author:
# Kaiwan N Billimoria
# kaiwan -at- kaiwantech -dot- com
# kaiwan -dot- billimoria -at- gmail -dot- com
# kaiwanTECH
# License: MIT.
PFX=$(dirname $(which $0 2>/dev/null))    # dir in which 'procmap' and tools reside
source ${PFX}/common.sh || {
 echo "${name}: fatal: could not source ${PFX}/common.sh , aborting..."
 exit 1
}
source ${PFX}/config || {
 echo "${name}: fatal: could not source ${PFX}/config , aborting..."
 exit 1
}
source ${PFX}/lib_procmap.sh || {
 echo "${name}: fatal: could not source ${PFX}/lib_procmap.sh , aborting..."
 exit 1
}
source ${PFX}/do_kernelseg.sh || {
 echo "${name}: fatal: could not source ${PFX}/do_kernelseg.sh , aborting..."
 exit 1
}
source ${ARCHFILE} || {
 echo "${name}: fatal: could not source ${ARCHFILE} , aborting..."
 exit 1
}

# Titles, etc...
NULLTRAP_STR="< NULL trap >"
SPARSE_ENTRY="<... Sparse Region ...>"

########### Functions follow #######################

#-------------------- p r e p _ f i l e -------------------------------
prep_file()
{
# Get rid of comment lines
sed --in-place '/^#/d' ${gINFILE}
} # end prep_file()

#------------------- g e t _ r a n g e _ i n f o ----------------------
get_range_info()
{
# Get the process user VAS (virtual addr space) range: start - end
#  -the first and last numbers!
local int_start=$(head -n1 ${gINFILE} |cut -d"${gDELIM}" -f1 |sed 's/ //') # also trim
local int_end=$(tail -n2 ${gINFILE} |head -n1 |cut -d"${gDELIM}" -f2 |sed 's/ //')
#decho "int_start = $int_start int_end $int_end"
#local int_end=$(tail -n1 ${gINFILE} |cut -d"${gDELIM}" -f2 |sed 's/ //')

# RELOOK : int value overflows here w/ large 64-bit # as input
# Fixed: use printf w/ %llu fmt
local start_dec=$(printf "%llu" 0x${int_start})   #$(echo $((16#${int_start})))
local end_dec=$(printf "%llu" 0x${int_end})
gTotalLen=$(printf "%llu" $((end_dec-start_dec)))
gFileLines=$(wc -l ${gINFILE} |awk '{print $1}')  # = # of VMAs
decho "range: [${start_dec} to ${end_dec}]: total size=${gTotalLen}"
} # end get_range_info()

#---
# Userspace array:
# We require a 6d array: each 'row' will hold these values:
#
#          col0     col1      col2       col3   col4    col5
# row'n' [segname],[size],[start_uva],[end_uva],[mode],[offset]
#
# HOWEVER, bash only actually supports 1d array; we thus treat a simple 1d
# array as an 'n'd (n=6) array! 
# So we just populate a 1d array like this:
#  [val1] [val2] [val3] [val4] [val5] [val6] [val7] [val8] [...]
# but INTERPRET it as 6d like so:
#  ([val1],[val2],[val3],[val4],[val5],[val6]),([val7],[val8],[val9],val[10],...) [...]
declare -a gArray
gRow=0
#---

# Kernel-space array: (see kseg file)
declare -a gkArray
gkRow=0

#-----------------------s h o w A r r a y -----------------------------
# Parameters:
#   $1 : debug print; if 1, it's just a debug print, if 0 we're writing it's
#        data to a file in order to proess further (sort/etc)
showArray()
{
local i k DIM=6

if [ $1 -eq 1 ] ; then
  echo
  decho "gRow = ${gRow}"
  # gArray ::  [segname],[size],[start_uva],[end_uva],[mode],[offset]
  echo "showArray():
[segname,size,start_uva,end_uva,mode,offset]"
fi

for ((i=0; i<${gRow}; i+=${DIM}))
do
    printf "%s," "${gArray[${i}]}"   # segname
	let k=i+1
    printf "%d," "${gArray[${k}]}"     # seg size
	let k=i+2
    #--- Nice bugfix here!
    # On the TI BBB 32-bit, i noticed that the 'heap' would appear at or near
    # the very top of the user VAS! that's just wrong... Investigating, i found
    # that its as the /tmp/procmap/pmu file records were'nt being correctly
    # sorted.. That was as running sort(1) on hex numbers does work *as long as
    # they're seen as numbers and not strings*. To do that, we have to ensure
    # that #s - like the start and end UVAs here - are left-padded with 0s!
    # Then sort works correctly and all's well!
    # (Interestingly, the %0zx printf format has it work portably for 32 and 64
    # bit - avoiding the need to explicitly do %08x / %016x for 32/64 bit!)
    printf "%0zx," "0x${gArray[${k}]}"   # start uva
	let k=i+3
    printf "%0zx," "0x${gArray[${k}]}"   # end uva
    #---
	let k=i+4
    printf "%s," "${gArray[${k}]}"     # mode+flag
	let k=i+5
    printf "%x\n" "0x${gArray[${k}]}" # file offset
done
} # end showArray()

gNumSparse=0
gTotalSparseSize=0
gTotalSegSize=0

setup_nulltrap_page()
{
  local pgsz_hex=$(printf "%x" ${PAGE_SIZE})
  append_userspace_mapping "${NULLTRAP_STR}" ${PAGE_SIZE} 0 \
     ${pgsz_hex} "----" 0

  # RELOOK? Treat the NULL trap page as a sparse region??
  inc_sparse ${PAGE_SIZE}
} # end setup_nulltrap_page()


#------------- i n t e r p r e t _ u s e r _ r e c ---------------------
# Interpret record (a CSV 'line' from the input stream) and populate the
# gArr[] n-dim array.
# Format:
#  start_uva,end_uva,mode/p|s,offset,image_file
#     ; uva = user virtual address
# eg.
#  7f1827411000,7f1827412000,rw-p,00028000,/lib/x86_64-linux-gnu/ld-2.27.so
# - 7f3390031000,7f3390053000,/lib/x86_64-linux-gnu/libc-2.28.so
# Parameters:
#  $1 : the above CSV format string of 5 fields {start_uva,end_uva,mode,off,segname}
#  $2 : loop index
# Populate the global 'n-dim' (n=6) array gArray.
# Arch-independent.
interpret_user_rec()
{
local gap=0
local start_uva=$(echo "${1}" |cut -d"${gDELIM}" -f1)
local end_uva=$(echo "${1}" |cut -d"${gDELIM}" -f2)

# Skip comment lines
echo "${start_uva}" | grep -q "^#" && return

local mode=$(echo "${1}" |cut -d"${gDELIM}" -f3)
local offset=$(echo "${1}" |cut -d"${gDELIM}" -f4)
local segment=$(echo "${1}" |cut -d"${gDELIM}" -f5)
[ -z "${segment}" ] && segment=" [-unnamed-] "

# Remove any leading zeroes from the offset
offset=$(echo ${offset}  |sed 's/^0*//')
[ -z "${offset}" ] && offset=0

# Convert hex to dec
local start_dec=$(printf "%llu" 0x${start_uva})
local end_dec=$(printf "%llu" 0x${end_uva})
local seg_sz=$(printf "%llu" $((end_dec-start_dec)))  # in bytes

local DetectedSparse=0

# The global 6d-array's format is:
#          col0     col1      col2       col3   col4    col5
# row'n' [segname],[size],[start_uva],[end_uva],[mode],[offset]

if [ "${offset}" = "00000000" ]; then
   offset="0"
fi

# NOTE-
# The '[vsyscall]' page is in kernel-space; hence, we only show it if
# our config requires us to...; default is No
if [ "${segment}" = "[vsyscall]" -a ${SHOW_VSYSCALL_PAGE} -eq 0 ]; then
   decho "skipping [vsyscall] page..."
   prevseg_start_uva=${start_dec}
   prevseg_name="[vsyscall]"
   return
fi

#------------ Sparse Detection
if [ ${SPARSE_SHOW} -eq 1 ]; then

 decho "
$2: seg=${segment} prevseg_name=${prevseg_name} ,  gRow=${gRow} "

 # Detect sparse region, and if present, insert into the gArr[].
 # Sparse region detected by condition:
 #  gap = this-segment-start - prev-segment-end > 1 page
 # Wait! With order by Descending va, we should take the prev segment's
 # start uva (not the end uva)!
 #  gap = prev_seg_start - this-segment-end > 1 page

 if [ "${segment}" != "[vsyscall]" ]; then
   #decho "end_dec=${end_dec} prevseg_start_uva=${prevseg_start_uva}"
   gap=$((${prevseg_start_uva}-${end_dec}))
   local gap_hex=$(printf "0x%llx" ${gap})
   decho "gap = ${gap}"
   [ ${gap} -gt ${PAGE_SIZE} ] && DetectedSparse=1
 fi

 if [ ${DetectedSparse} -eq 1 -a "${prevseg_name}" != "[vsyscall]" ]; then
   local prevseg_start_uva_hex=$(printf "%llx" ${prevseg_start_uva})
   local sparse_start_uva_dec=$((${prevseg_start_uva}-${gap}))
#   local sparse_start_uva=$((0x${prevseg_start_uva_hex}-${gap_hex}))
   local sparse_start_uva=$(printf "%llx" ${sparse_start_uva_dec})
   decho "prevseg_start_uva_hex=${prevseg_start_uva_hex}  gap = ${gap_hex} sparse_start_uva=${sparse_start_uva}"
   #prompt
 
   append_userspace_mapping "${SPARSE_ENTRY}" ${gap} ${sparse_start_uva} \
      ${prevseg_start_uva_hex} "----" 0

   inc_sparse ${gap}
 fi

 prevseg_start_uva=${start_dec}
fi
#--------------

#if [ ${DetectedSparse} -eq 0 ]; then
#--- Populate the global array
append_userspace_mapping "${segment}" ${seg_sz} ${start_uva} \
     ${end_uva} "${mode}" ${offset}

prevseg_name=${segment}
#decho "prevseg_name = ${prevseg_name}
#"
} # end interpret_user_rec()

# query_highest_valid_uva()
# Require the topmost valid userspace va, query it from the o/p of our
# prep_mapfile.sh script
# TODO : ARCH SPECIFIC !!
query_highest_valid_uva()
{
local TMPF=/tmp/${name}/qhva
awk -F"${gDELIM}" '{print $2}' ${gINFILE} > ${TMPF}
[ ! -s ${TMPF} ] && {
  warn "couldn't fetch highest valid uva, aborting..."
  return
}

#set -x
 local va
 for va in $(cat ${TMPF})
 do 
   decho "va: $va"
   local va_dec=$(printf "%llu" 0x${va})
   if (( $(echo "${va_dec} < ${END_UVA_DEC}" |bc -l) )); then
     HIGHEST_VALID_UVA=${va}
	 rm -f ${TMPF}
	 return
   fi
 done
 HIGHEST_VALID_UVA=0x0
#set +x
 rm -f ${TMPF}
} # end query_highest_valid_uva()

# Setup the userspace Sparse region at the very top (high) end of the VAS
# in the gArray[]
# TODO : ARCH SPECIFIC !!
setup_usparse_top()
{
 gRow=0
 query_highest_valid_uva
 local HIGHEST_VALID_UVA_DEC=$(printf "%llu" 0x${HIGHEST_VALID_UVA})

 decho "HIGHEST_VALID_UVA = ${HIGHEST_VALID_UVA}"

 [ ${HIGHEST_VALID_UVA_DEC} -eq 0 ] && {
  echo "Warning! couldn't fetch highest valid uva, aborting..."
  return
}

 local gap_dec=$(bc <<< "(${END_UVA_DEC}-${HIGHEST_VALID_UVA_DEC})")
 if [ ${gap_dec} -gt ${PAGE_SIZE} ]; then
  append_userspace_mapping "${SPARSE_ENTRY}" "${gap_dec}" ${HIGHEST_VALID_UVA} \
     "${END_UVA}" "----" 0

  inc_sparse ${gap_dec}
 fi
} # end setup_usparse_top()

disp_fmt()
{
 if [ ${VERBOSE} -eq 1 ] ; then
    tput bold ; fg_red #; bg_gray
    printf "VAS mappings:  name    [ size,perms,u:maptype,u:0xfile-offset]\n"
    color_reset
 fi
}

total_size_userspc()
{
local TMPF=/tmp/${name}/pmutmp
showArray 1 > ${TMPF}
# rm first header line and lines with 'Sparse' in them..
sed --in-place '1,3d' ${TMPF}
sed --in-place '/Sparse/d' ${TMPF}
# rm last line, it has the null trap page
sed --in-place '$d' ${TMPF}

# cumulatively total the 2nd field, the size
gTotalSegSize=$(awk -F, 'total+=$2 ; END {print total}' ${TMPF} |tail -n1)
#echo "gTotalSegSize = ${gTotalSegSize} bytes"
[ ${DEBUG} -eq 0 ] && rm -f ${TMPF}
}

# footer_stats_etc()
# Write a footer, addn details if in verbose mode, show the 'statistics' as
# required. Also, check for work like --export-map= ...
footer_stats_etc()
{
disp_fmt

 #--- Footer
 tput bold
 [[ ${ITS_A_THREAD} -eq 0 ]] && {
	printf "[=====---  End memory map for process %d:%s  ---=====]\n" ${PID} ${PRCS_NAME}
 } || {
	printf "[=====---  End memory map for thread %d:%s of process %d:%s  ---=====]\n" \
		${PID} ${THRD_NAME} ${PARENT_PROCESS} ${PRCS_NAME}
 }
 color_reset

 if [ ${VERBOSE} -eq 1 -a ${SHOW_USERSPACE} -eq 1 ]; then
    printf "[Pathname: %s ]\n" ${PRCS_PATHNAME}
    printf "\n[v] "
    runcmd sudo ls -l ${PRCS_PATHNAME}
    printf "\n[v] "
    runcmd sudo file ${PRCS_PATHNAME}

    which ldd >/dev/null 2>&1 && {
	  # arch-specific?
      printf "\n[v] "
      runcmd sudo ldd ${PRCS_PATHNAME}
      #printf "\n"
    }
 fi

 stats ${PID} ${PRCS_NAME}

 if [ ! -z "${XMAP_FILE}" ]; then
    touch /tmp/${name}/.kusep
    if [ -s /tmp/${name}/pmkfinal -a -s /tmp/${name}/pmufinal ] ; then
       cat > /tmp/${name}/.kusep << @EOF@
+++-------------- Kernel-User boundary --------------+++
@EOF@
    fi
	cat /tmp/${name}/pmkfinal /tmp/${name}/.kusep /tmp/${name}/pmufinal > ${XMAP_FILE} #2>/dev/null
    if [ -s /tmp/${name}/pmkfinal -o -s /tmp/${name}/pmufinal ] ; then
      # Perform multiple ops w/ sed on the file; 1i inserts a line at the top
      sed --in-place -e "1i# Generated by procmap   (c) kaiwanTECH\n\
# ${PRJ_URL}\n\
# Via the --export-maps=<fname> option\n\
# CSV format:\n# name,size,start_va,end_va,perms[u:maptype],[u:0xfile-offset]\n" ${XMAP_FILE}
      echo "[i] Maps info written to file ${XMAP_FILE} (as CSV)."
	fi
 fi
} # end footer_stats_etc()

#--------------------------- m a i n _ w r a p p e r -------------------
# Parameters:
#  $1 : PID of process
main_wrapper()
{
 local PID=$1
 local szKB szMB szGB

 prep_file
 get_range_info
 export IFS=$'\n'

 #--- Header
 tput bold
 printf "\n[==================---     P R O C M A P     ---==================]\n"
 color_reset
 printf "Process Virtual Address Space (VAS) Visualization utility\n"
 printf "https://github.com/kaiwan/procmap\n\n"
 date

 PRCS_PATHNAME=$(realpath /proc/${PID}/exe 2>/dev/null) || true
 [[ -z "${PRCS_PATHNAME}" ]] && PRCS_PATHNAME=$(sudo realpath /proc/${PID}/exe 2>/dev/null) || true
 PRCS_NAME=$(sudo cat /proc/${PARENT_PROCESS}/comm)
 THRD_NAME=$(sudo cat /proc/${PID}/comm)

 tput bold
 [[ ${ITS_A_THREAD} -eq 0 ]] && {
	printf "[=====---  Start memory map for process %d:%s  ---=====]\n" ${PID} ${PRCS_NAME}
 } || {
	printf "[=====---  Start memory map for thread %d:%s of process %d:%s  ---=====]\n" \
		${PID} ${THRD_NAME} ${PARENT_PROCESS} ${PRCS_NAME}
 }
 printf "[Pathname: %s ]\n" ${PRCS_PATHNAME} #$(sudo realpath /proc/${PID}/exe)
 color_reset
 disp_fmt

 LOC_LEN=0
 #decho "LOCATE_SPEC = ${LOCATE_SPEC}"
 # Any specific region to locate in the memory map?
 if [ ! -z "${LOCATE_SPEC}" ]; then
   LOC_STARTADDR=$(echo "${LOCATE_SPEC}" |cut -d, -f1)
   LOC_STARTADDR_DEC=$(printf "%llu" ${LOC_STARTADDR})
   LOC_LEN=$(echo "${LOCATE_SPEC}" |cut -d, -f2)
 fi

 #----------- KERNEL-SPACE VAS calculation and drawing
 # Show kernelspace? Yes by default!
 if [ ${SHOW_KERNELSEG} -eq 1 ] ; then
    populate_kernel_segment_mappings
    graphit -k
 else
   decho "Skipping kernel segment display..."
 fi

 # Show userspace? Yes by default!
 [ ${SHOW_USERSPACE} -eq 0 ] && {
   decho "Skipping userspace display..."
   footer_stats_etc
   return
 }

 #----------- USERSPACE VAS calculation and drawing

 # Redirect to stderr what we don't want in the log
 #printf "\n%s: Processing, pl wait ...\n" "${name}" 1>&2

 color_reset
 setup_usparse_top

 # Loop over the 'infile', populating the global 'n-d' array gArray
 local i=0 REC
 for REC in $(cat ${gINFILE})
 do 
   decho "REC: $REC"
   interpret_user_rec ${REC} ${i}
   printf "=== %06d / %06d\r" ${i} $((${gFileLines}-1))
   let i=i+1
 done 1>&2

# By now, we've populated the gArr[] ;
# Order is by descending va's, so check for and insert the last two entries:
#  a conditional/possible sparse region and the NULL trap page

# Setup the Sparse region just before the NULL trap page:
#decho "prevseg_start_uva = ${prevseg_start_uva}"
local gap_dec=$((prevseg_start_uva-PAGE_SIZE))
local gap=$(printf "0x%llx" ${gap_dec})
local prevseg_start_uva_hex=$(printf "%llx" ${prevseg_start_uva})

if [ ${gap_dec} -gt ${PAGE_SIZE} ]; then
  append_userspace_mapping "${SPARSE_ENTRY}" ${gap_dec} ${PAGE_SIZE} \
     ${prevseg_start_uva_hex} "----" 0
  inc_sparse ${gap}
fi

# Setup the NULL trap page: the very last entry
setup_nulltrap_page

[ ${DEBUG} -eq 1 ] && showArray 1
total_size_userspc

##################
# Get all the user mapping data into a file:
# Reverse sort by 4th field, the hexadecimal end va; simple ASCII sort works
# because numbers 0-9a-f are anyway in alphabetical order
showArray 0 > /tmp/${name}/pmu
sort -f -t"," -k4 -r /tmp/${name}/pmu > /tmp/${name}/pmufinal
##################

# draw it!
[ ${SHOW_USERSPACE} -eq 1 ] && graphit -u

footer_stats_etc
} # end main_wrapper()

# stats()
stats()
{
if [ ${SHOW_STATS} -eq 0 ]; then
   echo "[!] stats display being skipped (see the config file)"
   return
fi

   printf "\n=== Statistics ===\n"
   printf "\nTotal Kernel VAS (Virtual Address Space):\n"
   # Here the KERNEL_VAS_SIZE is, f.e., the number 549755813888.0000
   # Need to convert it to an integer first (else a runtime err occurs)
   local kvsize=$(printf "%d\n" ${KERNEL_VAS_SIZE} 2>/dev/null)
   largenum_display ${kvsize}
   local uvsize=$(printf "%d\n" ${USER_VAS_SIZE} 2>/dev/null)
   printf "\nTotal User VAS (Virtual Address Space):\n"
   largenum_display ${uvsize}

   local PID=$1
   local name="$2"
   local numvmas=$(sudo wc -l /proc/${PID}/maps |awk '{print $1}')
   #[ ${gFileLines} -ne ${numvmas} ] && printf " [!] Warning! # VMAs does not match /proc/${PID}/maps\n"
   # The [vsyscall] VMA shows up but the NULL trap doesn't
   [ ${SHOW_VSYSCALL_PAGE} -eq 1 ] && let numvmas=numvmas+1  # for the NULL trap page

   #--- Total reported memory (RAM) on the system
   local totalram_kb=$(grep "^MemTotal" /proc/meminfo |cut -d: -f2|awk '{print $1}')
   local totalram=$(bc <<< "${totalram_kb}*1024")
   printf "\nTotal reported memory (RAM) on this system:\n"
   largenum_display ${totalram}

 if [ ${SHOW_USERSPACE} -eq 1 ] ; then
   printf "\n\n=== Statistics for Userspace: ===\n"
   printf "For PID %d:%s\n" ${PID} ${name}
   printf " %d VMAs (segments or mappings)" ${numvmas}

   [ ${SPARSE_SHOW} -eq 1 ] && {
     printf ", %d sparse regions (includes NULL trap page)\n" ${gNumSparse}
     printf "Total User VAS that is Sparse memory:\n"
     largenum_display ${gTotalSparseSize} ${USER_VAS_SIZE}
   }

   # Valid regions (segments) total size
   printf "\nTotal User VAS that's valid (mapped) memory:\n"
   largenum_display ${gTotalSegSize} ${USER_VAS_SIZE}
   printf "\n===\n"

   # Show ps and smem stats only if it's a process and not a worker/child thread of some process
   [[ ${ITS_A_THREAD} -eq 1 ]] && {
	echo ; return
   }

   printf "\n\nMemory Usage stats for process PID %d:%s\n" ${PID} ${name}
   printf "Via ps(1):\n"
# ps aux|head -n1
# USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
   sudo ps aux |awk -v pid=${PID} '$2==pid {printf(" %%MEM=%u   VSZ=%lu KB   \
RSS=%lu KB\n", $4,$5,$6)}'

  which smem >/dev/null 2>&1 && {
   printf "Via smem(8) [might take a while, pl wait ...] :\n"
# smem|head -n1
# PID User     Command                         Swap      USS      PSS      RSS 
   sudo smem |awk -v pid=${PID} '$1==pid {printf(" swap=%u   USS=%lu KB   \
PSS=%lu KB   RSS=%lu KB\n", $4,$5,$6,$7)}'
  } || {
    vecho "smem(8) not installed? skipping..."
  }
 else
  echo
 fi       # if ${SHOW_USERSPACE} -eq 1
} # end stats()

usage()
{
  echo "Usage: ${name} -u -k [-d] -p PID-of-process -f input-CSV-filename(5 column format)
  -f : input CSV file
  -k : show only kernel-space
  -u : show only userspace
   [default: show BOTH]
  -d : run in debug mode
  -v : run in verbose mode"
}


##### 'main' : execution starts here #####

#echo "test_256"
#test_256
#exit 0

which bc >/dev/null 2>&1 || {
  echo "${name}: bc(1) package missing, pl install. Aborting..."
  exit 1
}

[ $# -lt 4 ] && {
  usage
  exit 1
}

SHOW_KERNELSEG=0
SHOW_USERSPACE=0

while getopts "p:f:l:h?kudv" opt; do
    case "${opt}" in
        h|\?) usage ; exit 0
                ;;
        p)
            PID=${OPTARG}
            ;;
        f)
            gINFILE=${OPTARG}
            ;;
        l)
            LOCATE_SPEC=${OPTARG}
            #echo "LOCATE_SPEC=${LOCATE_SPEC}"
            ;;
        k)
            SHOW_KERNELSEG=1
            ;;
        u)
            SHOW_USERSPACE=1
            ;;
        d)
            DEBUG=1
            ;;
        v)
            VERBOSE=1
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))
decho "gINFILE=${gINFILE}"
main_wrapper ${PID}
exit 0
