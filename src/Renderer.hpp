#pragma once

#include <Metal/Metal.hpp>
#include <MetalKit/MetalKit.hpp>
#include <cstdint>

class Renderer {
public:
    explicit Renderer(MTL::Device* device);
    ~Renderer();

    void draw(MTK::View* view);
    void update_orbit(float dx, float dy);

private:
    void build_pipelines();
    void build_texture(uint32_t width, uint32_t height);
    void build_camera_buffer(uint32_t width, uint32_t height);

    MTL::Device*               device_;
    MTL::CommandQueue*         command_queue_;
    MTL::ComputePipelineState* compute_pipeline_ = nullptr;
    MTL::ComputePipelineState* accum_pipeline_   = nullptr;
    MTL::RenderPipelineState*  render_pipeline_  = nullptr;
    MTL::Texture*              render_texture_   = nullptr;
    MTL::Texture*              accum_texture_    = nullptr;
    MTL::Buffer*               camera_buffer_    = nullptr;

    uint32_t frame_count_ = 0;

    uint32_t texture_width_  = 0;
    uint32_t texture_height_ = 0;

    float azimuth_   = 0.0f;
    float elevation_ = 0.1974f;  // asin(3 / sqrt(234)), matches initial position {0,3,-15}
    float radius_    = 15.2971f; // sqrt(0² + 3² + 15²)
};
