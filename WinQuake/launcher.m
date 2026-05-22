// launcher.m -- MacQuake Launcher
// Modern dark UI with cover art and settings panel.

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <CommonCrypto/CommonCrypto.h>
#import <unistd.h>

#define SHAREWARE_ZIP_URL @"https://ftp.gamers.org/pub/games/idgames2/idstuff/quake/quake106.zip"
#define SHAREWARE_MD5     @"5906e5998fc3d896ddaf5e6a62e03abb"
#define ZIP_SIZE          9094045

#pragma mark - Utilities

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

static NSColor *ColorPanelBg(void)   { return [NSColor colorWithCalibratedWhite:0.11 alpha:1.0]; }
static NSColor *ColorSectionText(void){ return [NSColor colorWithCalibratedWhite:0.50 alpha:1.0]; }
static NSColor *ColorFieldBg(void)   { return [NSColor colorWithCalibratedWhite:0.16 alpha:1.0]; }
static NSColor *ColorFieldBorder(void){ return [NSColor colorWithCalibratedWhite:0.22 alpha:1.0]; }
static NSColor *ColorGreenStatus(void){ return [NSColor colorWithCalibratedRed:0.35 green:0.75 blue:0.45 alpha:1.0]; }
static NSColor *ColorRedStatus(void)  { return [NSColor colorWithCalibratedRed:0.85 green:0.30 blue:0.25 alpha:1.0]; }
static NSColor *ColorPlayBtn(void)    { return [NSColor colorWithCalibratedRed:0.42 green:0.22 blue:0.12 alpha:1.0]; }
static NSColor *ColorPlayBtnHover(void){ return [NSColor colorWithCalibratedRed:0.50 green:0.28 blue:0.16 alpha:1.0]; }

#pragma mark - Custom Button

@interface StyledButton : NSButton
@property (nonatomic, strong) NSColor *bgColor;
@property (nonatomic, strong) NSColor *hoverColor;
@property (nonatomic, strong) NSColor *textColor;
@end

@implementation StyledButton
{
    NSTrackingArea *_trackingArea;
    BOOL _hover;
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect bounds = self.bounds;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:6 yRadius:6];
    NSColor *fill = _hover && self.hoverColor ? self.hoverColor : (self.bgColor ?: [NSColor controlColor]);
    [fill setFill];
    [path fill];

    NSString *title = self.title;
    if (title.length > 0) {
        NSDictionary *attrs = @{
            NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:13],
            NSForegroundColorAttributeName: self.textColor ?: [NSColor labelColor]
        };
        NSSize ts = [title sizeWithAttributes:attrs];
        NSRect tr = NSMakeRect(
            bounds.origin.x + (bounds.size.width - ts.width) / 2.0,
            bounds.origin.y + (bounds.size.height - ts.height) / 2.0 - 1,
            ts.width, ts.height
        );
        [title drawInRect:tr withAttributes:attrs];
    }
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways)
                                                  owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event { _hover = YES; [self setNeedsDisplay:YES]; }
- (void)mouseExited:(NSEvent *)event  { _hover = NO;  [self setNeedsDisplay:YES]; }
@end

#pragma mark - id Logo View

@interface IDLogoView : NSView
@end

@implementation IDLogoView
- (void)drawRect:(NSRect)dirtyRect
{
    NSRect r = self.bounds;
    NSBezierPath *path = [NSBezierPath bezierPathWithRect:r];
    [[NSColor colorWithCalibratedWhite:0.85 alpha:0.9] setFill];
    [path fill];

    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:r.size.height * 0.55],
        NSForegroundColorAttributeName: [NSColor blackColor]
    };
    NSString *txt = @"id";
    NSSize ts = [txt sizeWithAttributes:attrs];
    NSPoint pt = NSMakePoint(
        r.origin.x + (r.size.width - ts.width) / 2.0,
        r.origin.y + (r.size.height - ts.height) / 2.0 - 1
    );
    [txt drawAtPoint:pt withAttributes:attrs];
}
@end

#pragma mark - Status Row

@interface StatusRow : NSView
@property (nonatomic, strong) NSTextField *label;
- (void)setOK:(BOOL)ok text:(NSString *)text;
@end

