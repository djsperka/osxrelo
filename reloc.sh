#!/bin/sh

# reloc.sh - relocate app for distribution
# usage: reloc.sh builddir bundle distdir
# - builddir e.g. release, bundle.app should live in this folder
# - bundle - bundle.app will be copied to distdir, and changes made to that copy. 
# - distdir - dir to do work. app bundle and libs copied here and modified in place. if this exists, will not run. Will not clobber.
#
# Assuming that exe name is same as bundle name, e.g. Contents/MacOS/bundle is the exe file

if [ $# -ne 3 ]
then
	echo "usage: reloc.sh BUILDDIR BUNDLE DISTDIR"
	exit -1
fi

BUILDDIR=$1	
BUNDLE=$2
DISTDIR=$3

DEPLIST=$DISTDIR/deps.txt

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

# move gstreamer libs in file 'gstreamer.txt'
# Need to create gstreamer.txt. This file is input to tar and specifies the files to
# copy. The gstreamer framework is a unix-style structure (lib/, bin/, libexec/), so set 
# up the gstreamer.txt file like this:
#
# -C
# /Library/Frameworks/GStreamer.framework/Versions/1.0
# lib/libgstreamer-1.0.0.dylib
# ...(more libs req'd by exe or by plugins)
# lib/gstreamer-1.0/libgstvideotestsrc.dylib
# ...(plugin libs that you need)
# bin/ (I don't think you need these, but gst-inspect is useful for debugging.)
# libexec/ (gst-plugin-scanner needed, GST_PLUGIN_SCANNER points to it and 
# is called in gst_init
# lib/gio (need this, env var for it)
# 
# 

tar -cf - --files-from gstreamer.txt | tar -C $DISTDIR/$BUNDLE.app/Contents/Frameworks -xf -

###################################
# move/copy files to dist directory - done
###################################


#################################
# non-gstreamer libs and files
#################################

# move other libs in file 'other.txt'
#tar -cf - --files-from other.txt | tar -C $DISTDIR/$BUNDLE.app/Contents/Frameworks -xf -

# move other libs in file 'myplugin.txt'
#tar -cf - --files-from myplugin.txt | tar -C $DISTDIR/$BUNDLE.app/Contents/Frameworks/lib/gstreamer-1.0 -xf -

# move stimuli
#mkdir -p $DISTDIR/$BUNDLE.app/Contents/Stimuli
#tar cf - --files-from stimuli.txt | tar -C $DISTDIR/$BUNDLE.app/Contents/Stimuli -xf -

# my config file. This will be custom-per-experiment as will stimuli
#tar cf - first.json | tar -C $DISTDIR/$BUNDLE.app/Contents/Stimuli -xf -

#################################
# non-gstreamer libs and files - done
#################################


#######################################################################################################
# relocate - osxrelocator traverses a directory structure (files with no extension, or ".dylib", ".so".
#            my hack also gets the "*-1.0" executables
#######################################################################################################
  
# exe first
# Here is where build settings matter. If you use pkg-config against gstreamer, then you 
# get these settings:
#
# pkg-config --libs gstreamer-1.0:
# -L/Library/Frameworks/GStreamer.framework/Versions/1.0/lib -lgstreamer-1.0 -lgobject-2.0 -lglib-2.0 -lintl
# 
# The load path for the gstreamer libs is a full path. Change the paths so they are relative to 
# the executable file. Given the osx bundle structure, make the substitution replacing 
# "/Library/Frameworks/GStreamer.framework/Versions/1.0" with 
# "@executable_path/../Frameworks"
# 
# The way the paths are split up in 'gstreamer.txt' file dictates how this is done. 
# You can (apparently) do pretty much whatever you want in the app bundle. Qt will hang its 
# frameworks off this (and an rpath is set for it)
osxrelocator $DISTDIR/$BUNDLE.app/Contents/MacOS /Library/Frameworks/GStreamer.framework/Versions/1.0 @executable_path/../Frameworks

# relocate gstreamer libs
osxrelocator -r $DISTDIR/$BUNDLE.app/Contents/Frameworks /Library/Frameworks/GStreamer.framework/Versions/1.0 @rpath

# gst-plugin-scanner has no rpath. create one: @executable_path/../..
# two dirs up from @executable_path because gstreamer distribution has : libexec/gstreamer-1.0/gst-plugin-scanner
install_name_tool -add_rpath @executable_path/../.. $DISTDIR/$BUNDLE.app/Contents/Frameworks/libexec/gstreamer-1.0/gst-plugin-scanner



#######################################################
# relocate libs included in dist that are not gstreamer 
#######################################################
#osxrelocator $DISTDIR/$BUNDLE.app/Contents/MacOS /usr/local/opt/boost @executable_path/../Frameworks




