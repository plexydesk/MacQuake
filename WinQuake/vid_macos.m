// vid_macos.m -- macOS Cocoa window + CAMetalLayer video driver

#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>
#import <CoreGraphics/CoreGraphics.h>

#include "quakedef.h"
#include "d_local.h"

// Global video state
viddef_t vid;
unsigned short d_8to16table[256];
unsigned d_8to24table[256];

// Mouse state (shared with in_macos.m)
float mouse_x, mouse_y;
float old_mouse_x, old_mouse_y;
int mouse_buttons = 3;
int mouse_buttonstate = 0;
int mouse_oldbuttonstate = 0;
qboolean mouse_avail = false;

static NSWindow *window = nil;
static NSView *gameView = nil;
static CAMetalLayer *metalLayer = nil;
static int windowed = 1;
static int vid_modenum = 0;
static unsigned char current_palette[768];

static NSUInteger prevModifiers = 0;
static qboolean mouse_locked = false;

// External Metal renderer functions
extern void Metal_InitLayer(CAMetalLayer *layer);
extern void Metal_CreateTextures(int width, int height);
extern void Metal_UpdateFrameTexture(unsigned char *buffer, int rowbytes);
extern void Metal_UpdatePalette(unsigned char *palette);
extern void Metal_RenderFrame(CAMetalLayer *layer);
extern void Metal_Shutdown(void);

// -------------------------------------------------------------------------
// Mouse lock / unlock
// -------------------------------------------------------------------------

static void LockMouse(void)
{
    if (mouse_locked || !window)
        return;
    mouse_locked = true;
    CGAssociateMouseAndMouseCursorPosition(NO);
    [NSCursor hide];
}

static void UnlockMouse(void)
{
    if (!mouse_locked)
        return;
    mouse_locked = false;
    CGAssociateMouseAndMouseCursorPosition(YES);
    [NSCursor unhide];
}

static void WarpMouseToCenter(void)
{
    if (!window)
        return;
    NSRect frame = [window frame];
    CGPoint center = CGPointMake(
        frame.origin.x + frame.size.width * 0.5,
        frame.origin.y + frame.size.height * 0.5
    );
    CGWarpMouseCursorPosition(center);
}

// -------------------------------------------------------------------------
// QuakeView
// -------------------------------------------------------------------------

@interface QuakeView : NSView
@end

@implementation QuakeView

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)becomeFirstResponder {
    return YES;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        [self.window setAcceptsMouseMovedEvents:YES];
    }
}

static int KeyCodeForEvent(NSEvent *event) {
    unsigned short keyCode = [event keyCode];

    switch (keyCode) {
        case 0x35: return K_ESCAPE;
        case 0x7E: return K_UPARROW;
        case 0x7D: return K_DOWNARROW;
        case 0x7B: return K_LEFTARROW;
        case 0x7C: return K_RIGHTARROW;
        case 0x30: return K_TAB;
        case 0x24: return K_ENTER;
        case 0x31: return K_SPACE;
        case 0x33: return K_BACKSPACE;
        case 0x72: return K_INS;
        case 0x75: return K_DEL;
        case 0x73: return K_HOME;
        case 0x77: return K_END;
        case 0x74: return K_PGUP;
        case 0x79: return K_PGDN;
        case 0x7A: return K_F1;
        case 0x78: return K_F2;
        case 0x63: return K_F3;
        case 0x76: return K_F4;
        case 0x60: return K_F5;
        case 0x61: return K_F6;
        case 0x62: return K_F7;
        case 0x64: return K_F8;
        case 0x65: return K_F9;
        case 0x6D: return K_F10;
        case 0x67: return K_F11;
        case 0x6F: return K_F12;
        case 0x71: return K_PAUSE;
    }

    NSString *chars = [event charactersIgnoringModifiers];
    if ([chars length] > 0) {
        unichar c = [chars characterAtIndex:0];
        if (c >= 'A' && c <= 'Z')
            c = c - 'A' + 'a';
        if (c >= 32 && c <= 126)
            return c;
    }

    return 0;
}

static int MouseButtonForEvent(NSEvent *event) {
    NSInteger button = [event buttonNumber];
    switch (button) {
        case 0: return K_MOUSE1;
        case 1: return K_MOUSE2;
        case 2: return K_MOUSE3;
        default: return K_AUX1 + (int)button - 3;
    }
}

- (void)keyDown:(NSEvent *)event {
    // Handle Cmd+Q as quit
    if (([event modifierFlags] & NSEventModifierFlagCommand) &&
        [[event charactersIgnoringModifiers] isEqualToString:@"q"]) {
        Sys_Quit();
        return;
    }

    int key = KeyCodeForEvent(event);
    if (key) {
        Key_Event(key, true);
    }
}