@implementation StatusRow
- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.label = [[NSTextField alloc] initWithFrame:NSMakeRect(14, 0, frame.size.width - 14, 18)];
        [self.label setBezeled:NO];
        [self.label setDrawsBackground:NO];
        [self.label setEditable:NO];
        [self.label setSelectable:NO];
        [self.label setFont:[NSFont systemFontOfSize:11]];
        [self.label setTextColor:ColorGreenStatus()];
        [self addSubview:self.label];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect dot = NSMakeRect(2, 6, 8, 8);
    NSBezierPath *p = [NSBezierPath bezierPathWithOvalInRect:dot];
    [[self.label textColor] setFill];
    [p fill];
}

- (void)setOK:(BOOL)ok text:(NSString *)text
{
    [self.label setStringValue:text];
    [self.label setTextColor:ok ? ColorGreenStatus() : ColorRedStatus()];
    [self setNeedsDisplay:YES];
}
@end

#pragma mark - Launcher Delegate

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

    // Right panel UI
    NSTextField *exePathField;
    StatusRow *exeStatus;
    NSTextField *dataPathField;
    StatusRow *dataStatus;
    NSPopUpButton *rendererPopup;
    NSPopUpButton *soundPopup;
    NSButton *musicCheckbox;
    NSButton *sfxCheckbox;
    NSTextField *argsField;
    StyledButton *playBtn;
    StyledButton *downloadSharewareBtn;

    // Progress / status
    NSProgressIndicator *progressBar;
    NSTextField *statusLabel;

    NSURLSessionDownloadTask *downloadTask;
    NSString *selectedGameBinary;
}

#pragma mark - Lifecycle

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    // Auto-copy bundled pak on first run
    if (!HasGameData()) {
        NSString *bundledPak = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"id1/pak0.pak"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:bundledPak]) {
            [self copyPakFilesFromDir:[bundledPak stringByDeletingLastPathComponent]];
        }
    }

    selectedGameBinary = [self findDefaultBinary];
    [self showMainWindow];
}

