import AppKit

enum WindowManager {
    enum Snap {
        case leftHalf, rightHalf, topHalf, bottomHalf
        case topLeft, topRight, bottomLeft, bottomRight
        case maximize, center
    }

    static func snap(_ snap: Snap) -> Bool {
        guard Accessibility.trusted else {
            Accessibility.requestPrompt()
            return false
        }
        guard let screen = NSScreen.main else { return false }
        let visible = screen.visibleFrame
        // Convert AppKit bottom-left coords to AX top-left style via screen frame
        let full = screen.frame
        let axVisible = CGRect(
            x: visible.origin.x,
            y: full.maxY - visible.maxY,
            width: visible.width,
            height: visible.height
        )

        let halfW = axVisible.width / 2
        let halfH = axVisible.height / 2
        let frame: CGRect
        switch snap {
        case .leftHalf:
            frame = CGRect(x: axVisible.minX, y: axVisible.minY, width: halfW, height: axVisible.height)
        case .rightHalf:
            frame = CGRect(x: axVisible.minX + halfW, y: axVisible.minY, width: halfW, height: axVisible.height)
        case .topHalf:
            frame = CGRect(x: axVisible.minX, y: axVisible.minY, width: axVisible.width, height: halfH)
        case .bottomHalf:
            frame = CGRect(x: axVisible.minX, y: axVisible.minY + halfH, width: axVisible.width, height: halfH)
        case .topLeft:
            frame = CGRect(x: axVisible.minX, y: axVisible.minY, width: halfW, height: halfH)
        case .topRight:
            frame = CGRect(x: axVisible.minX + halfW, y: axVisible.minY, width: halfW, height: halfH)
        case .bottomLeft:
            frame = CGRect(x: axVisible.minX, y: axVisible.minY + halfH, width: halfW, height: halfH)
        case .bottomRight:
            frame = CGRect(x: axVisible.minX + halfW, y: axVisible.minY + halfH, width: halfW, height: halfH)
        case .maximize:
            frame = axVisible
        case .center:
            let w = axVisible.width * 0.7
            let h = axVisible.height * 0.75
            frame = CGRect(
                x: axVisible.minX + (axVisible.width - w) / 2,
                y: axVisible.minY + (axVisible.height - h) / 2,
                width: w,
                height: h
            )
        }
        return Accessibility.setFrontWindowFrame(frame)
    }
}