- (void)keyUp:(NSEvent *)event {
    int key = KeyCodeForEvent(event);
    if (key) {
        Key_Event(key, false);
    }
}

- (void)flagsChanged:(NSEvent *)event {
    NSUInteger flags = [event modifierFlags];
    NSUInteger changed = flags ^ prevModifiers;

    if (changed & NSEventModifierFlagShift) {
        Key_Event(K_SHIFT, (flags & NSEventModifierFlagShift) ? true : false);
    }
    if (changed & NSEventModifierFlagControl) {
        Key_Event(K_CTRL, (flags & NSEventModifierFlagControl) ? true : false);
    }
    if (changed & NSEventModifierFlagOption) {
        Key_Event(K_ALT, (flags & NSEventModifierFlagOption) ? true : false);
    }

    prevModifiers = flags;
}

- (void)mouseDown:(NSEvent *)event {
    int btn = MouseButtonForEvent(event);
    mouse_buttonstate |= (1 << [event buttonNumber]);
    Key_Event(btn, true);
}

- (void)mouseUp:(NSEvent *)event {
    int btn = MouseButtonForEvent(event);
    mouse_buttonstate &= ~(1 << [event buttonNumber]);
    Key_Event(btn, false);
}

- (void)rightMouseDown:(NSEvent *)event {
    int btn = MouseButtonForEvent(event);
    mouse_buttonstate |= (1 << [event buttonNumber]);
    Key_Event(btn, true);
}

- (void)rightMouseUp:(NSEvent *)event {
    int btn = MouseButtonForEvent(event);
    mouse_buttonstate &= ~(1 << [event buttonNumber]);
    Key_Event(btn, false);
}

- (void)otherMouseDown:(NSEvent *)event {
    int btn = MouseButtonForEvent(event);
    mouse_buttonstate |= (1 << [event buttonNumber]);
    Key_Event(btn, true);
}

- (void)otherMouseUp:(NSEvent *)event {
    int btn = MouseButtonForEvent(event);
    mouse_buttonstate &= ~(1 << [event buttonNumber]);
    Key_Event(btn, false);
}

- (void)mouseMoved:(NSEvent *)event {
    mouse_x += [event deltaX];
    mouse_y -= [event deltaY];
    if (mouse_locked) {
        WarpMouseToCenter();
    }
}

- (void)mouseDragged:(NSEvent *)event {
    mouse_x += [event deltaX];
    mouse_y -= [event deltaY];
    if (mouse_locked) {
        WarpMouseToCenter();
    }
}

- (void)rightMouseDragged:(NSEvent *)event {
    mouse_x += [event deltaX];
    mouse_y -= [event deltaY];
    if (mouse_locked) {
        WarpMouseToCenter();
    }
}

- (void)otherMouseDragged:(NSEvent *)event {
    mouse_x += [event deltaX];
    mouse_y -= [event deltaY];
    if (mouse_locked) {
        WarpMouseToCenter();
    }
}

@end

// -------------------------------------------------------------------------
// Window Delegate
// -------------------------------------------------------------------------

@interface QuakeWindowDelegate : NSObject <NSWindowDelegate>
@end

@implementation QuakeWindowDelegate

- (BOOL)windowShouldClose:(NSWindow *)sender {
    Sys_Quit();
    return NO;
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    LockMouse();
}

- (void)windowDidResignKey:(NSNotification *)notification {
    UnlockMouse();
}

- (void)windowDidResize:(NSNotification *)notification {
    NSWindow *win = [notification object];
    NSView *view = [win contentView];
    if (view && view.layer && [view.layer isKindOfClass:[CAMetalLayer class]]) {
        CAMetalLayer *layer = (CAMetalLayer *)view.layer;
        NSRect backingRect = [view convertRectToBacking:view.bounds];
        layer.drawableSize = CGSizeMake(backingRect.size.width, backingRect.size.height);
    }
}

@end

// -------------------------------------------------------------------------
// Video Interface
// -------------------------------------------------------------------------

void VID_SetPalette(unsigned char *palette)
{
    int i;

    memcpy(current_palette, palette, sizeof(current_palette));

    for (i = 0; i < 256; i++) {
        int r = palette[i * 3 + 0];
        int g = palette[i * 3 + 1];
        int b = palette[i * 3 + 2];

        d_8to16table[i] = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);
        d_8to24table[i] = (r << 0) | (g << 8) | (b << 16);
    }

    Metal_UpdatePalette(current_palette);
}

void VID_ShiftPalette(unsigned char *palette)
{
    VID_SetPalette(palette);
}

