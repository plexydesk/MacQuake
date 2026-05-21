// launcher.m -- MacQuake first-run launcher
// Handles game data setup (download shareware or select existing) then launches the engine.

#import <Cocoa/Cocoa.h>
#import <CommonCrypto/CommonCrypto.h>
#import <unistd.h>

#define SHAREWARE_URL @"https://archive.org/download/QuakeSwarm/Quake%20Shareware/id1/pak0.pak"
#define SHAREWARE_MD5 @"5906e5998fc3d896ddaf5e6a62e03abb"
#define PAK_SIZE      18689235

static NSString *AppSupportDir(void)
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = [paths firstObject];
    return [base stringByAppendingPathComponent:@"MacQuake"];
}

static NSString *DataDir(void)
{
    return [AppSupportDir() stringByAppendingPathComponent:@"id1"];
}

static NSString *PakPath(void)
{
    return [DataDir() stringByAppendingPathComponent:@"pak0.pak"];
}

static BOOL HasGameData(void)
{
    return [[NSFileManager defaultManager] fileExistsAtPath:PakPath()];
}

static NSString *MD5OfFile(NSString *path)
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;

    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, (CC_LONG)data.length, digest);

    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }
    return output;
}

// -------------------------------------------------------------------------
// Launcher Window Controller
// -------------------------------------------------------------------------

@interface LauncherWindow : NSWindow
@end
@implementation LauncherWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
@end

@interface LauncherDelegate : NSObject <NSApplicationDelegate, NSURLSessionDownloadDelegate>
@end

@implementation LauncherDelegate
{
    NSWindow *window;
    NSTextField *statusLabel;
    NSProgressIndicator *progressBar;
    NSButton *downloadBtn;
    NSButton *selectBtn;
    NSButton *launchBtn;
    NSURLSessionDownloadTask *downloadTask;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    [self showSetupWindow];
}

- (void)showSetupWindow
{
    NSRect frame = NSMakeRect(0, 0, 480, 280);
    window = [[LauncherWindow alloc] initWithContentRect:frame
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    [window setTitle:@"MacQuake Setup"];
    [window center];
    [window setLevel:NSNormalWindowLevel];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    NSView *view = [window contentView];

    // Title
    NSTextField *title = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 220, 440, 30)];
    [title setStringValue:@"Welcome to MacQuake"];
    [title setFont:[NSFont boldSystemFontOfSize:18]];
    [title setBezeled:NO];
    [title setDrawsBackground:NO];
    [title setEditable:NO];
    [title setSelectable:NO];
    [title setAlignment:NSTextAlignmentCenter];
    [view addSubview:title];

    // Subtitle
    NSTextField *subtitle = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 185, 440, 40)];
    [subtitle setStringValue:@"Game data is required to play.\nChoose an option below to get started."];
    [subtitle setFont:[NSFont systemFontOfSize:13]];
    [subtitle setBezeled:NO];
    [subtitle setDrawsBackground:NO];
    [subtitle setEditable:NO];
    [subtitle setSelectable:NO];
    [subtitle setAlignment:NSTextAlignmentCenter];
    [view addSubview:subtitle];

    // Open download page button
    downloadBtn = [[NSButton alloc] initWithFrame:NSMakeRect(60, 130, 360, 32)];
    [downloadBtn setTitle:@"Get Shareware from Archive.org…"];
    [downloadBtn setBezelStyle:NSBezelStyleRounded];
    [downloadBtn setTarget:self];
    [downloadBtn setAction:@selector(openDownloadPage:)];
    [view addSubview:downloadBtn];

    // Use local data button (for dev builds with id1/ next to the app)
    NSButton *localBtn = [[NSButton alloc] initWithFrame:NSMakeRect(60, 95, 360, 28)];
    [localBtn setTitle:@"Use Local id1/ Folder"];
    [localBtn setBezelStyle:NSBezelStyleRounded];
    [localBtn setTarget:self];
    [localBtn setAction:@selector(useLocalData:)];
    [localBtn setTag:100];
    [view addSubview:localBtn];

    // Select button
    selectBtn = [[NSButton alloc] initWithFrame:NSMakeRect(60, 60, 360, 28)];
    [selectBtn setTitle:@"Select Existing Game Data…"];
    [selectBtn setBezelStyle:NSBezelStyleRounded];
    [selectBtn setTarget:self];
    [selectBtn setAction:@selector(selectExistingData:)];
    [view addSubview:selectBtn];

    // Progress bar
    progressBar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(60, 60, 360, 16)];
    [progressBar setStyle:NSProgressIndicatorStyleBar];
    [progressBar setIndeterminate:NO];
    [progressBar setMinValue:0];
    [progressBar setMaxValue:PAK_SIZE];
    [progressBar setDoubleValue:0];
    [progressBar setHidden:YES];
    [view addSubview:progressBar];

    // Status label
    statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 30, 440, 20)];
    [statusLabel setStringValue:@""];
    [statusLabel setFont:[NSFont systemFontOfSize:11]];
    [statusLabel setBezeled:NO];
    [statusLabel setDrawsBackground:NO];
    [statusLabel setEditable:NO];
    [statusLabel setSelectable:NO];
    [statusLabel setAlignment:NSTextAlignmentCenter];
    [statusLabel setTextColor:[NSColor secondaryLabelColor]];
    [view addSubview:statusLabel];

    // Launch button
    launchBtn = [[NSButton alloc] initWithFrame:NSMakeRect(140, 100, 200, 40)];
    [launchBtn setTitle:@"Launch MacQuake"];
    [launchBtn setBezelStyle:NSBezelStyleRounded];
    [launchBtn setFont:[NSFont boldSystemFontOfSize:14]];
    [launchBtn setTarget:self];
    [launchBtn setAction:@selector(launchGame)];
    [view addSubview:launchBtn];

    // Replace data button (shown when data already exists)
    NSButton *replaceBtn = [[NSButton alloc] initWithFrame:NSMakeRect(180, 70, 120, 24)];
    [replaceBtn setTitle:@"Replace Data…"];
    [replaceBtn setBezelStyle:NSBezelStyleRoundRect];
    [replaceBtn setFont:[NSFont systemFontOfSize:11]];
    [replaceBtn setTarget:self];
    [replaceBtn setAction:@selector(showReplaceOptions:)];
    [replaceBtn setTag:101];
    [view addSubview:replaceBtn];

    [self updateUIForDataState];
}

