import CoreGraphics
import Foundation

public enum WindowLayoutAction: String, CaseIterable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case maximize
    case center
    case restore
    case nextDisplay
}

public enum WindowLayout {
    public static func frame(for action: WindowLayoutAction, in area: CGRect, current: CGRect) -> CGRect? {
        guard area.width > 0, area.height > 0 else { return nil }
        let halfWidth = floor(area.width / 2)
        let halfHeight = floor(area.height / 2)
        let rightWidth = area.width - halfWidth
        let bottomHeight = area.height - halfHeight

        switch action {
        case .leftHalf:
            return CGRect(x: area.minX, y: area.minY, width: halfWidth, height: area.height)
        case .rightHalf:
            return CGRect(x: area.minX + halfWidth, y: area.minY, width: rightWidth, height: area.height)
        case .topHalf:
            return CGRect(x: area.minX, y: area.minY, width: area.width, height: halfHeight)
        case .bottomHalf:
            return CGRect(x: area.minX, y: area.minY + halfHeight, width: area.width, height: bottomHeight)
        case .topLeft:
            return CGRect(x: area.minX, y: area.minY, width: halfWidth, height: halfHeight)
        case .topRight:
            return CGRect(x: area.minX + halfWidth, y: area.minY, width: rightWidth, height: halfHeight)
        case .bottomLeft:
            return CGRect(x: area.minX, y: area.minY + halfHeight, width: halfWidth, height: bottomHeight)
        case .bottomRight:
            return CGRect(x: area.minX + halfWidth, y: area.minY + halfHeight, width: rightWidth, height: bottomHeight)
        case .maximize:
            return area
        case .center:
            let width = min(current.width, area.width)
            let height = min(current.height, area.height)
            return CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
        case .restore, .nextDisplay:
            return nil
        }
    }

    public static func frameOnNextDisplay(current: CGRect, from source: CGRect, to target: CGRect) -> CGRect? {
        guard source.width > 0, source.height > 0, target.width > 0, target.height > 0 else { return nil }
        let widthRatio = min(max(current.width / source.width, 0), 1)
        let heightRatio = min(max(current.height / source.height, 0), 1)
        let movableX = max(source.width - current.width, 0)
        let movableY = max(source.height - current.height, 0)
        let relativeX = movableX > 0 ? (current.minX - source.minX) / movableX : 0.5
        let relativeY = movableY > 0 ? (current.minY - source.minY) / movableY : 0.5
        let width = target.width * widthRatio
        let height = target.height * heightRatio
        return CGRect(
            x: target.minX + max(target.width - width, 0) * min(max(relativeX, 0), 1),
            y: target.minY + max(target.height - height, 0) * min(max(relativeY, 0), 1),
            width: width,
            height: height
        ).integral
    }
}
