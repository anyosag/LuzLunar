#include "notchstatus_mac.h"

#include <cmath>

#include <QCoreApplication>

#import <QuartzCore/QuartzCore.h>

// [fork] Stream status, as designed on the notch bar's canvas: the stream's health, its latency from
// a click to the picture in four parts, the last two minutes of it, and the connection. The model
// comes from the bar each second while the panel is open (notchbar.mm).

namespace
{
    const CGFloat k_Inset = 9;              // between the view's edges and its text, as in menu rows
    const CGFloat k_HeaderHeight = 32;
    const CGFloat k_LabelRowHeight = 20;
    const CGFloat k_HeadlineHeight = 30;
    const CGFloat k_BarHeight = 10;
    const CGFloat k_LegendRowHeight = 22;
    const CGFloat k_SummaryRowHeight = 22;
    const CGFloat k_GraphHeight = 66;
    const CGFloat k_GraphBase = 64;         // the graph's 0 ms line
    const CGFloat k_AxisHeight = 16;
    const CGFloat k_ValueRowHeight = 24;
    const CGFloat k_SeparatorSpace = 11;
    const CGFloat k_TooltipHeight = 34;
    const double k_FreshSeconds = 3;        // a newer sample than this is "Now"

    NSString* tr(const char* text)
    {
        return QCoreApplication::translate("NotchBar", text).toNSString();
    }

    NSColor* rgb(int hex, CGFloat alpha = 1)
    {
        return [NSColor colorWithSRGBRed:((hex >> 16) & 0xff) / 255.0 green:((hex >> 8) & 0xff) / 255.0
                                    blue:(hex & 0xff) / 255.0 alpha:alpha];
    }

    NSColor* primaryText() { return rgb(0xebebf0); }
    NSColor* secondaryText() { return rgb(0x98989f); }
    NSColor* axisText() { return rgb(0x8e8e93); }

    // The latency parts' colours, in StreamHistory::Part order
    NSColor* partColor(int part)
    {
        static const int colors[StreamHistory::PartCount] = { 0x3987e5, 0xd55181, 0x9085e9, 0x199e70 };
        return rgb(colors[part]);
    }

    NSString* partName(int part)
    {
        switch (part) {
        case StreamHistory::PcCaptureAndEncode:
            return tr("PC capture and encode");
        case StreamHistory::NetworkRoundTrip:
            return tr("Network round trip");
        case StreamHistory::MacDecode:
            return tr("Mac decode");
        default:
            return tr("Display, including V-Sync");
        }
    }

    NSTextField* makeLabel(NSString* text, NSFont* font, NSColor* color)
    {
        NSTextField* label = [NSTextField labelWithString:text != nil ? text : @""];
        label.font = font;
        label.textColor = color;
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.maximumNumberOfLines = 1;
        return label;
    }

    NSString* orDash(const QString& text)
    {
        return text.isEmpty() ? @"—" : text.toNSString();
    }

    // "20 ms", "4.2 ms"; "—" when unknown
    NSString* msText(double ms, int decimals)
    {
        return StreamHistory::known(ms) ? [NSString stringWithFormat:@"%.*f ms", decimals, ms] : @"—";
    }

    NSString* agoText(int seconds)
    {
        return seconds == 0 ? tr("Now") : QCoreApplication::translate("NotchBar", "%1 s ago").arg(seconds).toNSString();
    }

    CGColorRef white(CGFloat alpha)
    {
        return [NSColor colorWithWhite:1 alpha:alpha].CGColor;
    }
}

@class ForkStatusView;

@interface ForkStatusView ()
- (void)partHovered:(int)part;
- (void)graphPointerAt:(CGFloat)x;
@end

// A latency bar segment or legend row: says when the pointer comes and goes
@interface ForkHoverView : NSView
{
@public
    ForkStatusView* m_Owner;    // not retained: it holds this view
    int m_Part;
    BOOL m_Hovered;
    NSTrackingArea* m_Tracking;
}
@end

@implementation ForkHoverView
- (void)dealloc
{
    [m_Tracking release];
    [super dealloc];
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (m_Tracking != nil) {
        [self removeTrackingArea:m_Tracking];
        [m_Tracking release];
    }
    // Always active: the panel is never key
    m_Tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                              options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                owner:self
                                             userInfo:nil];
    [self addTrackingArea:m_Tracking];
}

