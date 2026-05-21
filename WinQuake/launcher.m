// launcher.m -- MacQuake first-run launcher
// Handles game data setup (download shareware or select existing) then launches the engine.

#import <Cocoa/Cocoa.h>
#import <CommonCrypto/CommonCrypto.h>

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
    // If data already present, launch immediately
    if (HasGameData()) {
        [self launchGame];
        return;
    }

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

    // Download button
    downloadBtn = [[NSButton alloc] initWithFrame:NSMakeRect(60, 130, 360, 32)];
    [downloadBtn setTitle:@"Download Shareware Data"];
    [downloadBtn setBezelStyle:NSBezelStyleRounded];
    [downloadBtn setTarget:self];
    [downloadBtn setAction:@selector(startDownload:)];
    [view addSubview:downloadBtn];

    // Select button
    selectBtn = [[NSButton alloc] initWithFrame:NSMakeRect(60, 90, 360, 32)];
    [selectBtn setTitle:@"I Already Have the Full Game…"];
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

    // Launch button (hidden until ready)
    launchBtn = [[NSButton alloc] initWithFrame:NSMakeRect(140, 90, 200, 40)];
    [launchBtn setTitle:@"Launch MacQuake"];
    [launchBtn setBezelStyle:NSBezelStyleRounded];
    [launchBtn setFont:[NSFont boldSystemFontOfSize:14]];
    [launchBtn setTarget:self];
    [launchBtn setAction:@selector(launchGame)];
    [launchBtn setHidden:YES];
    [view addSubview:launchBtn];
}

// -------------------------------------------------------------------------
// Download shareware
// -------------------------------------------------------------------------

- (void)startDownload:(id)sender
{
    [downloadBtn setEnabled:NO];
    [selectBtn setEnabled:NO];
    [progressBar setHidden:NO];
    [statusLabel setStringValue:@"Downloading shareware data…"];

    NSURL *url = [NSURL URLWithString:SHAREWARE_URL];
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    downloadTask = [session downloadTaskWithURL:url];
    [downloadTask resume];
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)task
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    [progressBar setDoubleValue:(double)totalBytesWritten];
    [statusLabel setStringValue:[NSString stringWithFormat:@"Downloading… %.1f MB / %.1f MB",
                                 totalBytesWritten / (1024.0 * 1024.0),
                                 totalBytesExpectedToWrite / (1024.0 * 1024.0)]];
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)task
 didFinishDownloadingToURL:(NSURL *)location
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *destDir = DataDir();
    NSString *destPath = PakPath();

    NSError *err = nil;
    [fm createDirectoryAtPath:destDir withIntermediateDirectories:YES attributes:nil error:&err];
    if (err) {
        [statusLabel setStringValue:[@"Failed to create directory: " stringByAppendingString:[err localizedDescription]]];
        [downloadBtn setEnabled:YES];
        [selectBtn setEnabled:YES];
        return;
    }

    [fm removeItemAtPath:destPath error:nil];
    [fm moveItemAtPath:[location path] toPath:destPath error:&err];
    if (err) {
        [statusLabel setStringValue:[@"Failed to save file: " stringByAppendingString:[err localizedDescription]]];
        [downloadBtn setEnabled:YES];
        [selectBtn setEnabled:YES];
        return;
    }

    // Verify MD5
    [statusLabel setStringValue:@"Verifying download…"];
    NSString *md5 = MD5OfFile(destPath);
    if (![md5 isEqualToString:SHAREWARE_MD5]) {
        [fm removeItemAtPath:destPath error:nil];
        [statusLabel setStringValue:@"Download corrupted. Please try again."];
        [progressBar setDoubleValue:0];
        [downloadBtn setEnabled:YES];
        [selectBtn setEnabled:YES];
        return;
    }

    [self dataReady];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if (error) {
        [statusLabel setStringValue:[@"Download failed: " stringByAppendingString:[error localizedDescription]]];
        [progressBar setDoubleValue:0];
        [downloadBtn setEnabled:YES];
        [selectBtn setEnabled:YES];
    }
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

    // Copy all .pak files from the selected dir to App Support
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *destDir = DataDir();
    NSError *err = nil;
    [fm createDirectoryAtPath:destDir withIntermediateDirectories:YES attributes:nil error:&err];
    if (err) {
        [statusLabel setStringValue:[@"Failed to create directory: " stringByAppendingString:[err localizedDescription]]];
        return;
    }

    NSArray *contents = [fm contentsOfDirectoryAtPath:sourceDir error:nil];
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
        }
    }

    [self dataReady];
}

// -------------------------------------------------------------------------
// Data ready / Launch
// -------------------------------------------------------------------------

- (void)dataReady
{
    [downloadBtn setHidden:YES];
    [selectBtn setHidden:YES];
    [progressBar setHidden:YES];
    [launchBtn setHidden:NO];
    [statusLabel setStringValue:@"Game data ready."];
    [statusLabel setTextColor:[NSColor labelColor]];
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

    NSTask *task = [[NSTask alloc] init];
    [task setExecutableURL:[NSURL fileURLWithPath:gameBinary]];
    [task setArguments:@[ @"-basedir", basedir ]];

    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe];

    NSError *err = nil;
    BOOL ok = [task launchAndReturnError:&err];
    if (!ok) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Failed to launch MacQuake"];
        [alert setInformativeText:[err localizedDescription]];
        [alert runModal];
        return;
    }

    [window close];
    [NSApp terminate:nil];
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
