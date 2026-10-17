// SPDX-License-Identifier: MIT
// Keep LaunchServices reopen events in a native host, not the Wine child.
#import <Cocoa/Cocoa.h>
#import <unistd.h>

@interface GameLauncher : NSObject <NSApplicationDelegate>
@property(strong) NSMutableSet<NSTask *> *workers;
@property(strong) NSFileHandle *log;
@property NSTimeInterval lastRequest;
- (void)requestLaunch;
@end

@implementation GameLauncher
- (void)record:(NSString *)message {
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", NSDate.date, message];
    [self.log writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
}
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    (void)note;
    self.workers = NSMutableSet.new;
    NSString *identifier = NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
    NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:
        [@".cache/chardonnay-launcher" stringByAppendingPathComponent:identifier]];
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory
            withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"Unable to create launcher log directory: %@", error);
        exit(1);
    }
    NSString *path = [directory stringByAppendingPathComponent:@"host.log"];
    if (![NSFileManager.defaultManager fileExistsAtPath:path])
        [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil];
    self.log = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!self.log) exit(1);
    [self.log seekToEndOfFile];
    [self record:[NSString stringWithFormat:@"host-start pid=%d", getpid()]];
    [self requestLaunch];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible {
    (void)app; (void)visible;
    [self requestLaunch];
    return NO;
}
- (void)requestLaunch {
    // LaunchServices can issue an initial reopen as well as didFinishLaunching.
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (self.lastRequest && now - self.lastRequest < 2.0) return;
    self.lastRequest = now;
    NSString *script = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"launch.command"];
    if (![NSFileManager.defaultManager isReadableFileAtPath:script]) {
        [self record:@"launch-error missing launch.command"];
        return;
    }
    NSTask *task = NSTask.new;
    task.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
    task.arguments = @[script];
    // Do not pass LaunchServices identity or ambient Wine routing to the child.
    task.environment = @{@"HOME":NSHomeDirectory(), @"USER":NSUserName(),
        @"PATH":@"/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"};
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    task.standardOutput = self.log;
    task.standardError = self.log;
    __weak GameLauncher *weakSelf = self;
    task.terminationHandler = ^(NSTask *finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            GameLauncher *host = weakSelf;
            [host record:[NSString stringWithFormat:@"worker-exit pid=%d status=%d",
                finished.processIdentifier, finished.terminationStatus]];
            [host.workers removeObject:finished];
        });
    };
    NSError *error = nil;
    [self.workers addObject:task];
    if (![task launchAndReturnError:&error]) {
        [self.workers removeObject:task];
        [self record:[NSString stringWithFormat:@"launch-error %@", error.localizedDescription]];
        return;
    }
    [self record:[NSString stringWithFormat:@"launch-request worker=%d", task.processIdentifier]];
}
// Quitting this host must not terminate Steam, EA, or a running game.
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app {
    (void)app;
    return NSTerminateNow;
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        GameLauncher *host = GameLauncher.new;
        app.delegate = host;
        [app run];
    }
    return 0;
}