- (void)mouseEntered:(NSEvent*)event
{
    (void)event;
    m_Hovered = YES;
    [m_Owner partHovered:m_Part];
}

- (void)mouseExited:(NSEvent*)event
{
    (void)event;
    m_Hovered = NO;
    [m_Owner partHovered:-1];
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event
{
    (void)event;
    return YES;
}
@end

// The last two minutes of latency: a line over an area, gridlines, "Bitrate lowered" markers, and
// the moment under the pointer
@interface ForkLatencyGraphView : NSView
{
@public
    ForkStatusView* m_Owner;    // not retained: it holds this view
    std::vector<StreamHistory::Sample> m_Samples;
    double m_Now;
    NotchStatus::Scale m_Scale;
    CGFloat m_CursorX;          // NaN without the pointer
    int m_CursorSample;         // -1 for none, or a gap
    NSTrackingArea* m_Tracking;
}
@end

@implementation ForkLatencyGraphView
- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self != nil) {
        m_CursorX = NAN;
        m_CursorSample = -1;
        m_Now = 0;
        [self setAccessibilityElement:YES];
        [self setAccessibilityRole:NSAccessibilityImageRole];
    }
    return self;
}

- (void)dealloc
{
    [m_Tracking release];
    [super dealloc];
}

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event
{
    (void)event;
    return YES;
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (m_Tracking != nil) {
        [self removeTrackingArea:m_Tracking];
        [m_Tracking release];
    }
    // Moves too, always active: the panel is never key
    m_Tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                              options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                                                      NSTrackingActiveAlways | NSTrackingInVisibleRect
                                                owner:self
                                             userInfo:nil];
    [self addTrackingArea:m_Tracking];
}

- (void)pointerEvent:(NSEvent*)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    [m_Owner graphPointerAt:MAX(0, MIN(point.x, NSWidth(self.bounds)))];
}

- (void)mouseEntered:(NSEvent*)event
{
    [self pointerEvent:event];
}

- (void)mouseMoved:(NSEvent*)event
{
    [self pointerEvent:event];
}

- (void)mouseExited:(NSEvent*)event
{
    (void)event;
    [m_Owner graphPointerAt:NAN];
}

- (CGFloat)xFor:(const StreamHistory::Sample&)sample
{
    return NotchStatus::xForAge(m_Now - sample.seconds, NSWidth(self.bounds));
}

