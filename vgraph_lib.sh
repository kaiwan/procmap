#!/bin/bash
# vgraph_lib.sh

# append_kernel_mapping()
# Append a new n-dim entry in the gkArray[] data structure,
# creating, in effect, a new mapping
# Parameters:
#   $1 : name of mapping/segment
#   $2 : size (in bytes, decimal) of mapping/segment
#   $3 : start va of mapping/segment
#   $4 : end va of mapping/segment
#   $5 : mode (perms) of mapping/segment
append_kernel_mapping()
{
  # row'n' [segname],[size],[start_uva],[end_uva],[mode],[offset]
  gkArray[${gkRow}]="${1}"
  let gkRow=gkRow+1
  gkArray[${gkRow}]="${2}"
  let gkRow=gkRow+1
  gkArray[${gkRow}]=${3}        # start kva
  let gkRow=gkRow+1
  gkArray[${gkRow}]="${4}"  # end (higher) kva
  let gkRow=gkRow+1
  gkArray[${gkRow}]="${5}"
  let gkRow=gkRow+1
  #let gNumSparse=gNumSparse+1
} # end append_kernel_mapping()

# append_userspace_mapping()
# Append a new n-dim entry in the gArray[] data structure,
# creating, in effect, a new mapping
# Parameters:
#   $1 : name of mapping/segment
#   $2 : size (in bytes, decimal) of mapping/segment
#   $3 : start va of mapping/segment
#   $4 : end va of mapping/segment
#   $5 : mode (perms) + mapping type (p|s) of mapping/segment
#   $6 : file offset (hex) of mapping/segment
append_userspace_mapping()
{
  # row'n' [segname],[size],[start_uva],[end_uva],[mode],[offset]
  gArray[${gRow}]="${1}"
  let gRow=gRow+1
  gArray[${gRow}]=${2}
  let gRow=gRow+1
  gArray[${gRow}]=${3}        # start kva
  let gRow=gRow+1
  gArray[${gRow}]=${4}  # end (higher) kva
  let gRow=gRow+1
  gArray[${gRow}]="${5}"
  let gRow=gRow+1
  gArray[${gRow}]=${6}
  let gRow=gRow+1
  #let gNumSparse=gNumSparse+1
} # end append_userspace_mapping()

