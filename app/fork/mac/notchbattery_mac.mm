#include "notchbattery_mac.h"

#include <QCoreApplication>

#include "fork/powerrules.h"

// [fork] The Battery menu's top, as designed on the notch bar's canvas: the level, the power source,
// Low Power Mode, and "While streaming": what the Mac draws and what that leaves, or how charging
// goes. The bar refreshes it as ForkPower reads the battery (every 10 s, and when macOS says).

namespace
{
    const CGFloat k_Inset = 9;              // between the view's edges and its text, as in menu rows
    const CGFloat k_HeaderHeight = 32;
    const CGFloat k_LowPowerRowHeight = 26;
    const CGFloat k_ValueRowHeight = 24;
    const CGFloat k_SeparatorSpace = 11;
    const CGFloat k_Dot = 7;

    NSString* tr(const char* text)
    {
        return QCoreApplication::translate("NotchBar", text).toNSString();
    }

    NSColor* rgb(int hex)
    {
        return [NSColor colorWithSRGBRed:((hex >> 16) & 0xff) / 255.0 green:((hex >> 8) & 0xff) / 255.0
                                    blue:(hex & 0xff) / 255.0 alpha:1];
    }

    NSColor* primaryText() { return rgb(0xebebf0); }
    NSColor* secondaryText() { return rgb(0x98989f); }

    NSTextField* makeLabel(NSFont* font, NSColor* color)
    {
        NSTextField* label = [NSTextField labelWithString:@""];
        label.font = font;
        label.textColor = color;
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.maximumNumberOfLines = 1;
        return label;
    }

    NSString* ns(const std::string& text)
    {
        return [NSString stringWithUTF8String:text.c_str()];
    }

    // A label's height for one line
    CGFloat lineHeight(NSTextField* label)
    {
        [label sizeToFit];
        return NSHeight(label.frame);
    }
}

@implementation ForkBatteryView
{
    CGFloat m_Width;
    NSTextField* m_Title;
    NSTextField* m_Level;
    NSTextField* m_Source;
    NSTextField* m_LowPowerTitle;
    NSView* m_LowPowerDot;
    NSTextField* m_LowPowerValue;
    NSTextField* m_LowPowerNote;
    NSView* m_Separator;
    NSTextField* m_StreamingTitle;
    NSTextField* m_Headline;
    NSTextField* m_HeadlineDetail;
    NSTextField* m_RowTitles[2];
    NSTextField* m_RowValues[2];
}

