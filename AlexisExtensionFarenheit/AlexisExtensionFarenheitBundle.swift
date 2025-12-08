//
//  AlexisExtensionFarenheitBundle.swift
//  Temperature Converter Widget Bundle
//
//  Created by Alexis Araujo (CS) on 05/12/25.
//

import WidgetKit
import SwiftUI

/// Main entry point for the widget extension
@main
struct AlexisExtensionFarenheitBundle: WidgetBundle {
    var body: some Widget {
        // Temperature converter widget (small, medium, large sizes)
        AlexisExtensionFarenheit()
    }
}
