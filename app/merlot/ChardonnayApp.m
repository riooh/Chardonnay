// SPDX-License-Identifier: MIT
// A native Cocoa owner for bottle/install actions; Wine never owns this app's lifecycle.
#import <Cocoa/Cocoa.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <unistd.h>

typedef void (^BackendCompletion)(NSDictionary *, NSString *);

@interface ChardonnayApp : NSObject <NSApplicationDelegate,NSTableViewDataSource,NSTableViewDelegate,NSWindowDelegate>
@property(strong) NSWindow *window;
@property(strong) NSTableView *bottleTable;
@property(strong) NSTableView *appTable;
@property(strong) NSTextField *heading;
@property(strong) NSTextField *details;
@property(strong) NSTextField *statusLabel;
@property(strong) NSProgressIndicator *progress;
@property(strong) NSButton *createButton;
@property(strong) NSButton *installButton;
@property(strong) NSButton *launchButton;
@property(strong) NSButton *uninstallButton;
@property(strong) NSButton *runtimeButton;
@property(strong) NSWindow *runtimeWindow;
@property(strong) NSTableView *runtimeTable;
@property(strong) NSTextField *runtimeLabel;
@property(strong) NSButton *runtimeRefreshButton;
@property(strong) NSButton *runtimeTerminateButton;
@property(strong) NSButton *runtimeForceButton;
@property(strong) NSButton *runtimeQuitButton;
@property(strong) NSButton *runtimeRestartButton;
@property(strong) NSArray *runtimeButtons;
@property(strong) NSDictionary *runtimeSnapshot;
@property(strong) NSDictionary *runtimeBottle;
@property(strong) NSDictionary *runtimeApp;
@property(strong) NSDictionary *lastRuntimeResult;
@property(strong) NSAlert *runtimeConfirmation;
@property(strong) NSNumber *runtimeTestResponse;
@property(copy) void (^runtimeCompletion)(void);
@property(copy) void (^runtimeCancelCompletion)(void);
@property BOOL runtimeForceRequired;
@property(copy) void (^runtimeLaunchCompletion)(void);
@property(strong) NSMutableArray *runtimeReports;
@property(strong) NSTask *runtimeStubborn;
@property(strong) NSMutableArray<NSButton *> *actionButtons;
@property(strong) NSDictionary *snapshot;
@property(strong) NSArray<NSDictionary *> *bottles;
@property(strong) NSArray<NSDictionary *> *apps;
@property(strong) NSArray<NSDictionary *> *engines;
@property(strong) NSString *entrypoint;
@property(strong) NSString *configPath;
@property(strong) NSString *stateDirectory;
@property(strong) NSTask *worker;
@property BOOL busy;
@property(strong) NSDictionary *acceptance;
@property NSUInteger fixtureIndex;
@property NSUInteger acceptanceStage;
@property(strong) NSString *acceptanceBottle;
@property(strong) NSMutableArray *acceptanceEvents;
- (void)refreshSelecting:(NSString *)identifier completion:(void (^)(void))completion;
- (void)createBottle:(id)sender;
- (void)installApplication:(id)sender;
- (void)launchApplication:(id)sender;
- (void)windowsUninstaller:(id)sender;
@end

