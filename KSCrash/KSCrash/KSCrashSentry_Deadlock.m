//
//  KSCrashSentry_Deadlock.m
//
//  Created by Karl Stenerud on 2012-12-09.
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import "KSCrashSentry_Deadlock.h"
#import "KSCrashSentry_Private.h"
#import "ARCSafe_MemMgmt.h"
#import <mach/mach.h>

//#define KSLogger_LocalLevel TRACE
#import "KSLogger.h"


#define kDefaultWatchdogInterval 0


@class KSCrashDeadlockMonitor;

// ============================================================================
#pragma mark - Globals -
// ============================================================================

/** Flag noting if we've installed our custom handlers or not.
 * It's not fully thread safe, but it's safer than locking and slightly better
 * than nothing.
 */
static volatile sig_atomic_t g_installed = 0;

/** Thread which monitors other threads. */
static KSCrashDeadlockMonitor* g_monitor;

/** Context to fill with crash information. */
static KSCrash_SentryContext* g_context;

/** Interval between watchdog pulses. */
static float g_watchdogInterval = kDefaultWatchdogInterval;


// ============================================================================
#pragma mark - X -
// ============================================================================


@interface KSCrashDeadlockMonitor: NSObject

@property(nonatomic, readwrite, assign) NSTimeInterval pollInterval;
@property(nonatomic, readwrite, retain) NSThread* monitorThread;
@property(nonatomic, readwrite, assign) thread_t mainThread;
@property(nonatomic, readwrite, assign) BOOL awaitingResponse;

@end

@implementation KSCrashDeadlockMonitor

@synthesize pollInterval = _pollInterval;
@synthesize monitorThread = _monitorThread;
@synthesize mainThread = _mainThread;
@synthesize awaitingResponse = _awaitingResponse;

- (id) init
{
    if((self = [super init]))
    {
        // target (self) is retained until selector (runMonitor) exits.
        self.monitorThread = as_autorelease([[NSThread alloc] initWithTarget:self selector:@selector(runMonitor) object:nil]);
        self.monitorThread.name = @"KSCrash Deadlock Detection Thread";
        [self.monitorThread start];

        dispatch_async(dispatch_get_main_queue(), ^
        {
            self.mainThread = mach_thread_self();
        });
    }
    return self;
}

- (void) dealloc
{
    as_release(_monitorThread);
    as_superdealloc();
}

- (void) cancel
{
    [self.monitorThread cancel];
}

- (void) watchdogPulse
{
    __block as_weak id blockSelf = self;
    self.awaitingResponse = YES;
    dispatch_async(dispatch_get_main_queue(), ^
                   {
                       [blockSelf watchdogAnswer];
                   });
}

- (void) watchdogAnswer
{
    self.awaitingResponse = NO;
}

- (void) handleDeadlock
{
    g_context->crashType = KSCrashTypeMainThreadDeadlock;
    g_context->offendingThread = self.mainThread;
    g_context->registersAreValid = false;
    
    KSLOG_DEBUG(@"Calling main crash handler.");
    g_context->onCrash();
    
    
    KSLOG_DEBUG(@"Crash handling complete. Restoring original handlers.");
    kscrashsentry_uninstall(KSCrashTypeAll);
    
    KSLOG_DEBUG(@"Calling abort()");
    abort();
}

- (void) runMonitor
{
    BOOL cancelled = NO;
    do
    {
        as_autoreleasepool_start(POOL);
        {
            BOOL runWatchdogCheck = g_watchdogInterval > 0;
            float interval = runWatchdogCheck ? g_watchdogInterval : 5.0f;
            [NSThread sleepForTimeInterval:interval];
            cancelled = self.monitorThread.isCancelled;
            if(!cancelled && runWatchdogCheck)
            {
                if(self.awaitingResponse)
                {
                    [self handleDeadlock];
                }
                else
                {
                    [self watchdogPulse];
                }
            }
        }
        as_autoreleasepool_end(POOL);
    } while (!cancelled);
}

@end

// ============================================================================
#pragma mark - API -
// ============================================================================

bool kscrashsentry_installDeadlockHandler(KSCrash_SentryContext* context)
{
    KSLOG_DEBUG(@"Installing deadlock handler.");
    if(g_installed)
    {
        KSLOG_DEBUG(@"Deadlock handler already installed.");
        return true;
    }
    g_installed = 1;

    g_context = context;

    KSLOG_DEBUG(@"Creating new deadlock monitor.");
    g_monitor = [[KSCrashDeadlockMonitor alloc] init];
    return true;
}

void kscrashsentry_uninstallDeadlockHandler(void)
{
    KSLOG_DEBUG(@"Uninstalling deadlock handler.");
    if(!g_installed)
    {
        KSLOG_DEBUG(@"Deadlock handler was already uninstalled.");
        return;
    }

    KSLOG_DEBUG(@"Stopping deadlock monitor.");
    [g_monitor cancel];
    as_release(g_monitor);
    g_monitor = nil;

    g_installed = 0;
}

void kscrashSentry_setDeadlockHandlerWatchdogInterval(float value)
{
    g_watchdogInterval = value;
}