- (NSString *)findDefaultBinary
{
    NSString *fromBundle = [[NSBundle mainBundle] pathForResource:@"quake" ofType:nil];
    if (fromBundle && [[NSFileManager defaultManager] fileExistsAtPath:fromBundle]) return fromBundle;

    NSString *exeDir = [[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent];
    NSString *candidate = [exeDir stringByAppendingPathComponent:@"quake"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) return candidate;

    return nil;
}

#pragma mark - Window Creation

- (void)showMainWindow
{
    CGFloat winW = 920;
    CGFloat winH = 720;
    NSRect frame = NSMakeRect(0, 0, winW, winH);
    window = [[LauncherWindow alloc] initWithContentRect:frame
                                               styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskFullSizeContentView
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    [window setTitle:@"Quake"];
    window.titleVisibility = NSWindowTitleHidden;
    window.titlebarAppearsTransparent = YES;
    [window center];
    [window setLevel:NSNormalWindowLevel];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    NSView *view = [window contentView];
    [view setWantsLayer:YES];
    [view.layer setBackgroundColor:[NSColor blackColor].CGColor];

    // ---- Left Cover Panel ----
    NSView *leftPanel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, winH)];
    [leftPanel setWantsLayer:YES];
    leftPanel.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.067 green:0.059 blue:0.051 alpha:1.0].CGColor;

    // Cover image
    NSImage *cover = nil;
    NSString *coverPath = [[NSBundle mainBundle] pathForResource:@"quake_art" ofType:@"png"];
    if (coverPath) cover = [[NSImage alloc] initWithContentsOfFile:coverPath];
    if (!cover) {
        NSString *exeDir = [[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent];
        cover = [[NSImage alloc] initWithContentsOfFile:[exeDir stringByAppendingPathComponent:@"quake_art.png"]];
    }

    // Aspect-fit cover image (maintain aspect ratio, fit entirely inside panel)
    // Panel background matches image average color so letterbox areas blend in
    NSImageView *coverView = [[NSImageView alloc] initWithFrame:leftPanel.bounds];
    [coverView setImageScaling:NSImageScaleProportionallyUpOrDown];
    [coverView setImage:cover];
    [leftPanel addSubview:coverView];

    // Gradient overlay at bottom for text readability
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = NSMakeRect(0, 0, 480, winH);
    gradient.colors = @[
        (id)[NSColor clearColor].CGColor,
        (id)[NSColor clearColor].CGColor,
        (id)[NSColor colorWithCalibratedWhite:0.0 alpha:0.6].CGColor
    ];
    gradient.locations = @[@0.0, @0.65, @1.0];
    [leftPanel.layer addSublayer:gradient];

    // id logo + copyright
    IDLogoView *idLogo = [[IDLogoView alloc] initWithFrame:NSMakeRect(20, 20, 30, 22)];
    [leftPanel addSubview:idLogo];

    NSTextField *copyLbl = [[NSTextField alloc] initWithFrame:NSMakeRect(58, 20, 300, 20)];
    [copyLbl setStringValue:@"© 1996 id Software, LLC"];
    [copyLbl setFont:[NSFont systemFontOfSize:12]];
    [copyLbl setTextColor:[NSColor colorWithCalibratedWhite:0.7 alpha:0.8]];
    [copyLbl setBezeled:NO];
    [copyLbl setDrawsBackground:NO];
    [copyLbl setEditable:NO];
    [copyLbl setSelectable:NO];
    [leftPanel addSubview:copyLbl];

    [view addSubview:leftPanel];

    // ---- Right Settings Panel ----
    CGFloat rightX = 480;
    CGFloat rightW = winW - rightX;
    NSView *rightPanel = [[NSView alloc] initWithFrame:NSMakeRect(rightX, 0, rightW, winH)];
    [rightPanel setWantsLayer:YES];
    [rightPanel.layer setBackgroundColor:ColorPanelBg().CGColor];
    [view addSubview:rightPanel];

    CGFloat y = winH - 40;
    CGFloat margin = 24;
    CGFloat fieldW = rightW - margin * 2;

    // --- GAME ---
    y -= 20;
    [self addSectionHeader:@"GAME" to:rightPanel atY:y x:margin];
    y -= 32;

    NSView *gameField = [self darkFieldFrame:NSMakeRect(margin, y, fieldW, 36)];
    [rightPanel addSubview:gameField];

    NSImageView *gameIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(10, 6, 24, 24)];
    [gameIcon setImage:[self quakeIconImage:24]];
    [gameField addSubview:gameIcon];

    NSTextField *gameName = [[NSTextField alloc] initWithFrame:NSMakeRect(42, 7, fieldW - 60, 22)];
    [gameName setStringValue:@"Quake (1996)"];
    [gameName setFont:[NSFont systemFontOfSize:13]];
    [gameName setTextColor:[NSColor whiteColor]];
    [gameName setBezeled:NO];
    [gameName setDrawsBackground:NO];
    [gameName setEditable:NO];
    [gameName setSelectable:NO];
    [gameField addSubview:gameName];

    NSTextField *arrow = [[NSTextField alloc] initWithFrame:NSMakeRect(fieldW - 28, 7, 20, 22)];
    [arrow setStringValue:@"▾"];
    [arrow setFont:[NSFont systemFontOfSize:14]];
    [arrow setTextColor:[NSColor colorWithCalibratedWhite:0.5 alpha:1.0]];
    [arrow setBezeled:NO];
    [arrow setDrawsBackground:NO];
    [arrow setEditable:NO];
    [arrow setSelectable:NO];
    [arrow setAlignment:NSTextAlignmentCenter];
    [gameField addSubview:arrow];

    // --- EXECUTABLE ---
    y -= 50;
    [self addSectionHeader:@"EXECUTABLE" to:rightPanel atY:y x:margin];
    y -= 32;

    NSView *exeField = [self darkFieldFrame:NSMakeRect(margin, y, fieldW, 36)];
    [rightPanel addSubview:exeField];

    exePathField = [[NSTextField alloc] initWithFrame:NSMakeRect(36, 7, fieldW - 110, 22)];
    [exePathField setStringValue:selectedGameBinary ? [selectedGameBinary lastPathComponent] : @"Quake"];
    [exePathField setFont:[NSFont systemFontOfSize:13]];
    [exePathField setTextColor:[NSColor whiteColor]];
    [exePathField setBezeled:NO];
    [exePathField setDrawsBackground:NO];
    [exePathField setEditable:NO];
    [exePathField setSelectable:NO];
    [exeField addSubview:exePathField];

    NSImageView *exeIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(10, 8, 18, 18)];
    [exeIcon setImage:[self quakeIconImage:18]];
    [exeField addSubview:exeIcon];

    StyledButton *exeSelect = [self smallButton:@"Select..." frame:NSMakeRect(fieldW - 82, 5, 76, 26)];
    [exeSelect setTarget:self];
    [exeSelect setAction:@selector(selectExecutable:)];
    [exeField addSubview:exeSelect];

    exeStatus = [[StatusRow alloc] initWithFrame:NSMakeRect(margin, y - 22, fieldW, 18)];
    [rightPanel addSubview:exeStatus];
    y -= 24;

    // --- GAME DATA FOLDER ---
    y -= 42;
    [self addSectionHeader:@"GAME DATA FOLDER" to:rightPanel atY:y x:margin];
    y -= 32;

    NSView *dataField = [self darkFieldFrame:NSMakeRect(margin, y, fieldW, 36)];
    [rightPanel addSubview:dataField];

    NSImageView *folderIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(10, 8, 18, 18)];
    [folderIcon setImage:[self folderIconImage:18]];
    [dataField addSubview:folderIcon];

    dataPathField = [[NSTextField alloc] initWithFrame:NSMakeRect(34, 7, fieldW - 120, 22)];
    NSString *shortPath = [self shortenPath:AppSupportDir()];
    [dataPathField setStringValue:shortPath];
    [dataPathField setFont:[NSFont systemFontOfSize:13]];
    [dataPathField setTextColor:[NSColor whiteColor]];
    [dataPathField setBezeled:NO];
    [dataPathField setDrawsBackground:NO];
    [dataPathField setEditable:NO];
    [dataPathField setSelectable:NO];
    [dataField addSubview:dataPathField];

    StyledButton *dataSelect = [self smallButton:@"Select..." frame:NSMakeRect(fieldW - 82, 5, 76, 26)];
    [dataSelect setTarget:self];
    [dataSelect setAction:@selector(selectDataFolder:)];
    [dataField addSubview:dataSelect];

    dataStatus = [[StatusRow alloc] initWithFrame:NSMakeRect(margin, y - 22, fieldW, 18)];
    [rightPanel addSubview:dataStatus];
    y -= 24;

    // Download / replace data action row
    downloadSharewareBtn = [self smallButton:@"Download Shareware"
                                       frame:NSMakeRect(margin, y - 30, 140, 28)];
    [downloadSharewareBtn setTarget:self];
    [downloadSharewareBtn setAction:@selector(startDownload:)];
    [downloadSharewareBtn setHidden:YES];
    [rightPanel addSubview:downloadSharewareBtn];
    y -= 20;

    // --- VIDEO ---
    y -= 40;
    [self addSectionHeader:@"VIDEO" to:rightPanel atY:y x:margin];
    y -= 32;

    NSView *videoField = [self darkFieldFrame:NSMakeRect(margin, y, fieldW, 36)];
    [rightPanel addSubview:videoField];

    NSImageView *monitorIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(10, 8, 18, 18)];
    [monitorIcon setImage:[self monitorIconImage:18]];
    [videoField addSubview:monitorIcon];

    NSTextField *videoLbl = [[NSTextField alloc] initWithFrame:NSMakeRect(34, 7, 90, 22)];
    [videoLbl setStringValue:@"Renderer"];
    [videoLbl setFont:[NSFont systemFontOfSize:13]];
    [videoLbl setTextColor:[NSColor whiteColor]];
    [videoLbl setBezeled:NO];
    [videoLbl setDrawsBackground:NO];
    [videoLbl setEditable:NO];
    [videoLbl setSelectable:NO];
    [videoField addSubview:videoLbl];

    rendererPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldW - 170, 5, 160, 26) pullsDown:NO];
    [rendererPopup addItemWithTitle:@"Software (Metal)"];
    [rendererPopup setFont:[NSFont systemFontOfSize:12]];
    [[rendererPopup cell] setBackgroundStyle:NSBackgroundStyleDark];
    [rendererPopup setBordered:NO];
    [videoField addSubview:rendererPopup];
    y -= 22;

    // --- AUDIO ---
    y -= 38;
    [self addSectionHeader:@"AUDIO" to:rightPanel atY:y x:margin];
    y -= 32;

    NSView *audioField = [self darkFieldFrame:NSMakeRect(margin, y, fieldW, 36)];
    [rightPanel addSubview:audioField];

    NSImageView *speakerIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(10, 8, 18, 18)];
    [speakerIcon setImage:[self speakerIconImage:18]];
    [audioField addSubview:speakerIcon];

    NSTextField *audioLbl = [[NSTextField alloc] initWithFrame:NSMakeRect(34, 7, 100, 22)];
    [audioLbl setStringValue:@"Sound Output"];
    [audioLbl setFont:[NSFont systemFontOfSize:13]];
    [audioLbl setTextColor:[NSColor whiteColor]];
    [audioLbl setBezeled:NO];
    [audioLbl setDrawsBackground:NO];
    [audioLbl setEditable:NO];
    [audioLbl setSelectable:NO];
    [audioField addSubview:audioLbl];

    soundPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldW - 170, 5, 160, 26) pullsDown:NO];
    [soundPopup addItemWithTitle:@"Default Output"];
    [soundPopup setFont:[NSFont systemFontOfSize:12]];
    [[soundPopup cell] setBackgroundStyle:NSBackgroundStyleDark];
    [soundPopup setBordered:NO];
    [audioField addSubview:soundPopup];
    y -= 32;

    // Checkboxes
    musicCheckbox = [self checkbox:@"Enable Music" frame:NSMakeRect(margin, y, 140, 20)];
    [musicCheckbox setState:NSControlStateValueOn];
    [rightPanel addSubview:musicCheckbox];

    sfxCheckbox = [self checkbox:@"Enable Sound Effects" frame:NSMakeRect(margin + 160, y, 170, 20)];
    [sfxCheckbox setState:NSControlStateValueOn];
    [rightPanel addSubview:sfxCheckbox];
    y -= 22;

    // --- COMMAND LINE ARGUMENTS ---
    y -= 38;
    [self addSectionHeader:@"COMMAND LINE ARGUMENTS" to:rightPanel atY:y x:margin];
    y -= 32;

    argsField = [[NSTextField alloc] initWithFrame:NSMakeRect(margin, y, fieldW, 34)];
    [argsField setFont:[NSFont systemFontOfSize:12]];
    [argsField setTextColor:[NSColor whiteColor]];
    [argsField setBezeled:NO];
    [[argsField cell] setBackgroundStyle:NSBackgroundStyleDark];
    [argsField setDrawsBackground:YES];
    [argsField setBackgroundColor:ColorFieldBg()];
    [argsField setEditable:YES];
    [argsField setSelectable:YES];
    [argsField setWantsLayer:YES];
    argsField.layer.cornerRadius = 6;
    argsField.layer.borderWidth = 1;
    argsField.layer.borderColor = ColorFieldBorder().CGColor;
    [rightPanel addSubview:argsField];
    y -= 20;

    // Progress & status (above buttons)
    progressBar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(margin, y - 14, fieldW, 10)];
    [progressBar setStyle:NSProgressIndicatorStyleBar];
    [progressBar setIndeterminate:NO];
    [progressBar setMinValue:0];
    [progressBar setMaxValue:ZIP_SIZE];
    [progressBar setDoubleValue:0];
    [progressBar setHidden:YES];
    [rightPanel addSubview:progressBar];

    statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(margin, y - 30, fieldW, 18)];
    [statusLabel setStringValue:@""];
    [statusLabel setFont:[NSFont systemFontOfSize:11]];
    [statusLabel setBezeled:NO];
    [statusLabel setDrawsBackground:NO];
    [statusLabel setEditable:NO];
    [statusLabel setSelectable:NO];
    [statusLabel setTextColor:[NSColor colorWithCalibratedWhite:0.5 alpha:1.0]];
    [rightPanel addSubview:statusLabel];

    // --- Bottom Buttons ---
    CGFloat btnY = 20;
    CGFloat btnH = 36;
    CGFloat playH = 44;

    StyledButton *advancedBtn = [self smallButton:@"Advanced Settings..."
                                            frame:NSMakeRect(margin, btnY + (playH - btnH)/2, 120, btnH)];
    [advancedBtn setTarget:self];
    [advancedBtn setAction:@selector(showAdvanced:)];
    [rightPanel addSubview:advancedBtn];

    StyledButton *modsBtn = [self smallButton:@"Mods & Addons..."
                                        frame:NSMakeRect(margin + 126, btnY + (playH - btnH)/2, 120, btnH)];
    [modsBtn setTarget:self];
    [modsBtn setAction:@selector(showMods:)];
    [rightPanel addSubview:modsBtn];

    CGFloat playX = margin + 126 + 120 + 10;
    CGFloat playW = rightW - margin - playX;
    playBtn = [[StyledButton alloc] initWithFrame:NSMakeRect(playX, btnY, playW, playH)];
    [playBtn setTitle:@"PLAY QUAKE"];
    [playBtn setFont:[NSFont boldSystemFontOfSize:15]];
    [playBtn setBgColor:ColorPlayBtn()];
    [playBtn setHoverColor:ColorPlayBtnHover()];
    [playBtn setTextColor:[NSColor whiteColor]];
    [playBtn setTarget:self];
    [playBtn setAction:@selector(launchGame)];
    [rightPanel addSubview:playBtn];

    [self refreshStatuses];
}

