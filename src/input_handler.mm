#import <AppKit/AppKit.h>
#include "input_handler.h"

InputHandler::InputHandler() {
    InputHandler* self = this;
    id token = [NSEvent addLocalMonitorForEventsMatchingMask:
        NSEventMaskLeftMouseDown | NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp
        handler:^NSEvent*(NSEvent* event) {
            switch (event.type) {
                case NSEventTypeLeftMouseDown:
                    self->dragging_ = true;
                    break;
                case NSEventTypeLeftMouseUp:
                    self->dragging_ = false;
                    break;
                case NSEventTypeLeftMouseDragged:
                    if (self->dragging_) {
                        self->delta_x_ += (float)event.deltaX;
                        self->delta_y_ += (float)event.deltaY;
                    }
                    break;
                default:
                    break;
            }
            return event;
        }];
    monitor_token_ = (__bridge_retained void*)token;
}

InputHandler::~InputHandler() {
    if (monitor_token_) {
        id token = (__bridge_transfer id)monitor_token_;
        [NSEvent removeMonitor:token];
        monitor_token_ = nullptr;
    }
}

void InputHandler::consume_delta(float& dx, float& dy) {
    dx = delta_x_;
    dy = delta_y_;
    delta_x_ = delta_y_ = 0.0f;
}
