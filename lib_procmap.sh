#!/bin/bash
# lib_procmap.sh
#
# Support script for the procmap project.
# Has several 'library' routines.
name=$(basename $0)
PFX=$(dirname $(which $0))    # dir in which 'procmap' and tools reside
source ${PFX}/common.sh || {
 echo "${name}: fatal: could not source ${PFX}/common.sh , aborting..."
 exit 1
}
source ${PFX}/config || {
 echo "${name}: fatal: could not source ${PFX}/config , aborting..."
 exit 1
}

LOCATED_REGION_ENTRY="<--LOCATED-->"

# locate_region()
# Insert a 'locate region'? (passed via -l)
# Parameters:
#   $1 = -u|-k; -u => from userspace, -k => from kernel-space
#   $2 = start virtual addr of the region to check for intersection (hex)
#   $3 =   end virtual addr of the region to check for intersection (hex)
locate_region()
{
 local lr_start_va=$2 lr_end_va=$3
 [ "${lr_start_va:0:2}" != "0x" ] && lr_start_va=0x$2
 [ "${lr_end_va:0:2}" != "0x" ] && lr_end_va=0x$3
#set -x

# TODO / RELOOK
# Error:
#/home/kaiwan/gitLinux_repos/procmap/lib_procmap.sh: line 32: printf: 558ba488c000: invalid number
#/home/kaiwan/gitLinux_repos/procmap/lib_procmap.sh: line 32: printf: 558ba488b000: invalid number
 local start_va_dec=$(printf "%llu" ${lr_start_va} 2>/dev/null)
 local   end_va_dec=$(printf "%llu" ${lr_end_va} 2>/dev/null)

 #local start_va_dec=$(printf "%llu" 0x${2})
 #local   end_va_dec=$(printf "%llu" 0x${3})
#set +x

 if (( $(echo "${LOC_STARTADDR_DEC} >= ${start_va_dec}" |bc -l) )) ; then
    if (( $(echo "${LOC_STARTADDR_DEC} <= ${end_va_dec}" |bc -l) )) ; then
	   decho " <-------- located :: start = ${LOC_STARTADDR} of length ${LOC_LEN} KB -------->"

	   local loc_len_bytes=$((LOC_LEN*1024))
	   local loc_end_va_dec=$(bc <<< "${LOC_STARTADDR_DEC}+${loc_len_bytes}")
	   LOC_END_VA=0x$(printf "%llx" ${loc_end_va_dec})

	   if [ "$1" = "-k" ]; then
         do_append_kernel_mapping "${LOCATED_REGION_ENTRY}" "${loc_len_bytes}" ${LOC_STARTADDR} \
	        ${LOC_END_VA} "..."
	   elif [ "$1" = "-u" ]; then
         do_append_userspace_mapping "${LOCATED_REGION_ENTRY}" "${loc_len_bytes}" ${LOC_STARTADDR} \
	        ${LOC_END_VA} "..." 0
       fi
    fi
 fi
} # end locate_region()

# inc_sparse()
# Parameters:
#   $1 : size of the sparse region (decimal, bytes)
inc_sparse()
{
  [ ${SPARSE_SHOW} -eq 1 ] && {
    let gNumSparse=gNumSparse+1
    let gTotalSparseSize=gTotalSparseSize+$1
  }
} # end inc_sparse()

