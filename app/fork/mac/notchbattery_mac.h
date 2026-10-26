#pragma once

// [fork] The notch bar's Battery menu above its switch (notchbattery_mac.mm), which notchmenus_mac.mm
// hosts under the battery item. Objective-C++ only.

#ifdef __OBJC__

#import <AppKit/AppKit.h>

#include "notchbar.h"

// The level, the power source, Low Power Mode and what the stream draws, as on the canvas. Plain
// views, so pointing at them or clicking them chooses nothing. update: changes them in place.
@interface ForkBatteryView : NSView
- (instancetype)initWithWidth:(CGFloat)width;
// Returns the height it needs now, which changes with the power source and Low Power Mode
- (CGFloat)update:(const NotchBar::MenuState&)state;
@end

#endif
