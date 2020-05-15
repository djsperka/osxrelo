# How to relocate a gstreamer/Qt application for distribution

This doc is a core dump of the process - the short version is this:

1. Project assumptions & setup

   Qt/GStreamer project. Your project's #\*.pro# file is the root of all, so the version of  *qmake* determines version of Qt throughout. The build will also use pkg-config for gstreamer (but need a workaround qmake seems broken unless run from command line). Use *PKG_CONFIG_DIR* to specify version&location of gstreamer used throughout. It helps to make the project have a build dir that also depends on build type (release/debug).
   
1. Set up exe to run correctly when installed (set env vars - can be done outside for testing obv) or not installed (i.e. on your machine when dev&testing). 
1. Generate dependency list, create input file for reloc.sh script. This file must be updated if plugin list changes.
1. run reloc.sh, test by running from cmd line (without args), then double-click. Run otool -L on entire app bundle, grep for /Library/Frameworks (and /usr/local/lib et al if you use such things). Common crash error is loading gstreamer (and hence glib) from two different libraries (and a reference to your developer libs remains) - glib crashes right away. Another would be having left out plugins - depends on how the app handles failure of gstreamer factory methods.
1. (TODO) run script to generate dmg and/or pkg. 

Applications that use dynamic libraries have "load commands" in the executable file (dynamic libraries also have load commands). The "load commands" tell the dynamic loader where to find a particular dynamic library needed by the executable (or library). The command can have an absolute path to a library, or it can have a path *relative to* one of several special variables whose exact path is determined at load time. Commands otool -L (brief list of dep libs), otool -l (full dump, including RPATHs if there)

If you copy the application to another machine (or to another location on your own machine), the application may or may not run, depending on whether the system can load the dynamic libraries it needs at run time. If user machine has Qt and GStreamer installed in same config as your build machine, then the app should run.