- (CGFloat)yFor:(double)ms
{
    return k_GraphBase - NotchStatus::heightFor(ms, m_Scale);
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    CGFloat width = NSWidth(self.bounds);

    // Gridlines at one and two steps, labelled at the left
    NSDictionary* gridLabel = @{ NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightRegular],
                                 NSForegroundColorAttributeName: axisText() };
    for (double ms : { m_Scale.stepMs, 2 * m_Scale.stepMs }) {
        CGFloat y = round([self yFor:ms]) + 0.5;
        [[NSColor colorWithWhite:1 alpha:0.08] setStroke];
        NSBezierPath* line = [NSBezierPath bezierPath];
        [line moveToPoint:NSMakePoint(0, y)];
        [line lineToPoint:NSMakePoint(width, y)];
        line.lineWidth = 1;
        [line stroke];
        // Above its line, or under it where the line is too near the top
        [[NSString stringWithFormat:@"%.0f ms", ms] drawAtPoint:NSMakePoint(1, y - 11.5 >= 0 ? y - 11.5 : y + 1) withAttributes:gridLabel];
    }
    [[NSColor colorWithWhite:1 alpha:0.18] setStroke];
    NSBezierPath* baseline = [NSBezierPath bezierPath];
    [baseline moveToPoint:NSMakePoint(0, k_GraphBase + 0.5)];
    [baseline lineToPoint:NSMakePoint(width, k_GraphBase + 0.5)];
    [baseline stroke];

    // "Bitrate lowered" lines under the latency line, their dots over it
    std::vector<CGFloat> markers;
    for (const StreamHistory::Sample& sample : m_Samples) {
        if (sample.lowered) {
            markers.push_back([self xFor:sample]);
        }
    }
    [[NSColor colorWithWhite:1 alpha:0.32] setStroke];
    for (CGFloat x : markers) {
        NSBezierPath* line = [NSBezierPath bezierPath];
        [line moveToPoint:NSMakePoint(round(x) + 0.5, 4)];
        [line lineToPoint:NSMakePoint(round(x) + 0.5, k_GraphBase)];
        [line stroke];
    }

    // The line, broken where frames stopped or a sample has no latency, over the area under it
    std::vector<std::size_t> starts = StreamHistory::runStarts(m_Samples);
    starts.push_back(m_Samples.size());
    for (std::size_t run = 0; run + 1 < starts.size(); run++) {
        std::vector<NSPoint> points;
        auto flush = [&]() {
            if (points.size() == 1) {
                [primaryText() setFill];
                [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(points[0].x - 1.5, points[0].y - 1.5, 3, 3)] fill];
            }
            else if (points.size() > 1) {
                NSBezierPath* area = [NSBezierPath bezierPath];
                [area moveToPoint:NSMakePoint(points.front().x, k_GraphBase)];
                for (NSPoint point : points) {
                    [area lineToPoint:point];
                }
                [area lineToPoint:NSMakePoint(points.back().x, k_GraphBase)];
                [area closePath];
                [rgb(0xebebf0, 0.08) setFill];
                [area fill];

                NSBezierPath* line = [NSBezierPath bezierPath];
                [line moveToPoint:points.front()];
                for (std::size_t i = 1; i < points.size(); i++) {
                    [line lineToPoint:points[i]];
                }
                line.lineWidth = 2;
                line.lineJoinStyle = NSLineJoinStyleRound;
                line.lineCapStyle = NSLineCapStyleRound;
                [primaryText() setStroke];
                [line stroke];
            }
            points.clear();
        };
        for (std::size_t i = starts[run]; i < starts[run + 1]; i++) {
            double total = StreamHistory::total(m_Samples[i].parts);
            if (!StreamHistory::known(total)) {
                flush();
                continue;
            }
            points.push_back(NSMakePoint([self xFor:m_Samples[i]], [self yFor:total]));
        }
        flush();
    }

    for (CGFloat x : markers) {
        NSBezierPath* dot = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - 3.5, k_GraphBase - 3.5, 7, 7)];
        [rgb(0xff9f0a) setFill];
        [dot fill];
        dot.lineWidth = 2;
        [rgb(0x26262a) setStroke];
        [dot stroke];
    }
    if (!markers.empty()) {
        // The newest marker's label, right of it, or left where it wouldn't fit
        NSDictionary* attributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:11],
                                      NSForegroundColorAttributeName: secondaryText() };
        NSString* label = tr("Bitrate lowered");
        CGFloat labelWidth = [label sizeWithAttributes:attributes].width;
        CGFloat x = markers.back() + 7;
        if (x + labelWidth > width) {
            x = markers.back() - 7 - labelWidth;
        }
        [label drawAtPoint:NSMakePoint(x, -1) withAttributes:attributes];
    }

    if (std::isnan(m_CursorX)) {
        return;
    }

    // The moment under the pointer: a crosshair at its sample, with a dot and a tooltip
    CGFloat x = m_CursorX;
    double total = StreamHistory::unknown();
    if (m_CursorSample >= 0 && m_CursorSample < (int)m_Samples.size()) {
        x = [self xFor:m_Samples[(std::size_t)m_CursorSample]];
        total = StreamHistory::total(m_Samples[(std::size_t)m_CursorSample].parts);
    }
    [[NSColor colorWithWhite:1 alpha:0.45] setStroke];
    NSBezierPath* crosshair = [NSBezierPath bezierPath];
    [crosshair moveToPoint:NSMakePoint(round(x) + 0.5, 0)];
    [crosshair lineToPoint:NSMakePoint(round(x) + 0.5, k_GraphBase)];
    [crosshair stroke];
    if (StreamHistory::known(total)) {
        NSBezierPath* dot = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - 4, [self yFor:total] - 4, 8, 8)];
        [primaryText() setFill];
        [dot fill];
        dot.lineWidth = 2;
        [rgb(0x26262a) setStroke];
        [dot stroke];
    }

    CGFloat tipX = NotchStatus::tooltipX(x, width);
    NSRect tip = NSMakeRect(tipX, 0, NotchStatus::k_TooltipWidth, k_TooltipHeight);
    NSBezierPath* box = [NSBezierPath bezierPathWithRoundedRect:tip xRadius:6 yRadius:6];
    [rgb(0x1c1c1f, 0.96) setFill];
    [box fill];
    box.lineWidth = 0.5;
    [[NSColor colorWithWhite:1 alpha:0.14] setStroke];
    [box stroke];
    double age = m_CursorSample >= 0 ? m_Now - m_Samples[(std::size_t)m_CursorSample].seconds : NotchStatus::ageForX(m_CursorX, width);
    [msText(total, 0) drawAtPoint:NSMakePoint(tipX + 6, 3)
                           withAttributes:@{ NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightSemibold],
                                             NSForegroundColorAttributeName: primaryText() }];
    [agoText(NotchStatus::secondsAgo(age)) drawAtPoint:NSMakePoint(tipX + 6, 18)
                                        withAttributes:@{ NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular],
                                                          NSForegroundColorAttributeName: secondaryText() }];
}
@end

