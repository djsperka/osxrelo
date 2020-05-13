# How to relocate a gstreamer/Qt application for distribution

Applications that use dynamic libraries have "load commands" in the executable file (dynamic libraries also have load commands). The "load commands" tell the dynamic loader where to find a particular dynamic library needed by the executable (or library). The command can have an absolute path to a library, or it can have a path *relative to* one of several special variables whose exact path is determined at load time. 

If you copy the application to another machine (or to another location on your own machine), the application may or may not run, depending on whether the system can load the dynamic libraries it needs at run time. 

System libraries (contained in /usr/lib, /System/Libraries) are linked with absolute filenames in their load commands, and do not need to be changed - you can safely assume they are present on any mac system (at least one that respects your applications *MINIMUM_SYSTEM_VERSION*. This procedure ignores these system libraries. 

Here I'll outline a procedure to modify your application bundle so it can be copied to another machine and run properly. Its a procedure, and it requires your intervention to make it all work.

## GStreamer framework 

I am working with the latest version of GStreamer on the mac (1.16 at this writing). This is important, because the libraries in the gstreamer framework use the same type of load commands, with some libraries using absolute file paths and others using paths relative to one of the special dynamic loader vars (*@rpath*). The executable files in the gstreamer framework use a loader path slightly different than that of the libraries they load. 

If you're not using gstreamer 1.16, this procedure may not work exactly as-is! 

I'm assuming that your build uses *pkg-config*, and that you set the env variable *PKG_CONFIG_PATH* to the *pkgconfig/* folder inside your gstreamer distribution. Essentially, your choice of *PKG_CONFIG_PATH* at build time determines the location of the gstreamer distribution that your application links with. (You can switch gstreamer versions in your app by changing the value of *PKG_CONFIG_PATH* and doing a full rebuild.)

Finally, this procedure was developed against the *official* distribution of gstreamer. The version distributed with *homebrew* may have some differences in how the libraries are linked, and so this procedure may need adjusting in that case. 

## With or without Qt?

If your application uses Qt, you will also have to deal with the Qt libraries (and licensing of course). I'll outline how to modify your app bundle to distribute Qt libraries within the bundle - **you should make sure your distribution complies with your Qt license**. 

Qt includes a deployment tool with its distribution on mac, called *macdeployqt*. This application modifies an app bundle to incorporate the Qt libraries inside it, and changes any load commands necessary to make the app work when moved to another machine. 

*macdeployqt* will ignore system libraries that are assumed to be on any mac system. It apparently treats anything found in /Library/Frameworks as "system" libraries and leaves them alone (with the obvious exception of the Qt libs themselves). The gstreamer libraries, however, fall into this category. 

In this procedure, I leave the *macdeployqt* step until last, so that the only libraries that need to be dealt with are the Qt libs themselves. 

## Libraries that are neither system, Qt, or gstreamer

If your app uses other dynamic libraries, the *macdeployqt* tool will move them to your app bundle and change load commands appropriately. Its probably the case that you can allow *macdeployqt* to relocate these libraries, or you can manage the relocation yourself. In this procedure, I do the latter. YMMV. 

# Procedure overview

The actual procedure goes something like this:

1. build your application so it runs on your development machine
1. generate a list of libraries that the app requires
1. create input file for tar to move libs
1. run reloc.sh to move app bundle and perform relocations


You do the numbered list above, the script reloc.sh does the rest. 

## Build your application

Presumably you can do this. If you have dynamic library loading errors this process may or may not help. 

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


## Run reloc.sh and try your application out

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




That doesn't work for all plugins, I've found. Another technique is to use *gst-inspect-1.0*
These have their own dependencies. Note that internally, the gstreamer libraries
all use '@rpath' in the loader paths. We will set the rpath in the exe file so it 
points to the 'Frameworks' folder.

```shell
1224 dan:relosx$ for ifile in `cat d1.txt`; do
> ./ldeps.sh $ifile >> d2.txt
> done
1225 dan:relosx$ cat d2.txt 
@rpath/lib/libgobject-2.0.0.dylib
@rpath/lib/libglib-2.0.0.dylib
@rpath/lib/libintl.8.dylib
@rpath/lib/libgmodule-2.0.0.dylib
@rpath/lib/libglib-2.0.0.dylib
@rpath/lib/libffi.7.dylib
@rpath/lib/libintl.8.dylib
```

For plugins, process is similar. Compile a list of plugins used. In my case its
*videotestsrc*, *videoconvert*, *osxvideosink*. I'm not certain, but it appears that plugins 
only refer to gstreamer libs (in the lib/ folder), not other plugins (in the lib/gstreamer-1.0/ 
folder). If I run ldeps.sh on videotestsrc lib, 

```shell
1232 dan:relosx$ ./ldeps.sh /Library/Frameworks/GStreamer.framework/Versions/1.0/lib/gstreamer-1.0/libgstvideotestsrc.dylib 
@rpath/lib/libgstvideo-1.0.0.dylib
@rpath/lib/libglib-2.0.0.dylib
@rpath/lib/libgobject-2.0.0.dylib
@rpath/lib/libgstbase-1.0.0.dylib
@rpath/lib/libgstreamer-1.0.0.dylib
@rpath/lib/liborc-0.4.0.dylib
```



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
