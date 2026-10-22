#import "metalfxscaler.h"

#include "fork/forkupscaling.h"
#include "fork/upscalerules.h"
#include "streaming/streamutils.h"
#include "SDL_compat.h"

#import <MetalFX/MetalFX.h>
#include <simd/simd.h>

namespace
{
    // vt_metal's vertex layout (struct Vertex there): position, then texture coordinates
    struct FullFrameVertex
    {
        simd_float4 position;
        simd_float2 texCoord;
    };
}

ForkMetalFxScaler::ForkMetalFxScaler()
    : m_Scaler(nil),
      m_Input(nil),
      m_Output(nil),
      m_DrawPipeline(nil),
      m_Format(MTLPixelFormatInvalid),
      m_FrameWidth(0),
      m_FrameHeight(0),
      m_OutWidth(0),
      m_OutHeight(0),
      m_Failure(nullptr)
{
}

ForkMetalFxScaler::~ForkMetalFxScaler()
{
    release();
}

void ForkMetalFxScaler::release()
{
    [m_Scaler release];
    m_Scaler = nil;
    [m_Input release];
    m_Input = nil;
    [m_Output release];
    m_Output = nil;
    [m_DrawPipeline release];
    m_DrawPipeline = nil;
}

id<MTLTexture> ForkMetalFxScaler::begin(id<MTLDevice> device, id<MTLLibrary> library, MTLPixelFormat format,
                                        int frameWidth, int frameHeight, int drawableWidth, int drawableHeight)
{
    UpscaleRules::Mode mode = ForkUpscaling::mode();
    if (mode == UpscaleRules::Mode::Off ||
            (mode == UpscaleRules::Mode::Quality && ForkUpscaling::superResolutionActive())) {
        // Off, or already super-resolved (superResolve() reported it)
        return nil;
    }

    SDL_Rect src = { 0, 0, frameWidth, frameHeight };
    SDL_Rect dst = { 0, 0, drawableWidth, drawableHeight };
    StreamUtils::scaleSourceToDestinationSurface(&src, &dst);
    if (!UpscaleRules::needsUpscale(frameWidth, frameHeight, dst.w, dst.h)) {
        ForkUpscaling::report(UpscaleRules::Engine::None, frameWidth, frameHeight, dst.w, dst.h, -1,
                              "the video already fills its area");
        return nil;
    }

    if (@available(macOS 13.0, *)) {
        if (frameWidth != m_FrameWidth || frameHeight != m_FrameHeight || dst.w != m_OutWidth ||
                dst.h != m_OutHeight || format != m_Format) {
            release();
            m_FrameWidth = frameWidth;
            m_FrameHeight = frameHeight;
            m_OutWidth = dst.w;
            m_OutHeight = dst.h;
            m_Format = format;
            m_Failure = nullptr;

            uint64_t startedAt = SDL_GetTicks64();
            if (![MTLFXSpatialScalerDescriptor supportsDevice:device]) {
                m_Failure = "MetalFX: not on this GPU";
            }
            else {
                MTLFXSpatialScalerDescriptor* descriptor = [[MTLFXSpatialScalerDescriptor new] autorelease];
                descriptor.inputWidth = frameWidth;
                descriptor.inputHeight = frameHeight;
                descriptor.outputWidth = dst.w;
                descriptor.outputHeight = dst.h;
                descriptor.colorTextureFormat = format;
                descriptor.outputTextureFormat = format;
                // vt_metal's colors are gamma or PQ encoded in [0, 1], not linear
                descriptor.colorProcessingMode = MTLFXSpatialScalerColorProcessingModePerceptual;

                id<MTLFXSpatialScaler> scaler = [descriptor newSpatialScalerWithDevice:device];
                if (scaler == nil) {
                    m_Failure = "MetalFX: refused this size or format";
                }
                else {
                    m_Scaler = scaler;

                    MTLTextureDescriptor* inputDescriptor =
                        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:frameWidth height:frameHeight mipmapped:NO];
                    inputDescriptor.storageMode = MTLStorageModePrivate;
                    inputDescriptor.usage = scaler.colorTextureUsage | MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
                    m_Input = [device newTextureWithDescriptor:inputDescriptor];

                    MTLTextureDescriptor* outputDescriptor =
                        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:dst.w height:dst.h mipmapped:NO];
                    outputDescriptor.storageMode = MTLStorageModePrivate;
                    outputDescriptor.usage = scaler.outputTextureUsage | MTLTextureUsageShaderRead;
                    m_Output = [device newTextureWithDescriptor:outputDescriptor];

                    // Draws the result as it is: vt_metal's own RGB shader, without its overlay blending
                    MTLRenderPipelineDescriptor* pipelineDescriptor = [[MTLRenderPipelineDescriptor new] autorelease];
                    pipelineDescriptor.vertexFunction = [[library newFunctionWithName:@"vs_draw"] autorelease];
                    pipelineDescriptor.fragmentFunction = [[library newFunctionWithName:@"ps_draw_rgb"] autorelease];
                    pipelineDescriptor.colorAttachments[0].pixelFormat = format;
                    m_DrawPipeline = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:nullptr];

                    if (m_Input == nil || m_Output == nil || m_DrawPipeline == nil) {
                        m_Failure = "MetalFX: no textures";
                        release();
                    }
                }
            }

            if (m_Failure != nullptr) {
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "[fork] Upscaling: %s (%dx%d -> %dx%d, Metal format %d)",
                            m_Failure, frameWidth, frameHeight, dst.w, dst.h, (int)format);
            }
            else {
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "[fork] Upscaling: MetalFX scaler for %dx%d -> %dx%d made in %llu ms",
                            frameWidth, frameHeight, dst.w, dst.h, (unsigned long long)(SDL_GetTicks64() - startedAt));
            }
        }
    }
    else {
        m_Failure = "MetalFX: needs macOS 13";
    }

    if (m_Failure != nullptr || m_Scaler == nil) {
        ForkUpscaling::report(UpscaleRules::Engine::Bilinear, frameWidth, frameHeight, dst.w, dst.h, -1,
                              m_Failure != nullptr ? m_Failure : "MetalFX: unavailable");
        return nil;
    }

    ForkUpscaling::report(UpscaleRules::Engine::MetalFx, frameWidth, frameHeight, dst.w, dst.h);
    return m_Input;
}