@implementation ForkStatusView
{
    ForkStatusModel m_Model;
    double m_CursorAge;         // NaN while the pointer isn't on the graph
    int m_HoveredPart;          // -1 for none
    CGFloat m_Width;

    // Not retained: subviews, held by the view hierarchy
    NSView* m_HealthDot;
    NSTextField* m_HealthText;
    NSTextField* m_When;
    NSTextField* m_Headline;
    NSTextField* m_Subline;
    NSView* m_Bar;
    ForkHoverView* m_Segments[StreamHistory::PartCount];
    ForkHoverView* m_LegendRows[StreamHistory::PartCount];
    NSTextField* m_LegendValues[StreamHistory::PartCount];
    NSTextField* m_Summary;
    ForkLatencyGraphView* m_Graph;
    NSTextField* m_RowValues[6];
}

- (BOOL)isFlipped
{
    return YES;
}

- (NSTextField*)addLabel:(NSString*)text font:(NSFont*)font color:(NSColor*)color frame:(NSRect)frame
{
    NSTextField* label = makeLabel(text, font, color);
    label.frame = frame;
    [self addSubview:label];
    return label;
}

- (CGFloat)addSeparatorAt:(CGFloat)y
{
    NSView* line = [[[NSView alloc] initWithFrame:NSMakeRect(k_Inset, y + 5, m_Width - 2 * k_Inset, 1)] autorelease];
    line.wantsLayer = YES;
    line.layer.backgroundColor = white(0.12);
    [self addSubview:line];
    return y + k_SeparatorSpace;
}

