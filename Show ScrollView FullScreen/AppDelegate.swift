//
//  AppDelegate.swift
//  Show ScrollView FullScreen
//
//  Show images in a ScrollView on full screen
//  with MainMenu.xib
//  decompress zipped images with ZipZap framework
//   see <https://github.com/pixelglow/zipzap>
//  Show pdf documents as images
//
//  includes multi-page display for tiff and pdf documents
//
//  cursor keys control image display
//   <-   previous image
//   ->   next image
//   up   previous page
//   down next page
//  backspace key controls return from zip file
//
//  Created by Erich Küster on 29.05.16.
//  Copyright © 2016 Erich Küster. All rights reserved.
//

import Cocoa
import Quartz
import ZipZap

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    @IBOutlet weak var window: NSWindow!

    var closeZIPItem: NSMenuItem!
    var mainFrame: NSRect!
    var windowFrame = NSZeroRect

    var entryIndex: Int = -1
    var pageIndex: Int = 0
    var urlIndex: Int = -1

    var directoryURL: NSURL = NSURL()
    var workDirectoryURL: NSURL = NSURL()
    
    var defaultSession: NSURLSession!
    var imageArchive: ZZArchive? = nil
    var imageBitmaps = [NSImageRep]()
    var imageURLs = [NSURL]()
    var sharedDocumentController: NSDocumentController!
    var showSlides: Bool = false
    var slidesTimer: NSTimer? = nil
    var subview: NSScrollView? = nil
    var useScrolling = false

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        // Insert code here to initialize your application
        let config = NSURLSessionConfiguration.defaultSessionConfiguration()
        defaultSession = NSURLSession(configuration: config)
        let presentationOptions: NSApplicationPresentationOptions = [.HideDock, .AutoHideMenuBar]
        NSApp.presentationOptions = NSApplicationPresentationOptions(rawValue: presentationOptions.rawValue)
        sharedDocumentController = NSDocumentController.sharedDocumentController()
        mainFrame = NSScreen.mainScreen()?.frame
        // find menu item "Close ZIP"
        let fileMenu = NSApp.mainMenu!.itemWithTitle("File")
        let fileMenuItems = fileMenu?.submenu?.itemArray
        for item in fileMenuItems! {
            if (item.title == "Close ZIP") {
                closeZIPItem = item
            }
        }
        window.alphaValue = 1.0 // window becomes 0 % transparent
        // set background color of window if desired, default is grey
        window.backgroundColor = NSColor.blackColor()
        // view applies the autoresizing behavior to its subviews, enabled
        window.contentView?.autoresizesSubviews = true
        // set user's directory as starting point of search
        let userDirectoryPath: NSString = "~"
        let userDirectoryURL = NSURL.fileURLWithPath(userDirectoryPath.stringByExpandingTildeInPath)
        workDirectoryURL = userDirectoryURL.URLByAppendingPathComponent("Pictures", isDirectory: true)
        window.delegate = self
        processImages()
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }

    func application(sender: NSApplication, openFile filename: String) -> Bool {
        // invoked when an item of recent documents is clicked
        let fileURL = NSURL(fileURLWithPath: filename)
        urlIndex += 1
        imageURLs.insert(fileURL, atIndex: urlIndex)
        processImages()
        // in fact never reached
        return true
    }

    func processImages() {
        if (urlIndex < 0) {
            // load new images from NSOpenPanel
            // generate File Open Dialog class
            let imageDialog: NSOpenPanel = NSOpenPanel()
            imageDialog.title = NSLocalizedString("Select image file", comment: "title of open panel")
            let imageFile = ""
            imageDialog.nameFieldStringValue = imageFile
            imageDialog.directoryURL = workDirectoryURL
            imageDialog.allowedFileTypes = ["bmp","jpg","jpeg","pdf","png","tif","tiff", "zip"]
            imageDialog.allowsMultipleSelection = true;
            imageDialog.canChooseDirectories = true;
            imageDialog.canCreateDirectories = false;
            imageDialog.canChooseFiles = true;
            imageDialog.beginSheetModalForWindow(window, completionHandler: { response in
                if response == NSFileHandlingPanelOKButton {
                    // NSFileHandlingPanelOKButton is Int(1)
                    self.urlIndex = 0
                    self.workDirectoryURL = (imageDialog.URL?.URLByDeletingLastPathComponent)!
                    self.imageURLs = imageDialog.URLs
                    self.processImages()
                }
            })
        }
        if (urlIndex >= 0) {
            // process images from existing URL(s)
            let actualURL = imageURLs[urlIndex]
            sharedDocumentController.noteNewRecentDocumentURL(actualURL)
            if let fileType = actualURL.pathExtension {
                switch fileType {
                case "zip":
                    // valid URL decodes zip file
                    do {
                        entryIndex = 0
                        imageArchive = try ZZArchive(URL: actualURL)
                        closeZIPItem.enabled = true
                        scrollViewWithArchiveEntry()
                    } catch let error as NSError {
                        entryIndex = -1
                        Swift.print("ZipZap error: could not open archive in \(error.domain)")
                    }
                default:
                    scrollViewfromURLRequest(actualURL)
                }
            }
        }
    }

    func scrollViewfromURLRequest(url: NSURL) {
        let urlRequest: NSURLRequest = NSURLRequest(URL: url)
        let task = defaultSession.dataTaskWithRequest(urlRequest, completionHandler: {
            (data: NSData?, response: NSURLResponse?, error: NSError?) -> Void in
            if error != nil {
                Swift.print("error from data task: \(error!.localizedDescription) in \(error!.domain)")
                return
            }
            else {
                dispatch_async(dispatch_get_main_queue()) {
                    self.fillBitmapsWithData(data!)
                    if let subview = self.scrollViewWithActualBitmap() {
                        self.window.setTitleWithRepresentedFilename(url.lastPathComponent!)
                        self.subview = subview
                        self.window.contentView!.addSubview(subview)
                    }
                }
            }
        })
        task.resume()
    }

    func scrollViewWithArchiveEntry() {
        let entry = imageArchive!.entries[entryIndex]
        do {
            let zipData = try entry.newData()
            self.fillBitmapsWithData(zipData)
            if let subview = scrollViewWithActualBitmap() {
                window.title = "ZIP - " + (entry.fileName)
                self.subview = subview
                window.contentView!.addSubview(subview)
            }
        } catch let error as NSError {
            Swift.print("Error: no valid data in \(error.domain)")
        }
    }

    func fitImageIntoScrollViewSettingWindowFrame(bitmap: NSImageRep) -> NSRect {
        var imageFrame = NSZeroRect
        var frameOrigin = NSZeroPoint
        var frameSize = mainFrame.size
        // calculate aspect ratios
        // get the real imagesize in pixels
        // see <http://briksoftware.com/blog/?p=72>
        let imageSize = NSMakeSize(CGFloat(bitmap.pixelsWide), CGFloat(bitmap.pixelsHigh))
        imageFrame.size = imageSize
        // now we differentiate between four cases
        // 1. image frame inside main frame
        //    at the same time respecting useScrolling
        // 2. mainFrame.width >= image width: imageFrame higher than mainFrame
        // 3. mainFrame.height >= image height: imageFrame wider than mainFrame
        // 4. image frame contains main frame
        let diffX = mainFrame.width - imageSize.width
        let diffY = mainFrame.height - imageSize.height
        if (((diffX >= 0) && (diffY >= 0)) || !useScrolling) {
            // case 1: imageFrame inside mainFrame or do not use scroll view
            // calculate aspect ratios
            let mainRatio = mainFrame.size.width / mainFrame.size.height
            let imageRatio = imageSize.width / imageSize.height
            // fit viewrect into mainrect
            if (mainRatio > imageRatio) {
                // portrait, scale maxWidth
                let innerWidth = mainFrame.height * imageRatio
                frameOrigin.x = (mainFrame.size.width - innerWidth) / 2.0
                frameSize.width = innerWidth
            }
            else {
                // landscape, scale maxHeight
                let innerHeight = mainFrame.width / imageRatio
                frameOrigin.y = (mainFrame.size.height - innerHeight) / 2.0
                frameSize.height = innerHeight
            }
            imageFrame.origin = frameOrigin
            imageFrame.size = frameSize
        }
        else {
            // we need a scrollview
            if ((diffX >= 0) && (diffY < 0)) {
                // case 2: image width inside main frame width
                frameOrigin.x = diffX / 2.0
                frameSize.width = imageSize.width
            }
            else {
                if ((diffX < 0) && (diffY >= 0)) {
                    // case 3: image height inside main frame height
                    frameOrigin.y = diffY / 2.0
                    frameSize.height = imageSize.height
                }
                // case 4: (diffX < 0) && (diffY < 0) no separate statement
            }
        }
        windowFrame.origin = frameOrigin
        windowFrame.size = frameSize
        window.setContentSize(window.contentRectForFrameRect(windowFrame).size)
        window.aspectRatio = imageSize
        window.setFrame(windowFrame, display: true)
        return imageFrame
    }

    func drawPDFPageInImage(page: CGPDFPage) -> NSImageRep? {
        let pageRect = CGPDFPageGetBoxRect(page, .MediaBox)
        let image = NSImage(size: pageRect.size)
        image.lockFocus()
        let context = NSGraphicsContext.currentContext()?.CGContext
        CGContextSetFillColorWithColor(context, NSColor.whiteColor().CGColor)
        CGContextFillRect(context,pageRect)
        // upside down and side inverted ( mirrored )
        //CGContextTranslateCTM(context, 0.0, pageRect.size.height);
        //CGContextScaleCTM(context, 1.0, -1.0);
        // just side-inverted
        //CGContextTranslateCTM(context, pageRect.size.width, 0.0);
        //CGContextScaleCTM(context, -1.0, 1.0);
        CGContextDrawPDFPage(context, page);
        image.unlockFocus()
        return image.representations.first
    }

    func fillBitmapsWithData(bitmapData: NSData) {
        // generate representation(s) for image
        if (imageBitmaps.count > 0) {
            imageBitmaps.removeAll(keepCapacity: false)
        }
        pageIndex = 0
        imageBitmaps = NSBitmapImageRep.imageRepsWithData(bitmapData)
        if (imageBitmaps.count == 0) {
            // no valid bitmaps, try PDF
            // create an image with NSCGImageSnapshotRep for every page
            let provider = CGDataProviderCreateWithCFData(bitmapData)
            if let document = CGPDFDocumentCreateWithProvider(provider) {
                let count = CGPDFDocumentGetNumberOfPages(document)
                for i in 1 ... count {
                    if let page = CGPDFDocumentGetPage(document, i) {
                        if let bitmap = drawPDFPageInImage(page) {
                            imageBitmaps.append(bitmap)
                        }
                    }
                }
            }
        }
    }

    func imageViewWithBitmap(bitmap: NSImageRep?) -> NSImageView? {
        // valid image bitmap, now look if subview contains data
        if (subview != nil) {
            subview?.removeFromSuperviewWithoutNeedingDisplay()
        }
        if let imageBitmap = bitmap {
            let viewFrame = fitImageIntoScrollViewSettingWindowFrame(imageBitmap)
            let image = NSImage()
            image.addRepresentation(imageBitmap)
            let imageView = NSImageView(frame: viewFrame)
            imageView.imageScaling = NSImageScaling.ScaleProportionallyUpOrDown
            imageView.image = image
            return imageView
        }
        return nil
    }

    func scrollViewWithActualBitmap() -> NSScrollView? {
        let scrollView = NSScrollView(frame: mainFrame)
        // the scroll view should have both horizontal
        // and vertical scrollers
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        // configure the scroller to have no visible border
        scrollView.borderType = .NoBorder //.NoBorder //.BezelBorder //.GrooveBorder
        scrollView.backgroundColor = NSColor.blackColor()
        // set the autoresizing mask so that the scroll view will
        // resize with the window
        let autoresizingMaskOptions: NSAutoresizingMaskOptions = [.ViewWidthSizable, .ViewHeightSizable]
        scrollView.autoresizingMask = NSAutoresizingMaskOptions(rawValue: autoresizingMaskOptions.rawValue)
        // set ImageView as the documentView of the ScrollView
        // read bitmap of image data with actual page index
        if let imageView = imageViewWithBitmap(imageBitmaps[pageIndex]) {
            scrollView.documentView = imageView
            return scrollView
        }
        return nil
    }
    //        Swift.print("recent URLs: \(sharedDocumentController.recentDocumentURLs)")

    // following are the actions for menu entries
    @IBAction func openDocument(sender: NSMenuItem) {
        // open new file(s)
        entryIndex = -1
        urlIndex = -1
        processImages()
    }

    @IBAction func closeZIP(sender: NSMenuItem) {
        // return from zipped images
        sender.enabled = false
        entryIndex = -1
        urlIndex = -1
        processImages()
    }

    @IBAction func pageUp(sender: NSMenuItem) {
        // show page up
        if (!imageBitmaps.isEmpty) {
            let nextIndex = pageIndex - 1
            if (nextIndex >= 0) {
                pageIndex = nextIndex
                if let subview = scrollViewWithActualBitmap() {
                    self.subview = subview
                    window.contentView!.addSubview(subview)
                }
            }
        }
    }

    @IBAction func pageDown(sender: NSMenuItem) {
        // show page down
        if (imageBitmaps.count > 1) {
            let nextIndex = pageIndex + 1
            if (nextIndex < imageBitmaps.count) {
                pageIndex = nextIndex
                if let subview = scrollViewWithActualBitmap() {
                    self.subview = subview
                    window.contentView!.addSubview(subview)
                }
            }
        }
    }

    @IBAction func previousImage(sender: AnyObject) {
        // show previous image
        if (entryIndex >= 0) {
            // display previous image of entry in zip archive
            let nextIndex = entryIndex - 1
            if (nextIndex >= 0) {
                entryIndex = nextIndex
                scrollViewWithArchiveEntry()
            }
        }
        else {
            if (urlIndex >= 0) {
                // test what is in previuos URL
                let nextIndex = urlIndex - 1
                if (nextIndex >= 0) {
                    urlIndex = nextIndex
                    processImages()
                }
            }
        }
    }

    @IBAction func nextImage(sender: AnyObject) {
        // show next image
        if (entryIndex >= 0) {
            // display next image from zip entry
            let nextindex = entryIndex + 1
            if (nextindex < imageArchive?.entries.count) {
                entryIndex = nextindex
                scrollViewWithArchiveEntry()
            }
        }
        else {
            if (urlIndex >= 0) {
                // test what is in next URL
                let nextIndex = urlIndex + 1
                if (nextIndex < imageURLs.count) {
                    urlIndex = nextIndex
                    processImages()
                }
            }
        }
    }

    @IBAction func slideShow(sender: NSMenuItem) {
        // start slide show, yes or no
        let item = sender
        if (showSlides) {
            item.state = NSOffState
            showSlides = false
            if let timer = slidesTimer {
                timer.invalidate()
                slidesTimer = nil
            }
        }
        else {
            item.state = NSOnState
            showSlides = true
            // 3 seconds
            slidesTimer = NSTimer.scheduledTimerWithTimeInterval(3, target: self, selector: #selector(nextImage(_:)), userInfo: nil, repeats: true)
        }
    }


    @IBAction func useScrollView(sender: NSMenuItem) {
        // scrolling of bigger images, yes or no
        let item = sender
        if (useScrolling) {
            item.state = NSOffState
            useScrolling = false
        }
        else {
            item.state = NSOnState
            useScrolling = true
        }
    }

    // following are methods for window delegate
    func windowWillEnterFullScreen(notification: NSNotification) {
        // window will enter full screen mode
        if (subview != nil) {
            subview!.removeFromSuperviewWithoutNeedingDisplay()
        }
    }

    func windowDidEnterFullScreen(notification: NSNotification) {
        // in full screen the view must have its own origin, correct it
        if (subview != nil) {
            subview!.frame = windowFrame
            window.contentView?.addSubview(subview!)
        }
    }

    func windowWillExitFullScreen(notification: NSNotification) {
        // window will exit full screen mode
        if (subview != nil) {
            subview!.removeFromSuperviewWithoutNeedingDisplay()
        }
    }

    func windowDidExitFullScreen(notification: NSNotification) {
        // window did exit full screen mode
        // correct wrong framesize, if during fullscreen mode
        // another image (with different size) was loaded
        window.setFrame(windowFrame, display: true, animate: true)
        if (subview != nil) {
            subview?.frame.origin = NSZeroPoint
            window.contentView?.addSubview(subview!)
        }
    }

    func windowWillClose(notification: NSNotification) {
        // window will close
        NSApp.terminate(self)
    }
}

