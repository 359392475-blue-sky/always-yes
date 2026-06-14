import AppKit

final class FeedbackPresenter {
    private var toastWindow: NSWindow?
    private var closeWorkItem: DispatchWorkItem?

    func show(_ message: String, mode: FeedbackMode, statusItem: NSStatusItem?) {
        switch mode {
        case .off:
            return
        case .toast:
            showToast(message, statusItem: statusItem)
        case .alert:
            showAlert(message)
        }
    }

    private func showToast(_ message: String, statusItem: NSStatusItem?) {
        closeWorkItem?.cancel()
        toastWindow?.close()

        let width = min(max(messageWidth(message) + 36, 220), 460)
        let height: CGFloat = 44
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = true
        panel.hasShadow = true
        panel.alphaValue = 0

        let container = NSView(frame: frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 0.92).cgColor
        container.layer?.cornerRadius = 10

        let label = NSTextField(labelWithString: message)
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        panel.contentView = container
        panel.setFrameOrigin(toastOrigin(size: frame.size, statusItem: statusItem))
        panel.orderFrontRegardless()
        toastWindow = panel

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        let item = DispatchWorkItem { [weak self, weak panel] in
            guard let panel = panel else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.close()
                if self?.toastWindow === panel {
                    self?.toastWindow = nil
                }
            }
        }
        closeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: item)
    }

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Yes Engineer"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func toastOrigin(size: NSSize, statusItem: NSStatusItem?) -> NSPoint {
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let margin: CGFloat = 16
        let x = visible.maxX - size.width - margin
        let y = visible.maxY - size.height - margin
        return NSPoint(x: x, y: y)
    }

    private func messageWidth(_ message: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium)]
        return ceil((message as NSString).size(withAttributes: attrs).width)
    }
}