#---------------------- g r a p h i t ---------------------------------
# Iterates over the global '6d' array gArr[] 'drawing' the vgraph.
# Data driven tech!
# Parameters:
#   $1 : -u|-k ; -u => userspace , -k = kernel-space
graphit()
{
local i k
local segname seg_sz start_va end_va mode offset
local szKB=0 szMB=0 szGB=0 szTB=0 szPB=0

local LIN_FIRST_K="+------------------  K E R N E L   S E G M E N T    end kva  ----------+"
local  LIN_LAST_K="+------------------  K E R N E L   S E G M E N T  start kva  ----------+"
local LIN_FIRST_U="+--------------------    U S E R   V A S    end uva  ------------------+"
local  LIN_LAST_U="+--------------------    U S E R   V A S  start uva  ------------------+"
local         LIN="+----------------------------------------------------------------------+"
local ELLIPSE_LIN="~ .       .       .       .       .       .        .       .        .  ~"
local   BOX_SIDES="|                                                                      |"
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

#set -x
	#szKB=$((${seg_sz}/1024))
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
#set +x
	decho "@@@ i=$i/${rows} , seg_sz = ${seg_sz}"

    #--- Drawing :-p  !
	# the horizontal line with the end uva at the end of it
	## the horizontal line with the start uva at the end of it
	# the first actual print emitted!
	# Eg.
	# +----------------------------------------------------------------------+ 000055681263b000
	# Changed to end_va first we now always print in descending order
    if [ ${IS_64_BIT} -eq 1 ] ; then
	  # last loop iteration
      if [ "$1" = "-k" -a ${i} -eq $((${rows}-${DIM})) ] ; then
	     tput bold
         printf "%s %016lx\n" "${LIN_LAST_K}" ${X86_64_START_KVA}
		 color_reset
	  elif [ ${i} -ne 0 ] ; then
         printf "%s %016lx\n" "${LIN}" "${end_va}"
	  else   # very first line
	     tput bold
         if [ "${1}" = "-k" ] ; then
            printf "%s %016lx\n" "${LIN_FIRST_K}" "${end_va}"
		 #else
         #   printf "%s %016lx\n" "${LIN_FIRST_U}" "${end_va}"
		 fi
		 color_reset
	  fi
    else
      printf "%s %08x\n" "${LIN}" "${end_va}"
    fi

	#--- Collate and print the details of the current mapping (segment)
	# Eg.
	# |<... Sparse Region ...> [ 14.73 MB] [----,0x0]                        |

	# Print segment name
	tmp1=$(printf "%s|%20s " $(fg_orange) ${segname})
	local segname_nocolor=$(printf "|%20s " ${segname})

	# Colour and Print segment size according to scale; in KB or MB or GB or TB or PB
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
		tmp5a=$(printf "%s,%s" $(fg_black) "${perms}")
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
	   tmp5b=$(printf "%s%s%s," $(fg_blue) "${maptype}" $(fg_black))
	   tmp5b_nocolor=$(printf "%s," "${maptype}")
	   len_maptype=${#tmp5b_nocolor}

	   # file offset
	   tmp5c=$(printf "%s0x%s%s" $(fg_black) "${offset}" $(color_reset))
	   #tmp5c=$(printf "%s0x%s" $(fg_black) "${offset}")
	   tmp5c_nocolor=$(printf "0x%s" "${offset}")
	   len_offset=${#tmp5c_nocolor}
	fi

    # Calculate the strlen of the printed string, and thus calculate and print
    # the appropriate number of spaces after until the "|" close-box symbol.
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

	# the second actual print emitted!
    if [ ${tlen} -lt ${#LIN} ] ; then
		echo "${tmp1}${tmp2}${tmp3}${tmp4}${tmp5}${tmp7}${tmp5a}${tmp5b}${tmp5c}${tmp6}"
	else
		echo "${tmp1}${tmp2}${tmp3}${tmp4}${tmp5}${tmp7}${tmp5a}"
	fi

    #--- NEW CALC for SCALING
    # Simplify: We base the 'height' of each segment on the number of digits
    # in the segment size (in bytes)!
    segscale=${#seg_sz}    # strlen(seg_sz)
    [ ${segscale} -lt 4 ] && {   # min seg size is 4096 bytes
        echo "${name}: fatal error, segscale (# digits) <= 3! Aborting..."
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
    #[ ${box_height} -ge ${LIMIT_SCALE_SZ} ] && {
    [ ${box_height} -ge ${LARGE_SPACE} ] && {
   	  #box_height=${LIMIT_SCALE_SZ}
   	  oversized=1
    }

    #decho "box_height = ${box_height} oversized=${oversized}"
	local x
    for ((x=1; x<${box_height}; x++))
    do
   	  printf "%s\n" "${BOX_SIDES}"
   	  if [ ${oversized} -eq 1 ] ; then
        [ ${x} -eq $(((LIMIT_SCALE_SZ-4)/2)) ] && printf "%s\n" "${ELLIPSE_LIN}"
        #[ ${x} -eq $(((LIMIT_SCALE_SZ-1)/2)) ] && printf "%s\n" "${ELLIPSE_LIN}"
   	  fi
    done
    oversized=0
done

# address space: the 'end uva' virt address
if [ "${1}" = "-k" ] ; then
	tput bold
    if [ ${IS_64_BIT} -eq 1 ] ; then
	  printf "%s %016lx\n" "${LIN_FIRST_U}" "${X86_64_END_UVA}"
	  #printf "%s %016lx\n" "${LIN_LAST_K}" "${X86_64_START_KVA}"
	else
	  printf "%s %08x\n" "${LIN_FIRST_U}" "${X86_END_UVA}"
	  #printf "%s %08x\n" "${LIN_LAST_K}" "${X86_START_KVA}"
	fi
	color_reset
fi

# userspace: last line, the zero-th virt address; always:
#+----------------------------------------------------------------------+ 0000000000000000
if [ "$1" = "-u" ] ; then
   tput bold
   if [ ${IS_64_BIT} -eq 1 ] ; then
      printf "%s %016lx\n" "${LIN_LAST_U}" "${start_va}"
   else
      printf "%s %08x\n" "${LIN}" "${start_va}"
   fi
   color_reset
fi
} # end graphit()

