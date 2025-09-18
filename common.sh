#!/bin/bash
#------------------------------------------------------------------
# common.sh
#
# Common convenience routines
# 
# (c) Kaiwan N Billimoria
# kaiwan -at- kaiwantech -dot- com
# License: MIT
#------------------------------------------------------------------
export TOPDIR="$(pwd)"
#ON=1
#OFF=0
name=$(basename $0)
PFX=$(dirname "$(which $0 2>/dev/null)")    # dir in which 'procmap' and tools reside
source ${PFX}/err_common.sh || {
 echo "$name: could not source ${PFX}/err_common.sh, aborting..."
 exit 1
}
source ${PFX}/color.sh || {
 echo "$name: could not source ${PFX}/color.sh, aborting..."
 exit 1
}

prompt()
{
 [ $# -gt 0 ] && echo "$@" || printf "[Enter] to continue... "
 read
}

# runcmd
# Parameters
#   $1 ... : params are the command to run
runcmd()
{
[ $# -eq 0 ] && return
echo "$*"
eval "$*"
}

# ref: https://stackoverflow.com/questions/369758/how-to-trim-whitespace-from-a-bash-variable
trim() {
    local var="$*"
    # remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"   
    printf '%s' "$var"
}

# If we're not in a GUI (X Windows) display, abort (reqd for yad)
check_gui()
{
 which xdpyinfo > /dev/null 2>&1 || {
   FatalError "xdpyinfo (package x11-utils) does not seem to be installed. Aborting..."
 }
 xdpyinfo >/dev/null 2>&1 || {
   FatalError "Sorry, we're not running in a GUI display environment. Aborting..."
 }
 which xrandr > /dev/null 2>&1 || {
   FatalError "xrandr (package x11-server-utils) does not seem to be installed. Aborting..."
 }

 #--- Screen Resolution stuff
 res_w=$(xrandr --current | grep '*' | uniq | awk '{print $1}' | cut -d 'x' -f1)
 res_h=$(xrandr --current | grep '*' | uniq | awk '{print $1}' | cut -d 'x' -f2)
 centre_x=$((($res_w/3)+0))
 centre_y=$((($res_h/3)-100))
 CAL_WIDTH=$((($res_w/3)+200))
 CAL_HT=$(($res_h/3))
}


# genLogFilename
# Generates a logfile name that includes the date/timestamp
# Format:
#  ddMmmYYYY[_HHMMSS]
# Parameter(s)
# #$1 : String to prefix to log filename, null okay as well [required]
#  $1 : Include time component or not [required]
#    $1 = 0 : Don't include the time component (only date) in the log filename
#    $1 = 1 : include the time component in the log filename
genLogFilename()
{
 [ $1 -eq 0 ] && log_filename=$(date +%d%b%Y)
 [ $1 -eq 1 ] && log_filename=$(date +%d%b%Y_%H%M%S)
 echo ${log_filename}
}

vecho()
{
[ ${VERBOSE} -eq 0 ] && return
echo "[v] $*"
}

#---------- c h e c k _ d e p s ---------------------------------------
# Checks passed packages - are they installed? (just using 'which';
# using the pkg management utils (apt/dnf/etc) would be too time consuming)
# Parameters:
#  $1 : 1 => fatal error, exit
#       0 => warn only
# [.. $@ ..] : space-sep string of all packages to check
# Eg.        check_deps "make perf spatch xterm"
check_deps()
{
local util needinstall=0
#report_progress

local severity=$1
shift

for util in $@
do
 #echo "util = $util"
 which ${util} > /dev/null 2>&1 || {
   [ ${needinstall} -eq 0 ] && wecho "The following utilit[y|ies] or package(s) do NOT seem to be installed:"
   iecho "[!]  ${util}"
   needinstall=1
   continue
 }
done
if [ ${needinstall} -eq 1 ] ; then
   [ ${severity} -eq 1 ] && {
      FatalError "You must first install the required package(s) or utilities shown above \
(check console and log output too) and then retry, thanks. Aborting..."
   } || {
      wecho "WARNING! The package(s) shown above are not present"
   }
fi
} # end check_deps()

# Simple wrappers over check_deps();
# Recall, the fundamental theorem of software engineering FTSE:
#  "We can solve any problem by introducing an extra level of indirection."
#    -D Wheeler
# ;-)
check_deps_fatal()
{
check_deps 1 "$@"
}

check_deps_warn()
{
check_deps 0 "$@"
}

verify_utils_present()
{
[ ! -d /proc ] && FatalError "proc fs not available or not mounted? Aborting..." || true
check_deps_fatal "getconf bc make gcc kmod grep awk sed kill readlink head tail \
cut cat tac sort wc ldd file"
check_deps_warn "sudo tput ps smem"
# need yad? GUI env?
which xdpyinfo > /dev/null 2>&1 && check_deps_warn "yad" || true
# need dtc? -only on systems that use the DT
[[ -d /proc/device-tree ]] && check_deps_fatal "dtc" || true
}

## isathread
# Param: PID
# Returns:
#   1 if $1 is a (worker/child) thread of some process, 0 if it's a process by itself, 127 on failure.
isathread()
{
[ $# -ne 1 ] && {
 aecho "isathread: parameter missing!" 1>&2
 return 127
}

PARENT_PROCESS=${PID}
local t1=$(ps -LA|grep -w "${PID}" |head -n1)
local pid=$(echo ${t1} |cut -d' ' -f1)
local lwp=$(echo ${t1} |cut -d' ' -f2)
[[ ${pid} -eq ${lwp} ]] && return 0 || {
	PARENT_PROCESS=${pid}
	return 1
  }
}