// -------------------------------------------------------------------------
// Open download page
// -------------------------------------------------------------------------

- (void)openDownloadPage:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://archive.org/details/quake106"]];
    [statusLabel setStringValue:@"Browser opened. Download the shareware, then return and select it."];
}

// -------------------------------------------------------------------------
// Use local id1/ folder (for dev builds)
// -------------------------------------------------------------------------

- (void)useLocalData:(id)sender
{
    // Look for id1/ next to the app bundle, or inside it
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *bundleParent = [bundlePath stringByDeletingLastPathComponent];

    NSArray *candidates = @[
        [bundleParent stringByAppendingPathComponent:@"id1"],
        [[bundleParent stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"id1"],
        [bundlePath stringByAppendingPathComponent:@"Contents/id1"],
    ];

    NSString *foundDir = nil;
    for (NSString *candidate in candidates) {
        NSString *pak = [candidate stringByAppendingPathComponent:@"pak0.pak"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:pak]) {
            foundDir = candidate;
            break;
        }
    }

    if (!foundDir) {
        [statusLabel setStringValue:@"No local id1/ folder found next to the app."];
        return;
    }

    [self copyPakFilesFromDir:foundDir];
}

// -------------------------------------------------------------------------
// Select existing data
// -------------------------------------------------------------------------

- (void)selectExistingData:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];
    [panel setMessage:@"Select your Quake id1 folder or pak0.pak file"];

    NSInteger result = [panel runModal];
    if (result != NSModalResponseOK) return;

    NSURL *url = [[panel URLs] firstObject];
    NSString *path = [url path];

    NSString *sourcePak = nil;
    NSString *sourceDir = nil;

    BOOL isDir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];

    if (isDir) {
        // User selected a folder — check if it contains pak0.pak
        NSString *candidate = [path stringByAppendingPathComponent:@"pak0.pak"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
            sourcePak = candidate;
            sourceDir = path;
        }
    } else if ([[path lastPathComponent] isEqualToString:@"pak0.pak"]) {
        sourcePak = path;
        sourceDir = [path stringByDeletingLastPathComponent];
    }

    if (!sourcePak) {
        [statusLabel setStringValue:@"No pak0.pak found in selection."];
        return;
    }

    [self copyPakFilesFromDir:sourceDir];
}

