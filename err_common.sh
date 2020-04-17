#!/bin/sh
#------------------------------------------------------------------
# err_common.sh
#
# Common error handling routines.
# 
# (c) Kaiwan N Billimoria
# kaiwan -at- kaiwantech -dot- com
# MIT / GPL v2
#------------------------------------------------------------------
export TOPDIR=$(pwd)
export VERBOSE_MSG=0
export DEBUG=0
# Replace with log filename
export LOGFILE_COMMON=/dev/null 
export COLOR=1

#--- Icons
# src: /usr/share/icons/Humanity/actions/
ICON_NEXT=go-next
ICON_BACK=go-previous
ICON_YES=add  #go-next
ICON_NO=remove   #gtk-remove
ICON_ADD=add  #gtk-add
ICON_REGISTER=player_record
ICON_SIGNIN=format-text-direction-ltr
ICON_EXIT=stock_mark   #system-log-out


# QP
# QuickPrint ;-)
# Print timestamp, script name, line#. Useful for debugging.
# [RELOOK / FIXME : not really useful as it doen't work as a true macro;
#  just prints _this_ script name, line#.]
QP()
{
	_ERR_HDR_FMT="%.23s %s[%s]: "
	_ERR_MSG_FMT="${_ERR_HDR_FMT}%s\n"
    [ ${COLOR} -eq 1 ] && fg_blue
	printf " QP: $_ERR_MSG_FMT" $(date +%F.%T.%N) " ${BASH_SOURCE[1]##*/}:${FUNCNAME[2]}" |tee -a ${LOGFILE_COMMON}
	dumpstack
	#printf " QP: $_ERR_MSG_FMT" $(date +%F.%T.%N) " ${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}" |tee -a ${LOGFILE_COMMON}
    [ ${COLOR} -eq 1 ] && color_reset
	unset _ERR_HDR_FMT
	unset _ERR_MSG_FMT
}

STACK_MAXDEPTH=32  # arbit?
dumpstack()
{
#for frame in $(seq 1 $1)
local frame=1
local funcname

ShowTitle " Stack Call-trace:"
[ ${COLOR} -eq 1 ] && fg_blue
while [ true ]
do
  funcname=${FUNCNAME[${frame}]}
  printf "   [frame #${frame}] ${BASH_SOURCE[${frame}]}:${funcname}:${BASH_LINENO[${frame}]}"
  #printf "   [frame #${frame}] ${funcname}"
  [ ${frame} -ne 1 ] && printf "\n" || {
    [ ${COLOR} -eq 1 ] && fg_magenta
    printf "        <-- top of stack\n"
    [ ${COLOR} -eq 1 ] && fg_blue
  }
  [ "${funcname}" = "main" ] && break  # stop, reached 'main'
  [ ${frame} -ge ${STACK_MAXDEPTH} ] && break  # just in case ...
  let frame=frame+1
done |tee -a ${LOGFILE_COMMON}
[ ${COLOR} -eq 1 ] && color_reset
}

# params: the error message
cli_handle_error()
{
  #QP
  if [ $# -lt 1 ] ; then
	cecho "FatalError :: <no errmsg>"
  else
	cecho "FatalError :: $@"
  fi
  dumpstack
  [ ${COLOR} -eq 1 ] && color_reset
  exit 1
}

#--------------------- F a t a l E r r o r ----------------------------
# Exits with exit status 1 !
# Parameters:
# $1 : error message [optional]
FatalError()
{
 local msgpre="<b><span foreground='Crimson'>Sorry, we've encountered a fatal error.</span></b>\n\n"
 local errmsg="<i>Details:</i>\n$(date):${name}:${FUNCNAME[ 1 ]}()"
 local msgpost="\n<span foreground='Crimson'>\
If you feel this is a bug / issue, kindly report it here:</span>
${SEALS_REPORT_ERROR_URL}\n
Many thanks.
"

 [ $# -ne 1 ] && {
  local msg="${msgpre}<span foreground='NavyBlue'>${errmsg}</span>\n${msgpost}"
 } || {
  local msg="${msgpre}<span foreground='NavyBlue'>${errmsg}\n ${1}</span>\n${msgpost}"
 }
 #cecho "Fatal Error! Details: ${errmsg} ${1}"

 local LN=$(echo "${MSG}" |wc -l)
 local calht=$(($LN*10))

 local title=" FATAL ERROR!"
 yad --title="${title}" --image=dialog-warning --text="${msg}" \
	--button="Close!${ICON_NO}:0" \
	--wrap --text-align=center --button-layout=center --center \
	--selectable-labels --no-escape --dialog-sep --sticky --on-top --skip-taskbar 2>/dev/null

 cli_handle_error "$@"
 exit 1
} # end FatalError()

# Prompt
# Interactive: prompt the user to continue by pressing ENTER or
# abort by pressing Ctrl-C
# Parameter(s):
#  $1 : string to display (string)
#  $2 : string to display on signal trap [optional]
Prompt()
{
  local msg="*** User Abort detected!  ***"

 trap 'wecho "${msg}" ; dumpstack ; color_reset ; exit 3' INT QUIT

 [ ${COLOR} -eq 1 ] && fg_magenta
 echo "Press ENTER to continue, or Ctrl-C to abort now..."
 read
 [ ${COLOR} -eq 1 ] && color_reset
} # end Prompt()