- (instancetype)initWithWidth:(CGFloat)width
{
    self = [super initWithFrame:NSMakeRect(0, 0, width, 0)];
    if (self == nil) {
        return nil;
    }
    m_Width = width;
    m_CursorAge = NAN;
    m_HoveredPart = -1;
    CGFloat inner = width - 2 * k_Inset;

    NSFont* body = [NSFont systemFontOfSize:13];
    NSFont* small = [NSFont systemFontOfSize:12];
    NSFont* smallSemibold = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    NSFont* numbers = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular];
    NSFont* smallNumbers = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    CGFloat y = 0;

    // "Stream", and how it's going
    [self addLabel:tr("Stream") font:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold] color:primaryText()
             frame:NSMakeRect(k_Inset, y + 7, inner / 2, 18)];
    m_HealthText = [self addLabel:@"" font:small color:secondaryText() frame:NSMakeRect(k_Inset + inner / 2, y + 8, inner / 2, 16)];
    m_HealthText.alignment = NSTextAlignmentRight;
    m_HealthDot = [[[NSView alloc] initWithFrame:NSMakeRect(0, y + 12.5, 7, 7)] autorelease];
    m_HealthDot.wantsLayer = YES;
    m_HealthDot.layer.cornerRadius = 3.5;
    [self addSubview:m_HealthDot];
    y += k_HeaderHeight;

    // Latency, now or at the moment under the pointer
    [self addLabel:tr("Latency") font:smallSemibold color:secondaryText() frame:NSMakeRect(k_Inset, y + 2, inner / 2, 16)];
    m_When = [self addLabel:@"" font:smallNumbers color:secondaryText() frame:NSMakeRect(k_Inset + inner / 2, y + 2, inner / 2, 16)];
    m_When.alignment = NSTextAlignmentRight;
    y += k_LabelRowHeight;

    m_Headline = [self addLabel:@"—" font:[NSFont monospacedDigitSystemFontOfSize:22 weight:NSFontWeightSemibold] color:primaryText()
                          frame:NSMakeRect(k_Inset, y + 1, 90, 28)];
    m_Subline = [self addLabel:tr("from your click to the picture") font:small color:secondaryText() frame:NSMakeRect(k_Inset, y + 10, inner, 16)];
    y += k_HeadlineHeight;

    y += 6;
    m_Bar = [[[NSView alloc] initWithFrame:NSMakeRect(k_Inset, y, inner, k_BarHeight)] autorelease];
    [m_Bar setAccessibilityElement:YES];
    [m_Bar setAccessibilityRole:NSAccessibilityImageRole];
    [self addSubview:m_Bar];
    for (int part = 0; part < StreamHistory::PartCount; part++) {
        ForkHoverView* segment = [[[ForkHoverView alloc] initWithFrame:NSZeroRect] autorelease];
        segment->m_Owner = self;
        segment->m_Part = part;
        segment.wantsLayer = YES;
        segment.layer.backgroundColor = partColor(part).CGColor;
        [m_Bar addSubview:segment];
        m_Segments[part] = segment;
    }
    y += k_BarHeight + 8;

    for (int part = 0; part < StreamHistory::PartCount; part++) {
        // The row's highlight reaches 5 points past the text, as the canvas's does
        ForkHoverView* row = [[[ForkHoverView alloc] initWithFrame:NSMakeRect(k_Inset - 5, y, inner + 10, k_LegendRowHeight)] autorelease];
        row->m_Owner = self;
        row->m_Part = part;
        row.wantsLayer = YES;
        row.layer.cornerRadius = 5;
        NSView* swatch = [[[NSView alloc] initWithFrame:NSMakeRect(5, 6, 10, 10)] autorelease];
        swatch.wantsLayer = YES;
        swatch.layer.cornerRadius = 2;
        swatch.layer.backgroundColor = partColor(part).CGColor;
        [row addSubview:swatch];
        NSTextField* name = makeLabel(partName(part), body, primaryText());
        name.frame = NSMakeRect(23, 2, inner - 18 - 70, 17);
        [row addSubview:name];
        NSTextField* value = makeLabel(@"—", numbers, secondaryText());
        value.alignment = NSTextAlignmentRight;
        value.frame = NSMakeRect(inner + 5 - 70, 2, 70, 17);
        [row addSubview:value];
        [row setAccessibilityElement:NO];
        [self addSubview:row];
        m_LegendRows[part] = row;
        m_LegendValues[part] = value;
        y += k_LegendRowHeight;
    }

    [self addLabel:tr("Not counting the game itself or the screen's own delay.") font:[NSFont systemFontOfSize:11]
             color:secondaryText() frame:NSMakeRect(k_Inset, y + 3, inner, 14)];
    y += 3 + 14 + 4;
    y = [self addSeparatorAt:y];

    // The last two minutes
    [self addLabel:tr("Last 2 minutes") font:smallSemibold color:secondaryText() frame:NSMakeRect(k_Inset, y + 3, inner / 2, 16)];
    m_Summary = [self addLabel:@"—" font:smallNumbers color:secondaryText() frame:NSMakeRect(k_Inset + inner / 3, y + 3, inner * 2 / 3, 16)];
    m_Summary.alignment = NSTextAlignmentRight;
    y += k_SummaryRowHeight + 4;

    m_Graph = [[[ForkLatencyGraphView alloc] initWithFrame:NSMakeRect(k_Inset, y, inner, k_GraphHeight)] autorelease];
    m_Graph->m_Owner = self;
    [self addSubview:m_Graph];
    y += k_GraphHeight;

    NSFont* axis = [NSFont systemFontOfSize:10];
    [self addLabel:tr("2 min ago") font:axis color:axisText() frame:NSMakeRect(k_Inset, y + 2, 80, 13)];
    NSTextField* middle = [self addLabel:tr("1 min") font:axis color:axisText() frame:NSMakeRect(k_Inset + inner / 2 - 40, y + 2, 80, 13)];
    middle.alignment = NSTextAlignmentCenter;
    NSTextField* now = [self addLabel:tr("Now") font:axis color:axisText() frame:NSMakeRect(k_Inset + inner - 80, y + 2, 80, 13)];
    now.alignment = NSTextAlignmentRight;
    y += k_AxisHeight + 2;
    y = [self addSeparatorAt:y];

    // The connection
    NSString* names[6] = { tr("Connection"), tr("Link speed"), tr("Frame rate"), tr("PC frame pacing"), tr("Frames lost"), tr("Video") };
    for (int i = 0; i < 6; i++) {
        // Each value gets what its own label leaves, 16 points from it, as the canvas's grid does:
        // "VPN over Wi-Fi · not via LAN" and "HEVC · 4:4:4 · HDR · 3840×2160" are long
        NSTextField* name = [self addLabel:names[i] font:body color:secondaryText() frame:NSMakeRect(k_Inset, y + 3, inner, 17)];
        [name sizeToFit];
        CGFloat nameWidth = ceil(NSWidth(name.frame));
        name.frame = NSMakeRect(k_Inset, y + 3, nameWidth, 17);
        m_RowValues[i] = [self addLabel:@"—" font:numbers color:primaryText()
                                  frame:NSMakeRect(k_Inset + nameWidth + 16, y + 3, inner - nameWidth - 16, 17)];
        m_RowValues[i].alignment = NSTextAlignmentRight;
        m_RowValues[i].lineBreakMode = NSLineBreakByTruncatingMiddle;
        y += k_ValueRowHeight;
    }
    y += 4;
    y = [self addSeparatorAt:y];

    // The menu around it is the group VoiceOver names "Stream status"
    [self setFrameSize:NSMakeSize(width, y)];
    return self;
}

