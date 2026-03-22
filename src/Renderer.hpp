#pragma once

#include <Metal/Metal.hpp>
#include <MetalKit/MetalKit.hpp>
#include <cstdint>

class Renderer {
public:
    explicit Renderer(MTL::Device* device);
    ~Renderer();

    void draw(MTK::View* view);

private:
    void buildPipelines();
    void buildTexture(uint32_t width, uint32_t height);
    void buildCameraBuffer(uint32_t width, uint32_t height);

    MTL::Device*               _device;
    MTL::CommandQueue*         _commandQueue;
    MTL::ComputePipelineState* _computePipeline = nullptr;
    MTL::RenderPipelineState*  _renderPipeline  = nullptr;
    MTL::Texture*              _renderTexture   = nullptr;
    MTL::Buffer*               _cameraBuffer    = nullptr;

    uint32_t _textureWidth  = 0;
    uint32_t _textureHeight = 0;
};
