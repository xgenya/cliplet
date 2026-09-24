import AppKit

/// The private window-server mesh warp behind the Dock's Genie effect. Symbols
/// are resolved at runtime, so a system without them only loses the effect.
@MainActor
enum WindowWarp {
    struct Point {
        var x: Float
        var y: Float
    }

    /// Maps a point in window coordinates (top-left origin) to global screen
    /// coordinates (top-left origin of the primary display), both in points.
    struct MeshPoint {
        var local: Point
        var global: Point
    }

    private typealias ConnectionFunction = @convention(c) () -> Int32
    /// The mesh is passed raw: `MeshPoint` has the C layout of four packed floats.
    private typealias WarpFunction = @convention(c) (Int32, UInt32, Int32, Int32, UnsafeRawPointer?) -> Int32

    private static let connection: ConnectionFunction? =
        symbol("CGSMainConnectionID") ?? symbol("SLSMainConnectionID")
    private static let warp: WarpFunction? = symbol("CGSSetWindowWarp") ?? symbol("SLSSetWindowWarp")

    static var isAvailable: Bool { connection != nil && warp != nil }

    /// `mesh` holds `rows` rows of `columns` points each, top row first.
    @discardableResult
    static func apply(_ mesh: [MeshPoint], columns: Int, rows: Int, to window: NSWindow) -> Bool {
        guard let connection, let warp, mesh.count == columns * rows, window.windowNumber > 0 else { return false }
        return mesh.withUnsafeBufferPointer {
            warp(
                connection(), UInt32(window.windowNumber), Int32(columns), Int32(rows),
                UnsafeRawPointer($0.baseAddress)) == 0
        }
    }

    static func reset(_ window: NSWindow) {
        guard let connection, let warp, window.windowNumber > 0 else { return }
        _ = warp(connection(), UInt32(window.windowNumber), 0, 0, nil)
    }

    /// A Genie mesh between a window and a narrow neck, both in global
    /// coordinates. At `collapse` 0 the window is untouched; the edges first
    /// bend toward the neck, then the content slides into it until 1.
    nonisolated static func genieMesh(
        window: CGRect, neck: CGRect, collapse: Double, rows: Int
    ) -> [MeshPoint] {
        let bend = CGFloat(min(collapse / 0.4, 1))
        let slide = CGFloat(max((collapse - 0.4) / 0.6, 0))
        let neckY = neck.maxY
        let mouthY = window.maxY
        let top = window.minY + (neckY - window.minY) * slide
        let bottom = window.maxY + (neckY - window.maxY) * slide
        return (0..<rows).flatMap { row -> [MeshPoint] in
            let v = CGFloat(row) / CGFloat(rows - 1)
            let y = top + (bottom - top) * v
            let u = min(max((y - neckY) / (mouthY - neckY), 0), 1)
            let squeeze = (1 - u * u * (3 - 2 * u)) * bend
            let left = window.minX + (neck.minX - window.minX) * squeeze
            let right = window.maxX + (neck.maxX - window.maxX) * squeeze
            let localY = Float(window.height * v)
            return [
                MeshPoint(local: Point(x: 0, y: localY), global: Point(x: Float(left), y: Float(y))),
                MeshPoint(local: Point(x: Float(window.width), y: localY), global: Point(x: Float(right), y: Float(y))),
            ]
        }
    }

    private static func symbol<T>(_ name: String) -> T? {
        // RTLD_DEFAULT searches every image already loaded into the process.
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
