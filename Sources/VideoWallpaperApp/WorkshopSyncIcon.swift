import SwiftUI

/// Keeps refresh and completion feedback in the sidebar button's icon slot.
struct WorkshopSyncIcon: View {
    let syncing: Bool
    let completed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation = 0.0
    @State private var checkProgress: CGFloat = 0

    var body: some View {
        ZStack {
            if completed {
                SyncCheckmark().trim(from: 0, to: checkProgress)
                    .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .padding(3)
                    .transition(.opacity)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .rotationEffect(.degrees(rotation))
                    .transition(.opacity)
            }
        }
        .frame(width: 18, height: 18)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: completed)
        .accessibilityHidden(true)
        .task(id: syncing && !reduceMotion) {
            rotation = 0
            if syncing && !reduceMotion {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { rotation = 360 }
            }
        }
        .task(id: completed) {
            checkProgress = 0
            if completed {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { checkProgress = 1 }
            }
        }
    }
}

private struct SyncCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.85))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.15))
        }
    }
}
