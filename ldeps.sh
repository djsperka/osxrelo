#!/bin/sh

LIBFILES=$*
for ifile in $LIBFILES
do
	
	if [ ! -e $ifile ]
	then
		echo "file not found: $ifile"
		echo "will list dynamic load libs listed in the file, with the following omitted: Qt frameworks, system stuff (/usr/lib and /System)"
		exit -1
	fi
	otool -L $ifile | tail -n +2 | grep -v -e '^\s/System' | grep -v -e '^\s@rpath/Qt' | grep -v -e '^\s/usr/lib' | awk '{print $1}'| grep -v $ifile
done