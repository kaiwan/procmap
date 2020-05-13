#!/bin/bash
# do_kernelseg.sh
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
VAS_NONCANONICAL_HOLE="<... 64-bit: non-canonical hole ...>"
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
# ARCH SPECIFIC ! See the arch-specific config setup func in lib_procmap.sh
# to see the actual values specified; it's sourced here via the
# 'source ${ARCHFILE}' done at the beginning!
setup_ksparse_top()
{
 gkRow=0

 # Require the topmost valid kernel va, query it from the o/p of our
 # kernel component, the procmap LKM
 local top_kva=0x$(head -n1 ${KSEGFILE} |awk -F"${gDELIM}" '{print $2}')

 #locate_region ${top_kva} ${HIGHEST_KVA}

 local gap_dec=$((HIGHEST_KVA-top_kva))
 if [ ${gap_dec} -gt ${PAGE_SIZE} ]; then
  append_kernel_mapping "${KSPARSE_ENTRY}" "${gap_dec}" ${top_kva} \
     "${HIGHEST_KVA}" "---"
 fi
} # end setup_ksparse_top()

# pa2va
# Convert the given phy addr (pa), to a kernel va (kva)
# CAREFUL!
#  We do so by exploiting the fact that the kernel direct-maps all platform
# RAM into the kernel segment starting at PAGE_OFFSET (i.e. into the lowmem
# region). So,
#   kva = pa + PAGE_OFFSET
# HOWEVER, this ONLY holds true for direct-mapped kernel RAM not for ANYTHING
# else!
# We EXPECT to ONLY be passed a physical addr that maps to the kernel direct-
# mapped addresses - lowmem addr.
# Parameters:
#   $1 : phy addr (pa)
pa2va()
{
# TIP : for bash arithmetic w/ large #s, first calculate in *decimal* base using
# bc(1), then convert it to hex as required (via printf)
local pgoff_dec=$(printf "%llu" 0x${PAGE_OFFSET})
local pa_dec=$(printf "%llu" 0x${1})
local kva=$(bc <<< "${pa_dec}+${pgoff_dec}")
printf "${FMTSPC_VA}" ${kva}
} # end pa2va

# UNUSED!
# setup_kernelimg_mappings
# Setup mappings for the kernel image itself; this usually consists of (could
# be fewer entries on some arch's):
# sudo grep -w "Kernel" /proc/iomem
#   297c00000-2988031d0 : Kernel code
#   2988031d1-29926c5bf : Kernel data
#   2994ea000-29978ffff : Kernel bss
# BUT, Carefully NOTE - the above are PHYSICAL ADDR, not kva's;
# So, we'll have to convert them to kva's and then insert them (in order by
# descending kva) into our gkArray[] data structure.
setup_kernelimg_mappings()
{
local TMPF=/tmp/kimgpa
local start_pa end_pa mapname
local start_kva end_kva

sudo grep -w "Kernel" /proc/iomem > ${TMPF}

#--- loop over the kernel image recs
 IFS=$'\n'
 local i=1
 local REC
 for REC in $(cat ${TMPF})
 do
   #decho "REC: $REC"
   start_pa=$(echo "${REC}" |cut -d"-" -f1)
   start_pa=$(trim ${start_pa})
   end_pa=$(echo "${REC}" |cut -d"-" -f2 |cut -d":" -f1)
   end_pa=$(trim ${end_pa})
   mapname=$(echo "${REC}" |cut -d":" -f2)
   mapname=$(trim ${mapname})

   # Convert pa to kva
   start_kva=$(pa2va ${start_pa})
   #echo "start_kva = ${start_kva}"
   end_kva=$(pa2va ${end_pa})

   # Write to 'kernel seg' file
   # ksegfile record fmt:
   #  start-kva,end-kva,perms,name
   echo "${start_kva},${end_kva},r-x,${mapname}" >> ${KSEGFILE}
   let i=i+1
 done 1>&2
 #----------

# Sort by descending kva!

[ ${DEBUG} -eq 0 ] && rm -f ${TMPF}
} # end setup_kernelimg_mappings

