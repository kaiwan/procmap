#!/bin/bash
# do_vgraph.sh
# https://github.com/kaiwan/vasu_grapher.git
#
# Quick Description:
# Don't invoke this directly, run the 'vasu_grapher' wrapper instead.
# do_vgraph.sh: Support script for the vasu_grapher project; really, it's
# where the stuff actually happens :)
# "Draw" out, (somewhat) to scale, ranges of numbers in a vertically tiled 
# format. For eg.: the output of /proc/iomem, /proc/vmalloc, 
# /proc/<pid>/maps, etc etc
# 
# We EXPECT as input a file (the job of the prep_mapsfile.sh script is to
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
# Our prep_mapsfile.sh script is invoked via the vasu_grapher wrapper to do
# precisely this.
#
# TODO
# [+] show Null trap vpage 0
# [+] show sparse regions of the VAS
# [+] separate config file
#     - move config vars to a config file for user convenience
# [ ] Validation: check input file for correct format
# [.] Statistics
#     [+] # VMAs, # sparse regions
#     [+] space taken by valid regions & by sparse (%age as well of total)
#     [ ] space taken by text, data, libs, stacks, ... regions (with %age)
# [.] Segment Attributes
#     [.] seg size
#         [ ] RSS   [ ] PSS  [ ] Swap  [ ] Locked (?)    [use smaps!]
#     [+] seg permissions
# [ ] Kernel Segment details !   (requires root)
# [ ] Reverse order: high-to-low address
#
# [ ] -h: horzontal render of process VAS
#     [ ] horizontal scrolling w/ less(1)?
# [ ] Graphical stuff-
#  convert to reqd format
#     [ ] write to SVG !
#     [ ] interactive GUI
#
# Last Updated : 20Apr2020
# Created      : 17Apr2020
# 
# Author:
# Kaiwan N Billimoria
# kaiwan -at- kaiwantech -dot- com
# kaiwan -dot- billimoria -at- gmail -dot- com
# kaiwanTECH
# License: MIT.
name=$(basename $0)
PFX=$(dirname $(which $0))    # dir in which 'vasu_grapher' and tools reside
source ${PFX}/common.sh || {
 echo "${name}: fatal: could not source ${PFX}/common.sh , aborting..."
 exit 1
}
source ${PFX}/config || {
 echo "${name}: fatal: could not source ${PFX}/config , aborting..."
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

# 32 or 64 bit OS?
IS_64_BIT=1
which getconf >/dev/null || {
  echo "${name}: WARNING! getconf(1) missing, assuming 64-bit OS!"
} && {
  local bitw=$(getconf -a|grep -w LONG_BIT|awk '{print $2}')
  [ ${bitw} -eq 32 ] && IS_64_BIT=0  # implies 32-bit
}
decho "64-bit OS? ${IS_64_BIT}"
} # end get_range_info()

#---
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

#-----------------------s h o w A r r a y -----------------------------
showArray()
{
local i k DIM=6
echo
decho "gRow = ${gRow}"
# gArray ::  [segname],[size],[start_uva],[end_uva],[mode],[offset]
echo "showArray():
[segname,size,start_uva,end_uva,mode,offset]"
for ((i=0; i<${gRow}; i+=${DIM}))
do
    printf "[%s," "${gArray[${i}]}"   # segname
	let k=i+1
    printf "%d," "${gArray[${k}]}"     # seg size
	let k=i+2
    printf "%x," "0x${gArray[${k}]}"   # start uva
	let k=i+3
    printf "%x," "0x${gArray[${k}]}"   # end uva
	let k=i+4
    printf "%s," "${gArray[${k}]}"     # mode+flag
	let k=i+5
    printf "%x]\n" "0x${gArray[${k}]}" # file offset
done
} # end showArray()

LIMIT_SCALE_SZ=10

