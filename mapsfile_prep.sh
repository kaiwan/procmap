#!/bin/bash
# prep_mapsfile.sh
# 
# Quick Description:
# Support script for the procmap project.
# Don't invoke this directly, run the 'procmap' wrapper instead.
# 
# Author:
# Kaiwan N Billimoria
# kaiwan -at- kaiwantech -dot- com
# kaiwanTECH
# License: MIT
PFX=$(dirname $(which $0 2>/dev/null))    # dir in which 'procmap' and tools reside
source ${PFX}/common.sh || {
 echo "${name}: fatal: could not source ${PFX}/common.sh , aborting..."
 exit 1
}
source ${PFX}/config || {
 echo "${name}: fatal: could not source ${PFX}/config , aborting..."
 exit 1
}

TMPF=/tmp/${name}/prep.$$
TMPF_R=${TMPF}.reversed
gencsv()
{
#sudo awk '{print $1, $6}' ${infile} > ${TMPF}
# CSV format for the foll fields:
#  start_uva,end_uva,mode/p|s,offset,image_file
sudo awk '{printf("%s,%s,%s,%s\n", $1,$2,$3,$6)}' ${infile} > ${TMPF}
sed --in-place 's/-/,/' ${TMPF}
sed --in-place 's/ /,/' ${TMPF}
# del comment lines
sed --in-place '/^#/d' ${TMPF}

# REVERSE the order of lines, thus ordering the VAS by descending va !!
tac ${TMPF} > ${TMPF_R} || {
  echo "tac(1) failed? aborting...(pl report as bug)"
  exit 1
}
cp ${TMPF_R} ${outfile}
rm -f ${TMPF} ${TMPF_R} 2>/dev/null
}


##### 'main' : execution starts here #####

[ $# -lt 2 ] && {
  echo "Usage: ${name} PID-of-process-for-maps-file output-filename.csv"
  exit 1
}

infile=/proc/$1/maps
outfile=$2

[ ! -r ${infile} ] && {
  echo "${name}: \"$1\" not readable (permissions issue)? aborting..."
  exit 1
}
[ -f ${outfile} ] && {
  decho "${name}: !WARNING! \"${outfile}\" exists, will be overwritten!"
}
gencsv
exit 0