#----------- i n t e r p r e t _ k e r n e l _ r e c -------------------
# Interpret record (a CSV 'line' passed as $1) and populate the gkArray[]
# n-dim array.
# Format:
#  start_kva,end_kva,mode,name_of_region
#     ; kva = kernel virtual address
# eg. $1 =
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
# vsyscall: manually place detail into gkArray[]

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
     local end_hex=$(printf "0x%llx" ${end_dec})
     prevseg_start_kva_hex=$(printf "0x%llx" ${prevseg_start_kva})

	 decho "@@ gap = prevseg_start_kva_hex: ${prevseg_start_kva_hex} -  end_hex: ${end_hex}"
     gap=$(bc <<< "(${prevseg_start_kva}-${end_dec})")
     local gap_hex=$(printf "0x%llx" ${gap})
     decho "gap = ${gap}"
     [ ${gap} -gt ${PAGE_SIZE} ] && DetectedSparse=1
  fi

 if [ ${DetectedSparse} -eq 1 ]; then
    local start_kva_dec=$(bc <<< "(${prevseg_start_kva}-${gap})")
    local start_kva_sparse=$(printf "0x%llx" ${start_kva_dec})

	append_kernel_mapping "${KSPARSE_ENTRY}" "${gap}" ${start_kva_sparse} \
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
 # The highest uva:
 #  On 32-bit = it can be the modules region on Aarch32
 #  On 64-bit = it varies with the arch
 #   x86_64: Ref: <kernel-src>/Documentation/x86/x86_64/mm.rst
 #     Start addr    |   Offset   |     End addr     |  Size   | VM area description
 #  0000000000000000 |    0       | 00007fffffffffff |  128 TB | user-space virtual memory, different per mm
 #
 # NOTE- this info is encoded into the arch-specific config setup code in
 # lib_procmap.sh, pl refer to it.

# The way to perform arithmetic in bash on large #s is to use bc(1);
# AND to to decimal arithmetic and then convert to hex if required!

# calculation: $1 - START_KVA
#  ;the START_KVA value is in the ARCHFILE
local kva_dec=$(printf "%llu" ${1})
#local START_KVA_DEC=$(printf "%llu" ${START_KVA})
local gap_dec=$(bc <<< "(${kva_dec}-${START_KVA_DEC})")

#decho "p1 = $1 , START_KVA = ${START_KVA} ; gap_dec=${gap_dec}"

if [ ${gap_dec} -gt ${PAGE_SIZE} ]; then
   append_kernel_mapping "${KSPARSE_ENTRY}" "${gap_dec}" 0x${START_KVA} \
		${1} "---"
fi
} # end setup_ksparse_lowest()

setup_noncanonical_sparse_region()
{
# this is ARCH SPECIFIC and ONLY for 64-bit
# the noncanonical 'hole' spans from 'start kva' down to 'end uva'
  if [ ${IS_64_BIT} -eq 1 ]; then
   append_kernel_mapping "${VAS_NONCANONICAL_HOLE}" "${NONCANONICAL_REG_SIZE}" \
	    0x${END_UVA} 0x${START_KVA} "---"
  fi
}

# populate_kernel_segment_mappings()
populate_kernel_segment_mappings()
{
 setup_ksparse_top
 #setup_kernelimg_mappings

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
 if [ ${IS_64_BIT} -eq 1 ]; then  #-a ${SHOW_USERSPACE} -eq 1 ] ; then
     setup_noncanonical_sparse_region
 fi

 [ ${DEBUG} -eq 0 ] && rm -f ${KSEGFILE}
 [ ${DEBUG} -eq 1 ] && show_gkArray
 cd ${TOP}
} # end populate_kernel_segment_mappings()

