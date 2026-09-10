import SwiftUI

/// Moves the original row in its stack; no system drag snapshot is created.
@MainActor
final class CardReorder: ObservableObject {
    @Published var active: String?
    @Published var translation: CGFloat = 0
    @Published var destination: Int = 0
    var frames: [String: CGRect] = [:]
    private var order: [String] = []

    func update(id: String, order: [String], translation: CGFloat) {
        if active == nil {
            self.order = order
            active = id
            destination = order.firstIndex(of: id) ?? 0
            Haptics.trigger(.selection)
        }
        self.translation = translation
        guard let frame = frames[id], let source = order.firstIndex(of: id) else { return }
        let center = frame.midY + translation
        var target = source
        for (index, item) in order.enumerated() where item != id {
            guard let other = frames[item] else { continue }
            if index > source && center > other.midY { target = max(target, index) }
            if index < source && center < other.midY { target = min(target, index) }
        }
        if target != destination {
            withAnimation(.easeOut(duration: 0.2)) { destination = target }
            Haptics.trigger(.selection)
        }
    }

    func offset(_ id: String, spacing: CGFloat) -> CGFloat {
        guard let active, let source = order.firstIndex(of: active),
              let index = order.firstIndex(of: id) else { return 0 }
        if id == active { return translation }
        let stride = (frames[active]?.height ?? 0) + spacing
        if destination > source && index > source && index <= destination { return -stride }
        if destination < source && index < source && index >= destination { return stride }
        return 0
    }

    func finish(_ commit: ([String], String) -> Void) {
        guard let active, let source = order.firstIndex(of: active) else { return }
        var next = order
        next.remove(at: source)
        next.insert(active, at: destination)
        withAnimation(.easeOut(duration: 0.2)) {
            self.active = nil
            translation = 0
            if next != order { commit(next, active) }
        }
    }

    func cancel() { active = nil; translation = 0 }
}

struct CardReorderPlacement: ViewModifier {
    @ObservedObject var reorder: CardReorder
    let id: String
    let spacing: CGFloat
    func body(content: Content) -> some View {
        content
            .background(GeometryReader { proxy in
                Color.clear.onAppear { if reorder.active == nil { reorder.frames[id] = proxy.frame(in: .global) } }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in
                        if reorder.active == nil { reorder.frames[id] = frame }
                    }
            })
            .offset(y: reorder.offset(id, spacing: spacing))
            .zIndex(reorder.active == id ? 100 : 0)
    }
}

struct CardReorderHandle: View {
    @ObservedObject var reorder: CardReorder
    let id: String
    let order: [String]
    let name: String
    let height: CGFloat
    let commit: ([String], String) -> Void
    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<3) { _ in
                HStack(spacing: 4) {
                    Circle().frame(width: 4, height: 4)
                    Circle().frame(width: 4, height: 4)
                }
            }
        }
        .foregroundStyle(Theme.primary)
        .frame(width: 44, height: height)
        .contentShape(Rectangle())
        .highPriorityGesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { reorder.update(id: id, order: order, translation: $0.translation.height) }
            .onEnded { _ in reorder.finish(commit) })
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Reorder \(name)")
        .accessibilityAdjustableAction { direction in
            guard let index = order.firstIndex(of: id) else { return }
            let target = index + (direction == .increment ? 1 : -1)
            guard order.indices.contains(target) else { return }
            var next = order
            next.swapAt(index, target)
            commit(next, id)
        }
    }
}