#pragma mark - UI Helpers

- (NSView *)darkFieldFrame:(NSRect)frame
{
    NSView *v = [[NSView alloc] initWithFrame:frame];
    [v setWantsLayer:YES];
    v.layer.backgroundColor = ColorFieldBg().CGColor;
    v.layer.cornerRadius = 6;
    v.layer.borderWidth = 1;
    v.layer.borderColor = ColorFieldBorder().CGColor;
    return v;
}

- (void)addSectionHeader:(NSString *)title to:(NSView *)parent atY:(CGFloat)y x:(CGFloat)x
{
    NSTextField *lbl = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, 300, 16)];
    [lbl setStringValue:title];
    [lbl setFont:[NSFont systemFontOfSize:10 weight:NSFontWeightMedium]];
    [lbl setTextColor:ColorSectionText()];
    [lbl setBezeled:NO];
    [lbl setDrawsBackground:NO];
    [lbl setEditable:NO];
    [lbl setSelectable:NO];
    [parent addSubview:lbl];
}

- (StyledButton *)smallButton:(NSString *)title frame:(NSRect)frame
{
    StyledButton *btn = [[StyledButton alloc] initWithFrame:frame];
    [btn setTitle:title];
    [btn setFont:[NSFont systemFontOfSize:12]];
    [btn setBgColor:[NSColor colorWithCalibratedWhite:0.24 alpha:1.0]];
    [btn setHoverColor:[NSColor colorWithCalibratedWhite:0.30 alpha:1.0]];
    [btn setTextColor:[NSColor whiteColor]];
    return btn;
}

