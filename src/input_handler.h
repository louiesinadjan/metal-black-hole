#pragma once

class InputHandler {
public:
    InputHandler();
    ~InputHandler();

    // Reads and resets the accumulated drag delta since the last call.
    // dx is horizontal (drives azimuth), dy is vertical (drives elevation).
    void consume_delta(float& dx, float& dy);

    // Reads and resets the accumulated scroll zoom since the last call.
    // Positive = zoom in (decrease radius), negative = zoom out.
    void consume_scroll(float& dz);

private:
    void* monitor_token_  = nullptr;  // drag monitor
    void* scroll_token_   = nullptr;  // scroll monitor
    float delta_x_  = 0.0f;
    float delta_y_  = 0.0f;
    float delta_z_  = 0.0f;  // scroll accumulator
    bool  dragging_ = false;
};
