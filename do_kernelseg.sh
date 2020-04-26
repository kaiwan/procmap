#!/bin/bash
# kseg
source ${PFX}/config || {
 echo "${name}: fatal: could not source ${PFX}/config , aborting..."
 exit 1
}
# All arch-specific vars are here!
source ${ARCHFILE} || {
 echo "${name}: fatal: could not source ${ARCHFILE} , aborting..."
 exit 1
}

KSPARSE_ENTRY="<... K sparse region ...>"
VAS_128TB_HOLE="<... Non-canonical hole ...>"
name=$(basename $0)

#-----------------------s h o w A r r a y -----------------------------
show_gkArray()
{
local i k DIM=5
echo
decho "gkRow = ${gkRow}"
echo "show_gkArray():
[segname,size,start_kva,end_kva,mode]"

for ((i=0; i<${gkRow}; i+=${DIM}))
do
    printf "[%s," "${gkArray[${i}]}"    # segname
	let k=i+1
    printf "%llu," "${gkArray[${k}]}"   # seg size
	let k=i+2
    printf "%llx," "${gkArray[${k}]}"   # start kva
	let k=i+3
    printf "%llx," "${gkArray[${k}]}"   # end kva
	let k=i+4
    printf "%s" "${gkArray[${k}]}"      # mode
	printf "]\n"
done
} # end show_gkArray()

# Setup the kernel Sparse region at the very top (high) end of the VAS
# in the gkArray[]
# TODO : ARCH SPECIFIC !!
setup_ksparse_top()
{
 gkRow=0

 # Require the topmost valid kernel va, query it from the o/p of our
 # kernel component, the procmap LKM
 local top_kva=0x$(head -n1 ${KSEGFILE} |awk -F"${gDELIM}" '{print $2}')

 local gap_dec=$((HIGHEST_KVA-top_kva))
 if [ ${gap_dec} -gt ${PAGE_SIZE} ]; then
  append_kernel_mapping "${KSPARSE_ENTRY}" "${gap_dec}" ${top_kva} \
     "${HIGHEST_KVA}" "---"
 fi
} # end setup_ksparse_top()

#decho() {
# echo "$@"
#}

#------------------ i n t e r p r e t _ r e c -------------------------
# Interpret record (a CSV 'line' from the input stream) and populate the
# gkArr[] n-dim array.
# Format:
#  start_kva,end_kva,mode,name_of_region
#     ; kva = kernel virtual address
# eg.
#  0xffff9be100000000,0xffff9be542800000,rwx,lowmem region
#
# Parameters:
#  $1 : the above CSV format string of 4 fields {start_kva,end_kva,mode,region-name}
#  $2 : loop index (starts @ 1)
# Populate the global 'n-dim' (n=5) array gkArr.
interpret_kernel_rec()
{
local gap=0  # size (in bytes, decimal) of the kernel region,
             # i.e., end_kva - start_kva
local start_kva=0x$(echo "${1}" |cut -d"${gDELIM}" -f1)
local end_kva=0x$(echo "${1}" |cut -d"${gDELIM}" -f2)

# Skip comment lines
echo "${start_kva}" | grep -q "^#" && return

local mode=$(echo "${1}" |cut -d"${gDELIM}" -f3)
local name=$(echo "${1}" |cut -d"${gDELIM}" -f4)
[ -z "${name}" ] && segment=" [-unnamed-] "

# Convert hex to dec
local start_dec=$(printf "%llu" ${start_kva})
local end_dec=$(printf "%llu" ${end_kva})
local seg_sz=$(printf "%llu" $((end_dec-start_dec)))  # in bytes

# The global 5d-array's format is:
#          col0     col1      col2       col3   col4
# row'n' [regname],[size],[start_kva],[end_kva],[mode]

# TODO
# vsyscall: manually retrieve detail into gkArray[]

#------------ Sparse Detection
if [ ${KSPARSE_SHOW} -eq 1 ]; then

DetectedSparse=0

decho "$2: seg=${name} prevseg_name=${prevseg_name} ,  gkRow=${gkRow} "

# Detect sparse region, and if present, insert into the gArr[].
# Sparse region detected by condition:
#  gap = prev_seg_start - this-segment-end > 1 page

  if [ $2 -eq 1 ] ; then   # ignore the first kernel region
     decho "k sparse check: skipping first kernel region"
  else
	 decho "prevseg_start_kva=${prevseg_start_kva}"
     gap=$(bc <<< "(${prevseg_start_kva}-${end_dec})")
     local gap_hex=$(printf "0x%llx" ${gap})
     decho "gap = ${gap}"
     [ ${gap} -gt ${PAGE_SIZE} ] && DetectedSparse=1
  fi

 if [ ${DetectedSparse} -eq 1 ]; then
    local prevseg_start_kva_hex=$(printf "0x%llx" ${prevseg_start_kva})
    local start_kva_hex=$((${prevseg_start_kva_hex}-${gap_hex}))
	append_kernel_mapping "${KSPARSE_ENTRY}" "${gap}" ${start_kva_hex} \
		${prevseg_start_kva_hex} "---"

    # Stats
    [ ${KSTATS_SHOW} -eq 1 ] && {
      let gNumSparse=gNumSparse+1
      let gTotalSparseSize=gTotalSparseSize+gap
    }
 fi

prevseg_start_kva=${start_dec}
fi
#--------------

#--- Populate the global array
append_kernel_mapping "${name}" ${seg_sz} ${start_kva} ${end_kva} ${mode}

[ ${KSTATS_SHOW} -eq 1 ] && {
  let gTotalSegSize=${gTotalSegSize}+${seg_sz}
}

prevseg_name=${name}
decho "prevseg_name = ${prevseg_name}
"
} # end interpret_kernel_rec()

