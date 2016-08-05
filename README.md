# Swift-Show-ScrollView-FullScreen
Show Images of different kind under OSX

Show the images in a scroll view optionally on full screen
( relatively spartan but working )

The program was written in Swift version 2.2 for Mac OS X.

The development environment in the moment is Xcode 7.3.1 under OS X 10.11 El Capitan.

You can choose one or more image files (including multipage TIFFs and PDF documents) from a directory, which are displayed successively, the sequence is controlled by the cursor keys:
 + left   : previous image
 + right  : next image
 + up     : previous page of document
 + down   : next page of document

There is a link in the source code to the ZipZap framework
 +   see <https://github.com/pixelglow/zipzap>

Thanks to this framework also images from a zipped archive can be shown, when you choose one. Cursor key control is in the manner as mentioned. The backspace key control gives you the possibility to return from displaying the zipped images and choose another sequence.

Further control is possible in the menu bar with help of the "View" menu. You can choose
 1. if you will use a scroll view for the image or leave it best fitted against the main screen and / or
 2. will use full screen mode for displaying.

A rudimentary slideshow function is built in. 

I wrote this program to become familiar with the Swift language and to get a feeling how to display images on the screen. It contains a lot of useful stuff regarding handling of windows, menus, images.

Disclaimer:
Use the program for what purpose you like, but hold in mind, that I will not be responsible for any harm it will cause to your hard- or software. It was your decision to use this piece of software.
