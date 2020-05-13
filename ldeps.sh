#!/bin/sh

LIBFILE=$1
if [ ! -e $LIBFILE ]
then
	echo "arg should be a libfile"
	echo "will list dynamic load libs listed in the file, with the following omitted: Qt frameworks, system stuff (/usr/lib and /System)"
	exit -1
fi

otool -L $LIBFILE | tail -n +2 | grep -v -e '^\s/System' | grep -v -e '^\s@rpath/Qt' | grep -v -e '^\s/usr/lib' | awk '{print $1}'| grep -v $LIBFILE