System libraries (contained in /usr/lib, /System/Libraries) are linked with absolute filenames in their load commands, and do not need to be changed - you can safely assume they are present on any mac system (at least one that respects your applications *MINIMUM_SYSTEM_VERSION*. This procedure ignores these system libraries -- *ldeps.sh* filters them out. 

Here I'll outline a procedure to modify your application bundle so it can be copied to another machine and run properly. Its a procedure, and it requires your intervention to make it all work.

## Prerequisites

*osxrelocator* - A project exists which forked this tool from gstreamer. It must be installed in the same python dist that you use throughout, I assume python3 throughout. My python dist is a mess - I prob have>5 installations in various places. After settling on using homebrew I found that everything worked. I cloned the repo & ran setup.py from there, but running pip3 (in same dist) against the pypi dist should work.

*XCode dev tools* - I've only done this with these, not homebrew gcc or clang. In theory those can work fine given the right libs. Good luck.

## GStreamer framework 

I am working with the latest version of GStreamer on the mac (1.16 at this writing). The lib/ folder has two components. The lib/ folder itself (not its subfolders) has general purpose libs that plugins and applications can use. These are linked with the full path to the installed libs. The lib/gstreamer-1.0 folder contains plugin dylibs. These are linked to the libraries in lib/ with a relative path in them, something like *@rpath/lib/libgstvideo-1.0.0.dylib*, so those links are not modified - just make sure the exe file has rpath in it that points to the correct location in the bundle (@executable_path+something else). All libs contain a load command to themselves, it seems, and that's hard-coded AFAICT, so *osxrelocator* should  be run recursively on bundle/Contents/Frameworks. 

## Qt license

Qt open source license allows redist of dependent libs, I'm not sure about other license types. 

Qt includes a deployment tool with its distribution on mac, called *macdeployqt*. This application modifies an app bundle to incorporate the Qt libraries inside it, and changes any load commands necessary to make the app work when moved to another machine. 

## Libraries that are neither system, Qt, or gstreamer

If your app uses other dynamic libraries, the *macdeployqt* tool will move them to your app bundle and change load commands appropriately. Its probably the case that you can allow *macdeployqt* to relocate these libraries, or you can manage the relocation yourself. In this procedure, I do the latter. YMMV. 

TODO - allow for turning macdeployqt step off to allow for insertion of other libs into bundle. 


## Generate list of libs your app requires

Use *ldeps.sh*. It runs the *otool* command to extract the list of loader paths. For my app the output looks like this:

```shell
1220 dan:relosx$ ./ldeps.sh ../habit2-src/apps/gstsp/release/gstsp.app/Contents/MacOS/gstsp 
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgstreamer-1.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgobject-2.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libglib-2.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libintl.8.dylib
/usr/local/opt/boost/lib/libboost_filesystem.dylib
```

The first four libs are gstreamer and glib, which will be linked into just about every gstreamer application. The boost library is one which I use for its file path handling, but which is not used by gstreamer. 

The generation of dependent libraries should be done for the gstreamer libs separate from any other libs because the type of loader commands may be different. 

Filter out the non-gstreamer libs and capture in a list file like this:

```script
1256 dan:relosx$ ./ldeps.sh ../habit2-src/apps/gstsp/release/gstsp.app/Contents/MacOS/gstsp | grep -E '^/Library/Frameworks/GStreamer' > deps.txt
1257 dan:relosx$ cat deps.txt 
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgstreamer-1.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgobject-2.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libglib-2.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libintl.8.dylib
```
## add plugin libraries to your list

This step is a little tedious. Only you know what plugins your application loads, normally because they are not linked directly but loaded when needed when gstreamer creates the element(s). In my application, the plugins are *videotestsrc*, *videoconvert*, *osxvideosink*, *fakesink*, *audiotestsrc*, *audiomixer*, *osxaudiosink*. 

Find the full paths to the dylib files corresponding to the plugins you use. For most of them, I've found that searching the plugin dir for files with the plugin name in them works pretty well. For *videotestsrc* I did this:

```scipt
1260 dan:relosx$ ls /Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/*videotestsrc*dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstvideotestsrc.dylib
```

This didn't work for *osxvideosink* or *osxaudiosink*. The foolproof method is to use *gst-inspect-1.0* with the plugin name as argument. Look for the label **Filename** under **Plugin Details** -- that's the name of the dylib. Append it to your list. 

```script
1270 dan:relosx$ gst-inspect-1.0 osxvideosink
Factory Details:
  Rank                     marginal (64)
  Long-name                OSX Video sink
  Klass                    Sink/Video
  Description              OSX native videosink
  Author                   Zaheer Abbas Merali <zaheerabbas at merali dot org>

Plugin Details:
  Name                     osxvideo
  Description              OSX native video output plugin
  Filename                 /Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstosxvideo.dylib
  Version                  1.16.2
  License                  LGPL
  Source module            gst-plugins-good
  Binary package           GStreamer Good Plug-ins source release
  Origin URL               Unknown package origin

==========CUT=========
```

When its all said and done, here is what my file looks like:

```script
1286 dan:relosx$ cat deps.txt 
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgstreamer-1.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgobject-2.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libglib-2.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libintl.8.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstvideotestsrc.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstvideoconvert.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstosxvideo.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstosxaudio.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstaudiomixer.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstcoreelements.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstaudiotestsrc.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstvideoscale.dylib
```

## Generate list of dependencies using your list of dylibs

The dylibs you've got now each has their own list of dynamic libs. The loader paths used within the libraries themselves are different, but it will be clear what libraries are referenced. Run the following to generate your first list:

```script
1290 dan:relosx$ ./ldeps.sh `cat deps.txt` | sort | uniq
@rpath/lib/libffi.7.dylib
@rpath/lib/libglib-2.0.0.dylib
@rpath/lib/libgmodule-2.0.0.dylib
@rpath/lib/libgobject-2.0.0.dylib
@rpath/lib/libgstaudio-1.0.0.dylib
@rpath/lib/libgstbase-1.0.0.dylib
@rpath/lib/libgstreamer-1.0.0.dylib
@rpath/lib/libgstvideo-1.0.0.dylib
@rpath/lib/libintl.8.dylib
@rpath/lib/liborc-0.4.0.dylib
```

There are a few here that weren't in the original list. Munge them to form complete filenames (they're in the same gstreamer directory structure) - replace *@rpath* with */Library/Frameworks/GStreamer.framework/Versions/1.0* and append to the list. After this is done, my list looks like this:

```script
1291 dan:relosx$ cat deps.txt
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgstreamer-1.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgobject-2.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libglib-2.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libintl.8.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstvideotestsrc.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstvideoconvert.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstosxvideo.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstosxaudio.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstaudiomixer.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstcoreelements.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstaudiotestsrc.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstvideoscale.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libffi.7.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgmodule-2.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgstaudio-1.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgstbase-1.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgstvideo-1.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libintl.8.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/liborc-0.4.0.dylib
```
Now I run *ldeps* again and I get one additional library (this one is *libgsttag-1.0.0.dylib*). 

