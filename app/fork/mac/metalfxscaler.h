#pragma once

#ifdef __OBJC__
#import <Metal/Metal.h>

// [fork] Upscaling's Fast engine for vt_metal: MetalFX's spatial scaler. vt_metal normally
// converts the frame's YUV to RGB straight into the drawable, scaling it with its bilinear
// sampler. With this, it converts into a texture at the frame's own size, MetalFX scales that
// to the video's area, and the result is drawn into the drawable 1:1:
//
//   id<MTLTexture> input = scaler.begin(...);          // nil: draw as before
//   encoder = [commandBuffer renderCommandEncoderWithDescriptor:ForkMetalFxScaler::inputPass(input)];
//   ... bind the YUV planes and the color conversion as before, then
//   ForkMetalFxScaler::drawFullFrame(encoder); [encoder endEncoding];
//   scaler.encodeUpscale(commandBuffer);
//   encoder = ...the drawable's pass...;
//   scaler.drawResult(encoder, videoVertices);         // then the overlays as before
//
// Used for Fast, and for Quality while super resolution isn't (forkupscaling.h). Reports what
// it does, including why it can't (no MetalFX on the GPU, a size or format it refuses); the
// frame then keeps the bilinear sampling. Not thread safe: one per renderer, on its render
// thread.
class ForkMetalFxScaler
{
public:
    ForkMetalFxScaler();
    ~ForkMetalFxScaler();

    ForkMetalFxScaler(const ForkMetalFxScaler&) = delete;
    ForkMetalFxScaler& operator=(const ForkMetalFxScaler&) = delete;

    // The texture to convert this frame's colors into, at its own size, when MetalFX upscales
    // it to its area in a drawable this size; nil to render as before. format is the layer's,
    // which vt_metal's color conversion pipeline renders in. Makes the scaler when the sizes
    // or format change (MetalFX takes a while to make one, so not every frame).
    id<MTLTexture> begin(id<MTLDevice> device, id<MTLLibrary> library, MTLPixelFormat format,
                         int frameWidth, int frameHeight, int drawableWidth, int drawableHeight);

    // A render pass into begin()'s texture
    static MTLRenderPassDescriptor* inputPass(id<MTLTexture> input);

    // Draws the whole frame into that pass (vertex buffer 0), with the pipeline already bound
    static void drawFullFrame(id<MTLRenderCommandEncoder> encoder);

    // Encodes the upscale, after the input pass has ended
    void encodeUpscale(id<MTLCommandBuffer> commandBuffer);

    // Draws the upscaled video into the drawable's pass with the video's vertices
    void drawResult(id<MTLRenderCommandEncoder> encoder, id<MTLBuffer> videoVertices);

private:
    void release();

    id m_Scaler; // id<MTLFXSpatialScaler>
    id<MTLTexture> m_Input;
    id<MTLTexture> m_Output;
    id<MTLRenderPipelineState> m_DrawPipeline;
    MTLPixelFormat m_Format;
    int m_FrameWidth;
    int m_FrameHeight;
    int m_OutWidth;
    int m_OutHeight;
    // Why the scaler can't be made for these sizes and format; empty when it was
    const char* m_Failure;
};
#endif
