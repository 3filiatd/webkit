/*
 * Copyright (C) 2010 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "AppDelegate.h"

#import "BrowserWindowController.h"
#import "BrowserStatisticsWindowController.h"

#import <WebKit2/WKContextPrivate.h>
#import <WebKit2/WKStringCF.h>
#import <WebKit2/WKURLCF.h>

static NSString *defaultURL = @"http://www.webkit.org/";

@implementation BrowserAppDelegate

void didRecieveMessageFromInjectedBundle(WKContextRef context, WKStringRef messageName, WKTypeRef messageBody, const void *clientInfo)
{
    CFStringRef cfMessageName = WKStringCopyCFString(0, messageName);

    WKTypeID typeID = WKGetTypeID(messageBody);
    if (typeID == WKStringGetTypeID()) {
        CFStringRef cfMessageBody = WKStringCopyCFString(0, (WKStringRef)messageBody);
        LOG(@"ContextInjectedBundleClient - didRecieveMessage - MessageName: %@ MessageBody %@", cfMessageName, cfMessageBody);
        CFRelease(cfMessageBody);
    } else {
        LOG(@"ContextInjectedBundleClient - didRecieveMessage - MessageName: %@ (MessageBody Unhandeled)\n", cfMessageName);
    }
    
    CFRelease(cfMessageName);

    WKStringRef newMessageName = WKStringCreateWithCFString(CFSTR("Response"));
    WKStringRef newMessageBody = WKStringCreateWithCFString(CFSTR("Roger that!"));

    WKContextPostMessageToInjectedBundle(context, newMessageName, newMessageBody);
    
    WKStringRelease(newMessageName);
    WKStringRelease(newMessageBody);
}

#pragma mark History Client Callbacks

static void didNavigateWithNavigationData(WKContextRef context, WKPageRef page, WKNavigationDataRef navigationData, WKFrameRef frame, const void *clientInfo)
{
    WKStringRef wkTitle = WKNavigationDataCopyTitle(navigationData);
    CFStringRef title = WKStringCopyCFString(0, wkTitle);
    WKStringRelease(wkTitle);

    WKURLRef wkURL = WKNavigationDataCopyURL(navigationData);
    CFURLRef url = WKURLCopyCFURL(0, wkURL);
    WKURLRelease(wkURL);

    LOG(@"HistoryClient - didNavigateWithNavigationData - title: %@ - url: %@", title, url);
    CFRelease(title);
    CFRelease(url);
}

static void didPerformClientRedirect(WKContextRef context, WKPageRef page, WKURLRef sourceURL, WKURLRef destinationURL, WKFrameRef frame, const void *clientInfo)
{
    CFURLRef cfSourceURL = WKURLCopyCFURL(0, sourceURL);
    CFURLRef cfDestinationURL = WKURLCopyCFURL(0, destinationURL);
    LOG(@"HistoryClient - didPerformClientRedirect - sourceURL: %@ - destinationURL: %@", cfSourceURL, cfDestinationURL);
    CFRelease(cfSourceURL);
    CFRelease(cfDestinationURL);
}

static void didPerformServerRedirect(WKContextRef context, WKPageRef page, WKURLRef sourceURL, WKURLRef destinationURL, WKFrameRef frame, const void *clientInfo)
{
    CFURLRef cfSourceURL = WKURLCopyCFURL(0, sourceURL);
    CFURLRef cfDestinationURL = WKURLCopyCFURL(0, destinationURL);
    LOG(@"HistoryClient - didPerformServerRedirect - sourceURL: %@ - destinationURL: %@", cfSourceURL, cfDestinationURL);
    CFRelease(cfSourceURL);
    CFRelease(cfDestinationURL);
}

static void didUpdateHistoryTitle(WKContextRef context, WKPageRef page, WKStringRef title, WKURLRef URL, WKFrameRef frame, const void *clientInfo)
{
    CFStringRef cfTitle = WKStringCopyCFString(0, title);
    CFURLRef cfURL = WKURLCopyCFURL(0, URL);
    LOG(@"HistoryClient - didUpdateHistoryTitle - title: %@ - URL: %@", cfTitle, cfURL);
    CFRelease(cfTitle);
    CFRelease(cfURL);
}

static void populateVisitedLinks(WKContextRef context, const void *clientInfo)
{
    LOG(@"HistoryClient - populateVisitedLinks");
}

- (id)init
{
    self = [super init];
    if (self) {
        if ([NSEvent modifierFlags] & NSShiftKeyMask)
            currentProcessModel = kProcessModelSharedSecondaryThread;
        else
            currentProcessModel = kProcessModelSharedSecondaryProcess;

        WKContextRef threadContext = WKContextGetSharedThreadContext();
        WKContextHistoryClient historyClient = {
            0,
            self,
            didNavigateWithNavigationData,
            didPerformClientRedirect,
            didPerformServerRedirect,
            didUpdateHistoryTitle,
            populateVisitedLinks
        };
        WKContextSetHistoryClient(threadContext, &historyClient);
    
        threadPageNamespace = WKPageNamespaceCreate(threadContext);
        WKContextRelease(threadContext);

        CFStringRef bundlePathCF = (CFStringRef)[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"WebBundle.bundle"];
        WKStringRef bundlePath = WKStringCreateWithCFString(bundlePathCF);

        WKContextRef processContext = WKContextCreateWithInjectedBundlePath(bundlePath);
        
        WKContextInjectedBundleClient bundleClient = {
            0,      /* version */
            0,      /* clientInfo */
            didRecieveMessageFromInjectedBundle
        };
        WKContextSetInjectedBundleClient(processContext, &bundleClient);
        WKContextSetHistoryClient(processContext, &historyClient);
        
        processPageNamespace = WKPageNamespaceCreate(processContext);
        WKContextRelease(processContext);

        WKStringRelease(bundlePath);
    }

    return self;
}