- (instancetype)initWithWidth:(CGFloat)width
{
    self = [super initWithFrame:NSMakeRect(0, 0, width, 100)];
    if (self == nil) {
        return nil;
    }
    m_Width = width;

    m_Title = makeLabel([NSFont systemFontOfSize:13 weight:NSFontWeightSemibold], primaryText());
    m_Title.stringValue = tr("Battery");
    m_Level = makeLabel([NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular], primaryText());
    m_Level.alignment = NSTextAlignmentRight;
    m_Source = makeLabel([NSFont systemFontOfSize:13], secondaryText());
    m_LowPowerTitle = makeLabel([NSFont systemFontOfSize:13], primaryText());
    m_LowPowerTitle.stringValue = tr("Low Power Mode");
    m_LowPowerDot = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, k_Dot, k_Dot)] autorelease];
    m_LowPowerDot.wantsLayer = YES;
    m_LowPowerDot.layer.cornerRadius = k_Dot / 2;
    m_LowPowerDot.layer.backgroundColor = rgb(0xffd60a).CGColor;
    m_LowPowerValue = makeLabel([NSFont systemFontOfSize:13], primaryText());
    m_LowPowerValue.alignment = NSTextAlignmentRight;
    m_LowPowerNote = makeLabel([NSFont systemFontOfSize:12], secondaryText());
    m_LowPowerNote.stringValue = tr("macOS holds the screen to 60 Hz while it’s on.");
    m_Separator = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
    m_Separator.wantsLayer = YES;
    m_Separator.layer.backgroundColor = [NSColor colorWithWhite:1 alpha:0.12].CGColor;
    m_StreamingTitle = makeLabel([NSFont systemFontOfSize:12 weight:NSFontWeightSemibold], secondaryText());
    m_StreamingTitle.stringValue = tr("While streaming");
    m_Headline = makeLabel([NSFont monospacedDigitSystemFontOfSize:22 weight:NSFontWeightSemibold], primaryText());
    m_HeadlineDetail = makeLabel([NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular], secondaryText());
    m_HeadlineDetail.alignment = NSTextAlignmentRight;
    for (int i = 0; i < 2; i++) {
        m_RowTitles[i] = makeLabel([NSFont systemFontOfSize:13], secondaryText());
        m_RowValues[i] = makeLabel([NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular], primaryText());
        m_RowValues[i].alignment = NSTextAlignmentRight;
    }

    for (NSView* view in @[ m_Title, m_Level, m_Source, m_LowPowerTitle, m_LowPowerDot, m_LowPowerValue, m_LowPowerNote,
                            m_Separator, m_StreamingTitle, m_Headline, m_HeadlineDetail, m_RowTitles[0], m_RowValues[0],
                            m_RowTitles[1], m_RowValues[1] ]) {
        [self addSubview:view];
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

// A title at the left and its value at the right, in a row of this height
- (void)placeLeft:(NSTextField*)left right:(NSTextField*)right y:(CGFloat)y height:(CGFloat)height
{
    CGFloat inner = m_Width - 2 * k_Inset;
    CGFloat rightWidth = 0;
    if (right != nil) {
        [right sizeToFit];
        rightWidth = MIN(NSWidth(right.frame), inner);
        right.frame = NSMakeRect(m_Width - k_Inset - rightWidth, y + round((height - NSHeight(right.frame)) / 2), rightWidth,
                                 NSHeight(right.frame));
    }
    [left sizeToFit];
    left.frame = NSMakeRect(k_Inset, y + round((height - NSHeight(left.frame)) / 2), MAX(inner - rightWidth - 12, 0), NSHeight(left.frame));
}

- (CGFloat)update:(const NotchBar::MenuState&)state
{
    const PowerRules::Reading& power = state.power;
    CGFloat y = 0;

    // "Battery" and the level
    m_Level.stringValue = power.present ? [NSString stringWithFormat:@"%d%%", power.level] : @"—";
    [self placeLeft:m_Title right:m_Level y:y height:k_HeaderHeight];
    y += k_HeaderHeight;

    m_Source.stringValue = QCoreApplication::translate("NotchBar", "Power Source: %1")
                               .arg(power.onAC ? QCoreApplication::translate("NotchBar", "Power Adapter")
                                               : QCoreApplication::translate("NotchBar", "Battery"))
                               .toNSString();
    CGFloat height = lineHeight(m_Source);
    m_Source.frame = NSMakeRect(k_Inset, y, m_Width - 2 * k_Inset, height);
    y += height + 4;

    // Low Power Mode, on with a yellow dot and what it does to the screen
    m_LowPowerValue.stringValue = state.lowPowerMode ? tr("On") : tr("Off");
    m_LowPowerValue.textColor = state.lowPowerMode ? primaryText() : secondaryText();
    [self placeLeft:m_LowPowerTitle right:m_LowPowerValue y:y height:k_LowPowerRowHeight];
    m_LowPowerDot.hidden = !state.lowPowerMode;
    [m_LowPowerDot setFrameOrigin:NSMakePoint(NSMinX(m_LowPowerValue.frame) - 6 - k_Dot, y + round((k_LowPowerRowHeight - k_Dot) / 2))];
    y += k_LowPowerRowHeight;
    m_LowPowerNote.hidden = !state.lowPowerMode;
    if (state.lowPowerMode) {
        height = lineHeight(m_LowPowerNote);
        m_LowPowerNote.frame = NSMakeRect(k_Inset, y, m_Width - 2 * k_Inset, height);
        y += height + 4;
    }

    m_Separator.frame = NSMakeRect(k_Inset, y + round(k_SeparatorSpace / 2), m_Width - 2 * k_Inset, 1);
    y += k_SeparatorSpace;

    height = lineHeight(m_StreamingTitle);
    m_StreamingTitle.frame = NSMakeRect(k_Inset, y + 4, m_Width - 2 * k_Inset, height);
    y += 4 + height + 2;

    // What the stream draws: on battery, the watts and what they leave; on a power adapter, charging
    NSString* headline = @"—";
    NSString* detail = @"";
    NSString* rows[2][2] = { { nil, nil }, { nil, nil } };
    switch (PowerRules::branch(power)) {
    case PowerRules::Branch::OnBattery: {
        double perHour = PowerRules::percentPerHour(power);
        if (PowerRules::known(power.watts)) {
            headline = ns(PowerRules::wattsText(power.watts));
            if (PowerRules::known(perHour)) {
                detail = QCoreApplication::translate("NotchBar", "about %1% an hour").arg(qRound(perHour)).toNSString();
            }
        }
        else if (PowerRules::known(perHour)) {
            // Without the watts, the rate the level falls at takes their place
            headline = QCoreApplication::translate("NotchBar", "%1% an hour").arg(qRound(perHour)).toNSString();
        }
        int left = PowerRules::minutesLeft(power);
        rows[0][0] = tr("Time left at this rate");
        rows[0][1] = left > 0 ? ns(PowerRules::duration(left)) : @"—";
        rows[1][0] = tr("This stream so far");
        rows[1][1] = state.powerStartLevel >= 0 ? ns(PowerRules::sinceStart(state.powerStartLevel, power.level, state.powerMinutes)) : @"—";
        break;
    }
    case PowerRules::Branch::Charging:
        headline = tr("Charging");
        if (power.minutesToFull > 0) {
            detail = QCoreApplication::translate("NotchBar", "Full in %1").arg(QString::fromStdString(PowerRules::duration(power.minutesToFull))).toNSString();
        }
        if (PowerRules::known(power.watts)) {
            rows[0][0] = tr("The Mac draws");
            rows[0][1] = ns(PowerRules::wattsText(power.watts));
        }
        break;
    case PowerRules::Branch::Charged:
        headline = tr("Charged");
        if (PowerRules::known(power.watts)) {
            rows[0][0] = tr("The Mac draws");
            rows[0][1] = ns(PowerRules::wattsText(power.watts));
        }
        break;
    }
    m_Headline.stringValue = headline;
    m_HeadlineDetail.stringValue = detail;
    height = lineHeight(m_Headline);
    [self placeLeft:m_Headline right:m_HeadlineDetail y:y + 2 height:height];
    // On the headline's baseline, as on the canvas
    CGFloat baseline = NSMaxY(m_Headline.frame) + m_Headline.font.descender;
    [m_HeadlineDetail setFrameOrigin:NSMakePoint(NSMinX(m_HeadlineDetail.frame),
                                                 round(baseline - NSHeight(m_HeadlineDetail.frame) - m_HeadlineDetail.font.descender))];
    y += 2 + height + 6;

    for (int i = 0; i < 2; i++) {
        BOOL shown = rows[i][0] != nil;
        m_RowTitles[i].hidden = !shown;
        m_RowValues[i].hidden = !shown;
        if (shown) {
            m_RowTitles[i].stringValue = rows[i][0];
            m_RowValues[i].stringValue = rows[i][1];
            [self placeLeft:m_RowTitles[i] right:m_RowValues[i] y:y height:k_ValueRowHeight];
            y += k_ValueRowHeight;
        }
    }
    y += 4;

    [self setFrameSize:NSMakeSize(m_Width, y)];
    return y;
}
@end
