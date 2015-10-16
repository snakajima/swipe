//
//  SwipeBrowser.swift
//  sample
//
//  Created by satoshi on 10/8/15.
//  Copyright © 2015 Satoshi Nakajima. All rights reserved.
//

#if os(OSX)
import Cocoa
public typealias UIViewController = NSViewController
#else
import UIKit
#endif

private func MyLog(text:String, level:Int = 0) {
    let s_verbosLevel = 0
    if level <= s_verbosLevel {
        NSLog(text)
    }
}



let g_typeMapping:[String:Void -> UIViewController] = [
    "net.swipe.list": { return SwipeTableViewController() },
    "net.swipe.swipe": { return SwipeViewController() },
]

class SwipeBrowser: UIViewController, SwipeDocumentViewerDelegate {
    static var stack = [SwipeBrowser]()

#if os(iOS)
    private var fVisibleUI = true
    @IBOutlet var toolbar:UIView?
    @IBOutlet var bottombar:UIView?
    @IBOutlet var slider:UISlider!
    @IBOutlet var labelTitle:UILabel?
#endif
    var url:NSURL? = NSBundle.mainBundle().URLForResource("index.swipe", withExtension: nil)
    var controller:UIViewController?
    var documentViewer:SwipeDocumentViewer?

    func browseTo(url:NSURL) {
#if os(iOS)
        let browser = SwipeBrowser(nibName: "SwipeBrowser", bundle: nil)
#else
        let browser = SwipeBrowser()
#endif
        browser.url = url // 
        //MyLog("SWBrows url \(browser.url!)")

#if os(OSX)
        self.presentViewControllerAsSheet(browser)
#else
        self.presentViewController(browser, animated: true) { () -> Void in
            SwipeBrowser.stack.append(browser)
            MyLog("SWBrows push \(SwipeBrowser.stack.count)", level: 1)
        }
#endif
    }
    
    deinit {
        MyLog("SWBrows deinit", level:1)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if SwipeBrowser.stack.count == 0 {
            SwipeBrowser.stack.append(self) // special case for the first one
            MyLog("SWBrows push first \(SwipeBrowser.stack.count)", level: 1)
        }
        
#if os(iOS)
        slider.hidden = true
#endif

        if let url = self.url {
            if url.scheme == "file" {
                if let data = NSData(contentsOfURL: url) {
                    self.openData(data)
                }
            } else {
                let manager = SwipeAssetManager.sharedInstance()
                manager.loadAsset(url, prefix: "") { (urlLocal:NSURL?, error:NSError!) -> Void in
                    if let urlL = urlLocal,
                           data = NSData(contentsOfURL: urlL) {
                        self.openData(data)
                    } else {
                        self.processError(error.localizedDescription)
                    }
                }
            }
        } else {
            MyLog("SWBrows nil URL")
            processError("No URL to load")
        }
    }
    
    private func openData(dataRetrieved:NSData?) {
        guard let data = dataRetrieved else {
            return processError("failed to open: no data")
        }
        do {
            guard let document = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions()) as? [String:AnyObject] else {
                return processError("Not a dictionary.")
            }
            var documentType = "net.swipe.swipe" // default
            if let type = document["type"] as? String {
                documentType = type
            }
            guard let type = g_typeMapping[documentType] else {
                return processError("Unknown type: \(g_typeMapping[documentType]).")
            }
            let vc = type()
            guard let documentViewer = vc as? SwipeDocumentViewer else {
                return processError("Programming Error: Not SwipeDocumentViewer.")
            }
            self.documentViewer = documentViewer
            do {
                documentViewer.setDelegate(self)
                try documentViewer.loadDocument(document, url: url)
#if os(iOS)
                if let title = documentViewer.documentTitle() {
                    labelTitle?.text = title
                } else {
                    labelTitle?.text = url?.lastPathComponent
                }
#endif
                controller = vc
                self.addChildViewController(vc)
#if os(OSX)
                self.view.addSubview(vc.view, positioned: .Below, relativeTo: nil)
#else
                self.view.insertSubview(vc.view, atIndex: 0)
#endif
                var rcFrame = self.view.bounds
#if os(iOS)
                if documentViewer.hideUI() {
                    let tap = UITapGestureRecognizer(target: self, action: "tapped")
                    self.view.addGestureRecognizer(tap)
                    hideUI()
                } else if let toolbar = self.toolbar, let bottombar = self.bottombar {
                    rcFrame.origin.y = toolbar.bounds.size.height
                    rcFrame.size.height -= rcFrame.origin.y + bottombar.bounds.size.height
                }
#endif
                vc.view.frame = rcFrame
            } catch let error as NSError {
                return processError("load Document Error: \(error.localizedDescription).")
            }
        } catch let error as NSError {
            let value = error.userInfo["NSDebugDescription"]!
            processError("Invalid JSON file: \(error.localizedDescription). \(value)")
            return
        }
    }
    
