/* SPDX-License-Identifier: MIT
 * Diagnostic driver build ONLY. Inputs stay inside this process's Cocoa event
 * loop: no CGEventPost, accessibility bypass, foreign windows or clipboard I/O.
 */
#include <dlfcn.h>

static NSWindow *chardonnayProbeWindow(void)
{
    for (NSWindow *window in [NSApp windows])
        if ([[window title] isEqualToString:@"Chardonnay Shortcut Fixture"]) return window;
    return nil;
}

static void chardonnayProbeReport(NSString *path, NSString *phase)
{
    NSMutableArray *bindings = [NSMutableArray array];
    for (NSMenuItem *parent in [[NSApp mainMenu] itemArray])
        for (NSMenuItem *item in [[parent submenu] itemArray])
            if ([item action]) [bindings addObject:@{@"action":NSStringFromSelector([item action]),
                @"key":[item keyEquivalent], @"modifiers":@([item keyEquivalentModifierMask])}];
    NSWindow *window = chardonnayProbeWindow();
    Dl_info image = {0};
    dladdr((void *)chardonnayConfigureMacShortcuts, &image);
    NSMutableArray *windows = [NSMutableArray array];
    for (NSWindow *candidate in [NSApp windows])
        [windows addObject:@{@"title":[candidate title], @"visible":@([candidate isVisible]),
            @"key":@([candidate isKeyWindow]), @"number":@([candidate windowNumber])}];
    NSDictionary *report = @{@"chardonnay_probe_only":@YES, @"phase":phase, @"windows":windows,
        @"pid":@([[NSProcessInfo processInfo] processIdentifier]),
        @"driver":image.dli_fname ? [NSString stringWithUTF8String:image.dli_fname] : @"",
        @"hidden":@([NSApp isHidden]), @"minimized":@(window && [window isMiniaturized]),
        @"fullscreen":@(window && (([window styleMask] & NSWindowStyleMaskFullScreen) != 0)),
        @"bindings":bindings};
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:0 error:NULL];
    if (json) [json writeToFile:path atomically:YES];
}

static void chardonnayProbeDispatch(NSString *path, NSString *testCase, unsigned int attempt)
{
    NSWindow *window = chardonnayProbeWindow();
    if (window && [NSApp keyWindow] != window)
    {
        [NSApp activateIgnoringOtherApps:YES];
        [window makeKeyAndOrderFront:nil];
    }
    if (attempt == 0) chardonnayProbeReport(path,@"waiting_for_key_window");
    if (!window || [NSApp keyWindow] != window)
    {
        if (attempt < 100) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
            dispatch_get_main_queue(), ^{ chardonnayProbeDispatch(path,testCase,attempt+1); });
        else chardonnayProbeReport(path,@"window_timeout");
        return;
    }
    NSString *key = @"";
    unsigned short code = 0;
    NSUInteger modifiers = NSEventModifierFlagCommand;
    if ([testCase hasPrefix:@"quit"]) { key=@"q"; code=kVK_ANSI_Q; }
    else if ([testCase hasPrefix:@"close"]) { key=@"w"; code=kVK_ANSI_W; }
    else if ([testCase isEqualToString:@"minimize"]) { key=@"m"; code=kVK_ANSI_M; }
    else if ([testCase isEqualToString:@"hide"]) { key=@"h"; code=kVK_ANSI_H; }
    else if ([testCase isEqualToString:@"fullscreen"]) { key=@"f"; code=kVK_ANSI_F; modifiers|=NSEventModifierFlagControl; }
    else if ([testCase isEqualToString:@"select-all"]) { key=@"a"; code=kVK_ANSI_A; }
    else if ([testCase isEqualToString:@"control-a"]) { key=@"a"; code=kVK_ANSI_A; modifiers=NSEventModifierFlagControl; }
    else if ([testCase isEqualToString:@"undo"]) { key=@"z"; code=kVK_ANSI_Z; }
    else if ([testCase isEqualToString:@"copy"]) { key=@"c"; code=kVK_ANSI_C; }
    else if ([testCase isEqualToString:@"paste"]) { key=@"v"; code=kVK_ANSI_V; }
    else if ([testCase isEqualToString:@"cut"]) { key=@"x"; code=kVK_ANSI_X; }
    else { chardonnayProbeReport(path,@"unknown_case"); return; }
    chardonnayProbeReport(path,@"sending");
    unsigned short modifierCode = modifiers == NSEventModifierFlagControl ? kVK_Control : kVK_Command;
    NSEvent *modifierDown = [NSEvent keyEventWithType:NSEventTypeFlagsChanged
        location:NSZeroPoint modifierFlags:modifiers timestamp:[NSProcessInfo processInfo].systemUptime
        windowNumber:[window windowNumber] context:nil characters:@""
        charactersIgnoringModifiers:@"" isARepeat:NO keyCode:modifierCode];
    [NSApp sendEvent:modifierDown];
    for (NSNumber *type in @[@(NSEventTypeKeyDown),@(NSEventTypeKeyUp)])
    {
        NSEvent *event = [NSEvent keyEventWithType:[type unsignedIntegerValue]
            location:NSZeroPoint modifierFlags:modifiers timestamp:[NSProcessInfo processInfo].systemUptime
            windowNumber:[window windowNumber] context:nil characters:key
            charactersIgnoringModifiers:key isARepeat:NO keyCode:code];
        [NSApp sendEvent:event];
    }
    NSEvent *modifierUp = [NSEvent keyEventWithType:NSEventTypeFlagsChanged
        location:NSZeroPoint modifierFlags:0 timestamp:[NSProcessInfo processInfo].systemUptime
        windowNumber:[window windowNumber] context:nil characters:@""
        charactersIgnoringModifiers:@"" isARepeat:NO keyCode:modifierCode];
    [NSApp sendEvent:modifierUp];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1500 * NSEC_PER_MSEC),
        dispatch_get_main_queue(), ^{ chardonnayProbeReport(path,@"observed"); });
}

static void chardonnayShortcutProbeStart(void)
{
    static BOOL started = NO;
    const char *output = getenv("CHARDONNAY_SHORTCUT_PROBE");
    const char *name = getenv("CHARDONNAY_SHORTCUT_CASE");
    if (started || !output || !name) return;
    started = YES;
    NSString *path = [NSString stringWithUTF8String:output];
    NSString *testCase = [NSString stringWithUTF8String:name];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
        dispatch_get_main_queue(), ^{ chardonnayProbeDispatch(path,testCase,0); });
}
