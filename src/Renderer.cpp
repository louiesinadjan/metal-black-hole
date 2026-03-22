#include "Renderer.hpp"
#include "ShaderTypes.h"

#include <cmath>
#include <cstdio>
#include <simd/simd.h>

Renderer::Renderer(MTL::Device* device)
    : _device(device->retain())
    , _commandQueue(_device->newCommandQueue())
{
    buildPipelines();
}

Renderer::~Renderer() {
    if (_cameraBuffer)    _cameraBuffer->release();
    if (_renderTexture)   _renderTexture->release();
    if (_renderPipeline)  _renderPipeline->release();
    if (_computePipeline) _computePipeline->release();
    _commandQueue->release();
    _device->release();
}

void Renderer::buildPipelines() {
    NS::Error* error = nullptr;

    // Load pre-compiled metallib (built via `make`)
    auto* libPath = NS::String::string("build/Shaders.metallib",
                                       NS::StringEncoding::UTF8StringEncoding);
    auto* libURL  = NS::URL::fileURLWithPath(libPath);
    auto* library = _device->newLibrary(libURL, &error);
    if (!library) {
        fprintf(stderr, "Failed to load build/Shaders.metallib: %s\n"
                        "Run `make` first and launch from the project root.\n",
                error->localizedDescription()->utf8String());
        exit(1);
    }

    // ── Compute pipeline: raytrace kernel ──────────────────────────────────
    auto* raytraceFn = library->newFunction(
        NS::String::string("raytrace", NS::StringEncoding::UTF8StringEncoding));

    _computePipeline = _device->newComputePipelineState(raytraceFn, &error);
    raytraceFn->release();
    if (!_computePipeline) {
        fprintf(stderr, "Failed to build compute pipeline: %s\n",
                error->localizedDescription()->utf8String());
        exit(1);
    }

    // ── Render pipeline: blit compute texture → screen ────────────────────
    auto* vertFn = library->newFunction(
        NS::String::string("blit_vertex", NS::StringEncoding::UTF8StringEncoding));
    auto* fragFn = library->newFunction(
        NS::String::string("blit_fragment", NS::StringEncoding::UTF8StringEncoding));

    auto* desc = MTL::RenderPipelineDescriptor::alloc()->init();
    desc->setVertexFunction(vertFn);
    desc->setFragmentFunction(fragFn);
    desc->colorAttachments()->object(0)->setPixelFormat(MTL::PixelFormatBGRA8Unorm_sRGB);

    _renderPipeline = _device->newRenderPipelineState(desc, &error);
    if (!_renderPipeline) {
        fprintf(stderr, "Failed to build render pipeline: %s\n",
                error->localizedDescription()->utf8String());
        exit(1);
    }

    vertFn->release();
    fragFn->release();
    desc->release();
    library->release();
}

void Renderer::buildTexture(uint32_t width, uint32_t height) {
    if (_renderTexture) _renderTexture->release();

    auto* desc = MTL::TextureDescriptor::texture2DDescriptor(
        MTL::PixelFormatRGBA16Float, width, height, false);
    desc->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
    desc->setStorageMode(MTL::StorageModePrivate);

    _renderTexture  = _device->newTexture(desc);
    _textureWidth   = width;
    _textureHeight  = height;
}

void Renderer::buildCameraBuffer(uint32_t width, uint32_t height) {
    if (!_cameraBuffer)
        _cameraBuffer = _device->newBuffer(sizeof(CameraData),
                                           MTL::ResourceStorageModeShared);

    // Camera: slightly above the equatorial plane, looking at the black hole
    simd_float3 position = {  0.0f,  3.0f, -15.0f };
    simd_float3 target   = {  0.0f,  0.0f,   0.0f };
    simd_float3 worldUp  = {  0.0f,  1.0f,   0.0f };

    simd_float3 forward  = simd_normalize(target - position);
    simd_float3 right    = simd_normalize(simd_cross(forward, worldUp));
    simd_float3 up       = simd_cross(right, forward);

    float fov         = M_PI / 3.0f;  // 60° vertical
    float aspectRatio = static_cast<float>(width) / static_cast<float>(height);

    auto* cam     = static_cast<CameraData*>(_cameraBuffer->contents());
    cam->position = { position.x, position.y, position.z, 0.0f };
    cam->forward  = { forward.x,  forward.y,  forward.z,  fov  };
    cam->right    = { right.x,    right.y,    right.z,    aspectRatio };
    cam->up       = { up.x,       up.y,       up.z,       0.0f };
}

void Renderer::draw(MTK::View* view) {
    NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();

    auto* drawable = view->currentDrawable();
    if (!drawable) { pool->release(); return; }

    // Rebuild resources if the window was resized
    uint32_t w = drawable->texture()->width();
    uint32_t h = drawable->texture()->height();
    if (w != _textureWidth || h != _textureHeight) {
        buildTexture(w, h);
        buildCameraBuffer(w, h);
    }

    auto* cmd = _commandQueue->commandBuffer();

    // ── Compute pass: raytrace into _renderTexture ─────────────────────────
    {
        auto* enc = cmd->computeCommandEncoder();
        enc->setComputePipelineState(_computePipeline);
        enc->setTexture(_renderTexture, 0);
        enc->setBuffer(_cameraBuffer, 0, 0);

        // 16×16 threadgroups; dispatchThreads handles non-power-of-two sizes
        MTL::Size threadgroup { 16, 16, 1 };
        MTL::Size grid        { w,  h,  1 };
        enc->dispatchThreads(grid, threadgroup);
        enc->endEncoding();
    }

    // ── Render pass: blit _renderTexture to the drawable ──────────────────
    {
        auto* rpd = view->currentRenderPassDescriptor();
        auto* enc = cmd->renderCommandEncoder(rpd);
        enc->setRenderPipelineState(_renderPipeline);
        enc->setFragmentTexture(_renderTexture, 0);
        enc->drawPrimitives(MTL::PrimitiveTypeTriangle,
                            NS::UInteger(0), NS::UInteger(3));
        enc->endEncoding();
    }

    cmd->presentDrawable(drawable);
    cmd->commit();

    pool->release();
}
