#!/bin/sh

# reloc.sh - relocate app for distribution
# usage: reloc.sh builddir bundle distdir
# - builddir e.g. release, bundle.app should live in this folder
# - bundle - bundle.app will be copied to distdir, and changes made to that copy. 
# - distdir - dir to do work. app bundle and libs copied here and modified in place. if this exists, will not run. Will not clobber.
#
# Assuming that exe name is same as bundle name, e.g. Contents/MacOS/bundle is the exe file

if [ $# -eq 4 ]
then
		
	BUILDDIR=$1	
	BUNDLE=$2
	LIBLIST=$3
	PKGLIST=""
	DISTDIR=$4
elif [ $# -eq 5 ]
then
	BUILDDIR=$1	
	BUNDLE=$2
	LIBLIST=$3
	PKGLIST=$4
	DISTDIR=$5
else
	echo "usage: reloc.sh BUILDDIR BUNDLE LIBLIST [PKGLIST] DISTDIR"
	exit -1
fi		
OSXRELOCATOR=`which osxrelocator`
MACDEPLOYQT=`which macdeployqt`

# if DISTDIR exists, make sure bundle isn't in it.
if [ -e $DISTDIR ]
then
	echo "DISTDIR already exists ($DISTDIR). Remove please."
	exit -1
fi

mkdir -p $DISTDIR
if [ $? -ne 0 ]
then
	echo "Cannot create $DISTDIR"
	exit -1
fi


###################################
# move/copy files to dist directory
###################################

# copy bundle to distdir
tar -C $BUILDDIR -cf - $BUNDLE.app | tar -C $DISTDIR -xf -

# mkdir Frameworks in app bundle
mkdir -p $DISTDIR/$BUNDLE.app/Contents/Frameworks

# Now copy files from $LIBLIST into 
tar -cf - --files-from $LIBLIST | tar -C $DISTDIR/$BUNDLE.app/Contents/Frameworks -xf -

# if defined, copy files from PKGLIST
if [ ! -z "$PKGLIST" ]
then
	echo "getting files from pkglist file $PKGLIST"
	while IFS= read -r pkg
	do
  		echo "getting files from pkg: $pkg"
  		tar -C /Library/Frameworks/GStreamer.Framework/Versions/Current -cf - `pkgutil --files $pkg | egrep '\.dylib$'` | tar -C $DISTDIR/$BUNDLE.app/Contents/Frameworks -xf -
	done < "$PKGLIST"
fi
###################################
# move/copy files to dist directory - done
###################################


#################################
# non-gstreamer libs and files
#################################

#################################
# non-gstreamer libs and files - done
#################################


#######################################################################################################
# relocate
#######################################################################################################

# executable
$OSXRELOCATOR $DISTDIR/$BUNDLE.app/Contents/MacOS /Library/Frameworks/GStreamer.framework/Versions/1.0 @executable_path/../Frameworks

# relocate gstreamer libs
$OSXRELOCATOR $DISTDIR/$BUNDLE.app/Contents/Frameworks /Library/Frameworks/GStreamer.framework/Versions/1.0 @rpath -r

# gst-plugin-scanner has no rpath. create one: @executable_path/../..
# two dirs up from @executable_path because gstreamer distribution has : libexec/gstreamer-1.0/gst-plugin-scanner
install_name_tool -add_rpath @executable_path/../.. $DISTDIR/$BUNDLE.app/Contents/Frameworks/libexec/gstreamer-1.0/gst-plugin-scanner

#######################################################################################################
# relocate - done
#######################################################################################################
$MACDEPLOYQT $DISTDIR/$BUNDLE.app




