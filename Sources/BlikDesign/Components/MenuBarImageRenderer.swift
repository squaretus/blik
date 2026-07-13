import AppKit

/// Рендер иконки menu bar (RPM + температура) с кэшем по точному ключу.
/// NSImage пересоздаётся только когда изменилось одно из значений.
/// `nil` для любого параметра рисуется как «—» (используется при невалидной лицензии).
public enum MenuBarImageRenderer {

    /// Максимальный размер LRU-кэша (в одном процессе).
    private static let cacheLimit = 128

    private static let lock = NSLock()
    private static var cache: [String: NSImage] = [:]
    private static var order: [String] = []

    public static func image(fan0: Int?, fan1: Int?, temp: Int?) -> NSImage {
        let key = "\(fan0.map(String.init) ?? "-")|\(fan1.map(String.init) ?? "-")|\(temp.map(String.init) ?? "-")"
        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let image = render(fan0: fan0, fan1: fan1, temp: temp)

        lock.lock()
        cache[key] = image
        order.append(key)
        if order.count > cacheLimit {
            let oldest = order.removeFirst()
            cache.removeValue(forKey: oldest)
        }
        lock.unlock()
        return image
    }

    private static func render(fan0: Int?, fan1: Int?, temp: Int?) -> NSImage {
        let fontSize: CGFloat = 9
        let tempFontSize: CGFloat = 14
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        let tempFont = NSFont.monospacedDigitSystemFont(ofSize: tempFontSize, weight: .medium)

        let textColor = NSColor.white
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let tempAttrs: [NSAttributedString.Key: Any] = [.font: tempFont, .foregroundColor: textColor]

        let line0 = fan0.map { "\($0) RPM" } ?? "— RPM"
        let line1 = fan1.map { "\($0) RPM" }
        let tempStr = temp.map { "\($0)\u{00B0}C" } ?? "—\u{00B0}C"

        let line0Size = (line0 as NSString).size(withAttributes: attrs)
        let line1Size = line1.map { ($0 as NSString).size(withAttributes: attrs) } ?? .zero
        let tempSize = (tempStr as NSString).size(withAttributes: tempAttrs)

        let fanWidth = max(line0Size.width, line1Size.width)
        let separatorWidth: CGFloat = 8
        let height: CGFloat = 22
        let totalWidth = fanWidth + separatorWidth + tempSize.width + 2

        let image = NSImage(size: NSSize(width: totalWidth, height: height))
        image.lockFocus()

        let lineHeight = fontSize + 1
        let fansBlockHeight = fan1 != nil ? lineHeight * 2 + 1 : lineHeight
        let fansY = (height - fansBlockHeight) / 2

        (line0 as NSString).draw(
            at: NSPoint(x: fanWidth - line0Size.width, y: fansY + (fan1 != nil ? lineHeight + 1 : 0)),
            withAttributes: attrs
        )
        if let line1 {
            (line1 as NSString).draw(
                at: NSPoint(x: fanWidth - line1Size.width, y: fansY),
                withAttributes: attrs
            )
        }

        let sepX = fanWidth + 3
        let sepAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .ultraLight),
            .foregroundColor: NSColor.gray
        ]
        let pipe = "|"
        let pipeSize = (pipe as NSString).size(withAttributes: sepAttrs)
        (pipe as NSString).draw(
            at: NSPoint(x: sepX, y: (height - pipeSize.height) / 2),
            withAttributes: sepAttrs
        )

        let tempX = fanWidth + separatorWidth
        let tempY = (height - tempSize.height) / 2
        (tempStr as NSString).draw(at: NSPoint(x: tempX, y: tempY), withAttributes: tempAttrs)

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