# Insert k sparse region from last (lowest) valid k mapping (often, lowmem)
# to first valid kernel va
# Parameters
#   $1 : prev segment/mapping start va (in hex)
setup_ksparse_lowest()
{
#set -x
 # TODO - verify!
 # The highest uva:
 #  On 32-bit = kernel PAGE_OFFSET-1
 #  On 64-bit = it varies with the arch
 #   x86_64: Ref: <kernel-src>/Documentation/x86/x86_64/mm.rst
 #     Start addr    |   Offset   |     End addr     |  Size   | VM area description
 #  0000000000000000 |    0       | 00007fffffffffff |  128 TB | user-space virtual memory, different per mm
 #
 # NOTE- this info is encoded into the 'config' file, pl refer to it.

# The way to perform arithmetic in bash on large #s is to use bc(1);
# AND to to decimal arithmetic and then convert to hex if required!

# TODO ::
#  this is ARCH-SPECIFIC !!!

# calculation: $1 - START_KVA
#  ;the START_KVA value is in the ARCHFILE
local kva_dec=$(printf "%llu" ${1})
#local START_KVA_DEC=$(printf "%llu" ${START_KVA})
local gap_dec=$(bc <<< "(${kva_dec}-${START_KVA_DEC})")

#decho "p1 = $1 , START_KVA = ${START_KVA} ; gap_dec=${gap_dec}"

if [ ${gap_dec} -gt ${PAGE_SIZE} ]; then
   append_kernel_mapping "${KSPARSE_ENTRY}" "${gap_dec}" ${START_KVA} \
		${1} "---"
fi
#set +x
} # end setup_ksparse_lowest()

setup_noncanonical_sparse_region()
{
# TODO :: this is ARCH SPECIFIC !! and ONLY for 64-bit

# the noncanonical 'hole' spans from 'start kva' to 'end uva'
  if [ "${ARCH}" = "x86_64" ]; then
   append_kernel_mapping "${VAS_128TB_HOLE}" "${NONCANONICAL_REG_SIZE}" \
	    ${END_UVA} ${START_KVA} "---"
  #elif [ "${ARCH}" = "Aarch64" ]; then
  fi
}

show_x86_64_arch()
{
# For x86_64, 4-level paging : the typical default
echo "START_UVA = ${START_UVA}"
echo "END_UVA = ${END_UVA}"
echo "NONCANONICAL_REG_SIZE = ${NONCANONICAL_REG_SIZE}"
echo "START_KVA = ${START_KVA}"
}

# init_kernel_lkm_get_details()
init_kernel_lkm_get_details()
{
#set +x

 #echo "[+] Kernel Segment details"
 if [ ! -d ${DBGFS_LOC} ] ; then
	echo "${name}: kernel debugfs not supported or mounted? aborting..."
	return
 else
    vecho " debugfs location verfied"
 fi

#show_x86_64_arch
#exit 0

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
  vecho " kseg: LKM inserted into kernel"
  sudo ls ${DBGFS_LOC}/${KMOD}/${DBGFS_FILENAME} >/dev/null 2>&1 || {
     echo "${name}: required debugfs file not present? aborting..."
	 sudo rmmod ${KMOD}
	 return
  }
  vecho " kseg: debugfs file is there"

  # Finally! generate the kernel seg details
  sudo cat ${DBGFS_LOC}/${KMOD}/${DBGFS_FILENAME} > ${KSEGFILE}
  decho "kseg dtl:
$(cat ${KSEGFILE})"

  get_pgoff_highmem
} # end init_kernel_lkm_get_details()

# populate_kernel_segment_mappings()
populate_kernel_segment_mappings()
{
 setup_ksparse_top

 #---------- Loop over the kernel segment data records
 export IFS=$'\n'
 local i=1
 local REC
 prevseg_start_kva=0
 for REC in $(cat ${KSEGFILE})
 do 
   decho "REC: $REC"
   interpret_kernel_rec ${REC} ${i}
   #printf "=== %06d / %06d\r" ${i} ${gFileLines}
   let i=i+1
 done 1>&2
 #----------

 # TODO - ins k sparse region from last (lowest) valid k mapping to top end uva
 prevseg_start_kva_hex=$(printf "0x%llx" ${prevseg_start_kva})
 decho "prevseg_start_kva_hex = ${prevseg_start_kva_hex}"
 setup_ksparse_lowest ${prevseg_start_kva_hex}

 # Non-canonical sparse region for 64-bit
 if [ ${IS_64_BIT} -eq 1 -a ${SHOW_USERSPACE} -eq 1 ] ; then
     setup_noncanonical_sparse_region
 fi

 [ ${DEBUG} -eq 0 ] && rm -f ${KSEGFILE}
 #sudo rmmod ${KMOD}

 [ ${DEBUG} -eq 1 ] && show_gkArray

 cd ${TOP}

} # end populate_kernel_segment_mappings()

