import Foundation

enum EdgeGeometry {
    static func panelFrame(visible: CGRect, width: CGFloat, heightRatio: CGFloat, isLeft: Bool) -> CGRect {
        let width = min(max(360, width), visible.width)
        let height = min(visible.height, max(320, visible.height * heightRatio))
        return CGRect(x: isLeft ? visible.minX : visible.maxX - width,
                      y: visible.midY - height / 2, width: width, height: height)
    }

    static func touchesOuterEdge(point: CGPoint, screen: CGRect, otherScreens: [CGRect],
                                 isLeft: Bool, exclusion: CGFloat) -> Bool {
        let edge = isLeft ? screen.minX : screen.maxX
        guard abs(point.x - edge) <= 3, point.y > screen.minY + exclusion,
              point.y < screen.maxY - exclusion else { return false }
        let beyond = CGPoint(x: edge + (isLeft ? -2 : 2), y: point.y)
        return !otherScreens.contains { $0.contains(beyond) }
    }
}