#---------------------- g r a p h i t ---------------------------------
# Iterates over the global '6d' array gArr[] 'drawing' the vgraph.
# Data driven tech!
graphit()
{
local i k
local segname seg_sz start_uva end_uva mode offset
local szKB=0 szMB=0 szGB=0 szTB=0

local         LIN="+----------------------------------------------------------------------+"
local ELLIPSE_LIN="~ .       .       .       .       .       .        .       .        .  ~"
local BOX_RT_SIDE="|                                                                      |"
local linelen=$((${#LIN}-2))
local oversized=0

color_reset
local DIM=6
for ((i=0; i<${gRow}; i+=${DIM}))
do
	local tlen=0 len_perms len_maptype len_offset
	local tmp1="" tmp2="" tmp3="" tmp4="" tmp5=""
	local tmp5a="" tmp5b="" tmp5c="" tmp6=""
	local segname_nocolor tmp1_nocolor tmp2_nocolor tmp3_nocolor
	local tmp4_nocolor tmp5a_nocolor tmp5b_nocolor tmp5c_nocolor
	local tmp5 tmp5_nocolor

    #--- Retrieve values from the array
    segname=${gArray[${i}]}    # col 1 [str: the label/segment name]
	let k=i+1
    seg_sz=${gArray[${k}]}     # col 2 [int: the segment size]
	let k=i+2
    start_uva=${gArray[${k}]}  # col 3 [int: the first number, start_uva]
	let k=i+3
    end_uva=${gArray[${k}]}    # col 4 [int: the second number, end_uva]
	let k=i+4
    mode=${gArray[${k}]}       # col 5 [str: the mode+flag]
	let k=i+5
    offset=${gArray[${k}]}     # col 6 [int: the file offset]

	# Calculate segment size in diff units as required
    szKB=$((${seg_sz}/1024))
    [ ${szKB} -ge 1024 ] && szMB=$(bc <<< "scale=2; ${szKB}/1024.0") || szMB=0
    # !EMB: if we try and use simple bash arithmetic comparison, we get a 
    # "integer expression expected" err; hence, use bc(1):
    szGB=0
    if (( $(echo "${szMB} > 1024" |bc -l) )); then
      szGB=$(bc <<< "scale=2; ${szMB}/1024.0")
    fi
    szTB=0
    if (( $(echo "${szGB} > 1024" |bc -l) )); then
      szTB=$(bc <<< "scale=2; ${szGB}/1024.0")
    fi

    #--- Drawing :-p  !
	# the horizontal line with the end uva at the end of it
	## the horizontal line with the start uva at the end of it
	# the first actual print emitted!
	# Eg.
	# +----------------------------------------------------------------------+ 000055681263b000
	# Changed to end_uva first we now always print in descending order
    if [ ${IS_64_BIT} -eq 1 ] ; then
      printf "%s %016lx\n" "${LIN}" "0x${end_uva}"
    else
      printf "%s %08x\n" "${LIN}" "0x${end_uva}"
    fi

	#--- Collate and print the details of the current mapping (segment)
	# Eg.
	# |<... Sparse Region ...> [ 14.73 MB] [----,0x0]                        |

	# Print segment name
	tmp1=$(printf "%s|%20s " $(fg_orange) ${segname})
	local segname_nocolor=$(printf "|%20s " ${segname})

	# Print segment size according to scale; in KB or MB or GB or TB
	tlen=0
    if (( $(echo "${szKB} < 1024" |bc -l) )); then
		# print KB only
		tmp2=$(printf "%s [%4d KB" $(fg_green) ${szKB})
		tmp2_nocolor=$(printf " [%4d KB" ${szKB})
		tlen=${#tmp2_nocolor}
    elif (( $(echo "${szKB} > 1024" |bc -l) )); then
      if (( $(echo "${szMB} < 1024" |bc -l) )); then
		# print MB only
		tmp3=$(printf "%s[%6.2f MB" $(fg_yellow) ${szMB})
		tmp3_nocolor=$(printf "[%6.2f MB" ${szMB})
		tlen=${#tmp3_nocolor}
    elif (( $(echo "${szKB} > 1024" |bc -l) )); then
      if (( $(echo "${szGB} < 1024" |bc -l) )); then
		# print GB only
		tmp4=$(printf "%s[%6.2f GB" $(fg_yellow) ${szGB})
		tmp4_nocolor=$(printf "[%6.2f GB" ${szGB})
		tlen=${#tmp4_nocolor}
	else
		# print TB only
		tmp5=$(printf "%s[%9.2f TB" $(fg_red) ${szTB})
		tmp5_nocolor=$(printf "[%9.2f TB" ${szTB})
		tlen=${#tmp5_nocolor}
      fi
	 fi
	fi

	# 'mode' xxxy has two pieces of info:
	#  - xxx is the mode (octal permissions / rwx style)
	#  - y is either p or s, private or shared mapping
	# seperate them out in order to print them in diff colors, etc
	# (substr op: ${string:position:length} ; position starts @ 0)
	local perms=$(echo ${mode:0:3})
	local maptype=$(echo ${mode:3:1})

	# mode + mapping type
	#  print in bold red fg if:
	#    mode == ---
	#    mode violates the W^X principle, i.e., w and x set
	local flag_null_perms=0 flag_wx_perms=0
	if [ "${perms}" = "---" ]; then
	   flag_null_perms=1
	fi
	echo "${perms}" | grep -q ".wx" && flag_wx_perms=1

	if [ ${flag_null_perms} -eq 1 -o ${flag_wx_perms} -eq 1 ] ; then
		tmp5a=$(printf "%s%s,%s%s," $(tput bold) $(fg_red) "${perms}" $(color_reset))
	else
		tmp5a=$(printf "%s,%s," $(fg_black) "${perms}")
	fi
	tmp5a_nocolor=$(printf ",%s," "${perms}")
	len_perms=${#tmp5a_nocolor}

	# mapping type
	tmp5b=$(printf "%s%s%s," $(fg_blue) "${maptype}" $(fg_black))
	tmp5b_nocolor=$(printf "%s," "${maptype}")
	len_maptype=${#tmp5b_nocolor}

	# file offset
	tmp5c=$(printf "%s0x%s" $(fg_black) "${offset}")
	tmp5c_nocolor=$(printf "0x%s" "${offset}")
	len_offset=${#tmp5c_nocolor}

    # Calculate the strlen of the printed string, and thus calculate and print
    # the appropriate number of spaces after until the "|" close-box symbol.
	# Final strlen value:
	local segnmlen=${#segname_nocolor}
	if [ ${segnmlen} -lt 20 ]; then
		segnmlen=20  # as we do printf "|%20s"...
	fi
	let tlen=${segnmlen}+${tlen}+${len_perms}+${len_maptype}+${len_offset}

    if [ ${tlen} -lt ${#LIN} ] ; then
       local spc_reqd=$((${linelen}-${tlen}))
       tmp6=$(printf "]%${spc_reqd}s|\n" " ") 
	       # print the required # of spaces and then the '|'
    else
		tmp6=$(printf "]")
	fi
    #decho "tlen=${tlen} spc_reqd=${spc_reqd}"

	# the second actual print emitted!
	echo "${tmp1}${tmp2}${tmp3}${tmp4}${tmp5}${tmp5a}${tmp5b}${tmp5c}${tmp6}"

    #--- NEW CALC for SCALING
    # Simplify: We base the 'height' of each segment on the number of digits
    # in the segment size (in bytes)!
    segscale=${#seg_sz}    # strlen(seg_sz)
    [ ${segscale} -lt 4 ] && {   # min seg size is 4096 bytes
        echo "${name}: fatal error, segscale (# digits) <= 3! Aborting..."
	    echo "Kindly report this as a bug, thanks!"
	    exit 1
    }
    #decho "seg_sz = ${seg_sz} segscale=${segscale}"

    local box_height=0
    # for segscale range [1-4]
    # i.e. from 1-4 digits, i.e., 0 to 9999 bytes (ie. ~ 0 to 9.8 KB, single line
    if [ ${segscale} -ge 1 -a ${segscale} -le 4 ]; then
		box_height=0
		# for segscale range [5-7]
		# i.e. for 5 digits, i.e., ~  10 KB to  99 KB, 1 line box
		# i.e. for 6 digits, i.e., ~ 100 KB to 999 KB ~= 1 MB, 2 line box
		# i.e. for 7 digits, i.e., ~ 1 MB to 9.9 MB, 3 line box
    elif [ ${segscale} -ge 5 -a ${segscale} -le 7 ]; then
		let box_height=segscale-4
    else
		# for segscale >= 8 digits
		# i.e. for 8 digits, i.e., from ~ 10 MB onwards, show an oversized ellipse box
		box_height=10
    fi
    #---

    # draw the sides of the 'box'
    [ ${box_height} -ge ${LIMIT_SCALE_SZ} ] && {
   	  box_height=${LIMIT_SCALE_SZ}
   	  oversized=1
    }

    #decho "box_height = ${box_height} oversized=${oversized}"
    for ((x=1; x<${box_height}; x++))
    do
   	  printf "%s\n" "${BOX_RT_SIDE}"
   	  if [ ${oversized} -eq 1 ] ; then
   		[ ${x} -eq $(((LIMIT_SCALE_SZ-1)/2)) ] && printf "%s\n" "${ELLIPSE_LIN}"
   	  fi
    done
    oversized=0
done

# last line, the zero-th virt address; always:
#+----------------------------------------------------------------------+ 0000000000000000
if [ ${IS_64_BIT} -eq 1 ] ; then
 printf "%s %016lx\n" "${LIN}" "0x${start_uva}"
else
 printf "%s %08x\n" "${LIN}" "0x${start_uva}"
fi
} # end graphit()

gNumSparse=0
gTotalSparseSize=0
gTotalSegSize=0

setup_nulltrap_page()
{
  gArray[${gRow}]="${NULLTRAP_STR}"
  let gRow=gRow+1
  gArray[${gRow}]=${PAGE_SIZE}
  let gRow=gRow+1
  gArray[${gRow}]=0
  let gRow=gRow+1
  gArray[${gRow}]=$(printf "%x" ${PAGE_SIZE})
  let gRow=gRow+1
  gArray[${gRow}]="----"
  let gRow=gRow+1
  gArray[${gRow}]=0
  let gRow=gRow+1
} # end setup_nulltrap_page()


#------------------ i n t e r p r e t _ r e c -------------------------
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
interpret_rec()
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

# Convert hex to dec
local start_dec=$(printf "%llu" 0x${start_uva})
local end_dec=$(printf "%llu" 0x${end_uva})
local seg_sz=$(printf "%llu" $((end_dec-start_dec)))  # in bytes

# The global 6d-array's format is:
#          col0     col1      col2       col3   col4    col5
# row'n' [segname],[size],[start_uva],[end_uva],[mode],[offset]


# NOTE-
# The '[vsyscall]' page is in kernel-space; hence, we only show it if
# our config requires us to...; default is No
if [ "${segment}" = "[vsyscall]" -a ${SHOW_VSYSCALL_PAGE} -eq 0 ]; then
   decho "skipping [vsyscall] page..."
   prevseg_start_uva=${start_dec}
   prevseg_name="[vsyscall]"
   return
fi

# Show null trap, vpage 0
local n=$((gFileLines-1))
if [ ${NULL_TRAP_SHOW} -eq 1 -a ${ORDER_BY_DESC_VA} -eq 0 -a $2 -eq 0 ]; then
  # very first entry
  setup_nulltrap_page
fi

#------------ Sparse Detection
if [ ${SPARSE_SHOW} -eq 1 ]; then

DetectedSparse=0

decho "$2: seg=${segment} prevseg_name=${prevseg_name} ,  gRow=${gRow} "

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
  [ ${gap} -gt ${PAGE_SIZE} ] && {
    DetectedSparse=1
  }
fi

if [ ${DetectedSparse} -eq 1 -a "${prevseg_name}" != "[vsyscall]" ]; then
    # name / label
	# The global 6d-array's format is:
	#          col0     col1      col2       col3   col4    col5
	# row'n' [segname],[size],[start_uva],[end_uva],[mode],[offset]

    gArray[${gRow}]="${SPARSE_ENTRY}"
    let gRow=gRow+1

    # segment size (bytes in decimal)
    [ ${NULL_TRAP_SHOW} -eq 0 ] && {
      gArray[${gRow}]=${gap}
    } || {
      let gap=$gap-$PAGE_SIZE
      gArray[${gRow}]=${gap}
    }
    let gRow=gRow+1

    # start uva (hex)
    local prevseg_start_uva_hex=$(printf "%x" ${prevseg_start_uva})
	#decho "prevseg_start_uva_hex=${prevseg_start_uva_hex}  gap = ${gap_hex}"
    gArray[${gRow}]=$((0x${prevseg_start_uva_hex}-${gap_hex}))
    let gRow=gRow+1

    # end uva (hex)
    gArray[${gRow}]=${prevseg_start_uva_hex}
    let gRow=gRow+1

    # mode+flag
    gArray[${gRow}]="----"
    let gRow=gRow+1

    # file off
    gArray[${gRow}]=0
    let gRow=gRow+1

    # Stats
    [ ${STATS_SHOW} -eq 1 ] && {
      let gNumSparse=gNumSparse+1
      let gTotalSparseSize=gTotalSparseSize+gap
    }
fi

prevseg_start_uva=${start_dec}
fi
#--------------

#--- Populate the global array
gArray[${gRow}]=${segment}
let gRow=gRow+1
gArray[${gRow}]=${seg_sz}
let gRow=gRow+1
gArray[${gRow}]=${start_uva}
let gRow=gRow+1
gArray[${gRow}]=${end_uva}
let gRow=gRow+1
gArray[${gRow}]=${mode}
let gRow=gRow+1
gArray[${gRow}]=${offset}
let gRow=gRow+1

[ ${STATS_SHOW} -eq 1 ] && {
  let gTotalSegSize=${gTotalSegSize}+${seg_sz}
  # does NOT include the null trap; that's correct
}

prevseg_name=${segment}
decho "prevseg_name = ${prevseg_name}
"
} # end interpret_rec()

# Display the number passed in a human-readable fashion
# As appropriate, also in KB, MB, GB, TB.
# $1 : the (large) number to display
# $2 : the total space size 'out of' (for percentage calculation)
#    percent = ($1/$2)*100
# $3 : the message string
largenum_display()
{
	local szKB=0 szMB=0 szGB=0 szTB=0

     # !EMB: if we try and use simple bash arithmetic comparison, we get a 
     # "integer expression expected" err; hence, use bc(1):
     [ ${1} -ge 1024 ] && szKB=$(bc <<< "scale=6; ${1}/1024.0") || szKB=0
     #[ ${szKB} -ge 1024 ] && szMB=$(bc <<< "scale=6; ${szKB}/1024.0") || szMB=0
     if (( $(echo "${szKB} > 1024" |bc -l) )); then
       szMB=$(bc <<< "scale=6; ${szKB}/1024.0")
     fi
     if (( $(echo "${szMB} > 1024" |bc -l) )); then
       szGB=$(bc <<< "scale=6; ${szMB}/1024.0")
     fi
     if (( $(echo "${szGB} > 1024" |bc -l) )); then
       szTB=$(bc <<< "scale=6; ${szGB}/1024.0")
     fi

     printf " $3 %llu bytes = %9.6f KB" ${1} ${szKB}
     if (( $(echo "${szKB} > 1024" |bc -l) )); then
       printf " = %9.6f MB" ${szMB}
       if (( $(echo "${szMB} > 1024" |bc -l) )); then
         printf " =  %9.6f GB" ${szGB}
       fi
       if (( $(echo "${szGB} > 1024" |bc -l) )); then
         printf " =  %9.6f TB" ${szTB}
       fi
     fi

     local pcntg=$(bc <<< "scale=12; (${1}/${2})*100.0")
     printf "\n  i.e. %2.6f%%" ${pcntg}
}

disp_fmt()
{
 tput bold ; fg_red; bg_gray
 printf "Userspace VAS segments:  name   [   size,mode,map-type,file-offset] \n"
 #color_reset
}

vecho()
{
[ ${VERBOSE} -eq 0 ] && return
echo "$@"
}

get_kernel_segment_details()
{
 echo "[+] Kernel Segment details"
 if [ ! -d ${DBGFS_LOC} ] ; then
	echo "${name}: kernel debugfs not present? aborting..."
	return
 else
    vecho " debugfs location verfied"
 fi

 (   # within a subshell
  cd ${KERNELDIR} || return
  #pwd
  if [ ! -s ${KMOD}.ko ] ; then
     make >/dev/null 2>&1 || {
	    echo "${name}: kernel module \"${KMOD}\" build failed, aborting..."
		return
	 }
     if [ ! -s ${KMOD}.ko ] ; then
	    echo "${name}: kernel module \"${KMOD}\" not generated? aborting..."
		return
	 fi
	 vecho " kseg: LKM built"
  fi

  # Ok, the kernel module is there, lets insert it!
  #ls -l ${KMOD}.ko
  sudo rmmod ${KMOD} 2>/dev/null   # rm any stale instance
  sudo insmod ./${KMOD}.ko || {
	    echo "${name}: insmod(8) on kernel module \"${KMOD}\" failed, aborting..."
		return
  }
  lsmod |grep -q ${KMOD} || {
	    echo "${name}: insmod(8) on kernel module \"${KMOD}\" failed? aborting..."
		return
  }
  vecho " kseg: LKM inserted into kernel"
  sudo ls ${DBGFS_LOC}/${KMOD}/${DBGFS_FILENAME} >/dev/null 2>&1 || {
     echo "${name}: required debugfs file not present? aborting..."
	 sudo rmmod ${KMOD}
	 return
  }
  vecho " kseg: debugfs file is there"

  # Finally! generate the kernel seg details
  local KTMP=/tmp/ktmp.$$
  sudo cat ${DBGFS_LOC}/${KMOD}/${DBGFS_FILENAME} > ${KTMP}

  vecho "kseg dtl:
$(cat ${KTMP})"

 # Loop over the kernel segment data records
 export IFS=$'\n'
 local REC
 for REC in $(cat ${KTMP})
 do 
   decho "REC: $REC"
   #interpret_rec ${REC} ${i}
   #printf "=== %06d / %06d\r" ${i} ${gFileLines}
   let i=i+1
 done #1>&2

 [ ${DEBUG} -eq 0 ] && rm -f ${KTMP}
 #sudo rmmod ${KMOD}
 )
} # end get_kernel_segment_details


#--------------------------- m a i n _ w r a p p e r -------------------
# Parameters:
#  $1 : PID of process
main_wrapper()
{
 local szKB szMB szGB

 prep_file
 get_range_info
 export IFS=$'\n'
 local i=0

 #--- Header
 tput bold
 printf "\n[==================---     P R O C M A P     ---==================]\n"
 color_reset
 printf "Process Virtual Address Space (VAS) Visualization project\n"
 printf " https://github.com/kaiwan/procmap\n\n"
 date

 #local nm=$(trim_string_middle $(realpath /proc/$1/exe) 50)
 local nm=$(basename $(realpath /proc/$1/exe))

 tput bold
 printf "[=====--- Start memory map for %d:%s ---=====]\n" $1 ${nm}
 printf "[Full pathname: %s]\n" $(realpath /proc/$1/exe)
 color_reset

 [ ${SHOW_KERNELSEG} -eq 1 ] && {
    get_kernel_segment_details
	exit 0
 }

 # Redirect to stderr what we don't want in the log
 printf "\n%s: Processing, pl wait ...\n" "${name}" 1>&2

 disp_fmt

 # Loop over the 'infile', populating the global 'n-d' array gArray
 local REC
 for REC in $(cat ${gINFILE})
 do 
   decho "REC: $REC"
   interpret_rec ${REC} ${i}
   printf "=== %06d / %06d\r" ${i} ${gFileLines}
   let i=i+1
 done 1>&2

# By now, we've populated the gArr[] ;
# If order is by descending va's (the default), then check for and insert
# the last two entries: a conditional/possible sparse region and the NULL
# trap page

# Setup the Sparse region just before the NULL trap page:
#decho "prevseg_start_uva = ${prevseg_start_uva}"
local gap_dec=$((prevseg_start_uva-PAGE_SIZE))
local gap=$(printf "0x%llx" ${gap_dec})
local prevseg_start_uva_hex=$(printf "%llx" ${prevseg_start_uva})

if [ ${gap_dec} -gt ${PAGE_SIZE} ]; then
  # row'n' [segname],[size],[start_uva],[end_uva],[mode],[offset]
  gArray[${gRow}]="${SPARSE_ENTRY}"
  let gRow=gRow+1
  gArray[${gRow}]="${gap_dec}"
  let gRow=gRow+1
  gArray[${gRow}]=${PAGE_SIZE} # start va
  let gRow=gRow+1
  gArray[${gRow}]="${prevseg_start_uva_hex}"  # end (higher) va
  let gRow=gRow+1
  gArray[${gRow}]="----"
  let gRow=gRow+1
  gArray[${gRow}]="0"
  let gRow=gRow+1
  let gNumSparse=gNumSparse+1
fi

# Setup the NULL trap page:
if [ ${NULL_TRAP_SHOW} -eq 1 -a ${ORDER_BY_DESC_VA} -eq 1 ]; then
  # very last entry
  setup_nulltrap_page
fi

[ ${DEBUG} -eq 1 ] && showArray
#exit 0

graphit
disp_fmt

GB_2=$(bc <<< "scale=6; 2.0*1024.0*1024.0*1024.0")
GB_3=$(bc <<< "scale=6; 3.0*1024.0*1024.0*1024.0")
GB_4=$(bc <<< "scale=6; 4.0*1024.0*1024.0*1024.0")
TB_128=$(bc <<< "scale=6; 128.0*1024.0*1024.0*1024.0*1024.0")

 #--- Footer
 tput bold
 printf "\n[=====--- End memory map for %d:%s ---=====]\n" $1 ${nm}
 printf "[Full pathname: %s]\n" $(realpath /proc/$1/exe)
 color_reset

 [ ${STATS_SHOW} -eq 1 ] && {
   # Paranoia
   local numvmas=$(sudo wc -l /proc/$1/maps |awk '{print $1}')
   [ ${gFileLines} -ne ${numvmas} ] && printf " [!] Warning! # VMAs does not match /proc/$1/maps\n"
   [ ${NULL_TRAP_SHOW} -eq 1 ] && let numvmas=numvmas+1

   printf "=== Statistics: ===\n %d VMAs (segments or mappings)" ${numvmas}
   # TODO - assuming the split on 64-bit is 128T:128T and on 32-bit 2:2 GB; query it
   [ ${SPARSE_SHOW} -eq 1 ] && {
     printf ", %d sparse regions\n" ${gNumSparse}
     if [ ${IS_64_BIT} -eq 1 ]; then
      largenum_display ${gTotalSparseSize} ${TB_128} "Total user virtual address space that is Sparse :\n"
     else
      largenum_display ${gTotalSparseSize} ${GB_4} "Total user virtual address space that is Sparse :\n"
     fi
   } # sparse show

   # Valid regions (segments) total size
   if [ ${IS_64_BIT} -eq 1 ]; then
    largenum_display ${gTotalSegSize} ${TB_128} "\n Total user virtual address space that is valid (mapped) memory :\n"
   else
    largenum_display ${gTotalSegSize} ${GB_4} "\n Total user virtual address space that is valid (mapped) memory :\n"
   fi
   printf "\n===\n"
 } # stats show
} # end main_wrapper()

usage()
{
  echo "Usage: ${name} [-s] [-d] -p PID-of-process -f input-CSV-filename(5 column format)
  -s : show in ascending order by va (virtual address)
  -d : run in debug mode"
}

##### 'main' : execution starts here #####

which bc >/dev/null || {
  echo "${name}: bc(1) package missing, pl install. Aborting..."
  exit 1
}

[ $# -lt 4 ] && {
  usage
  exit 1
}

ORDER_BY_DESC_VA=1

while getopts "p:f:h?dv" opt; do
    case "${opt}" in
        h|\?) usage ; exit 0
                ;;
        p)
            PID=${OPTARG}
            #echo "-p passed; PID=${PID}"
            ;;
        f)
            gINFILE=${OPTARG}
            #echo "-p passed; PID=${PID}"
            ;;
        #s)
        #    echo "[+] -s: will display in ascending order by va"
	    #ORDER_BY_DESC_VA=0
        #    ;;
        d)
            echo "[+] -d: run in debug mode"
            DEBUG=1
            ;;
        v)
            #echo "[+] -d: run in debug mode"
            VERBOSE=1
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

main_wrapper ${PID}
exit 0