#if os(iOS)
    override func prefersStatusBarHidden() -> Bool {
        return true
    }

    override func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        return (self.documentViewer != nil && self.documentViewer!.landscape()) ?
            UIInterfaceOrientationMask.Landscape
            : UIInterfaceOrientationMask.Portrait
    }

// LATER: Implement!
/*
    @IBAction func viewSource() {
        let vc = SourceViewController(nibName: "SourceViewController", bundle: nil)
        vc.book = self.book
        self.presentViewController(vc, animated: true, completion: nil)
    }
*/
    @IBAction func tapped() {
        MyLog("SWBrows tapped", level: 1)
        if fVisibleUI {
            hideUI()
        } else {
            showUI()
        }
    }
    
    private func showUI() {
        fVisibleUI = true
        UIView.animateWithDuration(0.2, animations: { () -> Void in
            self.toolbar?.alpha = 1.0
            self.bottombar?.alpha = 1.0
        })
    }
    
    private func hideUI() {
        fVisibleUI = false
        UIView.animateWithDuration(0.2, animations: { () -> Void in
            self.toolbar?.alpha = 0.0
            self.bottombar?.alpha = 0.0
        })
    }

    @IBAction func slided(sender:UISlider) {
        MyLog("SWBrows \(slider.value)")
    }
#endif

    private func processError(message:String) {
        dispatch_async(dispatch_get_main_queue()) {
#if !os(OSX) // REVIEW
            let alert = UIAlertController(title: "Can't open the document.", message: message, preferredStyle: UIAlertControllerStyle.Alert)
            alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.Default) { (_:UIAlertAction) -> Void in
                self.presentingViewController?.dismissViewControllerAnimated(true, completion: nil)
            })
            self.presentViewController(alert, animated: true, completion: nil)
#endif
        }
    }
    
#if !os(OSX)
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
#endif
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        if self.isBeingDismissed() {
            SwipeBrowser.stack.popLast()
            MyLog("SWBrows pop \(SwipeBrowser.stack.count)", level:1)
            if SwipeBrowser.stack.count == 1 {
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    SwipePage.checkMemoryLeak()
                    SwipeElement.checkMemoryLeak()
                })
            }
        }
    }

    @IBAction func close(sender:AnyObject) {
#if os(OSX)
        self.presentingViewController!.dismissViewController(self)
#else
        self.presentingViewController!.dismissViewControllerAnimated(true, completion: nil)
#endif
    }
    
    func becomeZombie() {
        if let documentViewer = self.documentViewer {
            documentViewer.becomeZombie()
        }
    }

    static func openURL(urlString:String) {
        NSLog("SWBrose openURL \(SwipeBrowser.stack.count) \(urlString)")
#if os(OSX)
        while SwipeBrowser.stack.count > 1 {
            let lastVC = SwipeBrowser.stack.last!
            lastVC.becomeZombie()
            SwipeBrowser.stack.last!.dismissViewController(lastVC)
        }
#else
        if SwipeBrowser.stack.count > 1 {
            let lastVC = SwipeBrowser.stack.last!
            lastVC.becomeZombie()
            SwipeBrowser.stack.last!.dismissViewControllerAnimated(false, completion: { () -> Void in
                openURL(urlString)
            })
            return
        }
#endif
        
        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            if let url = NSURL.url(urlString, baseURL: nil) {
                SwipeBrowser.stack.last!.browseTo(url)
            }
        }
/*
        if SwipeBrowser.stack.count > 1 {
            SwipeBrowser.stack.last!.becomeZombie()
            SwipeBrowser.stack.popLast()
            SwipeBrowser.stack.last!.dismissViewControllerAnimated(false, completion: { () -> Void in
                SwipeBrowser.openURL(urlString)
            })
        } else {
            SwipeBrowser.stack.last!.browseTo(urlString)
        }
*/
    }
}