import SwiftUI

// MARK: - Coordinate Space

enum HomeWalkthroughCoordinateSpace {
    static let name = "homeWalkthroughCoordinateSpace"
}

// MARK: - Targets

enum HomeWalkthroughTarget: Hashable {
    case todaySnapshot
    case quickActions
    case myCities
    case tools
}

// MARK: - Preference Key

struct HomeWalkthroughFramePreferenceKey: PreferenceKey {
    static var defaultValue: [HomeWalkthroughTarget: CGRect] = [:]

    static func reduce(value: inout [HomeWalkthroughTarget: CGRect], nextValue: () -> [HomeWalkthroughTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - Target Modifier

private struct HomeWalkthroughTargetModifier: ViewModifier {
    let target: HomeWalkthroughTarget

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HomeWalkthroughFramePreferenceKey.self,
                    value: [target: proxy.frame(in: .named(HomeWalkthroughCoordinateSpace.name))]
                )
            }
        )
    }
}

extension View {
    func homeWalkthroughTarget(_ target: HomeWalkthroughTarget) -> some View {
        modifier(HomeWalkthroughTargetModifier(target: target))
    }
}
