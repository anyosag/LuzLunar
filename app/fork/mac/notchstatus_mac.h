#pragma once

// [fork] The notch bar's Stream status panel (notchstatus_mac.mm), which notchmenus_mac.mm hosts
// under the stats item. Objective-C++ only.

#ifdef __OBJC__

#import <AppKit/AppKit.h>

#include <vector>

#include <QString>

#include "fork/notchstatus.h"

// What the panel shows, gathered by the bar (notchbar.mm) on the main thread
struct ForkStatusModel {
    double now = 0;     // ForkStreamStats::nowSeconds()
    std::vector<StreamHistory::Sample> samples;     // the last two minutes
    bool haveLatest = false;                        // a snapshot arrived this stream, maybe longer ago
    StreamHistory::Sample latest;
    NotchStatus::Health health = NotchStatus::Health::Waiting;
    // The rows, formatted; empty ones show "—"
    QString connection;
    QString linkSpeed;
    QString frameRate;
    QString pacing;
    QString framesLost;
    QString video;
};

// Everything in the panel above its two rows. Plain views rather than menu controls, so pointing at
// them or clicking them selects and chooses nothing. Pointing at the latency graph shows that moment
// in the latency block; pointing at a part of the latency bar or its legend picks the part out.
// Updated in place, at a fixed height, so the panel never moves under the pointer.
@interface ForkStatusView : NSView
- (instancetype)initWithWidth:(CGFloat)width;
- (void)update:(const ForkStatusModel&)model;
@end

#endif