- (NSButton *)checkbox:(NSString *)title frame:(NSRect)frame
{
    NSButton *cb = [[NSButton alloc] initWithFrame:frame];
    [cb setButtonType:NSButtonTypeSwitch];
    [cb setTitle:title];
    [cb setFont:[NSFont systemFontOfSize:12]];
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.75 alpha:1.0]
    };
    NSAttributedString *attrTitle = [[NSAttributedString alloc] initWithString:title attributes:attrs];
    [cb setAttributedTitle:attrTitle];
    return cb;
}

- (NSString *)shortenPath:(NSString *)path
{
    NSString *home = NSHomeDirectory();
    if ([path hasPrefix:home]) {
        return [path stringByReplacingCharactersInRange:NSMakeRange(0, home.length) withString:@"~"];
    }
    return path;
}

#pragma mark - Icons ( programmatic )

- (NSImage *)quakeIconImage:(CGFloat)size
{
    NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [img lockFocus];
    NSColor *gold = [NSColor colorWithCalibratedRed:0.65 green:0.45 blue:0.20 alpha:1.0];
    [gold setStroke];
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(2, 2, size-4, size-4)];
    [circle setLineWidth:2];
    [circle stroke];
    NSBezierPath *line = [NSBezierPath bezierPath];
    [line moveToPoint:NSMakePoint(size/2, 4)];
    [line lineToPoint:NSMakePoint(size/2, size-4)];
    [line setLineWidth:2];
    [line stroke];
    [img unlockFocus];
    return img;
}

