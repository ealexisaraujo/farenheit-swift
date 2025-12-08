//
//  AlexisExtensionFarenheitLiveActivity.swift
//  AlexisExtensionFarenheit
//
//  Created by Alexis Araujo (CS) on 05/12/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct AlexisExtensionFarenheitAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct AlexisExtensionFarenheitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlexisExtensionFarenheitAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension AlexisExtensionFarenheitAttributes {
    fileprivate static var preview: AlexisExtensionFarenheitAttributes {
        AlexisExtensionFarenheitAttributes(name: "World")
    }
}

extension AlexisExtensionFarenheitAttributes.ContentState {
    fileprivate static var smiley: AlexisExtensionFarenheitAttributes.ContentState {
        AlexisExtensionFarenheitAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: AlexisExtensionFarenheitAttributes.ContentState {
         AlexisExtensionFarenheitAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: AlexisExtensionFarenheitAttributes.preview) {
   AlexisExtensionFarenheitLiveActivity()
} contentStates: {
    AlexisExtensionFarenheitAttributes.ContentState.smiley
    AlexisExtensionFarenheitAttributes.ContentState.starEyes
}
