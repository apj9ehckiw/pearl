import SwiftUI

enum PearlTheme {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.43, green: 0.75, blue: 1.0, alpha: 1)
            : UIColor(red: 0.16, green: 0.54, blue: 0.88, alpha: 1)
    })
    static let highlight = Color(red: 0.72, green: 0.85, blue: 1.0)
}