- (NSImage *)folderIconImage:(CGFloat)size
{
    NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [img lockFocus];
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1, 3, size-2, size-5) xRadius:2 yRadius:2];
    [[NSColor colorWithCalibratedWhite:0.55 alpha:1.0] setFill];
    [p fill];
    [img unlockFocus];
    return img;
}

- (NSImage *)monitorIconImage:(CGFloat)size
{
    NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [img lockFocus];
    NSRect r = NSMakeRect(1, 4, size-2, size-8);
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:2 yRadius:2];
    [[NSColor colorWithCalibratedWhite:0.55 alpha:1.0] setStroke];
    [p setLineWidth:1.5];
    [p stroke];
    NSBezierPath *base = [NSBezierPath bezierPath];
    [base moveToPoint:NSMakePoint(size*0.35, 2)];
    [base lineToPoint:NSMakePoint(size*0.65, 2)];
    [base moveToPoint:NSMakePoint(size*0.50, 4)];
    [base lineToPoint:NSMakePoint(size*0.50, 1)];
    [base setLineWidth:1.5];
    [base stroke];
    [img unlockFocus];
    return img;
}

- (NSImage *)speakerIconImage:(CGFloat)size
{
    NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [img lockFocus];
    NSBezierPath *cone = [NSBezierPath bezierPath];
    [cone moveToPoint:NSMakePoint(3, size*0.35)];
    [cone lineToPoint:NSMakePoint(size*0.45, size*0.35)];
    [cone lineToPoint:NSMakePoint(size*0.75, 2)];
    [cone lineToPoint:NSMakePoint(size*0.75, size-2)];
    [cone lineToPoint:NSMakePoint(size*0.45, size*0.65)];
    [cone lineToPoint:NSMakePoint(3, size*0.65)];
    [cone closePath];
    [[NSColor colorWithCalibratedWhite:0.55 alpha:1.0] setFill];
    [cone fill];
    [img unlockFocus];
    return img;
}

