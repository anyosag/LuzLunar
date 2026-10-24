#pragma once

// [fork] The notch bar's astral projection (notchreach_mac.mm), for notchbar.mm: Mac trackpad mode's
// pointer floating up into the bar as a ghost, and sucked back home into the PC's pointer as it
// comes back down, drawn on a click-through panel over the stream and the bar. The PC's pointer
// pulses twice before it goes and once as it comes back; the PC draws that itself (Apollo's
// cursor_pulse.h), and this draws it only for a PC that can't. Objective-C++ only.

#ifdef __OBJC__

#import <AppKit/AppKit.h>

#include <functional>
#include <optional>
#include <utility>

@interface ForkReachOverlay : NSObject
- (instancetype)initWithStreamWindow:(NSWindow*)window;

// The ghost of the PC's pointer, from this point of the screen (Cocoa's coordinates), floats up to
// that one in the strip, where the Mac's pointer has been put; the Mac's pointer is hidden until the
// ghost gets there. With Reduce Motion it's there at once.
- (void)projectFrom:(NSPoint)from to:(NSPoint)to;

// The ghost of the Mac's pointer, from this point of the screen, is sucked back into the PC's,
// chasing it to wherever target says the stream has put it (none: where it was), as the picture
// shows it lagMs later (the stream's latency); arriving is called just before it gets there, for
// the PC's pulse
- (void)pullFrom:(NSPoint)from
          target:(std::function<std::optional<NSPoint>()>)target
           lagMs:(double)lagMs
        arriving:(std::function<void()>)arriving;

// Pulses drawn over the PC's pointer at this point of the screen, for a PC that can't pulse it
// itself; size: the PC's arrow's height in points
- (void)pulseAt:(NSPoint)point count:(int)count size:(CGFloat)size;
- (void)settlePulse;

// Ends whatever plays, and shows the Mac's pointer if it hid it
- (void)invalidate;
@end

#endif