- (void)copyPakFilesFromDir:(NSString *)sourceDir
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *destDir = DataDir();
    NSError *err = nil;
    [fm createDirectoryAtPath:destDir withIntermediateDirectories:YES attributes:nil error:&err];
    if (err) {
        [statusLabel setStringValue:[@"Failed to create directory: " stringByAppendingString:[err localizedDescription]]];
        return;
    }

    NSArray *contents = [fm contentsOfDirectoryAtPath:sourceDir error:nil];
    int copied = 0;
    for (NSString *item in contents) {
        if ([[item pathExtension] isEqualToString:@"pak"]) {
            NSString *src = [sourceDir stringByAppendingPathComponent:item];
            NSString *dst = [destDir stringByAppendingPathComponent:item];
            [fm removeItemAtPath:dst error:nil];
            [fm copyItemAtPath:src toPath:dst error:&err];
            if (err) {
                [statusLabel setStringValue:[@"Failed to copy: " stringByAppendingString:[err localizedDescription]]];
                return;
            }
            copied++;
        }
    }

    [statusLabel setStringValue:[NSString stringWithFormat:@"Copied %d .pak file(s).", copied]];
    [self updateUIForDataState];
}

// -------------------------------------------------------------------------
// Data ready / Launch
// -------------------------------------------------------------------------

- (void)updateUIForDataState
{
    NSButton *localBtn = [window.contentView viewWithTag:100];
    NSButton *replaceBtn = [window.contentView viewWithTag:101];

    if (HasGameData()) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *paks = [[fm contentsOfDirectoryAtPath:DataDir() error:nil]
                         filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self ENDSWITH[c] %@", @".pak"]];
        NSString *pakList = [paks componentsJoinedByString:@", "];
        [statusLabel setStringValue:[NSString stringWithFormat:@"Detected: %@", pakList]];
        [statusLabel setTextColor:[NSColor labelColor]];
        [launchBtn setHidden:NO];
        [downloadBtn setHidden:YES];
        if (localBtn) [localBtn setHidden:YES];
        [selectBtn setHidden:YES];
        if (replaceBtn) [replaceBtn setHidden:NO];
        [progressBar setHidden:YES];
    } else {
        [statusLabel setStringValue:@"No game data found."];
        [statusLabel setTextColor:[NSColor secondaryLabelColor]];
        [launchBtn setHidden:YES];
        [downloadBtn setHidden:NO];
        if (localBtn) [localBtn setHidden:NO];
        [selectBtn setHidden:NO];
        if (replaceBtn) [replaceBtn setHidden:YES];
        [progressBar setHidden:YES];
    }
}

- (void)showReplaceOptions:(id)sender
{
    [launchBtn setHidden:YES];
    [[window.contentView viewWithTag:101] setHidden:YES];
    [downloadBtn setHidden:NO];
    [[window.contentView viewWithTag:100] setHidden:NO];
    [selectBtn setHidden:NO];
    [statusLabel setStringValue:@"Select a new data source below."];
}

- (void)launchGame
{
    NSString *gameBinary = [[NSBundle mainBundle] pathForResource:@"quake" ofType:nil];
    if (!gameBinary) {
        // Fallback: look next to our own binary in MacOS/
        NSString *exePath = [[NSBundle mainBundle] executablePath];
        NSString *exeDir = [exePath stringByDeletingLastPathComponent];
        gameBinary = [exeDir stringByAppendingPathComponent:@"quake"];
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:gameBinary]) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Game binary not found"];
        [alert setInformativeText:[NSString stringWithFormat:@"Could not find quake binary at %@", gameBinary]];
        [alert runModal];
        return;
    }

    NSString *basedir = AppSupportDir();

    // Use execv to replace this process with the game — clean handoff, no child-process issues
    const char *exe = [gameBinary UTF8String];
    const char *arg_basedir = [basedir UTF8String];
    const char *argv[] = { exe, "-basedir", arg_basedir, NULL };

    // Close the launcher window before handing off
    [window close];

    execv(exe, (char *const *)argv);

    // If execv returns, it failed
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Failed to launch MacQuake"];
    [alert setInformativeText:[NSString stringWithFormat:@"execv failed: %s", strerror(errno)]];
    [alert runModal];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

@end

// -------------------------------------------------------------------------
// Main
// -------------------------------------------------------------------------

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        LauncherDelegate *delegate = [[LauncherDelegate alloc] init];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
