import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Более крупное окно по умолчанию, по центру экрана.
    let defaultSize = NSSize(width: 1280, height: 860)
    if let screen = self.screen ?? NSScreen.main {
      let visible = screen.visibleFrame
      let width = min(defaultSize.width, visible.width)
      let height = min(defaultSize.height, visible.height)
      let x = visible.origin.x + (visible.width - width) / 2
      let y = visible.origin.y + (visible.height - height) / 2
      self.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    } else {
      self.setFrame(NSRect(origin: self.frame.origin, size: defaultSize), display: true)
    }
    self.minSize = NSSize(width: 960, height: 640)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
