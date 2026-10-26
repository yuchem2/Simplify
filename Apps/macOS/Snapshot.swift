#if DEBUG
import AppKit
import SwiftUI

/// Debug-only: renders the main window to PNGs and quits, for checking the layout without
/// screen-recording access. Run with `open --env SIMPLIFY_SNAPSHOT=1 Simplify.app`; files land in
/// `~/Library/Containers/dev.yoom.simplify/Data/tmp/snapshot-{light,dark}.png`.
@MainActor
enum Snapshot {
    static func runIfRequested(model: AppModel) {
        guard ProcessInfo.processInfo.environment["SIMPLIFY_SNAPSHOT"] != nil else { return }
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                let renderer = ImageRenderer(content: MainView(model: model)
                    .frame(width: 1260, height: 800)
                    .environment(\.colorScheme, name == "dark" ? .dark : .light))
                renderer.scale = 2
                guard let image = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
                try? png.write(to: FileManager.default.temporaryDirectory.appending(path: "snapshot-\(name).png"))
            }
        }
        NSApp.terminate(nil)
    }
}
#endif