- (IBAction)newWindow:(id)sender
{
    BrowserWindowController *controller = [[BrowserWindowController alloc] initWithPageNamespace:[self getCurrentPageNamespace]];
    [[controller window] makeKeyAndOrderFront:sender];
    
    [controller loadURLString:defaultURL];
}

- (WKPageNamespaceRef)getCurrentPageNamespace
{
    return (currentProcessModel == kProcessModelSharedSecondaryThread) ? threadPageNamespace : processPageNamespace;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    if ([menuItem action] == @selector(setSharedProcessProcessModel:))
        [menuItem setState:currentProcessModel == kProcessModelSharedSecondaryProcess ? NSOnState : NSOffState];
    else if ([menuItem action] == @selector(setSharedThreadProcessModel:))
        [menuItem setState:currentProcessModel == kProcessModelSharedSecondaryThread ? NSOnState : NSOffState];
    return YES;
}        

- (void)_setProcessModel:(ProcessModel)processModel
{
    if (processModel == currentProcessModel)
        return;
 
    currentProcessModel = processModel;
}

- (IBAction)setSharedProcessProcessModel:(id)sender
{
    [self _setProcessModel:kProcessModelSharedSecondaryProcess];
}

- (IBAction)setSharedThreadProcessModel:(id)sender
{
    [self _setProcessModel:kProcessModelSharedSecondaryThread];
}

- (IBAction)showStatisticsWindow:(id)sender
{
    static BrowserStatisticsWindowController* windowController;
    if (!windowController)
        windowController = [[BrowserStatisticsWindowController alloc] initWithThreadedWKContextRef:WKPageNamespaceGetContext(threadPageNamespace) 
                                                                               processWKContextRef:WKPageNamespaceGetContext(processPageNamespace)];

    [[windowController window] makeKeyAndOrderFront:self];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [self newWindow:self];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    NSArray* windows = [NSApp windows];
    for (NSWindow* window in windows) {
        id delegate = [window delegate];
        if ([delegate isKindOfClass:[BrowserWindowController class]]) {
            BrowserWindowController *controller = (BrowserWindowController *)delegate;
            [controller applicationTerminating];
        }
    }
    
    WKPageNamespaceRelease(threadPageNamespace);
    threadPageNamespace = 0;

    WKPageNamespaceRelease(processPageNamespace);
    processPageNamespace = 0;
}

- (BrowserWindowController *)frontmostBrowserWindowController
{
    NSArray* windows = [NSApp windows];
    for (NSWindow* window in windows) {
        id delegate = [window delegate];
        if ([delegate isKindOfClass:[BrowserWindowController class]])
            return (BrowserWindowController *)delegate;
    }

    return 0;
}

- (IBAction)openDocument:(id)sender
{
    NSOpenPanel *openPanel = [[NSOpenPanel openPanel] retain];
    [openPanel beginForDirectory:nil
        file:nil
        types:nil
        modelessDelegate:self
        didEndSelector:@selector(openPanelDidEnd:returnCode:contextInfo:)
        contextInfo:0];
}

- (void)openPanelDidEnd:(NSOpenPanel *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    [sheet autorelease];
    if (returnCode != NSOKButton || ![[sheet filenames] count])
        return;
    
    NSString* filePath = [[sheet filenames] objectAtIndex:0];

    BrowserWindowController *controller = [self frontmostBrowserWindowController];
    if (!controller) {
        controller = [[BrowserWindowController alloc] initWithPageNamespace:[self getCurrentPageNamespace]];
        [[controller window] makeKeyAndOrderFront:self];
    }
    
    [controller loadURLString:[[NSURL fileURLWithPath:filePath] absoluteString]];
}

@end
