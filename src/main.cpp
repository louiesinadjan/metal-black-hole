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

#include "Renderer.hpp"

// ── MTKViewDelegate ────────────────────────────────────────────────────────────

class ViewDelegate : public MTK::ViewDelegate {
public:
    explicit ViewDelegate(MTL::Device* device)
        : _renderer(new Renderer(device)) {}

    ~ViewDelegate() override { delete _renderer; }

    void drawInMTKView(MTK::View* view) override {
        _renderer->draw(view);
    }

private:
    Renderer* _renderer;
};

// ── AppDelegate ────────────────────────────────────────────────────────────────

class AppDelegate : public NS::ApplicationDelegate {
public:
    ~AppDelegate() override {
        delete _viewDelegate;
        _window->release();
        _device->release();
    }

    void applicationDidFinishLaunching(NS::Notification*) override {
        CGRect frame = { {100.0, 100.0}, {1280.0, 720.0} };

        _window = NS::Window::alloc()->init(
            frame,
            NS::WindowStyleMaskClosable |
            NS::WindowStyleMaskTitled   |
            NS::WindowStyleMaskResizable,
            NS::BackingStoreBuffered,
            false);

        _device = MTL::CreateSystemDefaultDevice();

        auto* view = MTK::View::alloc()->init(frame, _device);
        view->setColorPixelFormat(MTL::PixelFormatBGRA8Unorm_sRGB);
        view->setClearColor(MTL::ClearColor::Make(0.0, 0.0, 0.0, 1.0));
        view->setPaused(false);
        view->setEnableSetNeedsDisplay(false);

        _viewDelegate = new ViewDelegate(_device);
        view->setDelegate(_viewDelegate);

        _window->setContentView(view);
        _window->setTitle(NS::String::string("Black Hole",
                          NS::StringEncoding::UTF8StringEncoding));
        _window->makeKeyAndOrderFront(nullptr);

        NS::Application::sharedApplication()->activateIgnoringOtherApps(true);

        view->release();
    }

    bool applicationShouldTerminateAfterLastWindowClosed(NS::Application*) override {
        return true;
    }

private:
    NS::Window*   _window       = nullptr;
    MTL::Device*  _device       = nullptr;
    ViewDelegate* _viewDelegate = nullptr;
};

// ── Entry point ────────────────────────────────────────────────────────────────

int main() {
    NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();

    AppDelegate delegate;
    NS::Application::sharedApplication()->setDelegate(&delegate);
    NS::Application::sharedApplication()->run();

    pool->release();
    return 0;
}
