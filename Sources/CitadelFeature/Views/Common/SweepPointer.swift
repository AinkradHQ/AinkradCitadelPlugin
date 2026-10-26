import SwiftUI

private struct SweepPointerKey: EnvironmentKey { static let defaultValue: CGPoint? = nil }

extension EnvironmentValues {
    /// Where the sweep tests rest the pointer (root-view coordinates). Nil in the app. A synthesized `mouseMoved`
    /// does not reach SwiftUI's hover tracking, so rows that hover read this to show their hover state in captures.
    var citadelSweepPointer: CGPoint? {
        get { self[SweepPointerKey.self] }
        set { self[SweepPointerKey.self] = newValue }
    }
}

extension View {
    /// `onHover` that also reads `citadelSweepPointer`, so a sweep capture can show the hover state. Use it for every
    /// hover in the plugin: a plain `.onHover` cannot be forced in a still.
    func citadelHover(_ hovering: Binding<Bool>) -> some View { modifier(CitadelHover(hovering: hovering)) }
}

private struct CitadelHover: ViewModifier {
    @Binding var hovering: Bool
    @Environment(\.citadelSweepPointer) private var sweepPointer

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .background {
                if let sweepPointer {
                    GeometryReader { proxy in
                        Color.clear.onAppear { if proxy.frame(in: .global).contains(sweepPointer) { hovering = true } }
                    }
                }
            }
    }
}
