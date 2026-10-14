// MIT: LaunchServices GUI-session host. No Terminal or foreground window.
#import <Cocoa/Cocoa.h>

@interface ShortcutHost : NSObject <NSApplicationDelegate>
@property(strong) NSTask *worker;
@end
@implementation ShortcutHost
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    (void)note;
    NSString *resources=NSBundle.mainBundle.resourcePath;
    NSString *logDir=[NSHomeDirectory() stringByAppendingPathComponent:@".cache/chardonnay-shortcuts"];
    [NSFileManager.defaultManager createDirectoryAtPath:logDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *log=[logDir stringByAppendingPathComponent:@"agent.log"];
    if(![NSFileManager.defaultManager fileExistsAtPath:log]) [NSFileManager.defaultManager createFileAtPath:log contents:nil attributes:nil];
    NSFileHandle *out=[NSFileHandle fileHandleForWritingAtPath:log];[out seekToEndOfFile];
    // This file access requests ordinary Desktop-folder permission for this
    // GUI app. Denial is reported by the importer; never bypass TCC.
    NSString *desktop=[NSHomeDirectory() stringByAppendingPathComponent:@"Desktop"];
    NSError *permissionError=nil;
    [NSFileManager.defaultManager contentsOfDirectoryAtPath:desktop error:&permissionError];
    if(permissionError) {
        NSString *message=@"Desktop access unavailable. Allow Wine Shortcuts under Privacy & Security > Files and Folders.\n";
        [out writeData:[message dataUsingEncoding:NSUTF8StringEncoding]];
    }
    self.worker=[NSTask new];self.worker.executableURL=[NSURL fileURLWithPath:@"/bin/bash"];
    NSArray *args=NSProcessInfo.processInfo.arguments;
    NSString *mode=[args containsObject:@"--once"]?@"sync":@"daemon";
    self.worker.arguments=@[[resources stringByAppendingPathComponent:@"entrypoint.command"],@"--programs",mode];
    self.worker.standardOutput=out;self.worker.standardError=out;
    self.worker.environment=@{@"HOME":NSHomeDirectory(),@"USER":NSUserName(),@"PATH":@"/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",@"PROGRAMS_HELPER":[resources stringByAppendingPathComponent:@"ShortcutInfo.exe"],@"PROGRAMS_ICON":[resources stringByAppendingPathComponent:@"AppIcon.icns"],@"PROGRAMS_ENTRYPOINT":[resources stringByAppendingPathComponent:@"entrypoint.command"]};
    self.worker.terminationHandler=^(NSTask *task){dispatch_async(dispatch_get_main_queue(),^{exit(task.terminationStatus);});};
    NSError *error=nil;if(![self.worker launchAndReturnError:&error]){[out writeData:[@"Unable to launch shortcut importer.\n" dataUsingEncoding:NSUTF8StringEncoding]];exit(1);}
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;if(self.worker.running)[self.worker terminate];return NSTerminateNow;
}
@end
int main(void) {@autoreleasepool {
    NSApplication *app=NSApplication.sharedApplication;[app setActivationPolicy:NSApplicationActivationPolicyAccessory];
    ShortcutHost *host=[ShortcutHost new];app.delegate=host;[app run];return 0;
}}