@implementation ChardonnayApp
- (NSButton *)button:(NSString *)title action:(SEL)action {
    NSButton *button=[NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle=NSBezelStyleRounded;button.font=[NSFont systemFontOfSize:13];

    [self.actionButtons addObject:button];return button;
}
- (NSTextField *)label:(NSString *)text size:(CGFloat)size bold:(BOOL)bold {
    NSTextField *label=[NSTextField wrappingLabelWithString:text];
    label.font=bold?[NSFont boldSystemFontOfSize:size]:[NSFont systemFontOfSize:size];
    return label;
}
- (NSScrollView *)tableContainer:(NSTableView **)destination sidebar:(BOOL)sidebar {
    NSTableView *table=NSTableView.new;table.delegate=self;table.dataSource=self;
    table.headerView=nil;table.rowHeight=sidebar?44:42;table.allowsEmptySelection=YES;
    table.usesAlternatingRowBackgroundColors=!sidebar;table.style=sidebar?NSTableViewStyleSourceList:NSTableViewStyleFullWidth;
    NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:@"name"];
    [table addTableColumn:column];table.columnAutoresizingStyle=NSTableViewUniformColumnAutoresizingStyle;
    if (!sidebar){table.target=self;table.doubleAction=@selector(launchApplication:);}
    NSScrollView *scroll=NSScrollView.new;scroll.documentView=table;scroll.hasVerticalScroller=YES;scroll.borderType=NSNoBorder;
    *destination=table;return scroll;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.actionButtons=NSMutableArray.new;self.acceptanceEvents=NSMutableArray.new;
    self.bottles=@[];self.apps=@[];self.engines=@[];
    self.entrypoint=[NSBundle.mainBundle objectForInfoDictionaryKey:@"ChardonnayEntrypoint"];
    NSArray<NSString *> *arguments=NSProcessInfo.processInfo.arguments;
    NSUInteger index=[arguments indexOfObject:@"--acceptance"];
    if (index!=NSNotFound){
        if (![NSBundle.mainBundle.bundleIdentifier hasPrefix:@"local.chardonnay.manager.acceptance."] || index+1>=arguments.count)exit(2);
        NSString *specification=arguments[index+1];
        NSData *data=[NSData dataWithContentsOfFile:specification];
        self.acceptance=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![self.acceptance isKindOfClass:NSDictionary.class])exit(2);
        NSString *root=[specification.stringByDeletingLastPathComponent.stringByStandardizingPath stringByAppendingString:@"/"];
        for (NSString *key in @[@"config",@"state_dir",@"report"])
            if (![[self.acceptance[key] stringByStandardizingPath] hasPrefix:root])exit(2);
        self.configPath=self.acceptance[@"config"];self.stateDirectory=self.acceptance[@"state_dir"];
    }
    [self buildMenu];[self buildWindow];
    [NSApp activateIgnoringOtherApps:YES];
    [self refreshSelecting:nil completion:^{
        if (self.acceptance){self.acceptanceStage=1;[self.createButton performClick:nil];}
    }];
}
- (void)buildMenu {
    NSMenu *bar=NSMenu.new;NSMenuItem *root=NSMenuItem.new;[bar addItem:root];
    NSMenu *application=NSMenu.new;
    [application addItemWithTitle:@"About Chardonnay" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [application addItem:NSMenuItem.separatorItem];
    [application addItemWithTitle:@"Quit Chardonnay" action:@selector(terminate:) keyEquivalent:@"q"];root.submenu=application;
    NSMenuItem *file=NSMenuItem.new;file.title=@"File";[bar addItem:file];NSMenu *items=NSMenu.new;
    NSMenuItem *install=[items addItemWithTitle:@"Install Windows Application…" action:@selector(installApplication:) keyEquivalent:@"o"];install.target=self;
    NSMenuItem *create=[items addItemWithTitle:@"New Bottle…" action:@selector(createBottle:) keyEquivalent:@"n"];create.target=self;file.submenu=items;
    NSApp.mainMenu=bar;
}
- (void)buildWindow {
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1040,680) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"Chardonnay";self.window.minSize=NSMakeSize(920,560);self.window.delegate=self;self.window.releasedWhenClosed=NO;
    NSView *content=self.window.contentView;
    NSStackView *layout=[NSStackView stackViewWithViews:@[]];layout.orientation=NSUserInterfaceLayoutOrientationVertical;layout.spacing=14;layout.alignment=NSLayoutAttributeLeading;layout.translatesAutoresizingMaskIntoConstraints=NO;
    [content addSubview:layout];
    [NSLayoutConstraint activateConstraints:@[[layout.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],[layout.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],[layout.topAnchor constraintEqualToAnchor:content.topAnchor constant:18],[layout.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16]]];
    [layout addArrangedSubview:[self label:@"Chardonnay" size:26 bold:YES]];
    NSTextField *tagline=[self label:@"Windows applications and games. Your existing environments stay where they are." size:13 bold:NO];tagline.textColor=NSColor.secondaryLabelColor;[layout addArrangedSubview:tagline];
    NSStackView *tools=[NSStackView stackViewWithViews:@[]];tools.spacing=8;
    self.installButton=[self button:@"Install Windows App…" action:@selector(installApplication:)];[tools addArrangedSubview:self.installButton];
    [tools addArrangedSubview:[self button:@"Refresh" action:@selector(refresh:)]];
    [layout addArrangedSubview:tools];
    NSStackView *panes=[NSStackView stackViewWithViews:@[]];panes.spacing=18;panes.alignment=NSLayoutAttributeTop;
    NSStackView *sidebar=[NSStackView stackViewWithViews:@[]];sidebar.orientation=NSUserInterfaceLayoutOrientationVertical;sidebar.alignment=NSLayoutAttributeLeading;sidebar.spacing=10;
    [sidebar addArrangedSubview:[self label:@"BOTTLES" size:11 bold:YES]];
    NSTableView *bottles=nil;NSScrollView *bottleScroll=[self tableContainer:&bottles sidebar:YES];self.bottleTable=bottles;[sidebar addArrangedSubview:bottleScroll];
    self.createButton=[self button:@"+ New Bottle…" action:@selector(createBottle:)];[sidebar addArrangedSubview:self.createButton];
    NSStackView *detail=[NSStackView stackViewWithViews:@[]];detail.orientation=NSUserInterfaceLayoutOrientationVertical;detail.alignment=NSLayoutAttributeLeading;detail.spacing=10;
    self.heading=[self label:@"Applications" size:21 bold:YES];self.details=[self label:@"Loading configured environments…" size:12 bold:NO];self.details.textColor=NSColor.secondaryLabelColor;
    [detail addArrangedSubview:self.heading];[detail addArrangedSubview:self.details];
    NSTableView *apps=nil;NSScrollView *appScroll=[self tableContainer:&apps sidebar:NO];self.appTable=apps;[detail addArrangedSubview:appScroll];
    self.launchButton=[self button:@"Launch" action:@selector(launchApplication:)];self.uninstallButton=[self button:@"Windows Uninstaller…" action:@selector(windowsUninstaller:)];
    NSStackView *operations=[NSStackView stackViewWithViews:@[self.launchButton,self.uninstallButton,[self button:@"Show Files" action:@selector(showFiles:)]]];operations.spacing=8;[detail addArrangedSubview:operations];
    self.runtimeButton=[self button:@"Running Apps / Recovery…" action:@selector(showRuntime:)];[detail addArrangedSubview:self.runtimeButton];
    NSTextField *policy=[self label:@"Install and uninstall Steam/EA games inside their clients. Desktop shortcuts remain optional." size:11 bold:NO];policy.textColor=NSColor.secondaryLabelColor;[detail addArrangedSubview:policy];
    [panes addArrangedSubview:sidebar];[panes addArrangedSubview:detail];[layout addArrangedSubview:panes];
    self.progress=NSProgressIndicator.new;self.progress.style=NSProgressIndicatorStyleSpinning;self.progress.controlSize=NSControlSizeSmall;self.progress.displayedWhenStopped=NO;
    self.statusLabel=[self label:@"Ready" size:12 bold:NO];self.statusLabel.textColor=NSColor.secondaryLabelColor;
    NSStackView *status=[NSStackView stackViewWithViews:@[self.progress,self.statusLabel]];status.spacing=8;[layout addArrangedSubview:status];
    [NSLayoutConstraint activateConstraints:@[[tools.widthAnchor constraintEqualToAnchor:layout.widthAnchor],[panes.widthAnchor constraintEqualToAnchor:layout.widthAnchor],[panes.heightAnchor constraintGreaterThanOrEqualToConstant:320],[sidebar.widthAnchor constraintEqualToConstant:220],[sidebar.heightAnchor constraintEqualToAnchor:panes.heightAnchor],[detail.heightAnchor constraintEqualToAnchor:panes.heightAnchor],[detail.widthAnchor constraintEqualToAnchor:panes.widthAnchor constant:-238],[bottleScroll.widthAnchor constraintEqualToAnchor:sidebar.widthAnchor],[appScroll.widthAnchor constraintEqualToAnchor:detail.widthAnchor],[self.details.widthAnchor constraintEqualToAnchor:detail.widthAnchor],[policy.widthAnchor constraintEqualToAnchor:detail.widthAnchor],[status.widthAnchor constraintEqualToAnchor:layout.widthAnchor]]];
    [panes setContentHuggingPriority:200 forOrientation:NSLayoutConstraintOrientationVertical];
    [bottleScroll setContentHuggingPriority:100 forOrientation:NSLayoutConstraintOrientationVertical];[appScroll setContentHuggingPriority:100 forOrientation:NSLayoutConstraintOrientationVertical];
    [self.window center];[self.window makeKeyAndOrderFront:nil];
}
- (NSDictionary *)selectedBottle {NSInteger row=self.bottleTable.selectedRow;return row>=0 && row<(NSInteger)self.bottles.count?self.bottles[row]:nil;}
- (NSDictionary *)selectedApp {NSInteger row=self.appTable.selectedRow;return row>=0 && row<(NSInteger)self.apps.count?self.apps[row]:nil;}
- (void)updateControls {
    for(NSButton *button in self.actionButtons)button.enabled=!self.busy;
    self.launchButton.enabled=!self.busy && self.selectedApp!=nil;
    self.uninstallButton.enabled=!self.busy && [self.selectedBottle[@"phase"] isEqual:@"ready"];
    self.runtimeButton.enabled=!self.busy && [self.selectedBottle[@"phase"] isEqual:@"ready"];
    NSDictionary *process=self.selectedRuntimeProcess;BOOL runtimeReady=!self.busy && self.runtimeSnapshot!=nil;
    self.runtimeTerminateButton.enabled=runtimeReady && process!=nil && ![process[@"server"] boolValue];
    self.runtimeForceButton.enabled=self.runtimeTerminateButton.enabled;
    self.runtimeQuitButton.enabled=runtimeReady && [self.runtimeSnapshot[@"complete"] boolValue] && [self.runtimeSnapshot[@"processes"] count]>0;
    self.runtimeQuitButton.title=self.runtimeForceRequired?@"Force Quit All Applications…":@"Quit All Applications…";
    self.runtimeRestartButton.enabled=runtimeReady && [self.runtimeSnapshot[@"complete"] boolValue] && self.runtimeApp!=nil;
    self.runtimeRestartButton.title=self.runtimeForceRequired?@"Force Stop & Restart App…":@"Restart Selected App…";
    if(self.busy)[self.progress startAnimation:nil];else[self.progress stopAnimation:nil];
}
- (void)backend:(NSArray<NSString *> *)arguments message:(NSString *)message completion:(BackendCompletion)completion {
    if(self.busy){completion(nil,@"Another operation is already running.");return;}
    if(!self.entrypoint.length || ![NSFileManager.defaultManager isReadableFileAtPath:self.entrypoint]){completion(nil,@"The Chardonnay source checkout is unavailable.");return;}
    self.busy=YES;self.statusLabel.stringValue=message;[self updateControls];[self recordUIHealth];
    NSMutableArray *command=[NSMutableArray arrayWithObjects:self.entrypoint,@"--bottles",nil];[command addObjectsFromArray:arguments];
    if(self.configPath){[command addObjectsFromArray:@[@"--config",self.configPath]];}if(self.stateDirectory){[command addObjectsFromArray:@[@"--state-dir",self.stateDirectory]];}
    NSTask *task=NSTask.new;task.executableURL=[NSURL fileURLWithPath:@"/bin/bash"];task.arguments=command;
    task.environment=@{@"HOME":NSHomeDirectory(),@"USER":NSUserName(),@"PATH":@"/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",@"DEVELOPER_DIR":@"/Applications/Xcode.app/Contents/Developer"};
    task.standardInput=NSFileHandle.fileHandleWithNullDevice;
    NSPipe *pipe=NSPipe.pipe;task.standardOutput=pipe;task.standardError=pipe;self.worker=task;
    NSError *launchError=nil;
    if(![task launchAndReturnError:&launchError]){self.worker=nil;self.busy=NO;[self updateControls];completion(nil,launchError.localizedDescription);return;}
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSData *data=[pipe.fileHandleForReading readDataToEndOfFile];[task waitUntilExit];
        id decoded=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSDictionary *result=[decoded isKindOfClass:NSDictionary.class]?decoded:nil;
        NSString *error=nil;
        if(task.terminationStatus!=0 || ![result isKindOfClass:NSDictionary.class])error=result[@"error"]?:@"Operation failed. Inspect the private bottle log; no environment was reset.";
        dispatch_async(dispatch_get_main_queue(),^{self.worker=nil;self.busy=NO;[self updateControls];completion(result,error);});
    });
}
- (void)reportError:(NSString *)message {
    self.statusLabel.stringValue=message;
    if(self.acceptance){[self finishAcceptance:NO error:message];return;}
    NSAlert *alert=NSAlert.new;alert.messageText=@"Chardonnay could not finish this operation";alert.informativeText=message;[alert beginSheetModalForWindow:self.window completionHandler:nil];
}
- (void)refreshSelecting:(NSString *)identifier completion:(void (^)(void))completion {
    NSString *selected=identifier?:self.selectedBottle[@"id"];
    [self backend:@[@"status"] message:@"Reading installed applications…" completion:^(NSDictionary *result,NSString *error){
        if(error){[self reportError:error];return;}
        self.snapshot=result;self.bottles=result[@"bottles"]?:@[];self.engines=result[@"engines"]?:@[];
        [self.bottleTable reloadData];NSUInteger index=[self.bottles indexOfObjectPassingTest:^BOOL(NSDictionary *row,NSUInteger i,BOOL *stop){(void)i;(void)stop;return [row[@"id"] isEqual:selected];}];
        if(index==NSNotFound && self.bottles.count)index=0;
        if(index!=NSNotFound)[self.bottleTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
        [self updateSelection];self.statusLabel.stringValue=@"Ready — existing environments retained; no game copies created.";
        [self recordUIHealth];
        if(completion)completion();
    }];
}
- (void)recordUIHealth {
    NSString *directory=self.stateDirectory?:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Chardonnay"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    NSMutableArray *buttons=NSMutableArray.new;
    for(NSButton *button in self.actionButtons)[buttons addObject:@{@"title":button.title,@"enabled":@(button.enabled)}];
    NSDictionary *value=@{@"busy":@(self.busy),@"operation":self.statusLabel.stringValue,@"runtime_confirmation_visible":@(self.runtimeConfirmation.window.isVisible),@"runtime_acceptance_events":self.acceptance?self.acceptanceEvents:@[],@"runtime_window_visible":@(self.runtimeWindow.isVisible),@"runtime_process_count":@([self.runtimeSnapshot[@"processes"] count]),@"runtime_bottle_id":self.runtimeBottle[@"id"]?:@"",@"pid":@(getpid()),@"window_visible":@(self.window.isVisible),@"bottles_loaded":@(self.bottles.count),@"applications_in_selected_bottle":@(self.apps.count),@"buttons":buttons,@"entrypoint":self.entrypoint?:@"",@"checked_at":@([NSDate.date timeIntervalSince1970])};
    NSString *path=[directory stringByAppendingPathComponent:@"manager-status.json"];
    [[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:nil] writeToFile:path atomically:YES];
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];
}
- (void)refresh:(id)sender {(void)sender;if(!self.busy)[self refreshSelecting:nil completion:nil];}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table {return (NSInteger)(table==self.runtimeTable?[self.runtimeSnapshot[@"processes"] count]:table==self.bottleTable?self.bottles.count:self.apps.count);}
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)index {
    NSArray *rows=table==self.runtimeTable?self.runtimeSnapshot[@"processes"]:table==self.bottleTable?self.bottles:self.apps;
    if(index<0 || index>=(NSInteger)rows.count)return nil;
    NSDictionary *row=rows[index];
    NSString *text=row[@"name"]?:@"Application";
    if(table==self.runtimeTable){if([column.identifier isEqual:@"pid"])text=[row[@"pid"] stringValue];else if([column.identifier isEqual:@"role"])text=[row[@"server"] boolValue]?@"Wine server (bottle-wide)":@"Windows process";}
    NSTableCellView *cell=NSTableCellView.new;NSTextField *label=[self label:text?:@"—" size:13 bold:NO];label.translatesAutoresizingMaskIntoConstraints=NO;[cell addSubview:label];cell.textField=label;
    [NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:10],[label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],[label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]]];return cell;
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification {if(notification.object==self.bottleTable)[self updateSelection];else[self updateControls];}
- (void)updateSelection {
    NSDictionary *row=self.selectedBottle;self.apps=row[@"apps"]?:@[];[self.appTable reloadData];
    if(self.apps.count)[self.appTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    self.heading.stringValue=row[@"name"]?:@"No bottles configured";
    NSString *engine=@"Engine unavailable";for(NSDictionary *candidate in self.engines)if([candidate[@"id"] isEqual:row[@"engine_id"]])engine=candidate[@"name"];
    self.details.stringValue=row?[NSString stringWithFormat:@"%@ · %@\n%@",engine,[row[@"external"] boolValue]?@"Existing environment — routing retained":@"Chardonnay-managed environment",row[@"path"]]:@"An existing Chardonnay/Wine engine is required for this development build.";
    [self updateControls];
}
- (NSString *)defaultEngine {
    for(NSDictionary *engine in self.engines)if([engine[@"available"] boolValue] && [engine[@"environment"] objectForKey:@"WINE_VERSION"])return engine[@"id"];
    for(NSDictionary *engine in self.engines)if([engine[@"available"] boolValue])return engine[@"id"];return nil;
}
- (void)createWithName:(NSString *)name engine:(NSString *)engine completion:(void (^)(NSString *))completion {
    [self backend:@[@"create",@"--name",name,@"--engine",engine] message:@"Creating an empty Windows environment — no games or account data are copied…" completion:^(NSDictionary *result,NSString *error){
        if(error){[self reportError:error];return;}
        NSString *identifier=result[@"id"];
        [self refreshSelecting:identifier completion:^{if(completion)completion(identifier);}];
    }];
}
- (void)createBottle:(id)sender {
    (void)sender;if(self.busy)return;
    NSString *engine=[self defaultEngine];if(!engine){[self reportError:@"No available engine binding. Set up the existing Wine stack first; this development app does not download engines."];return;}
    if(self.acceptance && self.acceptanceStage==1){
        [self createWithName:self.acceptance[@"bottle_name"]?:@"Installer Fixture" engine:engine completion:^(NSString *identifier){self.acceptanceBottle=identifier;[self.acceptanceEvents addObject:@"native-create-button -> wineboot -> ready"];self.acceptanceStage=2;[self.installButton performClick:nil];}];return;
    }
    NSAlert *alert=NSAlert.new;alert.messageText=@"Create an empty bottle";alert.informativeText=@"Programs installed here share Windows settings. Nothing will be cloned from your existing games or accounts.";[alert addButtonWithTitle:@"Create"];[alert addButtonWithTitle:@"Cancel"];
    NSView *accessory=[[NSView alloc]initWithFrame:NSMakeRect(0,0,380,88)];NSTextField *name=[[NSTextField alloc]initWithFrame:NSMakeRect(0,52,380,24)];name.stringValue=@"Windows App";[accessory addSubview:name];
    NSPopUpButton *engines=[[NSPopUpButton alloc]initWithFrame:NSMakeRect(0,8,380,28) pullsDown:NO];
    for(NSDictionary *entry in self.engines)if([entry[@"available"] boolValue]){[engines addItemWithTitle:entry[@"name"]];engines.lastItem.representedObject=entry[@"id"];}
    for(NSMenuItem *item in engines.itemArray)if([item.representedObject isEqual:engine])[engines selectItem:item];
    [accessory addSubview:engines];alert.accessoryView=accessory;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){if(response==NSAlertFirstButtonReturn)[self createWithName:name.stringValue engine:engines.selectedItem.representedObject completion:nil];}];
}
- (void)runInstaller:(NSString *)path bottle:(NSString *)identifier quiet:(BOOL)quiet completion:(void (^)(void))completion {
    NSMutableArray *args=[NSMutableArray arrayWithArray:@[@"install-file",@"--bottle",identifier,@"--file",path]];if(quiet)[args addObject:@"--quiet"];
    [self backend:args message:@"Windows installer is running. Follow its own prompts; optional shortcuts remain your choice." completion:^(NSDictionary *result,NSString *error){
        if(error){[self reportError:error];return;}
        [self refreshSelecting:identifier completion:^{self.statusLabel.stringValue=[result[@"reboot_required"] boolValue]?@"Installer finished and requested a Windows restart. No active session was reset.":@"Installer process finished. Applications appear when the installer creates a shortcut.";if(completion)completion();}];
    }];
}
- (void)chooseInstallerDestination:(NSString *)path {
    NSAlert *alert=NSAlert.new;alert.messageText=[@"Install " stringByAppendingString:path.lastPathComponent];alert.informativeText=@"A new bottle is the default. Choose an existing bottle only when these programs should share Windows settings. Install only software you trust.";[alert addButtonWithTitle:@"Continue"];[alert addButtonWithTitle:@"Cancel"];
    NSView *view=[[NSView alloc]initWithFrame:NSMakeRect(0,0,430,80)];NSPopUpButton *destination=[[NSPopUpButton alloc]initWithFrame:NSMakeRect(0,42,430,28) pullsDown:NO];[destination addItemWithTitle:@"New bottle (recommended)"];destination.lastItem.representedObject=@"";
    for(NSDictionary *row in self.bottles)if([row[@"phase"] isEqual:@"ready"]){[destination addItemWithTitle:[@"Existing: " stringByAppendingString:row[@"name"]]];destination.lastItem.representedObject=row[@"id"];}
    NSTextField *name=[[NSTextField alloc]initWithFrame:NSMakeRect(0,4,430,24)];name.stringValue=path.lastPathComponent.stringByDeletingPathExtension;name.placeholderString=@"New bottle name";[view addSubview:destination];[view addSubview:name];alert.accessoryView=view;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){
        if(response!=NSAlertFirstButtonReturn)return;
        NSString *identifier=destination.selectedItem.representedObject;
        if(identifier.length)[self runInstaller:path bottle:identifier quiet:NO completion:nil];
        else {NSString *engine=[self defaultEngine];if(!engine){[self reportError:@"No available Wine engine is configured."];return;}[self createWithName:name.stringValue engine:engine completion:^(NSString *created){[self runInstaller:path bottle:created quiet:NO completion:nil];}];}
    }];
}
- (void)installApplication:(id)sender {
    (void)sender;if(self.busy)return;
    if(self.acceptance && self.acceptanceStage==2){
        NSArray *fixtures=self.acceptance[@"fixtures"];
        if(self.fixtureIndex>=fixtures.count){self.acceptanceStage=3;[self launchAcceptanceApp];return;}
        NSDictionary *fixture=fixtures[self.fixtureIndex];
        [self runInstaller:fixture[@"path"] bottle:self.acceptanceBottle quiet:[fixture[@"quiet"] boolValue] completion:^{[self.acceptanceEvents addObject:[@"native-install-button -> " stringByAppendingString:[fixture[@"path"] pathExtension]]];self.fixtureIndex++;[self.installButton performClick:nil];}];return;
    }
    NSOpenPanel *panel=NSOpenPanel.openPanel;panel.title=@"Choose a Windows installer";panel.message=@"Choose a trusted .exe or .msi file. No program runs until you confirm its destination.";panel.canChooseDirectories=NO;panel.allowsMultipleSelection=NO;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){
        if(response!=NSModalResponseOK)return;
        if(![@[@"exe",@"msi"] containsObject:panel.URL.pathExtension.lowercaseString]){[self reportError:@"Choose a Windows .exe or .msi installer."];return;}
        [self chooseInstallerDestination:panel.URL.path];
    }];
}
- (void)launchApplication:(id)sender {
    (void)sender;if(self.busy || !self.selectedBottle || !self.selectedApp)return;
    NSString *identifier=self.selectedBottle[@"id"],*application=self.selectedApp[@"id"];
    [self backend:@[@"launch",@"--bottle",identifier,@"--app",application] message:@"Sending launch request through this bottle’s configured engine…" completion:^(NSDictionary *result,NSString *error){
        (void)result;if(error){[self reportError:error];return;}self.statusLabel.stringValue=@"Launch request sent. A dispatch is not a compatibility verdict.";
        if(self.acceptance && self.acceptanceStage==3){[self.acceptanceEvents addObject:@"native-launch-button -> Wine shell link"];[self waitForAcceptanceMarker:0];}
        if(self.runtimeLaunchCompletion){void (^done)(void)=self.runtimeLaunchCompletion;self.runtimeLaunchCompletion=nil;done();}
    }];
}
- (void)windowsUninstaller:(id)sender {
    (void)sender;if(self.busy || !self.selectedBottle)return;
    NSAlert *alert=NSAlert.new;alert.messageText=@"Open this bottle’s Windows uninstaller?";alert.informativeText=@"Steam and EA games should be removed inside their store clients. This opens the Windows application list; it does not delete the bottle or any backups.";[alert addButtonWithTitle:@"Open Uninstaller"];[alert addButtonWithTitle:@"Cancel"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response){if(response!=NSAlertFirstButtonReturn)return;[self backend:@[@"uninstaller",@"--bottle",self.selectedBottle[@"id"]] message:@"Opening Windows application management…" completion:^(NSDictionary *result,NSString *error){(void)result;if(error)[self reportError:error];else self.statusLabel.stringValue=@"Windows application management opened. No bottle or backup was removed.";}];}];
}
- (NSDictionary *)selectedRuntimeProcess {
    NSInteger row=self.runtimeTable.selectedRow;NSArray *processes=self.runtimeSnapshot[@"processes"];
    return row>=0 && row<(NSInteger)processes.count?processes[row]:nil;
}
- (void)showRuntime:(id)sender {
    (void)sender;if(self.busy || ![self.selectedBottle[@"phase"] isEqual:@"ready"])return;
    if(self.runtimeWindow){[self.runtimeWindow close];}
    self.runtimeBottle=self.selectedBottle.copy;self.runtimeApp=self.selectedApp.copy;self.runtimeSnapshot=nil;self.runtimeForceRequired=NO;
    self.runtimeWindow=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,850,500) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.runtimeWindow.title=[@"Running Apps — " stringByAppendingString:self.runtimeBottle[@"name"]?:@"Bottle"];
    self.runtimeWindow.minSize=NSMakeSize(800,420);self.runtimeWindow.releasedWhenClosed=NO;self.runtimeWindow.delegate=self;
    NSView *content=self.runtimeWindow.contentView;
    NSStackView *layout=[NSStackView stackViewWithViews:@[]];layout.orientation=NSUserInterfaceLayoutOrientationVertical;layout.alignment=NSLayoutAttributeLeading;layout.spacing=12;layout.translatesAutoresizingMaskIntoConstraints=NO;[content addSubview:layout];
    [NSLayoutConstraint activateConstraints:@[[layout.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],[layout.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],[layout.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],[layout.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20]]];
    self.runtimeLabel=[self label:@"Inspecting this bottle without starting Wine…" size:13 bold:NO];[layout addArrangedSubview:self.runtimeLabel];
    NSTableView *table=NSTableView.new;self.runtimeTable=table;table.dataSource=self;table.delegate=self;table.rowHeight=28;table.allowsEmptySelection=YES;
    for(NSArray *definition in @[@[@"name",@"Process",@420],@[@"pid",@"macOS PID",@100],@[@"role",@"Role",@180]]){
        NSTableColumn *column=[[NSTableColumn alloc]initWithIdentifier:definition[0]];column.title=definition[1];column.width=[definition[2] doubleValue];[table addTableColumn:column];
    }
    self.runtimeTable=table;NSScrollView *scroll=NSScrollView.new;scroll.documentView=table;scroll.hasVerticalScroller=YES;[layout addArrangedSubview:scroll];
    self.runtimeRefreshButton=[self button:@"Refresh Processes" action:@selector(refreshRuntime:)];
    self.runtimeTerminateButton=[self button:@"Terminate Process…" action:@selector(terminateRuntimeProcess:)];
    self.runtimeForceButton=[self button:@"Force Quit Process…" action:@selector(forceRuntimeProcess:)];
    NSStackView *individual=[NSStackView stackViewWithViews:@[self.runtimeRefreshButton,self.runtimeTerminateButton,self.runtimeForceButton]];individual.spacing=8;[layout addArrangedSubview:individual];
    self.runtimeQuitButton=[self button:@"Quit All Applications…" action:@selector(quitRuntimeBottle:)];
    self.runtimeRestartButton=[self button:@"Restart Selected App…" action:@selector(restartRuntimeApp:)];
    NSStackView *bottle=[NSStackView stackViewWithViews:@[self.runtimeQuitButton,self.runtimeRestartButton]];bottle.spacing=8;[layout addArrangedSubview:bottle];
    self.runtimeButtons=@[self.runtimeRefreshButton,self.runtimeTerminateButton,self.runtimeForceButton,self.runtimeQuitButton,self.runtimeRestartButton];
    NSTextField *warning=[self label:@"Termination can lose unsaved work and interrupt installs/downloads. Other bottles and files are not reset. No automatic recovery is enabled." size:11 bold:NO];warning.textColor=NSColor.secondaryLabelColor;[layout addArrangedSubview:warning];
    [NSLayoutConstraint activateConstraints:@[[scroll.widthAnchor constraintEqualToAnchor:layout.widthAnchor],[scroll.heightAnchor constraintGreaterThanOrEqualToConstant:180],[self.runtimeLabel.widthAnchor constraintEqualToAnchor:layout.widthAnchor],[warning.widthAnchor constraintEqualToAnchor:layout.widthAnchor]]];
    [self.runtimeWindow center];[self.runtimeWindow makeKeyAndOrderFront:nil];[self refreshRuntime:nil];
}
- (void)refreshRuntime:(id)sender {
    (void)sender;if(self.busy || !self.runtimeBottle)return;
    NSDictionary *bottle=self.runtimeBottle;self.runtimeSnapshot=nil;[self.runtimeTable reloadData];[self updateControls];
    [self backend:@[@"processes",@"--bottle",bottle[@"id"]] message:@"Inspecting native Wine processes; no Windows helper is launched…" completion:^(NSDictionary *result,NSString *error){
        if(![self.runtimeBottle[@"id"] isEqual:bottle[@"id"]])return;
        if(error){self.runtimeLabel.stringValue=error;[self reportError:error];return;}
        self.runtimeSnapshot=result;[self.runtimeTable reloadData];
        if([result[@"processes"] count])[self.runtimeTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        self.runtimeLabel.stringValue=[NSString stringWithFormat:@"%@ · %lu processes · Restart target: %@\n%@",bottle[@"name"],(unsigned long)[result[@"processes"] count],self.runtimeApp[@"name"]?:@"none selected",[result[@"complete"] boolValue]?@"Prefix ownership verified. Responsiveness is not measured by this list.":@"Some ownership could not be verified. Bottle-wide actions are blocked; refresh before retrying."];
        [self updateControls];[self recordUIHealth];
        if(self.runtimeCompletion){void (^done)(void)=self.runtimeCompletion;self.runtimeCompletion=nil;done();}
    }];
}
- (void)confirmRuntimeAction:(NSString *)operation process:(NSDictionary *)process {
    if(self.busy || !self.runtimeSnapshot || !self.runtimeBottle)return;
    // Capture immutable targets NOW: changing the main selection while a sheet
    // is open must never redirect consent into another bottle or process.
    NSDictionary *snapshot=self.runtimeSnapshot.copy,*bottle=self.runtimeBottle.copy,*application=self.runtimeApp.copy;
    BOOL force=[operation hasPrefix:@"force-"];BOOL single=[operation isEqual:@"terminate"]||[operation isEqual:@"force-process"];BOOL restart=[operation isEqual:@"restart"]||[operation isEqual:@"force-restart"];
    if(single && (!process || [process[@"server"] boolValue]))return;
    if(!single && ![snapshot[@"complete"] boolValue])return;
    NSString *title=single?[NSString stringWithFormat:@"%@ %@ (PID %@)?",force?@"Force quit":@"Terminate",process[@"name"],process[@"pid"]]:restart?[NSString stringWithFormat:@"Stop this bottle and restart %@?",application[@"name"]?:@"the selected app"]:[NSString stringWithFormat:@"%@ all applications in %@?",force?@"Force quit":@"Quit",bottle[@"name"]];
    NSAlert *alert=NSAlert.new;alert.alertStyle=NSAlertStyleWarning;alert.messageText=title;
    alert.informativeText=[NSString stringWithFormat:@"%@ Unsaved games/documents may be lost and installation, repair or download writes may be interrupted. %@ Other bottles, saved login and bottle files are not reset. A changed process list requires fresh confirmation.",force?@"This sends an immediate, uncatchable kill to the explicitly selected processes.":@"This sends native termination requests, not a guaranteed Windows save-dialog handshake.",restart?@"Only this registered application is relaunched after a verified stop; an installer/uninstaller is never replayed.":@"Nothing is automatically relaunched or escalated."];
    [alert addButtonWithTitle:@"Cancel"];[alert addButtonWithTitle:force?@"Force Quit":restart?@"Stop and Restart":@"Terminate"];
    self.runtimeConfirmation=alert;
    [alert beginSheetModalForWindow:self.runtimeWindow completionHandler:^(NSModalResponse response){
        self.runtimeConfirmation=nil;
        if(response!=NSAlertSecondButtonReturn){if(self.runtimeCancelCompletion){void (^done)(void)=self.runtimeCancelCompletion;self.runtimeCancelCompletion=nil;done();}return;}
        NSMutableArray *args=[NSMutableArray arrayWithArray:@[@"runtime-action",@"--bottle",bottle[@"id"],@"--snapshot",snapshot[@"token"],@"--operation",operation,@"--yes"]];
        if(single)[args addObjectsFromArray:@[@"--pid",[process[@"pid"] stringValue]]];
        if(restart){if(!application[@"id"]){[self reportError:@"Select a registered application before opening Running Apps."];return;}[args addObjectsFromArray:@[@"--app",application[@"id"]]];}
        [self backend:args message:force?@"Force quitting only the confirmed process identities…":@"Terminating only the confirmed process identities; no automatic force escalation…" completion:^(NSDictionary *result,NSString *error){
            if(error){self.runtimeSnapshot=nil;[self.runtimeTable reloadData];[self updateControls];[self reportError:error];return;}
            self.lastRuntimeResult=result;self.runtimeForceRequired=([operation isEqual:@"quit-all"]||[operation isEqual:@"restart"]) && [result[@"force_required"] boolValue];
            self.statusLabel.stringValue=[result[@"stopped"] boolValue]?([result[@"launch_dispatched"] boolValue]?@"Old session stopped; selected app launch dispatched. Verify its window before resuming work.":@"Confirmed process/session exited. No files were reset."):@"Some processes remain or ownership changed. No automatic force quit or relaunch occurred.";
            [self refreshRuntime:nil];
        }];
    }];
    // Acceptance drives the actual NSAlert buttons, not a backend bypass. It is
    // gated to a private bundle/specification and isolated fixture prefixes.
    [self recordUIHealth];
    if(self.runtimeTestResponse){NSInteger choice=self.runtimeTestResponse.integerValue;self.runtimeTestResponse=nil;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.15*NSEC_PER_SEC)),dispatch_get_main_queue(),^{if(self.runtimeConfirmation==alert && choice>=0 && choice<(NSInteger)alert.buttons.count)[alert.buttons[choice] performClick:nil];});}
}
- (void)terminateRuntimeProcess:(id)sender {(void)sender;[self confirmRuntimeAction:@"terminate" process:self.selectedRuntimeProcess];}
- (void)forceRuntimeProcess:(id)sender {(void)sender;[self confirmRuntimeAction:@"force-process" process:self.selectedRuntimeProcess];}
- (void)quitRuntimeBottle:(id)sender {(void)sender;[self confirmRuntimeAction:self.runtimeForceRequired?@"force-all":@"quit-all" process:nil];}
- (void)restartRuntimeApp:(id)sender {(void)sender;[self confirmRuntimeAction:self.runtimeForceRequired?@"force-restart":@"restart" process:nil];}
- (void)windowWillClose:(NSNotification *)notification {
    if(notification.object==self.runtimeWindow){[self.actionButtons removeObjectsInArray:self.runtimeButtons?:@[]];self.runtimeButtons=nil;self.runtimeWindow=nil;self.runtimeSnapshot=nil;self.runtimeBottle=nil;self.runtimeApp=nil;}
}

