// kit-candidate: AinkradZoomCanvas (spec 03 K1) — a pan / zoom world with Fit, re-fit on resize until moved,
// drag-to-pan on the background, two-finger scroll pans, ⌘-scroll and pinch zoom at the pointer.
import AinkradAppKit
import AppKit
import SwiftUI

/// The camera over a world: scale, the world's top-left in the viewport, and whether it still follows Fit.
struct PanZoomCamera: Equatable {
    static let minScale: CGFloat = 0.35
    static let maxScale: CGFloat = 2

    var scale: CGFloat = 1
    var offset: CGSize = .zero
    var fits = true
    /// The viewport and world sizes, as the canvas last laid them out.
    var viewport: CGSize = .zero
    var world: CGSize = .zero

    /// Everything in view, never above 100 %, centred, `top` from the top (prototype: 48 margin, 30 for the
    /// legend row).
    mutating func fit(margin: CGFloat = 48, bottom: CGFloat = 30) {
        guard world.width > 0, world.height > 0, viewport.width > 0 else { return }
        scale = max(
            Self.minScale,
            min(1, (viewport.width - margin * 2) / world.width, (viewport.height - margin * 2 - bottom) / world.height))
        offset = CGSize(width: (viewport.width - world.width * scale) / 2, height: margin)
        fits = true
    }

    /// Zooms to `scale × factor` keeping `point` (viewport coordinates, the centre by default) where it is.
    mutating func zoom(by factor: CGFloat, at point: CGPoint? = nil) {
        let p = point ?? CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let next = min(Self.maxScale, max(Self.minScale, scale * factor))
        offset = CGSize(
            width: p.x - (p.x - offset.width) * next / scale, height: p.y - (p.y - offset.height) * next / scale)
        scale = next
        fits = false
    }

    mutating func pan(_ delta: CGSize) {
        offset.width += delta.width
        offset.height += delta.height
        fits = false
    }

    var percent: Int { Int((scale * 100).rounded()) }
}

/// Draws `world` (laid out at `worldSize`, zoom 1) through `camera`. Nodes in the world keep their own taps;
/// a drag that starts on empty space pans.
struct PanZoomCanvas<World: View>: View {
    @Binding var camera: PanZoomCamera
    let worldSize: CGSize
    @ViewBuilder let world: () -> World
    @State private var dragStart: CGSize?
    @State private var pinchStart: CGFloat?
    @State private var pointer: CGPoint?
    @State private var wheel = WheelMonitor()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(Rectangle()).gesture(pan)
                world()
                    .frame(width: worldSize.width, height: worldSize.height, alignment: .topLeading)
                    .scaleEffect(camera.scale, anchor: .topLeading)
                    .offset(camera.offset)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(pinch)
            .onContinuousHover { phase in
                if case .active(let location) = phase { pointer = location } else { pointer = nil }
            }
            .onAppear { layout(geo.size) }
            .onChange(of: geo.size) { _, size in layout(size) }
            .onChange(of: worldSize) { _, _ in layout(geo.size) }
        }
        .onAppear {
            wheel.install { event in
                guard let at = pointer else { return false }
                if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
                    camera.zoom(
                        by: exp(-event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.01 : 0.1)), at: at)
                } else {
                    camera.pan(CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
                }
                return true
            }
        }
        .onDisappear { wheel.remove() }
    }

    private func layout(_ size: CGSize) {
        camera.viewport = size
        camera.world = worldSize
        if camera.fits { camera.fit() }
    }

    private var pan: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = dragStart ?? camera.offset
                dragStart = start
                camera.offset = CGSize(
                    width: start.width + value.translation.width, height: start.height + value.translation.height)
                camera.fits = false
            }
            .onEnded { _ in dragStart = nil }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? camera.scale
                pinchStart = start
                camera.zoom(by: start * value.magnification / camera.scale, at: value.startLocation)
            }
            .onEnded { _ in pinchStart = nil }
    }
}

/// Scroll-wheel events while the pointer is over the canvas (SwiftUI has no wheel gesture on macOS 14); the
/// handler returns whether it used the event.
@MainActor
private final class WheelMonitor {
    private var token: Any?

    func install(_ handler: @escaping @MainActor (NSEvent) -> Bool) {
        remove()
        token = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            nonisolated(unsafe) let box = event
            let used = MainActor.assumeIsolated { handler(box) }
            return used ? nil : event
        }
    }

    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}