MTLRenderPassDescriptor* ForkMetalFxScaler::inputPass(id<MTLTexture> input)
{
    MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = input;
    pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    return pass;
}

void ForkMetalFxScaler::drawFullFrame(id<MTLRenderCommandEncoder> encoder)
{
    // The whole texture, upright: the top row (NDC y = 1) samples texture row 0, as vt_metal's
    // video quad does
    static const FullFrameVertex vertices[] = {
        { { -1.0f, -1.0f, 0.0f, 1.0f }, { 0.0f, 1.0f } },
        { { -1.0f, 1.0f, 0.0f, 1.0f }, { 0.0f, 0.0f } },
        { { 1.0f, -1.0f, 0.0f, 1.0f }, { 1.0f, 1.0f } },
        { { 1.0f, 1.0f, 0.0f, 1.0f }, { 1.0f, 0.0f } },
    };
    [encoder setVertexBytes:vertices length:sizeof(vertices) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

void ForkMetalFxScaler::encodeUpscale(id<MTLCommandBuffer> commandBuffer)
{
    if (@available(macOS 13.0, *)) {
        id<MTLFXSpatialScaler> scaler = (id<MTLFXSpatialScaler>)m_Scaler;
        scaler.colorTexture = m_Input;
        scaler.outputTexture = m_Output;
        scaler.inputContentWidth = m_FrameWidth;
        scaler.inputContentHeight = m_FrameHeight;
        [scaler encodeToCommandBuffer:commandBuffer];
    }
}

void ForkMetalFxScaler::drawResult(id<MTLRenderCommandEncoder> encoder, id<MTLBuffer> videoVertices)
{
    [encoder setRenderPipelineState:m_DrawPipeline];
    [encoder setFragmentTexture:m_Output atIndex:0];
    [encoder setVertexBuffer:videoVertices offset:0 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}