- (void)showFiles:(id)sender {(void)sender;NSString *path=self.selectedBottle[@"path"];if(path)[NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:path]];}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)application hasVisibleWindows:(BOOL)visible {(void)application;(void)visible;[self.window makeKeyAndOrderFront:nil];return NO;}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application {(void)application;return NO;}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;if(!self.busy)return NSTerminateNow;
    NSAlert *alert=NSAlert.new;alert.messageText=@"A Windows operation is still running";alert.informativeText=@"Quitting Chardonnay will not terminate the installer or Windows applications. Leave it open to see the result.";[alert addButtonWithTitle:@"Keep Open"];[alert addButtonWithTitle:@"Quit Manager Only"];
    return [alert runModal]==NSAlertSecondButtonReturn?NSTerminateNow:NSTerminateCancel;
}
- (NSDictionary *)runtimeFixtureProcess {
    for(NSDictionary *process in self.runtimeSnapshot[@"processes"])if([process[@"name"] isEqual:@"RuntimeFixture.exe"])return process;
    return nil;
}
- (void)waitForRuntimeFixture:(NSUInteger)attempt completion:(void (^)(void))completion {
    __weak ChardonnayApp *weakSelf=self;
    if(attempt>80){[weakSelf finishAcceptance:NO error:@"Runtime fixture did not reach a complete native process inventory"];return;}
    weakSelf.runtimeCompletion=^{
        if(weakSelf.runtimeFixtureProcess && [weakSelf.runtimeSnapshot[@"complete"] boolValue])completion();
        else dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.25*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[weakSelf waitForRuntimeFixture:attempt+1 completion:completion];});
    };
    [weakSelf refreshRuntime:nil];
}
- (void)selectRuntimeFixture {
    __weak ChardonnayApp *weakSelf=self;
    NSArray *processes=weakSelf.runtimeSnapshot[@"processes"];NSUInteger row=[processes indexOfObject:weakSelf.runtimeFixtureProcess];
    if(row!=NSNotFound)[weakSelf.runtimeTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
}
- (void)acceptanceLaunchRuntime:(void (^)(void))completion {
    __weak ChardonnayApp *weakSelf=self;
    weakSelf.runtimeLaunchCompletion=^{[weakSelf waitForRuntimeFixture:0 completion:completion];};
    [weakSelf.launchButton performClick:nil];
}
- (void)startRuntimeAcceptance {
    __weak ChardonnayApp *weakSelf=self;
    weakSelf.acceptanceStage=4;weakSelf.runtimeReports=NSMutableArray.new;
    weakSelf.runtimeCompletion=^{[weakSelf waitForRuntimeFixture:0 completion:^{[weakSelf runtimeAcceptanceCancel];}];};
    [weakSelf.runtimeButton performClick:nil];
}
- (void)runtimeAcceptanceCancel {
    __weak ChardonnayApp *weakSelf=self;
    [weakSelf selectRuntimeFixture];NSDictionary *before=weakSelf.runtimeFixtureProcess.copy;
    weakSelf.runtimeTestResponse=@0;
    weakSelf.runtimeCancelCompletion=^{
        if(![weakSelf.runtimeFixtureProcess[@"birth"] isEqual:before[@"birth"]]){[weakSelf finishAcceptance:NO error:@"Cancel changed the selected process"];return;}
        [weakSelf.acceptanceEvents addObject:@"runtime-native-confirmation-cancel"];[weakSelf runtimeAcceptanceTerminate];
    };
    [weakSelf.runtimeTerminateButton performClick:nil];
}
- (void)runtimeAcceptanceTerminate {
    __weak ChardonnayApp *weakSelf=self;
    [weakSelf selectRuntimeFixture];weakSelf.runtimeTestResponse=@1;
    weakSelf.runtimeCompletion=^{
        if(![weakSelf.lastRuntimeResult[@"stopped"] boolValue] || weakSelf.runtimeFixtureProcess){[weakSelf finishAcceptance:NO error:@"Targeted TERM did not retire only the fixture"];return;}
        [weakSelf.runtimeReports addObject:weakSelf.lastRuntimeResult];[weakSelf.acceptanceEvents addObject:@"runtime-native-targeted-TERM"];
        [weakSelf acceptanceLaunchRuntime:^{[weakSelf runtimeAcceptanceForceProcess];}];
    };
    [weakSelf.runtimeTerminateButton performClick:nil];
}
- (void)runtimeAcceptanceForceProcess {
    __weak ChardonnayApp *weakSelf=self;
    [weakSelf selectRuntimeFixture];weakSelf.runtimeTestResponse=@1;
    weakSelf.runtimeCompletion=^{
        if(![weakSelf.lastRuntimeResult[@"stopped"] boolValue] || weakSelf.runtimeFixtureProcess){[weakSelf finishAcceptance:NO error:@"Explicit process force quit failed"];return;}
        [weakSelf.runtimeReports addObject:weakSelf.lastRuntimeResult];[weakSelf.acceptanceEvents addObject:@"runtime-native-explicit-process-KILL"];
        [weakSelf acceptanceLaunchRuntime:^{[weakSelf runtimeAcceptanceRestart];}];
    };
    [weakSelf.runtimeForceButton performClick:nil];
}
- (void)runtimeAcceptanceRestart {
    __weak ChardonnayApp *weakSelf=self;
    weakSelf.runtimeTestResponse=@1;
    weakSelf.runtimeCompletion=^{
        [weakSelf.runtimeReports addObject:weakSelf.lastRuntimeResult];
        if(![weakSelf.lastRuntimeResult[@"stopped"] boolValue]){
            if(!weakSelf.runtimeForceRequired || [weakSelf.lastRuntimeResult[@"launch_dispatched"] boolValue]){[weakSelf finishAcceptance:NO error:@"Unverified restart dispatched a new app"];return;}
            [weakSelf.acceptanceEvents addObject:@"runtime-native-restart-requires-separate-force-consent"];
            weakSelf.runtimeTestResponse=@1;
            weakSelf.runtimeCompletion=^{
                if(![weakSelf.lastRuntimeResult[@"stopped"] boolValue] || ![weakSelf.lastRuntimeResult[@"launch_dispatched"] boolValue]){[weakSelf finishAcceptance:NO error:@"Explicit force-restart did not retire and relaunch the fixture"];return;}
                [weakSelf.runtimeReports addObject:weakSelf.lastRuntimeResult];[weakSelf.acceptanceEvents addObject:@"runtime-native-whole-bottle-restart"];
                [weakSelf waitForRuntimeFixture:0 completion:^{[weakSelf runtimeAcceptanceStartStubborn];}];
            };[weakSelf.runtimeRestartButton performClick:nil];return;
        }
        if(![weakSelf.lastRuntimeResult[@"launch_dispatched"] boolValue]){[weakSelf finishAcceptance:NO error:@"Verified restart did not dispatch its app"];return;}
        [weakSelf.acceptanceEvents addObject:@"runtime-native-whole-bottle-restart"];
        [weakSelf waitForRuntimeFixture:0 completion:^{[weakSelf runtimeAcceptanceStartStubborn];}];
    };
    [weakSelf.runtimeRestartButton performClick:nil];
}
- (void)runtimeAcceptanceStartStubborn {
    __weak ChardonnayApp *weakSelf=self;
    NSString *executable=weakSelf.acceptance[@"stubborn_executable"],*marker=[weakSelf.runtimeBottle[@"path"] stringByAppendingPathComponent:@"drive_c/ChardonnayRuntime-stubborn.txt"];
    NSString *root=[weakSelf.acceptance[@"report"] stringByDeletingLastPathComponent];
    if(![executable hasPrefix:[root stringByAppendingString:@"/"]] || ![weakSelf.runtimeBottle[@"path"] hasPrefix:[weakSelf.stateDirectory stringByAppendingString:@"/bottles/"]]){[weakSelf finishAcceptance:NO error:@"Unowned stubborn fixture destination"];return;}
    NSDictionary *binding=weakSelf.runtimeSnapshot[@"binding"];
    NSString *directory=[NSString stringWithFormat:@"/private/tmp/.wine-%u/server-%llx-%llx",getuid(),[binding[@"device"] unsignedLongLongValue],[binding[@"inode"] unsignedLongLongValue]];
    NSTask *task=NSTask.new;task.executableURL=[NSURL fileURLWithPath:executable];task.arguments=@[directory,marker];
    task.standardInput=NSFileHandle.fileHandleWithNullDevice;task.standardOutput=NSFileHandle.fileHandleWithNullDevice;task.standardError=NSFileHandle.fileHandleWithNullDevice;
    weakSelf.runtimeStubborn=task;NSError *error=nil;if(![task launchAndReturnError:&error]){[weakSelf finishAcceptance:NO error:error.localizedDescription];return;}
    [weakSelf waitForStubbornMarker:marker attempt:0];
}
- (void)waitForStubbornMarker:(NSString *)marker attempt:(NSUInteger)attempt {
    __weak ChardonnayApp *weakSelf=self;
    if(attempt>50){[weakSelf finishAcceptance:NO error:@"Stubborn native fixture did not start"];return;}
    if(![NSFileManager.defaultManager fileExistsAtPath:marker]){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[weakSelf waitForStubbornMarker:marker attempt:attempt+1];});return;}
    weakSelf.runtimeCompletion=^{
        if(![weakSelf.runtimeSnapshot[@"complete"] boolValue]){[weakSelf finishAcceptance:NO error:@"Stubborn fixture namespace was not attributed"];return;}
        weakSelf.runtimeTestResponse=@1;weakSelf.runtimeCompletion=^{[weakSelf runtimeAcceptanceForceAll];};[weakSelf.runtimeQuitButton performClick:nil];
    };[weakSelf refreshRuntime:nil];
}
- (void)runtimeAcceptanceForceAll {
    __weak ChardonnayApp *weakSelf=self;
    if([weakSelf.lastRuntimeResult[@"stopped"] boolValue] || !weakSelf.runtimeForceRequired || !weakSelf.runtimeStubborn.running){[weakSelf finishAcceptance:NO error:@"Normal quit escalated or failed to retain the stubborn fixture"];return;}
    [weakSelf.runtimeReports addObject:weakSelf.lastRuntimeResult];[weakSelf.acceptanceEvents addObject:@"runtime-native-no-automatic-escalation"];
    weakSelf.runtimeTestResponse=@0;weakSelf.runtimeCancelCompletion=^{
        if(!weakSelf.runtimeStubborn.running){[weakSelf finishAcceptance:NO error:@"Cancelling force quit killed the fixture"];return;}
        [weakSelf.acceptanceEvents addObject:@"runtime-native-force-all-cancel"];
        weakSelf.runtimeTestResponse=@1;weakSelf.runtimeCompletion=^{
            if(![weakSelf.lastRuntimeResult[@"stopped"] boolValue] || [weakSelf.runtimeSnapshot[@"processes"] count]){[weakSelf finishAcceptance:NO error:@"Force quit did not verify an empty fixture session"];return;}
            [weakSelf.runtimeReports addObject:weakSelf.lastRuntimeResult];[weakSelf.acceptanceEvents addObject:@"runtime-native-explicit-force-all"];
            [weakSelf finishAcceptance:YES error:nil];
        };[weakSelf.runtimeQuitButton performClick:nil];
    };[weakSelf.runtimeQuitButton performClick:nil];
}

