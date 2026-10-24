import CoreGraphics

/// One-dimensional splitting shared by every layout.
enum AxisSplitter {
    /// Splits `length` into `weights.count` segments separated by `gap`, proportional
    /// to `weights`, while giving each segment at least its minimum.
    /// Returns nil when the minimums cannot fit.
    static func split(length: CGFloat, gap: CGFloat, weights: [Double], minimums: [CGFloat]) -> [CGFloat]? {
        let count = weights.count
        guard count > 0, minimums.count == count, length.isFinite else { return nil }
        let available = length - gap * CGFloat(count - 1)
        guard available > 0, minimums.reduce(0, +) <= available + 0.001 else { return nil }

        var fixed = [Bool](repeating: false, count: count)
        var sizes = [CGFloat](repeating: 0, count: count)
        // Each pass pins at least one more segment at its minimum, so `count` passes suffice.
        for _ in 0...count {
            let freeWeight = (0..<count).filter { !fixed[$0] }.reduce(0.0) { $0 + max(weights[$1], 0.0001) }
            let fixedTotal = (0..<count).filter { fixed[$0] }.reduce(0) { $0 + sizes[$1] }
            let remaining = available - fixedTotal
            var pinnedAny = false
            for index in 0..<count where !fixed[index] {
                let share = remaining * CGFloat(max(weights[index], 0.0001) / freeWeight)
                if share < minimums[index] {
                    sizes[index] = minimums[index]
                    fixed[index] = true
                    pinnedAny = true
                } else {
                    sizes[index] = share
                }
            }
            if !pinnedAny { break }
        }
        return sizes
    }

    /// Cuts `length` into consecutive spans starting at `origin`.
    static func spans(origin: CGFloat, sizes: [CGFloat], gap: CGFloat) -> [(start: CGFloat, length: CGFloat)] {
        var cursor = origin
        return sizes.map { size in
            defer { cursor += size + gap }
            return (cursor, size)
        }
    }
}