```script
1292 dan:relosx$ ./ldeps.sh `cat deps.txt` | sort | uniq
@rpath/lib/libffi.7.dylib
@rpath/lib/libglib-2.0.0.dylib
@rpath/lib/libgmodule-2.0.0.dylib
@rpath/lib/libgobject-2.0.0.dylib
@rpath/lib/libgstaudio-1.0.0.dylib
@rpath/lib/libgstbase-1.0.0.dylib
@rpath/lib/libgstreamer-1.0.0.dylib
@rpath/lib/libgsttag-1.0.0.dylib
@rpath/lib/libgstvideo-1.0.0.dylib
@rpath/lib/libintl.8.dylib
@rpath/lib/liborc-0.4.0.dylib
```

Append the additional library to deps.txt, and run *ldeps* again. Repeat this process until there are no more additional libraries found. Once that happens, you have the complete list of gstreamer libs that your application needs. 



## create input file for tar to move libs

After the last step, here is my list of required dylibs:

```script
1296 dan:relosx$ cat deps.txt 
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgstreamer-1.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgobject-2.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libglib-2.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libintl.8.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstvideotestsrc.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstvideoconvert.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstosxvideo.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstosxaudio.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstaudiomixer.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstcoreelements.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstaudiotestsrc.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstvideoscale.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libffi.7.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgmodule-2.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgstaudio-1.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgstbase-1.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgstvideo-1.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libintl.8.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/liborc-0.4.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libgsttag-1.0.0.dylib
/Library/Frameworks/GStreamer.framework/Versions/1.0/lib/libz.1.dylib
```

Now modify the file so it can be used by tar. Tar will allow commands that tell it to change directory, then gather a list of *relative filenames*. Make the following changes with your file (note the addition of three directories at the bottom)

```script
1298 dan:relosx$ cat deps-tar.txt
-C
/Library/Frameworks/GStreamer.framework/Versions/1.0
lib/libgstreamer-1.0.0.dylib
lib/libgobject-2.0.0.dylib
lib/libglib-2.0.0.dylib
lib/libintl.8.dylib
lib/gstreamer-1.0/libgstvideotestsrc.dylib
lib/gstreamer-1.0/libgstvideoconvert.dylib
lib/gstreamer-1.0/libgstosxvideo.dylib
lib/gstreamer-1.0/libgstosxaudio.dylib
lib/gstreamer-1.0/libgstaudiomixer.dylib
lib/gstreamer-1.0/libgstcoreelements.dylib
lib/gstreamer-1.0/libgstaudiotestsrc.dylib
lib/gstreamer-1.0/libgstvideoscale.dylib
lib/libffi.7.dylib
lib/libgmodule-2.0.0.dylib
lib/libgstaudio-1.0.0.dylib
lib/libgstbase-1.0.0.dylib
lib/libgstvideo-1.0.0.dylib
lib/libintl.8.dylib
lib/liborc-0.4.0.dylib
lib/libgsttag-1.0.0.dylib
lib/libz.1.dylib
bin/
libexec/
lib/gio
```

**Important:** tar is not tolerant of trailing spaces! Make sure each line in this file does NOT have trailing spaces. 


## Run reloc.sh

First, you need a copy of *osxrelocator.py* from gstreamer's *cerbero* project. The latest repo can be had at https://github.com/GStreamer/cerbero.git. The *reloc.sh* script will check for an env variable OSXRELOCATOR which should point to the osxrelocator.py script. 


reloc.sh takes four arguments:

```script
reloc.sh BUILDDIR BUNDLE LIBLIST DISTDIR
```

- BUILDDIR is the path to your application's build directory, i.e. where the app bundle resides
- BUNDLE is the name of your app bundle - what comes before ".app"
- LIBLIST is the file you created in the steps above
- DISTDIR is a (new) directory where the relocated app will be created

DISTDIR must not exist before the script is run. This folder will be created and your (relocated) app bundle will be placed inside it. The entire DISTDIR folder may be safely deleted. 

I get these types of error messages - the come from macdeployqt and don't seem to matter ( I don't use these libs anyways, looks like their dependency gets picked up by some other inclusion)

```script
ERROR: no file at "/Library/lib/GStreamer.framework/Versions/1.0/lib"
WARNING: Plugin "libqsqlodbc.dylib" uses private API and is not Mac App store compliant.
WARNING: Plugin "libqsqlpsql.dylib" uses private API and is not Mac App store compliant.
ERROR: no file at "/usr/local/opt/libiodbc/lib/libiodbc.2.dylib"
ERROR: no file at "/Applications/Postgres.app/Contents/Versions/9.6/lib/libpq.5.dylib"
```