- (void)launchAcceptanceApp {
    NSUInteger index=[self.apps indexOfObjectPassingTest:^BOOL(NSDictionary *row,NSUInteger i,BOOL *stop){(void)i;(void)stop;return [row[@"name"] isEqual:self.acceptance[@"launch_name"]];}];
    if(index==NSNotFound){[self finishAcceptance:NO error:@"Installed fixture shortcut was not discovered"];return;}
    [self.appTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];[self.launchButton performClick:nil];
}
- (void)waitForAcceptanceMarker:(NSUInteger)attempt {
    BOOL runtime=[self.acceptance[@"workflow"] isEqual:@"runtime"];
    NSString *marker=[self.selectedBottle[@"path"] stringByAppendingPathComponent:runtime?@"drive_c/ChardonnayRuntime-launch.txt":@"drive_c/ChardonnayFixture-launch.txt"];
    if([NSFileManager.defaultManager fileExistsAtPath:marker]){if(runtime)[self startRuntimeAcceptance];else[self finishAcceptance:YES error:nil];return;}
    if(attempt>=120){[self finishAcceptance:NO error:@"Launched fixture did not produce its fresh marker"];return;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[self waitForAcceptanceMarker:attempt+1];});
}
- (void)finishAcceptance:(BOOL)success error:(NSString *)error {
    if(!self.acceptance)return;
    NSDictionary *report=@{@"success":@(success),@"error":error?:@"",@"window_visible":@(self.window.isVisible),@"window_title":self.window.title,@"bottle_rows":@(self.bottleTable.numberOfRows),@"application_rows":@(self.appTable.numberOfRows),@"bottle_id":self.acceptanceBottle?:@"",@"bottle_path":self.selectedBottle[@"path"]?:@"",@"events":self.acceptanceEvents,@"runtime_results":self.runtimeReports?:@[],@"runtime_window_visible":@(self.runtimeWindow.isVisible),@"pid":@(getpid())};
    NSWindow *captureWindow=self.runtimeWindow?:self.window;NSView *view=captureWindow.contentView;
    NSBitmapImageRep *bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
    if(bitmap){[view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];[[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[self.acceptance[@"report"] stringByAppendingString:@".png"] atomically:YES];}
    // ScreenCaptureKit's current-process API exposes only content this process
    // may capture without requesting global TCC screen-recording permission.
    // Never enumerate/capture another app; an unavailable image is not a pass.
    __block BOOL completed=NO;
    void (^finish)(NSString *)=^(NSString *source){dispatch_async(dispatch_get_main_queue(),^{
        if(completed)return;completed=YES;
        NSMutableDictionary *result=report.mutableCopy;result[@"capture_source"]=source;
        NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];[data writeToFile:self.acceptance[@"report"] atomically:YES];
        self.busy=NO;[NSApp terminate:nil];
    });};
    if(@available(macOS 14.4,*)){
        CGWindowID identifier=(CGWindowID)captureWindow.windowNumber;
        size_t width=(size_t)(captureWindow.frame.size.width*captureWindow.backingScaleFactor);
        size_t height=(size_t)(captureWindow.frame.size.height*captureWindow.backingScaleFactor);
        [SCShareableContent getCurrentProcessShareableContentWithCompletionHandler:^(SCShareableContent *content,NSError *contentError){
            if(contentError){finish(@"compositor-unavailable");return;}
            SCWindow *owned=nil;for(SCWindow *candidate in content.windows)if(candidate.windowID==identifier && candidate.owningApplication.processID==getpid()){owned=candidate;break;}
            if(!owned){finish(@"own-window-not-shareable");return;}
            SCContentFilter *filter=[[SCContentFilter alloc]initWithDesktopIndependentWindow:owned];
            SCStreamConfiguration *configuration=SCStreamConfiguration.new;configuration.width=width;configuration.height=height;configuration.showsCursor=NO;
            [SCScreenshotManager captureImageWithFilter:filter configuration:configuration completionHandler:^(CGImageRef image,NSError *captureError){
                if(captureError || !image){finish(@"compositor-unavailable");return;}
                NSBitmapImageRep *composited=[[NSBitmapImageRep alloc]initWithCGImage:image];
                BOOL saved=[[composited representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[self.acceptance[@"report"] stringByAppendingString:@".compositor.png"] atomically:YES];
                finish(saved?@"ScreenCaptureKit-own-window":@"compositor-write-failed");
            }];
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{finish(@"compositor-timeout");});
    }else finish(@"appkit-view-cache-only");
}
@end

int main(int argc,const char *argv[]){(void)argc;(void)argv;@autoreleasepool{NSApplication *application=NSApplication.sharedApplication;ChardonnayApp *delegate=ChardonnayApp.new;application.delegate=delegate;[application run];}return 0;}
