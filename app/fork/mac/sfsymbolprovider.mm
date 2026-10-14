#include "fork/sfsymbols.h"

#include <QImage>
#include <QQuickImageProvider>

#import <AppKit/AppKit.h>

namespace
{
    // Draws an SF Symbol in black on a transparent image, centered and scaled to fit
    class SfSymbolProvider : public QQuickImageProvider
    {
    public:
        SfSymbolProvider()
            : QQuickImageProvider(QQuickImageProvider::Image)
        {
        }

        QImage requestImage(const QString& id, QSize* size, const QSize& requestedSize) override
        {
            // requestedSize is in pixels. A control's icon (IconLabel) already asks for its size
            // times the screen scale; a plain Image/IconImage gets exactly its sourceSize, so QML
            // asks for twice the drawn size to stay sharp on Retina (see PcView.qml).
            int width = requestedSize.width() > 0 ? requestedSize.width() : 128;
            int height = requestedSize.height() > 0 ? requestedSize.height() : width;
            if (size != nullptr) {
                *size = QSize(width, height);
            }

            // Drawing goes into this call's own bitmap context, so it is also safe if an image
            // using the provider is ever loaded asynchronously (off the GUI thread)
            @autoreleasepool {
                NSImage* symbol = [NSImage imageWithSystemSymbolName:id.toNSString() accessibilityDescription:nil];
                if (symbol == nil) {
                    return QImage();
                }

                // A point size near the drawn size keeps the stroke weight right
                NSImageSymbolConfiguration* config =
                        [NSImageSymbolConfiguration configurationWithPointSize:qMin(width, height) * 0.8
                                                                        weight:NSFontWeightRegular];
                symbol = [symbol imageWithSymbolConfiguration:config];

                NSBitmapImageRep* rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr
                                                                                 pixelsWide:width
                                                                                 pixelsHigh:height
                                                                              bitsPerSample:8
                                                                            samplesPerPixel:4
                                                                                   hasAlpha:YES
                                                                                   isPlanar:NO
                                                                             colorSpaceName:NSDeviceRGBColorSpace
                                                                                bytesPerRow:0
                                                                               bitsPerPixel:0] autorelease];
                if (rep == nil) {
                    return QImage();
                }

                NSSize symbolSize = symbol.size;
                CGFloat scale = qMin(width / symbolSize.width, height / symbolSize.height);
                NSSize drawSize = NSMakeSize(symbolSize.width * scale, symbolSize.height * scale);
                NSRect drawRect = NSMakeRect((width - drawSize.width) / 2, (height - drawSize.height) / 2,
                                             drawSize.width, drawSize.height);

                [NSGraphicsContext saveGraphicsState];
                NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
                [symbol drawInRect:drawRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
                [NSGraphicsContext restoreGraphicsState];

                // NSBitmapImageRep's default layout is premultiplied RGBA, top row first
                return QImage(rep.bitmapData, width, height, rep.bytesPerRow,
                              QImage::Format_RGBA8888_Premultiplied).copy();
            }
        }
    };
}

QQuickImageProvider* createSfSymbolProvider()
{
    return new SfSymbolProvider();
}
