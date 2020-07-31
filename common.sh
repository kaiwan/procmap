#!/bin/sh
#------------------------------------------------------------------
# common.sh
#
# Common convenience routines
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

export TOPDIR=$(pwd)
ON=1
OFF=0

PFX=$(dirname $(which $0))    # dir in which 'vasu_grapher' and tools reside
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
echo "$@"
eval "$@"
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

# mysudo
# Simple front end to gksudo/sudo
# Parameter(s):
#  $1 : descriptive message
#  $2 ... $n : command to execute
mysudo()
{
[ $# -lt 2 ] && {
 #echo "Usage: mysudo "
 return
}
local msg=$1
shift
local cmd="$@"
aecho "${LOGNAME}: ${msg}"
sudo --preserve-env sh -c "${cmd}"
}

# check_root_AIA
# Check whether we are running as root user; if not, exit with failure!
# Parameter(s):
#  None.
# "AIA" = Abort If Absent :-)
check_root_AIA()
{
	if [ `id -u` -ne 0 ]; then
		Echo "Error: need to run as root! Aborting..."
		exit 1
	fi
}

# check_file_AIA
# Check whether the file, passed as a parameter, exists; if not, exit with failure!
# Parameter(s):
#  $1 : Pathname of file to check for existence. [required]
# "AIA" = Abort If Absent :-)
# Returns: 0 on success, 1 on failure
check_file_AIA()
{
	[ $# -ne 1 ] && return 1
	[ ! -f $1 ] && {
		Echo "Error: file \"$1\" does not exist. Aborting..."
		exit 1
	}
}

# check_folder_AIA
# Check whether the directory, passed as a parameter, exists; if not, exit with failure!
# Parameter(s):
#  $1 : Pathname of folder to check for existence. [required]
# "AIA" = Abort If Absent :-)
# Returns: 0 on success, 1 on failure
check_folder_AIA()
{
	[ $# -ne 1 ] && return 1
	[ ! -d $1 ] && {
		Echo "Error: folder \"$1\" does not exist. Aborting..."
		exit 1
	}
}

# check_folder_createIA
# Check whether the directory, passed as a parameter, exists; if not, create it!
# Parameter(s):
#  $1 : Pathname of folder to check for existence. [required]
# "IA" = If Absent :-)
# Returns: 0 on success, 1 on failure
check_folder_createIA()
{
	[ $# -ne 1 ] && return 1
	[ ! -d $1 ] && {
		Echo "Folder \"$1\" does not exist. Creating it..."
		mkdir -p $1	&& return 0 || return 1
	}
}


# GetIP
# Extract IP address from ifconfig output
# Parameter(s):
#  $1 : name of network interface (string)
# Returns: IPaddr on success, non-zero on failure
GetIP()
{
	[ $# -ne 1 ] && return 1
	ifconfig $1 >/dev/null 2>&1 || return 2
	ifconfig $1 |grep 'inet addr'|awk '{print $2}' |cut -f2 -d':'
}

# get_yn_reply
# User's reply should be Y or N.
# Returns:
#  0  => user has answered 'Y'
#  1  => user has answered 'N'
get_yn_reply()
{
aecho -n "Type Y or N please (followed by ENTER) : "
str="${@}"
while true
do
   aecho ${str}
   read reply

   case "$reply" in
   	y | yes | Y | YES ) 	return 0
			;;
   	n* | N* )		return 1
			;;	
   	*) aecho "What? Pl type Y / N"
   esac
done
}

# MountPartition
# Mounts the partition supplied as $1
# Parameters:
#  $1 : device node of partition to mount
#  $2 : mount point
# Returns:
#  0  => mount successful
#  1  => mount failed
MountPartition()
{
[ $# -ne 2 ] && {
 aecho "MountPartition: parameter(s) missing!"
 return 1
}

DEVNODE=$1
[ ! -b ${DEVNODE} ] && {
 aecho "MountPartition: device node $1 does not exist?"
 return 1
}

MNTPT=$2
[ ! -d ${MNTPT} ] && {
 aecho "MountPartition: folder $2 does not exist?"
 return 1
}

mount |grep ${DEVNODE} >/dev/null || {
 #echo "The partition is not mounted, attempting to mount it now..."
 mount ${DEVNODE} -t auto ${MNTPT} || {
  wecho "Could not mount the '$2' partition!"
  return 1
 }
}
return 0
}

## is_kernel_thread
# Param: PID
# Returns:
#   1 if $1 is a kernel thread, 0 if not, 127 on failure.
is_kernel_thread()
{
[ $# -ne 1 ] && {
 aecho "is_kernel_thread: parameter missing!" 1>&2
 return 127
}

prcs_name=$(ps aux |awk -v pid=$1 '$2 == pid {print $11}')
#echo "prcs_name = ${prcs_name}"
[ -z ${prcs_name} ] && {
 wecho "is_kernel_thread: could not obtain process name!" 1>&2
 return 127
}

firstchar=$(echo "${prcs_name:0:1}")
#echo "firstchar = ${firstchar}"
len=${#prcs_name}
let len=len-1
lastchar=$(echo "${prcs_name:${len}:1}")
#echo "lastchar = ${lastchar}"
[ ${firstchar} = "[" -a ${lastchar} = "]" ] && return 1 || return 0
}


# trim_string_middle()
# Given a string ($1), if it's above the 'allowed' length, express it in 2
# parts seperated by the ellipse '...'
# Eg. the pathname
#   /usr/lib/gnome-settings-daemon/gsd-screensaver-proxy
# becomes:
#   /usr/lib/gnome-settings-d...emon/gsd-screensaver-proxy
#
# Parameters:
#  $1 : string to process
#  $2 : max length of final string
# Do Not echo anything other than the name here, as it's the 'return value'
trim_string_middle()
{
 local NM_MAXLEN=$(($2-3)) # leave chars for '...'
 local NM_MAXLEN_HALF=$((${NM_MAXLEN}/2))
 local nmlen=${#1}

 if [ ${nmlen} -le ${NM_MAXLEN} ]; then
    echo "${1}"
 else
	local remlen=$((nmlen-NM_MAXLEN_HALF))
	local n1=$(echo "${1}"|cut -c-${NM_MAXLEN_HALF})
	local n2=$(echo "${1}"|cut -c${remlen}-)
	local final="${n1}...${n2}"
	printf "%s...%s" ${n1} ${n2}
 fi
}

vecho()
{
[ ${VERBOSE} -eq 0 ] && return
echo "[v] $@"
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
 which ${util} > /dev/null 2>&1 || {
   [ ${needinstall} -eq 0 ] && wecho "The following utilit[y|ies] or package(s) do NOT seem to be installed:"
   iecho "[!]  ${util}"
   needinstall=1
   continue
 }
done
[ ${needinstall} -eq 1 ] && {
   [ ${severity} -eq 1 ] && {
      FatalError "Kindly first install the required package(s) shown above \
(check console and log output too) and then retry, thanks. Aborting now..."
   } || {
      wecho "WARNING! The package(s) shown above are not present"
   }
}
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
check_deps_fatal "getconf bc make gcc kmod grep awk sed kill readlink head tail \
cut cat tac sort wc ldd file"
check_deps_warn "sudo tput ps smem"
[ ! -d /proc ] && FatalError "proc fs not available or not mounted? Aborting..."
}

