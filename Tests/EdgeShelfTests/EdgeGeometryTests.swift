import XCTest
@testable import EdgeShelf

final class EdgeGeometryTests: XCTestCase {
    func testPanelFitsOffsetDisplayAndTinyDisplay() {
        let visible = CGRect(x: -1920, y: 80, width: 1920, height: 1000)
        let left = EdgeGeometry.panelFrame(visible: visible, width: 420, heightRatio: 0.8, isLeft: true)
        XCTAssertEqual(left.minX, -1920)
        XCTAssertEqual(left.height, 800)
        XCTAssertEqual(left.midY, visible.midY)
        let right = EdgeGeometry.panelFrame(visible: visible, width: 420, heightRatio: 1, isLeft: false)
        XCTAssertEqual(right.maxX, 0)
        XCTAssertEqual(right.height, visible.height)
        let tiny = EdgeGeometry.panelFrame(visible: CGRect(x: 0, y: 0, width: 300, height: 250), width: 640, heightRatio: 0.5, isLeft: false)
        XCTAssertEqual(tiny.size, CGSize(width: 300, height: 250))
    }

    func testSharedScreenEdgeDoesNotTrigger() {
        let first = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        XCTAssertFalse(EdgeGeometry.touchesOuterEdge(point: CGPoint(x: 1439, y: 500), screen: first,
                                                    otherScreens: [second], isLeft: false, exclusion: 32))
        XCTAssertTrue(EdgeGeometry.touchesOuterEdge(point: CGPoint(x: 1, y: 500), screen: first,
                                                   otherScreens: [second], isLeft: true, exclusion: 32))
        XCTAssertFalse(EdgeGeometry.touchesOuterEdge(point: CGPoint(x: 1, y: 20), screen: first,
                                                    otherScreens: [], isLeft: true, exclusion: 32))
    }
}
