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
name=$(basename $0)
PFX=$(dirname $(which $0))    # dir in which 'vasu_grapher' and tools reside
source ${PFX}/common.sh || {
 echo "${name}: fatal: could not source ${PFX}/common.sh , aborting..."
 exit 1
}

TMPF=/tmp/prep.$$
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

# If !-s option passed (default), reverse the order of lines, thus ordering
# the VAS by descending va !!
if [ ${ORDER_BY_DESC_VA} -eq 1 ] ; then
  tac ${TMPF} > ${TMPF_R}
  cp ${TMPF_R} ${outfile}
else
  cp ${TMPF} ${outfile}
fi
rm -f ${TMPF} ${TMPF_R} 2>/dev/null
}


##### 'main' : execution starts here #####

[ $# -lt 2 ] && {
  echo "Usage: ${name} [-s] PID-of-process-for-maps-file output-filename.csv"
  exit 1
}

infile=/proc/$1/maps
outfile=$2
if [ $# -eq 3 ] ; then
   [ "$1" = "-s" ] && ORDER_BY_DESC_VA=0
   infile=/proc/$2/maps
   outfile=$3
fi

[ ! -r ${infile} ] && {
  echo "${name}: \"$1\" not readable (permissions issue)? aborting..."
  exit 1
}
[ -f ${outfile} ] && {
  decho "${name}: !WARNING! \"${outfile}\" exists, will be overwritten!"
}
gencsv
echo "outfile = ${outfile}"
exit 0
