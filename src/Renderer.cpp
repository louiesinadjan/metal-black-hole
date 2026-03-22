#include "renderer.hpp"
#include "shader_types.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <simd/simd.h>

Renderer::Renderer(MTL::Device* device)
    : device_(device->retain())
    , command_queue_(device_->newCommandQueue())
{
    build_pipelines();
}

Renderer::~Renderer() {
    if (camera_buffer_)   camera_buffer_->release();
    if (render_texture_)  render_texture_->release();
    if (render_pipeline_) render_pipeline_->release();
    if (compute_pipeline_) compute_pipeline_->release();
    command_queue_->release();
    device_->release();
}

void Renderer::build_pipelines() {
    NS::Error* error = nullptr;

    auto* lib_path = NS::String::string("build/Shaders.metallib", NS::StringEncoding::UTF8StringEncoding);
    auto* lib_url  = NS::URL::fileURLWithPath(lib_path);
    auto* library  = device_->newLibrary(lib_url, &error);
    if (!library) {
        fprintf(stderr,
                "Failed to load build/Shaders.metallib: %s\n"
                "Run `make` first and launch from the project root.\n",
                error->localizedDescription()->utf8String());
        exit(1);
    }

    // Compute pipeline: raytrace kernel
    auto* raytrace_fn = library->newFunction(NS::String::string("raytrace", NS::StringEncoding::UTF8StringEncoding));
    compute_pipeline_ = device_->newComputePipelineState(raytrace_fn, &error);
    raytrace_fn->release();
    if (!compute_pipeline_) {
        fprintf(stderr, "Failed to build compute pipeline: %s\n", error->localizedDescription()->utf8String());
        exit(1);
    }

    // Render pipeline: blit compute texture → screen
    auto* vert_fn = library->newFunction(NS::String::string("blit_vertex",   NS::StringEncoding::UTF8StringEncoding));
    auto* frag_fn = library->newFunction(NS::String::string("blit_fragment", NS::StringEncoding::UTF8StringEncoding));

    auto* desc = MTL::RenderPipelineDescriptor::alloc()->init();
    desc->setVertexFunction(vert_fn);
    desc->setFragmentFunction(frag_fn);
    desc->colorAttachments()->object(0)->setPixelFormat(MTL::PixelFormatBGRA8Unorm_sRGB);

    render_pipeline_ = device_->newRenderPipelineState(desc, &error);
    if (!render_pipeline_) {
        fprintf(stderr, "Failed to build render pipeline: %s\n", error->localizedDescription()->utf8String());
        exit(1);
    }

    vert_fn->release();
    frag_fn->release();
    desc->release();
    library->release();
}

void Renderer::build_texture(uint32_t width, uint32_t height) {
    if (render_texture_) render_texture_->release();

    auto* desc = MTL::TextureDescriptor::texture2DDescriptor(
        MTL::PixelFormatRGBA16Float, width, height, false);
    desc->setUsage(MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
    desc->setStorageMode(MTL::StorageModePrivate);

    render_texture_  = device_->newTexture(desc);
    texture_width_   = width;
    texture_height_  = height;
}

void Renderer::build_camera_buffer(uint32_t width, uint32_t height) {
    if (!camera_buffer_)
        camera_buffer_ = device_->newBuffer(sizeof(CameraData), MTL::ResourceStorageModeShared);

    float cx = radius_ * cosf(elevation_) * sinf(azimuth_);
    float cy = radius_ * sinf(elevation_);
    float cz = -radius_ * cosf(elevation_) * cosf(azimuth_);

    simd_float3 position = { cx, cy, cz };
    simd_float3 target   = { 0.0f, 0.0f, 0.0f };
    simd_float3 world_up = { 0.0f, 1.0f, 0.0f };

    simd_float3 forward = simd_normalize(target - position);
    simd_float3 right   = simd_normalize(simd_cross(forward, world_up));
    simd_float3 up      = simd_cross(right, forward);

    float fov          = (float)M_PI / 3.0f;
    float aspect_ratio = static_cast<float>(width) / static_cast<float>(height);

    auto* cam      = static_cast<CameraData*>(camera_buffer_->contents());
    cam->position  = { cx,        cy,        cz,        0.0f         };
    cam->forward   = { forward.x, forward.y, forward.z, fov          };
    cam->right     = { right.x,   right.y,   right.z,   aspect_ratio };
    cam->up        = { up.x,      up.y,      up.z,      0.0f         };
}

void Renderer::update_orbit(float dx, float dy) {
    constexpr float k_sens     = 0.005f;
    constexpr float k_elev_min = -(float)M_PI / 2.0f + 0.05f;
    constexpr float k_elev_max =  (float)M_PI / 2.0f - 0.05f;

    azimuth_   += dx * k_sens;
    elevation_ -= dy * k_sens;
    elevation_  = std::clamp(elevation_, k_elev_min, k_elev_max);

    if      (azimuth_ >  (float)M_PI) azimuth_ -= 2.0f * (float)M_PI;
    else if (azimuth_ < -(float)M_PI) azimuth_ += 2.0f * (float)M_PI;

    build_camera_buffer(texture_width_, texture_height_);
}

void Renderer::draw(MTK::View* view) {
    NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();

    auto* drawable = view->currentDrawable();
    if (!drawable) { pool->release(); return; }

    uint32_t w = drawable->texture()->width();
    uint32_t h = drawable->texture()->height();
    if (w != texture_width_ || h != texture_height_) {
        build_texture(w, h);
        build_camera_buffer(w, h);
    }

    auto* cmd = command_queue_->commandBuffer();

    // Compute pass: raytrace into render_texture_
    {
        auto* enc = cmd->computeCommandEncoder();
        enc->setComputePipelineState(compute_pipeline_);
        enc->setTexture(render_texture_, 0);
        enc->setBuffer(camera_buffer_, 0, 0);

        MTL::Size threadgroup { 16, 16, 1 };
        MTL::Size grid        { w,  h,  1 };
        enc->dispatchThreads(grid, threadgroup);
        enc->endEncoding();
    }

    // Render pass: blit render_texture_ to the drawable
    {
        auto* rpd = view->currentRenderPassDescriptor();
        auto* enc = cmd->renderCommandEncoder(rpd);
        enc->setRenderPipelineState(render_pipeline_);
        enc->setFragmentTexture(render_texture_, 0);
        enc->drawPrimitives(MTL::PrimitiveTypeTriangle, NS::UInteger(0), NS::UInteger(3));
        enc->endEncoding();
    }

    cmd->presentDrawable(drawable);
    cmd->commit();

    pool->release();
}
