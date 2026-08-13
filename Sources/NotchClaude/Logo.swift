import SwiftUI

/// Звёздочка Claude как в прототипе: четыре перекрещенные полоски шириной 2 pt —
/// длинные по вертикали и горизонтали, короткие по диагоналям.
struct ClaudeMark: View {
    var size: CGFloat = 14
    var color: Color = Theme.accent

    var body: some View {
        ZStack {
            spoke(length: size, angle: 0)
            spoke(length: size, angle: 90)
            spoke(length: size * 0.71, angle: 45)
            spoke(length: size * 0.71, angle: 135)
        }
        .frame(width: size, height: size)
    }

    private func spoke(length: CGFloat, angle: Double) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(width: 2, height: length)
            .rotationEffect(.degrees(angle))
    }
}