#pragma mark - State Refresh

- (void)refreshStatuses
{
    BOOL exeOK = selectedGameBinary && [[NSFileManager defaultManager] fileExistsAtPath:selectedGameBinary];
    [exeStatus setOK:exeOK text:exeOK ? @"Executable found" : @"Executable not found"];

    BOOL dataOK = HasGameData();
    [dataStatus setOK:dataOK text:dataOK ? @"Game data found" : @"Game data not found"];

    [playBtn setEnabled:(exeOK && dataOK)];
    [playBtn setAlphaValue:(exeOK && dataOK) ? 1.0 : 0.5];
    // Download button always visible for convenience
    [downloadSharewareBtn setHidden:NO];

    if (dataOK) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *paks = [[fm contentsOfDirectoryAtPath:DataDir() error:nil]
                         filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self ENDSWITH[c] %@", @".pak"]];
        if (paks.count > 0) {
            [statusLabel setStringValue:[NSString stringWithFormat:@"Detected: %@", [paks componentsJoinedByString:@", "]]];
        } else {
            [statusLabel setStringValue:@""];
        }
    } else {
        [statusLabel setStringValue:@"No game data found. Download shareware or select existing data."];
    }
}

#pragma mark - Actions

- (void)selectExecutable:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setAllowsMultipleSelection:NO];
    [panel setMessage:@"Select the Quake engine binary"];

    if ([panel runModal] == NSModalResponseOK) {
        selectedGameBinary = [[[panel URLs] firstObject] path];
        [exePathField setStringValue:[selectedGameBinary lastPathComponent]];
        [self refreshStatuses];
    }
}

- (void)selectDataFolder:(id)sender
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
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"No pak0.pak found"];
        [alert setInformativeText:@"The selected location does not contain a pak0.pak file."];
        [alert runModal];
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
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Failed to create directory"];
        [alert setInformativeText:[err localizedDescription]];
        [alert runModal];
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
                NSAlert *alert = [[NSAlert alloc] init];
                [alert setMessageText:@"Failed to copy"];
                [alert setInformativeText:[err localizedDescription]];
                [alert runModal];
                return;
            }
            copied++;
        }
    }

    [dataPathField setStringValue:[self shortenPath:destDir]];
    [self refreshStatuses];
}

- (void)showAdvanced:(id)sender
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Advanced Settings"];
    [alert setInformativeText:@"Advanced settings are not yet implemented."];
    [alert runModal];
}

- (void)showMods:(id)sender
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Mods & Addons"];
    [alert setInformativeText:@"Mod management is not yet implemented."];
    [alert runModal];
}

#pragma mark - Download

