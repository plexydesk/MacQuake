// metal_renderer.m -- Metal framebuffer blit renderer

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/CAMetalLayer.h>

#include "quakedef.h"

static id<MTLDevice> device = nil;
static id<MTLCommandQueue> commandQueue = nil;
static id<MTLRenderPipelineState> pipelineState = nil;
static id<MTLTexture> frameTexture = nil;
static id<MTLTexture> paletteTexture = nil;
static id<MTLLibrary> library = nil;
static int frameWidth = 0;
static int frameHeight = 0;

void Metal_InitLayer(CAMetalLayer *layer)
{
	device = MTLCreateSystemDefaultDevice();
	if (!device) {
		Sys_Error("Metal is not supported on this system");
	}

	layer.device = device;
	layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
	layer.framebufferOnly = YES;

	commandQueue = [device newCommandQueue];

	// Load metallib — try bundle Resources first, then executable dir, then CWD
	NSError *error = nil;
	NSString *libPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"shaders.metallib"];
	library = [device newLibraryWithFile:libPath error:&error];
	if (!library) {
		NSString *exePath = [[NSBundle mainBundle] executablePath];
		NSString *exeDir = [exePath stringByDeletingLastPathComponent];
		libPath = [exeDir stringByAppendingPathComponent:@"shaders.metallib"];
		library = [device newLibraryWithFile:libPath error:&error];
	}
	if (!library) {
		libPath = [@"shaders.metallib" stringByStandardizingPath];
		library = [device newLibraryWithFile:libPath error:&error];
	}
	if (!library) {
		Sys_Error("Failed to load shaders.metallib: %s", [[error localizedDescription] UTF8String]);
	}

	id<MTLFunction> vertexFunc = [library newFunctionWithName:@"vertexMain"];
	id<MTLFunction> fragmentFunc = [library newFunctionWithName:@"fragmentMain"];

	MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];
	desc.vertexFunction = vertexFunc;
	desc.fragmentFunction = fragmentFunc;
	desc.colorAttachments[0].pixelFormat = layer.pixelFormat;

	pipelineState = [device newRenderPipelineStateWithDescriptor:desc error:&error];
	if (!pipelineState) {
		Sys_Error("Failed to create pipeline state: %s", [[error localizedDescription] UTF8String]);
	}
}

void Metal_CreateTextures(int width, int height)
{
	frameWidth = width;
	frameHeight = height;

	MTLTextureDescriptor *frameDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
																							  width:width
																							 height:height
																						 mipmapped:NO];
	frameDesc.usage = MTLTextureUsageShaderRead;
	frameTexture = [device newTextureWithDescriptor:frameDesc];

	MTLTextureDescriptor *palDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
																							 width:256
																						 height:1
																					 mipmapped:NO];
	palDesc.usage = MTLTextureUsageShaderRead;
	paletteTexture = [device newTextureWithDescriptor:palDesc];
}

void Metal_UpdateFrameTexture(unsigned char *buffer, int rowbytes)
{
	if (!frameTexture) return;

	MTLRegion region = {
		{0, 0, 0},
		{frameWidth, frameHeight, 1}
	};
	[frameTexture replaceRegion:region mipmapLevel:0 withBytes:buffer bytesPerRow:rowbytes];
}

void Metal_UpdatePalette(unsigned char *palette)
{
	if (!paletteTexture) return;

	unsigned char rgba[256 * 4];
	for (int i = 0; i < 256; i++) {
		rgba[i * 4 + 0] = palette[i * 3 + 0];
		rgba[i * 4 + 1] = palette[i * 3 + 1];
		rgba[i * 4 + 2] = palette[i * 3 + 2];
		rgba[i * 4 + 3] = 255;
	}

	MTLRegion region = {
		{0, 0, 0},
		{256, 1, 1}
	};
	[paletteTexture replaceRegion:region mipmapLevel:0 withBytes:rgba bytesPerRow:256 * 4];
}

void Metal_RenderFrame(CAMetalLayer *layer)
{
	if (!layer || !pipelineState) return;

	id<CAMetalDrawable> drawable = [layer nextDrawable];
	if (!drawable) return;

	MTLRenderPassDescriptor *passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
	passDesc.colorAttachments[0].texture = drawable.texture;
	passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
	passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
	passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);

	id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
	id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDesc];

	CGSize drawableSize = layer.drawableSize;
	MTLViewport viewport = {0, 0, drawableSize.width, drawableSize.height, 0, 1};
	[encoder setViewport:viewport];

	[encoder setRenderPipelineState:pipelineState];
	[encoder setFragmentTexture:frameTexture atIndex:0];
	[encoder setFragmentTexture:paletteTexture atIndex:1];
	[encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];

	[encoder endEncoding];
	[commandBuffer presentDrawable:drawable];
	[commandBuffer commit];
}

void Metal_Shutdown(void)
{
	frameTexture = nil;
	paletteTexture = nil;
	pipelineState = nil;
	library = nil;
	commandQueue = nil;
	device = nil;
}