# Display the number passed in a human-readable fashion
# As appropriate, also in KB, MB, GB, TB
# $1 : the (large) number to display
# $2 : OPTIONAL PARAM: 
#      the total space size 'out of' (for percentage calculation)
#      percent = ($1/$2)*100
largenum_display()
{
	local szKB=0 szMB=0 szGB=0 szTB=0

     # !EMB: if we try and use simple bash arithmetic comparison, we get a 
     # "integer expression expected" err; hence, use bc(1):
     [ ${1} -ge 1024 ] && szKB=$(bc <<< "scale=6; ${1}/1024.0") || szKB=0

     if (( $(echo "${szKB} > 1024" |bc -l) )); then
       szMB=$(bc <<< "scale=6; ${szKB}/1024.0")
     fi
     if (( $(echo "${szMB} > 1024" |bc -l) )); then
       szGB=$(bc <<< "scale=6; ${szMB}/1024.0")
     fi
     if (( $(echo "${szGB} > 1024" |bc -l) )); then
       szTB=$(bc <<< "scale=6; ${szGB}/1024.0")
     fi

     #printf "%s: %llu bytes = %9.6f KB" ${3} ${1} ${szKB}
     printf " %llu bytes = %9.6f KB" ${1} ${szKB}
     if (( $(echo "${szKB} > 1024" |bc -l) )); then
       printf " = %9.6f MB" ${szMB}
       if (( $(echo "${szMB} > 1024" |bc -l) )); then
         printf " =  %9.6f GB" ${szGB}
       fi
       if (( $(echo "${szGB} > 1024" |bc -l) )); then
         printf " =  %9.6f TB" ${szTB}
       fi
     fi

     if [ $# -eq 2 ] ; then
       local pcntg=$(bc <<< "scale=12; (${1}/${2})*100.0")
       printf "\n  i.e. %2.6f%%" ${pcntg}
	 fi
} # end largenum_display()

# parse_ksegfile_getvars()
# Here, we parse information obtained via procmap's kernel component - the
# procmap LKM (loadable kernel module); it's already been written into the
# file ${KSEGFILE} (via it's debugfs file from the
# init_kernel_lkm_get_details() function)
parse_ksegfile_getvars()
{
 vecho " Parsing in various kernel variables as required"
 VECTORS_BASE=$(grep -w "vector" ${KSEGFILE} |cut -d"${gDELIM}" -f1)
 FIXADDR_START=$(grep -w "fixmap" ${KSEGFILE} |cut -d"${gDELIM}" -f1)
 MODULES_VADDR=$(grep -w "module" ${KSEGFILE} |cut -d"${gDELIM}" -f1)
 MODULES_END=$(grep -w "module" ${KSEGFILE} |cut -d"${gDELIM}" -f2)
 KASAN_SHADOW_START=$(grep -w "KASAN" ${KSEGFILE} |cut -d"${gDELIM}" -f1)
 KASAN_SHADOW_END=$(grep -w "KASAN" ${KSEGFILE} |cut -d"${gDELIM}" -f2)
 VMALLOC_START=$(grep -w "vmalloc" ${KSEGFILE} |cut -d"${gDELIM}" -f1)
 VMALLOC_END=$(grep -w "vmalloc" ${KSEGFILE} |cut -d"${gDELIM}" -f2)
 PAGE_OFFSET=$(grep -w "lowmem" ${KSEGFILE} |cut -d"${gDELIM}" -f1)
 high_memory=$(grep -w "lowmem" ${KSEGFILE} |cut -d"${gDELIM}" -f2)
 PKMAP_BASE=$(grep -w "HIGHMEM" ${KSEGFILE} |cut -d"${gDELIM}" -f1)

 # TODO: DEAD code, (test some more &) remove
[ 0 -eq 1 ] && {
 # Retrieve the PAGE_OFFSET and HIGHMEM lines from the KSEGFILE file
 PAGE_OFFSET=$(grep "^PAGE_OFFSET" ${KSEGFILE} |cut -d"${gDELIM}" -f2)
 HIGHMEM=$(grep "^high_memory" ${KSEGFILE} |cut -d"${gDELIM}" -f2)
 decho "PAGE_OFFSET = ${PAGE_OFFSET} , high_memory = ${HIGHMEM}"

 # Delete the PAGE_OFFSET and HIGHMEM lines from the KSEGFILE file
 # as we don't want them in the kernel map processing loop that follows
 sed --in-place '/^PAGE_OFFSET/d' ${KSEGFILE}
 sed --in-place '/^high_memory/d' ${KSEGFILE}
}

# We *require* these 'globals' again later in the script;
# So we place them into an 'arch' file (in descending order by kva) and source
# this file in the scripts that require it.
# It's arch-dependent, some vars may be NULL; that's okay.
 cat > ${ARCHFILE} << @EOF@
VECTORS_BASE=${VECTORS_BASE}
FIXADDR_START=${FIXADDR_START}
MODULES_VADDR=${MODULES_VADDR}
MODULES_END=${MODULES_END}
KASAN_SHADOW_START=${KASAN_SHADOW_START}
KASAN_SHADOW_END=${KASAN_SHADOW_END}
VMALLOC_START=${VMALLOC_START}
VMALLOC_END=${VMALLOC_END}
PAGE_OFFSET=${PAGE_OFFSET}
high_memory=${high_memory}
PKMAP_BASE=${PKMAP_BASE}
@EOF@
} # end parse_ksegfile_getvars()

# build_lkm()
# (Re)build the LKM - Loadable Kernel Module for this project
build_lkm()
{
 echo "[i] kseg: building the LKM ..."
 make clean >/dev/null 2>&1
 make >/dev/null 2>&1 || {
    echo "${name}: kernel module \"${KMOD}\" build failed, aborting..."
    return
 }
 if [ ! -s ${KMOD}.ko ] ; then
    echo "${name}: kernel module \"${KMOD}\" not generated? aborting..."
	return
 fi
 vecho " kernel: LKM built"
} # end build_lkm()

# init_kernel_lkm_get_details()
init_kernel_lkm_get_details()
{
#set +x
  vecho "kernel: init kernel LKM and get details:"
  if [ ! -d ${DBGFS_LOC} ] ; then
 	echo "${name}: kernel debugfs not supported or mounted? aborting..."
 	return
  else
    vecho " debugfs location verfied"
  fi

  TOP=$(pwd)
  cd ${KERNELDIR} || return
  #pwd

  if [ ! -s ${KMOD}.ko ] ; then
     build_lkm
  fi

  # Ok, the kernel module is there, lets insert it!
  #ls -l ${KMOD}.ko
  sudo rmmod ${KMOD} 2>/dev/null   # rm any stale instance
  sudo insmod ./${KMOD}.ko || {
	    echo "${name}: insmod(8) on kernel module \"${KMOD}\" failed, build again and retry..."
        build_lkm
	    sudo insmod ./${KMOD}.ko || return
  }
  lsmod |grep -q ${KMOD} || {
	    echo "${name}: insmod(8) on kernel module \"${KMOD}\" failed? aborting..."
		return
  }
  vecho " LKM inserted into kernel"
  sudo ls ${DBGFS_LOC}/${KMOD}/${DBGFS_FILENAME} >/dev/null 2>&1 || {
     echo "${name}: required debugfs file not present? aborting..."
	 sudo rmmod ${KMOD}
	 return
  }
  vecho " debugfs file present"

  # Finally! generate the kernel seg details
  sudo cat ${DBGFS_LOC}/${KMOD}/${DBGFS_FILENAME} > ${KSEGFILE}
  # CSV fmt:
  #  start_kva,end_kva,mode,name-of-region
  decho "kseg dtl:
$(cat ${KSEGFILE})"

  parse_ksegfile_getvars
} # end init_kernel_lkm_get_details()

#######################################################################
# Arch-specific details
#######################################################################
# To calculate stuff (like the kernel start va), we require:
#  end_uva ; highest user va
#  size of the sparse non-canonical region

#----------------------------------------------------------------------
# For x86_64, 4-level paging, 4k page : the typical default
#----------------------------------------------------------------------
set_config_x86_64()
{
  vecho "set config for x86_64:"
ARCH=x86_64
PAGE_SIZE=4096
USER_VAS_SIZE_TB=128
KERNEL_VAS_SIZE_TB=128

# bash debugging TIP:
#  set -x : turn tracing ON
#  set +x : turn tracing OFF
#set -x

# TIP : for bash arithmetic w/ large #s, first calculate in *decimal* base using
# bc(1), then convert it to hex as required (via printf)
# start kva = end uva + sparse non-canonical region size
# For hex, bc(1) Requires the #s to be in UPPERCASE; so we use the ^^ op to
#  achieve this (bash ver>=4)

# sparse non-canonical region size = 2^64 - (user VAS + kernel VAS)
NONCANONICAL_REG_SIZE=$(bc <<< "2^64-(${USER_VAS_SIZE_TB}*${TB_1}+${KERNEL_VAS_SIZE_TB}*${TB_1})")
NONCANONICAL_REG_SIZE_HEX=$(printf "0x%llx" ${NONCANONICAL_REG_SIZE})

END_UVA_DEC=$(bc <<< "(${USER_VAS_SIZE_TB}*${TB_1}-1)")
END_UVA=$(printf "%llx" ${END_UVA_DEC})

START_KVA_DEC=$(bc <<< "(${END_UVA_DEC}+${NONCANONICAL_REG_SIZE}+1)")
START_KVA=$(printf "%llx" ${START_KVA_DEC})
HIGHEST_KVA=ffffffffffffffff
HIGHEST_KVA_DEC=$(printf "%llu" 0x${HIGHEST_KVA})
START_UVA=0
START_UVA_DEC=0

# Calculate size of K and U VAS's
KERNEL_VAS_SIZE=$(bc <<< "(${HIGHEST_KVA_DEC}-${START_KVA_DEC}+1)")
# user VAS size is the kernel macro TASK_SIZE (?)
USER_VAS_SIZE=$(bc <<< "(${END_UVA_DEC}-${START_UVA_DEC}+1)")

# We *require* these 'globals' in the other scripts
# So we place all of them into a file and source this file in the
# scripts that require it
cat >> ${ARCHFILE} << @EOF@

ARCH=x86_64
IS_64_BIT=1
PAGE_SIZE=4096
USER_VAS_SIZE_TB=128
KERNEL_VAS_SIZE_TB=128
START_KVA_DEC=${START_KVA_DEC}
START_KVA=${START_KVA}
HIGHEST_KVA=0xffffffffffffffff
NONCANONICAL_REG_SIZE=${NONCANONICAL_REG_SIZE}
NONCANONICAL_REG_SIZE_HEX=${NONCANONICAL_REG_SIZE_HEX}
START_UVA=0x0
END_UVA_DEC=${END_UVA_DEC}
END_UVA=${END_UVA}
KERNEL_VAS_SIZE=${KERNEL_VAS_SIZE}
USER_VAS_SIZE=${USER_VAS_SIZE}
FMTSPC_VA=${FMTSPC_VA}
@EOF@
} # end set_config_x86_64()

#----------------------------------------------------------------------
# For Aarch32 (ARM-32), 2-level paging, 4k page
#----------------------------------------------------------------------
set_config_aarch32()
{
  vecho "set config for Aarch32:"
ARCH=Aarch32
PAGE_SIZE=4096

# 32-bit, so no sparse non-canonical region.
# Retrieve the PAGE_OFFSET and HIGHMEM lines from the ARCHFILE file
PAGE_OFFSET=$(grep "^PAGE_OFFSET" ${ARCHFILE} |cut -d"=" -f2)
HIGHMEM=$(grep "^HIGHMEM" ${ARCHFILE} |cut -d"=" -f2)
decho "PAGE_OFFSET = ${PAGE_OFFSET} , HIGHMEM = ${HIGHMEM}"
[ -z "${PAGE_OFFSET}" ] && {
	echo "ERROR: Aarch32: couldn't fetch the PAGE_OFFSET value, aborting..."
	exit 1
}

HIGHEST_KVA=ffffffff
HIGHEST_KVA_DEC=$(printf "%lu" 0x${HIGHEST_KVA})

# For Aarch32 (and possibly other arch's as well), we cannot simply assume
# that the 'start kva' is PAGE_OFFSET; very often it's the start of the kernel
# module region which is *below* PAGE_OFFSET; check for this and update..
START_KVA=$(tail -n1 ${KSEGFILE} |cut -d"${gDELIM}" -f1)
if (( $(echo "0x${START_KVA^^} > 0x${PAGE_OFFSET^^}" |bc -l "obase=16" 2>/dev/null) )); then
  START_KVA=${PAGE_OFFSET}
fi
START_KVA_DEC=$(printf "%lu" 0x${START_KVA})

END_UVA_DEC=$((0x${START_KVA}-1))
END_UVA=$(printf "%lx" ${END_UVA_DEC})
START_UVA=0x0
START_UVA_DEC=0

# Calculate size of K and U VAS's
KERNEL_VAS_SIZE=$(bc <<< "(${HIGHEST_KVA_DEC}-${START_KVA_DEC}+1)")
  USER_VAS_SIZE=$(bc <<< "(${END_UVA_DEC}-${START_UVA_DEC}+1)")

# We *require* these 'globals' in the other scripts
# So we place all of them into a file and source this file in the
# scripts that require it
cat >> ${ARCHFILE} << @EOF@
ARCH=Aarch32
IS_64_BIT=0
PAGE_SIZE=4096
START_KVA_DEC=${START_KVA_DEC}
START_KVA=${START_KVA}
HIGHEST_KVA=0xffffffff
START_UVA=0x0
END_UVA_DEC=${END_UVA_DEC}
END_UVA=${END_UVA}
KERNEL_VAS_SIZE=${KERNEL_VAS_SIZE}
USER_VAS_SIZE=${USER_VAS_SIZE}
FMTSPC_VA=${FMTSPC_VA}
@EOF@
} # end set_config_aarch32()

# human_readdbl_kernel_arch()
human_readdbl_kernel_arch()
{
if [ ${VERBOSE} -eq 0 -a ${DEBUG} -eq 0 ] ; then
   return
fi

local TMPF1=/tmp/karch1 TMPF2=/tmp/karch2
awk -F= 'NF > 1 {print $1, "=", $2}' ${ARCHFILE} > ${TMPF1}
awk 'NF == 3 {print $0}' ${TMPF1} > ${TMPF2}
sed --in-place '/FMTSPC_VA/ d' ${TMPF2}

local LIN="--------------------------------------------------"
echo "${LIN}
[v] System details detected ::
${LIN}
$(cat ${TMPF2})
${LIN}"
rm -f ${TMPF1} ${TMPF2}
} # end human_readdbl_kernel_arch()

show_machine_kernel_dtl()
{
printf "Detected machine type: "
tput bold
if [ ${IS_X86_64} -eq 1 ] ; then
   echo -n "x86_64"
elif [ ${IS_Aarch32} -eq 1 ] ; then
	echo -n "Aarch32 (ARM-32)"
elif [ ${IS_Aarch64} -eq 1 ] ; then
	echo -n "Aarch64 (ARM-64)"
elif [ ${IS_X86_32} -eq 1 ] ; then
      echo -n "x86-32"
fi

[ ${IS_64_BIT} -eq 1 ] && {
  printf ", 64-bit OS\n"
} || {
  printf ", 32-bit OS\n"
}
color_reset

human_readdbl_kernel_arch
}

#----------------------------------------------------------------------
# get_machine_type()
get_machine_type()
{
# 32 or 64 bit OS?
IS_64_BIT=1
which getconf >/dev/null || {
  echo "${name}: WARNING! getconf(1) missing, assuming 64-bit OS!"
} && {
  local bitw=$(getconf -a|grep -w LONG_BIT|awk '{print $2}')
  [ ${bitw} -eq 32 ] && IS_64_BIT=0  # implies 32-bit
}

# Portable printing
if [ ${IS_64_BIT} -eq 1 ] ; then
   FMTSPC_VA="%016lx"
else    # 32-bit
   FMTSPC_VA="%08lx"
fi

local mach=$(uname -m)
local cpu=${mach:0:3}

if [ "${mach}" = "x86_64" ]; then
   IS_X86_64=1
   set_config_x86_64
elif [ "${cpu}" = "arm" ]; then
   if [ ${IS_64_BIT} -eq 0 ] ; then
      IS_Aarch32=1
      set_config_aarch32
   else
      IS_Aarch64=1
      #set_config_aarch64
   fi
elif [ "${cpu}" = "x86" ]; then
   if [ ${IS_64_BIT} -eq 0 ] ; then
      IS_X86_32=1
      set_config_x86_32
   fi
else
   printf "\n\nSorry, your CPU (\"$(uname -m)\") isn't supported...\n"
   # TODO - 'pl report this'
   exit 1
fi

show_machine_kernel_dtl
} # end get_machine_type()

# do_append_kernel_mapping()
# Append a new n-dim entry in the gkArray[] data structure,
# creating, in effect, a new mapping
# Parameters:
#   $1 : name of mapping/segment
#   $2 : size (in bytes, decimal) of mapping/segment
#   $3 : start va of mapping/segment
#   $4 : end va of mapping/segment
#   $5 : mode (perms) of mapping/segment
do_append_kernel_mapping()
{
  # row'n' [segname],[size],[start_uva],[end_uva],[mode],[offset]
  gkArray[${gkRow}]="${1}"
  let gkRow=gkRow+1
  gkArray[${gkRow}]="${2}"
  let gkRow=gkRow+1
  gkArray[${gkRow}]=${3}        # start kva
  let gkRow=gkRow+1
  gkArray[${gkRow}]="${4}"      # end (higher) kva
  let gkRow=gkRow+1
  gkArray[${gkRow}]="${5}"
  let gkRow=gkRow+1
} # end do_append_kernel_mapping()

append_kernel_mapping()
{
  # $3 = start va
  # $4 = end va
  do_append_kernel_mapping "$1" $2 $3 $4 $5
  [ ${LOC_LEN} -ne 0 ] && locate_region -k $3 $4
}

# do_append_userspace_mapping()
# Append a new n-dim entry in the gArray[] data structure,
# creating, in effect, a new mapping
# Parameters:
#   $1 : name of mapping/segment
#   $2 : size (in bytes, decimal) of mapping/segment
#   $3 : start va of mapping/segment
#   $4 : end va of mapping/segment
#   $5 : mode (perms) + mapping type (p|s) of mapping/segment
#   $6 : file offset (hex) of mapping/segment
do_append_userspace_mapping()
{
  # row'n' [segname],[size],[start_uva],[end_uva],[mode],[offset]
  gArray[${gRow}]="${1}"
  let gRow=gRow+1
  gArray[${gRow}]=${2}
  let gRow=gRow+1
  gArray[${gRow}]=${3}        # start kva
  let gRow=gRow+1
  gArray[${gRow}]=${4}        # end (higher) kva
  let gRow=gRow+1
  gArray[${gRow}]="${5}"
  let gRow=gRow+1
  gArray[${gRow}]=${6}
  let gRow=gRow+1
} # end do_append_userspace_mapping()

# append_userspace_mapping()
append_userspace_mapping()
{
  # $3 = start va
  # $4 = end va
  do_append_userspace_mapping "$1" $2 $3 $4 $5 $6
  [ ${LOC_LEN} -ne 0 ] && locate_region -u $3 $4
}

#---------------------- g r a p h i t ---------------------------------
# Iterates over the global n-dim arrays 'drawing' the vgraph.
#  when invoked with -k, it iterates over the gkArray[] ds
#  when invoked with -u, it iterates over the gArray[] ds
# Data driven tech!
#
# Parameters:
#   $1 : -u|-k ; -u => userspace , -k = kernel-space
graphit()
{
local i k
local segname seg_sz start_va end_va mode offset
local szKB=0 szMB=0 szGB=0 szTB=0 szPB=0

local LIN_FIRST_K="+------------------  K E R N E L   V A S    end kva  ------------------+"
local  LIN_LAST_K="+------------------  K E R N E L   V A S  start kva  ------------------+"
local LIN_FIRST_U="+------------------      U S E R   V A S    end uva  ------------------+"
local  LIN_LAST_U="+------------------      U S E R   V A S  start uva  ------------------+"
local         LIN="+----------------------------------------------------------------------+"
local ELLIPSE_LIN="~ .       .       .       .       .       .        .       .        .  ~"
local   BOX_SIDES="|                                                                      |"
local LIN_LOCATED_REGION="       +------------------------------------------------------+"
local MARK_LOCATION="X"

local linelen=$((${#LIN}-2))
local oversized=0

decho "+++ graphit(): param = $1"
color_reset
if [ "$1" = "-u" ] ; then
   local DIM=6
   local rows=${gRow}
elif [ "$1" = "-k" ] ; then
   local DIM=5
   local rows=${gkRow}
fi

for ((i=0; i<${rows}; i+=${DIM}))
do
	local tlen=0 len_perms len_maptype len_offset
	local tmp1="" tmp2="" tmp3="" tmp4="" tmp5=""
	local tmp5a="" tmp5b="" tmp5c="" tmp6=""
	local segname_nocolor tmp1_nocolor tmp2_nocolor tmp3_nocolor
	local tmp4_nocolor tmp5a_nocolor tmp5b_nocolor tmp5c_nocolor
	local tmp5 tmp5_nocolor
	local tmp7 tmp7_nocolor
	local archfile_entry archfile_entry_label

    #--- Retrieve values from the array
	if [ "$1" = "-u" ] ; then
		segname=${gArray[${i}]}    # col 1 [str: the label/segment name]
		let k=i+1
		seg_sz=${gArray[${k}]}     # col 2 [int: the segment size]
		let k=i+2
		start_va=0x${gArray[${k}]}  # col 3 [int: the first number, start_va]
		let k=i+3
		end_va=0x${gArray[${k}]}    # col 4 [int: the second number, end_va]
		let k=i+4
		mode=${gArray[${k}]}       # col 5 [str: the mode+flag]
		let k=i+5
		offset=${gArray[${k}]}     # col 6 [int: the file offset]
	elif [ "$1" = "-k" ] ; then
		segname=${gkArray[${i}]}    # col 1 [str: the label/segment name]
		let k=i+1
		seg_sz=${gkArray[${k}]}     # col 2 [int: the segment size]
		let k=i+2
		start_va=${gkArray[${k}]}  # col 3 [int: the first number, start_va]
		let k=i+3
		end_va=${gkArray[${k}]}    # col 4 [int: the second number, end_va]
		let k=i+4
		mode=${gkArray[${k}]}       # col 5 [str: the mode+flag]
	fi

	# Calculate segment size in diff units as required
	if [ -z "${seg_sz}" ] ; then
	  decho "-- invalid mapping size, skipping..."
	  return
	fi

    szKB=$(bc <<< "${seg_sz}/1024")
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
    szPB=0
    if (( $(echo "${szTB} > 1024" |bc -l) )); then
      szPB=$(bc <<< "scale=2; ${szTB}/1024.0")
    fi
	#decho "@@@ i=$i/${rows} , seg_sz = ${seg_sz}"

decho "end_va = ${end_va}   ,   start_va = ${start_va}"


    #--- Drawing :-p  !
	# the horizontal line with the end uva at the end of it
	#=====================================
	# the first actual print emitted!
	# Eg.
	# +----------------------------------------------------------------------+ 000055681263b000
	# Changed to end_va @EOL as we now always print in descending order

    if [ "$1" = "-k" -a ${i} -eq $((${rows}-${DIM})) ] ; then   # last loop iteration
       if [ ${IS_64_BIT} -eq 1 ] ; then
           tput bold
           printf "%s ${FMTSPC_VA}\n" "${LIN_LAST_K}" 0x${START_KVA}
	       color_reset
	   else
           printf "%s ${FMTSPC_VA}\n" "${LIN}" ${end_va}
           #printf "%s ${FMTSPC_VA}\n" "${LIN}" 0x${START_KVA}
	   fi
    elif [ ${i} -ne 0 ] ; then   # ** normal case **

		 #============ -l option: LOCATE region ! ======================
		 if [ 1 -eq 1 ] ; then
         if [ "${segname}" = "${LOCATED_REGION_ENTRY}" ]; then
		    tput bold; fg_red
			if [ ${IS_64_BIT} -eq 1 ] ; then
               printf "|                          %s ${FMTSPC_VA}                          |\n" \
			        "${MARK_LOCATION}" ${LOC_STARTADDR}
			else
               printf "|                              %s ${FMTSPC_VA}                              |\n" \
			        "${MARK_LOCATION}" ${LOC_STARTADDR}
			fi
			color_reset
		    oversized=0
			continue
		 fi
		 fi

		 #=== ** normal case ** ===
         if [ "${segname}" != "${LOCATED_REGION_ENTRY}" ]; then
            printf "%s ${FMTSPC_VA}" "${LIN}" "${end_va}"
		 fi

		 # Check, if the currently printed 'end_va' matches an entry in our ARCHFILE;
		 # If so, print the entry 'label' (name); f.e. 0x.... <-- PAGE_OFFSET
		 # TODO: x86_64: buggy when -k option passed, ok when both VAS's are displayed
		 if [ "${end_va:0:2}" = "0x" ]; then
		    archfile_entry=$(grep "${end_va:2}" ${ARCHFILE})  # ${end_va:2} => leave out the '0x' part
		 else
		    archfile_entry=$(grep "${end_va}" ${ARCHFILE})
		 fi
		 [ ! -z "${archfile_entry}" ] && {
		   archfile_entry_label=$(echo "${archfile_entry}" |cut -d"=" -f1)
           tput bold
		   printf "%s  <-- %s\n" $(${FG_KVAR}) "${archfile_entry_label}"
		   #printf "  <-- %s\n" "${archfile_entry_label}"
	       color_reset
		 } || {
		   printf "\n"
		 }
    else   # very first line
         tput bold
         if [ "${1}" = "-k" ] ; then
            printf "%s ${FMTSPC_VA}\n" "${LIN_FIRST_K}" "${end_va}"
         fi
	color_reset
    fi

	#--- Collate and print the details of the current mapping (segment)
	# Eg.
	# |<... Sparse Region ...> [ 14.73 MB] [----,0x0]                        |

	# Print segment name
	tmp1=$(printf "%s|%20s " $(${FG_MAPNAME}) ${segname})
	local segname_nocolor=$(printf "|%20s " ${segname})

	# Colour and Print segment *size* according to scale; in KB or MB or GB or TB or PB
	tlen=0
    if (( $(echo "${szKB} < 1024" |bc -l) )); then
		# print KB only
		tmp2=$(printf "%s [%4d KB" $(fg_darkgreen) ${szKB})
		tmp2_nocolor=$(printf " [%4d KB" ${szKB})
		tlen=${#tmp2_nocolor}
    elif (( $(echo "${szKB} > 1024" |bc -l) )); then
      if (( $(echo "${szMB} < 1024" |bc -l) )); then
		# print MB only
		tmp3=$(printf "%s[%7.2f MB" $(fg_navyblue) ${szMB})
		tmp3_nocolor=$(printf "[%7.2f MB" ${szMB})
		tlen=${#tmp3_nocolor}
    elif (( $(echo "${szMB} > 1024" |bc -l) )); then
      if (( $(echo "${szGB} < 1024" |bc -l) )); then
		# print GB only
		tmp4=$(printf "%s%s[%7.2f GB%s" $(tput bold) $(fg_purple) ${szGB} $(color_reset))
		tmp4_nocolor=$(printf "[%7.2f GB" ${szGB})
		tlen=${#tmp4_nocolor}
    elif (( $(echo "${szGB} > 1024" |bc -l) )); then
      if (( $(echo "${szTB} < 1024" |bc -l) )); then
		# print TB only
		tmp5=$(printf "%s%s[%7.2f TB%s" $(tput bold) $(fg_red) ${szTB} $(color_reset))
		tmp5_nocolor=$(printf "[%7.2f TB" ${szTB})
		tlen=${#tmp5_nocolor}
	else
		# print PB only
		tmp7=$(printf "%s%s[%9.2f PB%s" $(tput bold) $(fg_red) ${szPB} $(color_reset))
		tmp7_nocolor=$(printf "[%9.2f PB" ${szPB})
		tlen=${#tmp7_nocolor}
       fi
      fi
	 fi
	fi

    # Mode field:
	#  Userspace:
	#   'mode' xxxy has two pieces of info:
	#    - xxx is the mode (octal permissions / rwx style)
	#    - y is either p or s, private or shared mapping
	#   seperate them out in order to print them in diff colors, etc
	#   (substr op: ${string:position:length} ; position starts @ 0)
	#  kernel: it's just 'mode'
	if [ "$1" = "-u" ] ; then
	  local perms=$(echo ${mode:0:3})
	  local maptype=$(echo ${mode:3:1})
	else
	  local perms=${mode}
	fi

	# mode (perms) + mapping type
	#  print in bold red fg if:
	#    mode == ---
	#    mode violates the W^X principle, i.e., w and x set
	local flag_null_perms=0 flag_wx_perms=0
	if [ "${perms}" = "---" ]; then
	   flag_null_perms=1
	fi
	echo "${perms}" | grep -q ".wx" && flag_wx_perms=1

	if [ ${flag_null_perms} -eq 1 -o ${flag_wx_perms} -eq 1 ] ; then
		tmp5a=$(printf "%s%s,%s%s" $(tput bold) $(fg_red) "${perms}" $(color_reset))
	    if [ "$1" = "-u" ] ; then # addn comma only for userspace
		   tmp5a="${tmp5a},"
		else                      # to compensate, addn space for kernel
		   tmp5a="${tmp5a} "
		fi
	else
		tmp5a=$(printf "%s,%s%s" $(fg_black) "${perms}" $(color_reset))
	    if [ "$1" = "-u" ] ; then # addn comma only for userspace
		   tmp5a="${tmp5a},"
		else                      # to compensate, addn space for kernel
		   tmp5a="${tmp5a} "
	    fi
	fi
	tmp5a_nocolor=$(printf ",%s," "${perms}")
	len_perms=${#tmp5a_nocolor}

	# userspace: mapping type and file offset
	if [ "$1" = "-u" ] ; then
	   tmp5b=$(printf "%s%s%s,%s" $(fg_blue) "${maptype}" $(fg_black) $(color_reset))
	   tmp5b_nocolor=$(printf "%s," "${maptype}")
	   len_maptype=${#tmp5b_nocolor}

	   # file offset
	   tmp5c=$(printf "%s0x%s%s" $(fg_black) "${offset}" $(color_reset))
	   tmp5c_nocolor=$(printf "0x%s" "${offset}")
	   len_offset=${#tmp5c_nocolor}
	fi

    # Calculate the strlen of the printed string, and thus calculate and print
    # the appropriate number of spaces after it until the "|" close-box symbol.
	# Final strlen value:
	local segnmlen=${#segname_nocolor}
	if [ ${segnmlen} -lt 20 ]; then
		segnmlen=20  # as we do printf "|%20s"...
	fi
	if [ "$1" = "-u" ] ; then
		let tlen=${segnmlen}+${tlen}+${len_perms}+${len_maptype}+${len_offset}
	else
		let tlen=${segnmlen}+${tlen}+${len_perms}
	fi

    if [ ${tlen} -lt ${#LIN} ] ; then
       local spc_reqd=$((${linelen}-${tlen}))
       tmp6=$(printf "]%${spc_reqd}s|\n" " ") 
	       # print the required # of spaces and then the '|'
    else
		tmp6=$(printf "]")
	fi
    #decho "tlen=${tlen} spc_reqd=${spc_reqd}"

	#================ The second actual print emitted!
	# f.e:
	# "|              [heap]  [ 132 KB,rw-,p,0x0]                             |"
    echo "${tmp1}${tmp2}${tmp3}${tmp4}${tmp5}${tmp7}${tmp5a}${tmp5b}${tmp5c}${tmp6}"


    #--- NEW CALC for SCALING
    # Simplify: We base the 'height' of each segment on the number of digits
    # in the segment size (in bytes)!
    segscale=${#seg_sz}    # strlen(seg_sz)
	# Exception to this check: if we're in a 'located region' (via -l option)
    [ "${segname}" != "${LOCATED_REGION_ENTRY}" -a ${segscale} -lt 4 ] && {   # min seg size is 4096 bytes
        echo "procmap:graphit(): fatal error, segscale (# digits) <= 3! Aborting..."
	    echo "Kindly report this as a bug, thanks!"
	    exit 1
    }
    decho "seg_sz = ${seg_sz} segscale=${segscale}"

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
    elif [ ${segscale} -ge 8 -a ${segscale} -le 13 ]; then
		# for segscale >= 8 digits
		let box_height=segscale-3
    elif [ ${segscale} -ge 14 -a ${segscale} -le 16 ]; then
		# for segscale >= 14 digits
		# i.e. for 14 digits, i.e., from ~ 1 TB onwards, show an oversized ellipse box
		box_height=16
    else
		# for segscale >= 16 digits
		# i.e. for 16 digits, i.e., realistically, for the noncanonical 'hole' on 64-bit
		# spanning close to 16 EB ! on x86_64
		box_height=20
    fi
    #---

    # draw the sides of the 'box'
    [ ${box_height} -ge ${LARGE_SPACE} ] && {
   	  oversized=1
    }

    #decho "box_height = ${box_height} oversized=${oversized}"
	local x
    for ((x=1; x<${box_height}; x++))
    do
   	  printf "%s\n" "${BOX_SIDES}"
   	  if [ ${oversized} -eq 1 ] ; then
        [ ${x} -eq $(((LIMIT_SCALE_SZ-4)/2)) ] && printf "%s\n" "${ELLIPSE_LIN}"
   	  fi
    done
    oversized=0
done

# address space: the K-U boundary! on 32-bit, display both the start kva and
# the 'end uva' virt addresses; on 64-bit, the noncanonical sparse region code
# takes care of printing it correctly...
if [ "${1}" = "-k" ] ; then
	tput bold
	[ ${IS_64_BIT} -eq 0 ] && printf "%s ${FMTSPC_VA}\n" "${LIN_LAST_K}" 0x${START_KVA}
	printf "%s ${FMTSPC_VA}\n" "${LIN_FIRST_U}" 0x${END_UVA}
	color_reset
fi

# userspace: last line, the zero-th virt address; always:
#+----------------------------------------------------------------------+ 0000000000000000
if [ "$1" = "-u" ] ; then
   tput bold
   printf "%s ${FMTSPC_VA}\n" "${LIN_LAST_U}" ${start_va}
   color_reset
fi
} # end graphit()
