#!/bin/bash
#------------------------------------------------------------------
# color.sh
#
# Common convenience routines for color support in bash.
# 
# (c) Kaiwan N Billimoria
# kaiwan -at- kaiwantech -dot- com
# MIT / GPL v2
#------------------------------------------------------------------
# The SEALS Opensource Project
# SEALS : Simple Embedded Arm Linux System
# Maintainer : Kaiwan N Billimoria
# kaiwan -at- kaiwantech -dot- com
# Project URL:
# https://github.com/kaiwan/seals

#------------------- Colors!! Yay :-) -----------------------------------------
# Ref: https://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux
# [Ans by Drew Noakes]
# Useful Ref! https://i.stack.imgur.com/a2S4s.png

#--- Foreground Colors
fg_black() { tput setaf 0 
}
fg_red() { tput setaf 1
}
fg_orange() { tput setaf 166
}
fg_green() { tput setaf 2 
}
fg_yellow() { tput setaf 3
}
fg_blue() { tput setaf 4
}
fg_magenta() { tput setaf 5
}
fg_cyan() { tput setaf 6
}
fg_white() { tput setaf 7
}
fg_grey() { tput setaf 8
}
 
#--- Background Colors
bg_white() { tput setab 7
}
bg_gray() { tput setab 250
}
bg_red() { tput setab 1
}
bg_green() { tput setab 2
}
bg_yellow() { tput setab 3
}
bg_blue() { tput setab 4
}
bg_cyan() { tput setab 6
}

#--- Text Attributes  <-- NOK!
#tb=$(tput bold)  # bold
#tsb=$(tput smso)  # enter standout bold mode
#trb=$(tput rmso)  # exit standout bold mode
#trev=$(tput rev)  # reverse video
#tdim=$(tput dim)  # half-brightness
#tBell=$(tput bel)  # sound bell!

#--- Composite text attribs [ta] <-- NOK!
#taErr="${tb}${fg_red}${bg_white}${tBell}"
#taTitle="${tb}${fg_black}${bg_yellow}"
#taReg=""  # 'regular' msgs
#taBold="$(tput bold)"
#taBold="${tb}"
#taAbnormal="${fg_white}${bg_blue}"  # 'Abnormal' msgs - error msgs,...
#taDebug="${tdim}"

#  Reset text attributes to normal without clearing screen.
color_reset()
{ 
   tput sgr0 
} 

#--------------------- E c h o ----------------------------------------
# The _base_ echo/logging function.
# Parameters:
# $1        : a tag that speicifies the logging level
# $2 ... $n : message to echo (to stdout and logfile)
#
# Logging Levels (from low->high 'criticality') are:
# --------     --------
# LogLevel     Function
# --------     --------
#  DDEBUG      decho
#  INFO        iecho
#  ALERT       aecho  [bold]
#  WARN        wecho
#  CRIT        cecho
#  TITL        techo <-- exception: this is NOT really a loglevel,
#               it's a special display attribute
# !WARNING! 
# Ensure you don't call any of the x[Ee]cho functions from here, as they
# call this func and it becomes infinitely recursive.
Echo()
{
 local SEP=" "
# echo "# = $# : params: $@"
 [ $# -eq 0 ] && return 1
 local numparams=$#
 local tag="${1}"
 [ ${numparams} -gt 1 ] && shift  # get rid of the tag, so that we can access the txt msg

 # Prefix the logging level : debug/info/warn/critical
 local loglevel
  # maintaining 4-char strings for 'loglevel' alleviates the need for more
  # code with printf etc
 case "${tag}" in
   DDEBUG) loglevel="dbug"
         ;;
   INFO)  loglevel="info"
         ;;
   ALERT)  loglevel="alrt"
         ;;
   WARN) loglevel="warn"
         ;;
   CRIT) loglevel="crit"
         ;;
   TITL) loglevel="titl"
         ;;
   *) loglevel="    "
         ;;
 esac

 local dt_log="[$(date +%a_%d%b%Y_%T.%N)]"
 local dt_disp
 [ ${VERBOSE_MSG} -eq 1 ] && dt_disp=${dt}

 local msgpfx1_log="[${loglevel}]${SEP}${dt_log}"
 local msgpfx1_disp="${dt}"
 [ ${VERBOSE_MSG} -eq 1 ] && msgpfx1_disp="${msgpfx1_log}"

 local msgpfx2_log="${SEP}${name}:${FUNCNAME[ 1 ]}()${SEP}"
 local msgpfx2_disp
 [ ${VERBOSE_MSG} -eq 1 ] && msgpfx2_disp="${msgpfx2_log}"

 local msgtxt="$@"
 local msgfull_log="${msgpfx1_log}${msgpfx2_log}${msgtxt}"
 local msg_disp="${msgpfx1_disp}${SEP}${msgtxt}"
 [ ${VERBOSE_MSG} -eq 1 ] && msg_disp="${msgfull_log}"

 # lets log it first anyhow
 [ -f ${LOGFILE_COMMON} ] && echo "${msgfull_log}" >> ${LOGFILE_COMMON}  

 if [ ${numparams} -eq 1 -o ${COLOR} -eq 0 ]; then   # no color/text attribute
    [ ${DEBUG} -eq 1 ] && echo "${msgfull_log}" || echo "${msg_disp}"
    return 0
 fi

 #--- 'color' or text attrib present!
 fg_green
 echo -n "${msgpfx1_disp}${SEP}"
 [ ${DEBUG} -eq 1 -o ${VERBOSE_MSG} -eq 1 ] && {
   fg_blue
   echo -n "${msgpfx2_disp}"
 }
 color_reset                      # Reset to normal.
 
 case "${tag}" in
   DDEBUG) tput dim ; fg_cyan #fg_magenta
         ;;
   INFO)  #tput        # Deliberate: no special attribs for 'info'
         ;;
   ALERT) tput bold
         ;;
   WARN) fg_red ; bg_yellow ; tput bold
         ;;
   CRIT) fg_white ; bg_red ; tput bold
         ;;
   TITL) fg_black ; bg_yellow ; tput bold
         ;;
 esac
 echo "${msgtxt}"
 color_reset                      # Reset to normal.
 return 0
} # end Echo()

#--- Wrappers over Echo follow ---
# Parameters:
# $1 : message to echo (to stdout and logfile)

#--------------------- d e c h o --------------------------------------
# DEBUG-level echo :-)
decho()
{
 [ ${DEBUG} -eq 1 ] && Echo DDEBUG "$1"
}
#--------------------- i e c h o ---------------------------------------
# INFO-level / regular Color-echo.
iecho ()
{
 Echo INFO "$1"
}
#--------------------- a e c h o ---------------------------------------
# ALERT-level Color-echo.
aecho ()
{
 Echo ALERT "$1"
}
#--------------------- w e c h o ---------------------------------------
# WARN-level Color-echo.
wecho ()
{
 Echo WARN "$1"
}
#--------------------- c e c h o ---------------------------------------
# CRITical-level Color-echo.
cecho ()
{
 Echo CRIT "$1"
}

#--------------------- t e c h o ---------------------------------------
# Title Color-echo.
techo ()
{
 Echo TITL "$1"
}
#---

# ShowTitle
# Display a string in "title" form
# Parameter(s):
#  $1 : String to display [required]
ShowTitle()
{
	techo "$1"
}


test_256()
{
for i in $(seq 0 255)
do
  tput setab $i
  printf '%03d ' $i
done
color_reset
}