void VID_Init(unsigned char *palette)
{
    int width = 640;
    int height = 480;
    int pnum;

    // Parse command line for resolution
    if ((pnum = COM_CheckParm("-width")) != 0)
        width = atoi(com_argv[pnum + 1]);
    if ((pnum = COM_CheckParm("-height")) != 0)
        height = atoi(com_argv[pnum + 1]);

    if ((pnum = COM_CheckParm("-window")) != 0)
        windowed = 1;

    // Initialize NSApplication
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp finishLaunching];

    // Create window (2x scale for Retina crispness, but renderer stays at chosen res)
    NSRect frame = NSMakeRect(0, 0, width * 2, height * 2);
    NSUInteger styleMask = NSWindowStyleMaskTitled
                         | NSWindowStyleMaskClosable
                         | NSWindowStyleMaskMiniaturizable
                         | NSWindowStyleMaskResizable;
    window = [[NSWindow alloc] initWithContentRect:frame
                                         styleMask:styleMask
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    [window setTitle:@"Quake"];
    [window center];
    [window makeKeyAndOrderFront:nil];
    [window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
    [NSApp activateIgnoringOtherApps:YES];

    // Set window delegate
    QuakeWindowDelegate *delegate = [[QuakeWindowDelegate alloc] init];
    [window setDelegate:delegate];

    // Create view with Metal layer
    gameView = [[QuakeView alloc] initWithFrame:frame];
    gameView.wantsLayer = YES;

    metalLayer = [CAMetalLayer layer];
    Metal_InitLayer(metalLayer);
    gameView.layer = metalLayer;
    window.contentView = gameView;

    // Set drawable size based on backing scale
    NSRect backingRect = [gameView convertRectToBacking:gameView.bounds];
    metalLayer.drawableSize = CGSizeMake(backingRect.size.width, backingRect.size.height);
    metalLayer.contentsScale = [window backingScaleFactor];

    // Set up vid structure
    vid.width = width;
    vid.height = height;
    vid.rowbytes = width;
    vid.aspect = ((float)height / width) * (320.0 / 240.0);
    vid.numpages = 1;
    vid.maxwarpwidth = WARP_WIDTH;
    vid.maxwarpheight = WARP_HEIGHT;
    vid.conwidth = width;
    vid.conheight = height;
    vid.conrowbytes = width;
    vid.colormap = host_colormap;
    vid.colormap16 = d_8to16table;
    vid.fullbright = 256 - LittleLong(*((int *)vid.colormap + 2048));

    // Allocate framebuffer
    int buffer_size = vid.width * vid.height;
    vid.buffer = (pixel_t *)malloc(buffer_size);
    vid.conbuffer = vid.buffer;
    memset(vid.buffer, 0, buffer_size);

    // Allocate z-buffer and surface cache
    int zbuf_size = vid.width * vid.height * sizeof(short);
    int surfcachesize = D_SurfaceCacheForRes(vid.width, vid.height);
    d_pzbuffer = (short *)malloc(zbuf_size + surfcachesize);
    if (!d_pzbuffer) {
        Sys_Error("VID_Init: failed to allocate z-buffer and surface cache");
    }
    D_InitCaches((byte *)d_pzbuffer + zbuf_size, surfcachesize);

    // Create Metal textures
    Metal_CreateTextures(width, height);
    VID_SetPalette(palette);

    // Hide cursor and lock mouse once window is active
    LockMouse();
}

void VID_Shutdown(void)
{
    UnlockMouse();
    Metal_Shutdown();
    if (window) {
        [window close];
        window = nil;
    }
    if (d_pzbuffer) {
        free(d_pzbuffer);
        d_pzbuffer = NULL;
    }
    if (vid.buffer) {
        free(vid.buffer);
        vid.buffer = NULL;
    }
}

void VID_Update(vrect_t *rects)
{
    vrect_t *rect;

    if (!metalLayer) return;

    // Update dirty rectangles in the frame texture
    for (rect = rects; rect; rect = rect->pnext) {
        // For simplicity, we update the entire framebuffer each frame.
        // A more optimized approach would update only dirty regions.
    }

    // Upload current framebuffer
    Metal_UpdateFrameTexture(vid.buffer, vid.rowbytes);

    // Render to screen
    Metal_RenderFrame(metalLayer);
}

int VID_SetMode(int modenum, unsigned char *palette)
{
    // Only support one mode
    return 0;
}

void VID_HandlePause(qboolean pause)
{
    if (pause) {
        UnlockMouse();
    } else {
        LockMouse();
    }
}

void D_BeginDirectRect(int x, int y, byte *pbitmap, int width, int height)
{
}

void D_EndDirectRect(int x, int y, int width, int height)
{
}

// -------------------------------------------------------------------------
// Event Pumping
// -------------------------------------------------------------------------

void VID_PumpEvents(void)
{
    @autoreleasepool {
        NSEvent *event;
        while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                            untilDate:nil
                                               inMode:NSDefaultRunLoopMode
                                              dequeue:YES])) {
            [NSApp sendEvent:event];
        }
    }
}