- (void)startDownload:(id)sender
{
    [downloadSharewareBtn setEnabled:NO];
    [progressBar setHidden:NO];
    [progressBar setMaxValue:ZIP_SIZE];
    [progressBar setDoubleValue:0];
    [statusLabel setStringValue:@"Downloading quake106.zip…"];

    NSURL *url = [NSURL URLWithString:SHAREWARE_ZIP_URL];
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
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *zipPath = [tmpDir stringByAppendingPathComponent:@"quake106.zip"];
    NSString *resPath = [tmpDir stringByAppendingPathComponent:@"resource.1"];
    NSString *extractDir = [tmpDir stringByAppendingPathComponent:@"quake_extract"];
    NSError *err = nil;

    [fm removeItemAtPath:zipPath error:nil];
    [fm moveItemAtPath:[location path] toPath:zipPath error:&err];
    if (err) {
        [self downloadFailed:[@"Failed to save download: " stringByAppendingString:[err localizedDescription]]];
        return;
    }

    [statusLabel setStringValue:@"Extracting archive…"];
    [progressBar setIndeterminate:YES];
    [progressBar startAnimation:nil];

    NSTask *unzipTask = [[NSTask alloc] init];
    [unzipTask setLaunchPath:@"/usr/bin/unzip"];
    [unzipTask setArguments:@[ @"-o", @"-j", zipPath, @"resource.1", @"-d", tmpDir ]];
    [unzipTask setStandardOutput:[NSPipe pipe]];
    [unzipTask setStandardError:[NSPipe pipe]];
    [unzipTask launch];
    [unzipTask waitUntilExit];

    if (![fm fileExistsAtPath:resPath]) {
        [self downloadFailed:@"Could not extract resource.1 from zip."];
        return;
    }

    [statusLabel setStringValue:@"Extracting LZH archive…"];
    [fm removeItemAtPath:extractDir error:nil];
    [fm createDirectoryAtPath:extractDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSTask *tarTask = [[NSTask alloc] init];
    [tarTask setLaunchPath:@"/usr/bin/tar"];
    [tarTask setCurrentDirectoryPath:extractDir];
    [tarTask setArguments:@[ @"-xf", resPath, @"ID1/PAK0.PAK" ]];
    [tarTask setStandardOutput:[NSPipe pipe]];
    [tarTask setStandardError:[NSPipe pipe]];
    [tarTask launch];
    [tarTask waitUntilExit];

    NSString *extractedPak = [extractDir stringByAppendingPathComponent:@"ID1/PAK0.PAK"];
    if (![fm fileExistsAtPath:extractedPak]) {
        [self downloadFailed:@"Could not extract pak0.pak from LZH archive."];
        return;
    }

    [statusLabel setStringValue:@"Installing…"];
    NSString *destDir = DataDir();
    NSString *destPath = PakPath();
    [fm createDirectoryAtPath:destDir withIntermediateDirectories:YES attributes:nil error:nil];
    [fm removeItemAtPath:destPath error:nil];
    [fm copyItemAtPath:extractedPak toPath:destPath error:&err];
    if (err) {
        [self downloadFailed:[@"Failed to install: " stringByAppendingString:[err localizedDescription]]];
        return;
    }

    NSString *md5 = MD5OfFile(destPath);
    if (![md5 isEqualToString:SHAREWARE_MD5]) {
        [fm removeItemAtPath:destPath error:nil];
        [self downloadFailed:@"File verification failed (MD5 mismatch)."];
        return;
    }

    [fm removeItemAtPath:zipPath error:nil];
    [fm removeItemAtPath:resPath error:nil];
    [fm removeItemAtPath:extractDir error:nil];

    [progressBar stopAnimation:nil];
    [progressBar setIndeterminate:NO];
    [progressBar setHidden:YES];
    [self refreshStatuses];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if (error) {
        [self downloadFailed:[@"Download failed: " stringByAppendingString:[error localizedDescription]]];
    }
}

- (void)downloadFailed:(NSString *)reason
{
    [progressBar stopAnimation:nil];
    [progressBar setHidden:YES];
    [statusLabel setStringValue:reason];
    [downloadSharewareBtn setEnabled:YES];
}

#pragma mark - Launch

- (void)launchGame
{
    NSString *gameBinary = selectedGameBinary;
    if (!gameBinary || ![[NSFileManager defaultManager] fileExistsAtPath:gameBinary]) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Game binary not found"];
        [alert setInformativeText:@"Please select a valid Quake executable."];
        [alert runModal];
        return;
    }

    NSString *basedir = AppSupportDir();
    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"-basedir", basedir, nil];

    // Parse extra args from text field
    NSString *extra = [argsField stringValue];
    if (extra.length > 0) {
        // Simple split by spaces (not perfect but works for basic args)
        NSArray *parts = [extra componentsSeparatedByString:@" "];
        for (NSString *part in parts) {
            NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (trimmed.length > 0) [args addObject:trimmed];
        }
    }

    const char *exe = [gameBinary UTF8String];
    int argc = (int)args.count;
    const char **argv = malloc((argc + 2) * sizeof(char *));
    argv[0] = exe;
    for (int i = 0; i < argc; i++) argv[i + 1] = [args[i] UTF8String];
    argv[argc + 1] = NULL;

    [window close];
    execv(exe, (char *const *)argv);
    free(argv);

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

#pragma mark - Main

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
