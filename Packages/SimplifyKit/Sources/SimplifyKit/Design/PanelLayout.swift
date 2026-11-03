import CoreGraphics

/// How the window shares its width between the calendar and the day panel. The panel is folded
/// away, beside the full calendar (normal), or wide beside a small month (`MiniMonth`); the spine
/// between them can be dragged, and dragging past the calendar's narrowest folds it into the small
/// month, the way a Finder sidebar folds.
public enum PanelLayout {
    /// The narrowest normal panel.
    public static let normalMin: CGFloat = 300
    /// The normal panel's own width until it is dragged: about a third of the window, up to this.
    public static let normalDefaultMax: CGFloat = 460
    /// The small month's column beside a wide panel; it starts at the narrowest.
    public static let miniRange: ClosedRange<CGFloat> = 248...360
    /// How far past the midpoint between the calendar's narrowest and the small month's widest the
    /// spine has to go before the calendar folds or unfolds, so it never flickers at the edge.
    public static let hysteresis: CGFloat = 24

    /// The window and the calendar's narrowest (seven of the smallest day cells and the sheet's padding).
    public struct Space: Equatable, Sendable {
        public var window: CGFloat
        public var calendarMin: CGFloat
        public var spine: CGFloat

        public init(window: CGFloat, calendarMin: CGFloat, spine: CGFloat) {
            self.window = window
            self.calendarMin = calendarMin
            self.spine = spine
        }

        /// The widest normal panel: the calendar keeps its narrowest. Never below the narrowest panel.
        public var normalMax: CGFloat { max(normalMin, window - spine - calendarMin) }

        /// A normal panel's width as first shown, or after a double-click on the spine.
        public var normalDefault: CGFloat {
            min(max(window * 0.32, normalMin), normalDefaultMax, normalMax)
        }
    }

    /// Where the spine is after a drag, from its place in the window (the calendar's width).
    public enum Place: Equatable, Sendable {
        /// The panel beside the full calendar, this wide.
        case normal(panel: CGFloat)
        /// The panel wide beside the small month, whose column is this wide.
        case wide(mini: CGFloat)
    }

    /// The normal panel's width: the one dragged to (nil until then), kept inside what the window allows.
    public static func normalWidth(_ chosen: CGFloat?, in space: Space) -> CGFloat {
        min(max(chosen ?? space.normalDefault, normalMin), space.normalMax)
    }

    /// The small month's column, kept inside its range.
    public static func miniWidth(_ chosen: CGFloat?) -> CGFloat {
        min(max(chosen ?? miniRange.lowerBound, miniRange.lowerBound), miniRange.upperBound)
    }

    /// The spine dragged to `x` (the calendar side's width) while the panel was wide or not.
    public static func drag(to x: CGFloat, isWide: Bool, in space: Space) -> Place {
        let middle = (space.calendarMin + miniRange.upperBound) / 2
        let wide = isWide ? x < middle + hysteresis : x < middle - hysteresis
        if wide { return .wide(mini: miniWidth(x)) }
        return .normal(panel: normalWidth(space.window - space.spine - x, in: space))
    }
}
