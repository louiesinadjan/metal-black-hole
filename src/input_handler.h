#pragma once

class InputHandler {
public:
    InputHandler();
    ~InputHandler();

    // Reads and resets the accumulated drag delta since the last call.
    // dx is horizontal (drives azimuth), dy is vertical (drives elevation).
    void consume_delta(float& dx, float& dy);

private:
    void* monitor_token_ = nullptr;  // opaque id; void* keeps this header ObjC-free
    float delta_x_  = 0.0f;
    float delta_y_  = 0.0f;
    bool  dragging_ = false;
};
