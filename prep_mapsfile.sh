#!/bin/bash
# prep_mapsfile.sh
# https://github.com/kaiwan/vasu_grapher.git
# 
# Quick Description:
# Support script for the vasu_grapher project.
# Don't invoke this directly, run the 'vasu_grapher' wrapper instead.
# 
# Author:
# Kaiwan N Billimoria
# kaiwan -at- kaiwantech -dot- com
# kaiwanTECH
# 
# License: # MIT License.
name=$(basename $0)
PFX=$(dirname $(which $0))    # dir in which 'vasu_grapher' and tools reside
source ${PFX}/common.sh || {
 echo "${name}: fatal: could not source ${PFX}/common.sh , aborting..."
 exit 1
}

TMPF=/tmp/prep.$$
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
cp ${TMPF} ${outfile}
rm -f ${TMPF}
}

##### 'main' : execution starts here #####

[ $# -ne 2 ] && {
  echo "Usage: ${name} PID-of-process-for-maps-file output-filename.csv"
  exit 1
}
infile=/proc/$1/maps
[ ! -r ${infile} ] && {
  echo "${name}: \"$1\" not readable (permissions issue)? aborting..."
  exit 1
}
[ -f $2 ] && {
  echo "${name}: !WARNING! \"$2\" exists, will be overwritten!"
  #exit 1
}
outfile=$2
gencsv
exit 0
