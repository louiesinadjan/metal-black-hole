//
// Black Hole Simulation — main.cpp
// Entry point: creates the macOS application, window, and MTKView.
//

#define NS_PRIVATE_IMPLEMENTATION
#define MTL_PRIVATE_IMPLEMENTATION
#define MTK_PRIVATE_IMPLEMENTATION
#define CA_PRIVATE_IMPLEMENTATION

#include <Metal/Metal.hpp>
#include <MetalKit/MetalKit.hpp>
#include <AppKit/AppKit.hpp>

#include "input_handler.h"
#include "renderer.hpp"

class ViewDelegate : public MTK::ViewDelegate {
public:
    explicit ViewDelegate(MTL::Device* device)
        : renderer_(new Renderer(device))
        , input_(new InputHandler())
    {}

    ~ViewDelegate() override {
        delete input_;
        delete renderer_;
    }

    void drawInMTKView(MTK::View* view) override {
        float dx = 0.0f, dy = 0.0f;
        input_->consume_delta(dx, dy);
        if (dx != 0.0f || dy != 0.0f)
            renderer_->update_orbit(dx, dy);
        renderer_->draw(view);
    }

private:
    Renderer*     renderer_;
    InputHandler* input_;
};

class AppDelegate : public NS::ApplicationDelegate {
public:
    ~AppDelegate() override {
        delete view_delegate_;
        window_->release();
        device_->release();
    }

    void applicationDidFinishLaunching(NS::Notification*) override {
        CGRect frame = { {100.0, 100.0}, {1280.0, 720.0} };

        window_ = NS::Window::alloc()->init(
            frame,
            NS::WindowStyleMaskClosable |
            NS::WindowStyleMaskTitled   |
            NS::WindowStyleMaskResizable,
            NS::BackingStoreBuffered,
            false);

        device_ = MTL::CreateSystemDefaultDevice();

        auto* view = MTK::View::alloc()->init(frame, device_);
        view->setColorPixelFormat(MTL::PixelFormatBGRA8Unorm_sRGB);
        view->setClearColor(MTL::ClearColor::Make(0.0, 0.0, 0.0, 1.0));
        view->setPaused(false);
        view->setEnableSetNeedsDisplay(false);

        view_delegate_ = new ViewDelegate(device_);
        view->setDelegate(view_delegate_);

        window_->setContentView(view);
        window_->setTitle(NS::String::string("Black Hole", NS::StringEncoding::UTF8StringEncoding));
        window_->makeKeyAndOrderFront(nullptr);

        NS::Application::sharedApplication()->activateIgnoringOtherApps(true);

        view->release();
    }

    bool applicationShouldTerminateAfterLastWindowClosed(NS::Application*) override {
        return true;
    }

private:
    NS::Window*    window_        = nullptr;
    MTL::Device*   device_        = nullptr;
    ViewDelegate*  view_delegate_ = nullptr;
};

int main() {
    NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();

    AppDelegate delegate;
    auto* app = NS::Application::sharedApplication();
    app->setActivationPolicy(NS::ActivationPolicyRegular);
    app->setDelegate(&delegate);
    app->run();

    pool->release();
    return 0;
}