- (void)dealloc
{
    // Its views may outlive it for a moment, while AppKit still holds them
    for (int part = 0; part < StreamHistory::PartCount; part++) {
        m_Segments[part]->m_Owner = nil;
        m_LegendRows[part]->m_Owner = nil;
    }
    m_Graph->m_Owner = nil;
    [super dealloc];
}

- (void)update:(const ForkStatusModel&)model
{
    m_Model = model;
    [self render];
}

- (void)partHovered:(int)part
{
    m_HoveredPart = part;
    [self render];
}

- (void)graphPointerAt:(CGFloat)x
{
    m_CursorAge = std::isnan(x) ? NAN : NotchStatus::ageForX(x, NSWidth(m_Graph.bounds));
    m_Graph->m_CursorX = x;
    [self render];
}

- (void)render
{
    const std::vector<StreamHistory::Sample>& samples = m_Model.samples;
    double now = m_Model.now;

    // Changes show at once, not faded in
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    // The header's dot and words
    NSColor* dot;
    NSString* health;
    switch (m_Model.health) {
    case NotchStatus::Health::Waiting:
        dot = axisText();
        health = tr("Waiting for video");
        break;
    case NotchStatus::Health::Poor:
        dot = rgb(0xff453a);
        health = tr("Poor connection");
        break;
    default:
        dot = rgb(0x30d158);
        health = tr("Smooth");
        break;
    }
    m_HealthDot.layer.backgroundColor = dot.CGColor;
    m_HealthText.stringValue = health;
    [m_HealthText sizeToFit];
    CGFloat right = m_Width - k_Inset;
    CGFloat healthWidth = NSWidth(m_HealthText.frame);
    m_HealthText.frame = NSMakeRect(right - healthWidth, NSMinY(m_HealthText.frame), healthWidth, NSHeight(m_HealthText.frame));
    [m_HealthDot setFrameOrigin:NSMakePoint(right - healthWidth - 6 - 7, NSMinY(m_HealthDot.frame))];

    // The moment the latency block shows: under the pointer, or the newest, even from before the
    // two minutes when frames stopped coming
    int shown = -1;
    double age = 0;
    StreamHistory::Parts parts = StreamHistory::unknownParts();
    bool any = false;
    if (!std::isnan(m_CursorAge)) {
        shown = NotchStatus::nearest(samples, now, m_CursorAge);
        age = shown >= 0 ? now - samples[(std::size_t)shown].seconds : m_CursorAge;
        if (shown >= 0) {
            parts = samples[(std::size_t)shown].parts;
        }
        any = true;
    }
    else if (m_Model.haveLatest) {
        parts = m_Model.latest.parts;
        age = now - m_Model.latest.seconds;
        if (age < k_FreshSeconds) {
            age = 0;
        }
        any = true;
    }
    double total = StreamHistory::total(parts);
    m_When.stringValue = any ? agoText(NotchStatus::secondsAgo(age)) : @"";

    m_Headline.stringValue = msText(total, 0);
    [m_Headline sizeToFit];
    NSRect headline = m_Headline.frame;
    // On the headline's baseline
    CGFloat baseline = NSMinY(headline) + m_Headline.font.ascender;
    m_Subline.frame = NSMakeRect(NSMaxX(headline) + 7, round(baseline - m_Subline.font.ascender), m_Width - k_Inset - NSMaxX(headline) - 7,
                                 NSHeight(m_Subline.frame));

    // The bar: each part's share, the others dimmed while one is pointed at. A part that's gone
    // gets no mouseExited, so it stops being pointed at here.
    std::array<double, StreamHistory::PartCount> widths = NotchStatus::segmentWidths(parts, NSWidth(m_Bar.bounds));
    int last = -1;
    for (int part = 0; part < StreamHistory::PartCount; part++) {
        if (widths[(std::size_t)part] > 0) {
            last = part;
        }
    }
    if (m_HoveredPart >= 0 && widths[(std::size_t)m_HoveredPart] <= 0 && !m_LegendRows[m_HoveredPart]->m_Hovered) {
        m_HoveredPart = -1;
    }
    CGFloat x = 0;
    NSMutableArray<NSString*>* described = [NSMutableArray array];
    for (int part = 0; part < StreamHistory::PartCount; part++) {
        ForkHoverView* segment = m_Segments[part];
        CGFloat width = widths[(std::size_t)part];
        segment.hidden = width <= 0;
        if (width > 0) {
            segment.frame = NSMakeRect(x, 0, width, k_BarHeight);
            x += width + NotchStatus::k_SegmentGap;
            // Only the right end is rounded, as on the canvas
            segment.layer.cornerRadius = part == last ? 4 : 0;
            segment.layer.maskedCorners = kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;
        }
        segment.alphaValue = m_HoveredPart >= 0 && m_HoveredPart != part ? 0.35 : 1;
        m_LegendRows[part].layer.backgroundColor = m_HoveredPart == part ? white(0.08) : CGColorGetConstantColor(kCGColorClear);
        m_LegendValues[part].stringValue = msText(parts[(std::size_t)part], 1);
        [described addObject:[NSString stringWithFormat:@"%@ %@", partName(part), m_LegendValues[part].stringValue]];
    }
    [m_Bar setAccessibilityLabel:[NSString stringWithFormat:@"%@ %@: %@", tr("Latency"), m_Headline.stringValue,
                                                            [described componentsJoinedByString:@", "]]];

    // The last two minutes
    NotchStatus::Summary summary = NotchStatus::summarize(samples);
    m_Summary.stringValue = summary.any ? QCoreApplication::translate("NotchBar", "usually %1 ms · peak %2 ms")
                                              .arg(std::lround(summary.usualMs)).arg(std::lround(summary.peakMs)).toNSString()
                                        : @"—";
    m_Graph->m_Samples = samples;
    m_Graph->m_Now = now;
    m_Graph->m_Scale = NotchStatus::scaleFor(summary.any ? summary.peakMs : StreamHistory::unknown());
    m_Graph->m_CursorSample = std::isnan(m_CursorAge) ? -1 : shown;
    m_Graph.needsDisplay = YES;
    if (summary.any) {
        double peakAgo = now - samples[summary.peakIndex].seconds;
        QString text = QCoreApplication::translate("NotchBar", "Latency over the last 2 minutes: usually %1 ms, peak %2 ms %3 seconds ago")
                           .arg(std::lround(summary.usualMs)).arg(std::lround(summary.peakMs)).arg(NotchStatus::secondsAgo(peakAgo));
        if (NotchStatus::loweredNear(samples, summary.peakIndex)) {
            text += QCoreApplication::translate("NotchBar", ", when the bitrate was lowered");
        }
        [m_Graph setAccessibilityLabel:(text + ".").toNSString()];
    }
    else {
        [m_Graph setAccessibilityLabel:tr("Latency over the last 2 minutes: no video yet.")];
    }

    // The connection
    const QString* values[6] = { &m_Model.connection, &m_Model.linkSpeed, &m_Model.frameRate,
                                 &m_Model.pacing, &m_Model.framesLost, &m_Model.video };
    for (int i = 0; i < 6; i++) {
        m_RowValues[i].stringValue = orDash(*values[i]);
        [m_RowValues[i] setToolTip:values[i]->isEmpty() ? nil : values[i]->toNSString()];
    }

    [CATransaction commit];
}
@end
