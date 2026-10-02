import AppKit
import ApplicationServices
import Carbon.HIToolbox

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            let app = AppDelegate()
            precondition(app.isTriggerHeld(flags: CGEventFlags(rawValue: 0x80040)))
            precondition(!app.isTriggerHeld(flags: CGEventFlags(rawValue: 0x80020)))
            precondition(!app.isTriggerHeld(flags: CGEventFlags(rawValue: 0)))
            precondition(Self.normalizedRect(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 100, y: 50)) == CGRect(x: 100, y: 50, width: 100, height: 150))
            print("PASS: right Option, left Option exclusion, released key, reverse drag")
            return
        }
        let application = NSApplication.shared
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.jerry.SilentShot")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            existing.activate(options: [.activateIgnoringOtherApps])
            return
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var triggerPressed = false
    private var dragStart: CGPoint?
    private var screenCapturePermitted = false
    private var lastAction = "启动中"
    private var lastMouseFlags: UInt64 = 0
    private var lastModifierKey: Int64 = -1
    private var interceptedDrags = 0
    private var successfulCaptures = 0

    // Device-side modifier bits from Apple's IOLLEvent.h.
    private func isTriggerHeld(flags: CGEventFlags) -> Bool {
        let sideMask: UInt64
        switch Int(triggerKeyCode) {
        case kVK_RightOption: sideMask = 0x40
        case kVK_Option: sideMask = 0x20
        case kVK_RightCommand: sideMask = 0x10
        case kVK_Command: sideMask = 0x08
        case kVK_RightControl: sideMask = 0x2000
        case kVK_Control: sideMask = 0x01
        case kVK_RightShift: sideMask = 0x04
        case kVK_Shift: sideMask = 0x02
        default: return false
        }
        return flags.rawValue & sideMask != 0
    }

    private func recordStatus(_ action: String) {
        lastAction = action
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let folder = directory.appendingPathComponent("com.jerry.SilentShot", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: [
                "pid": ProcessInfo.processInfo.processIdentifier,
                "accessibility": AXIsProcessTrusted(),
                "screenCapture": screenCapturePermitted,
                "eventTap": eventTap != nil,
                "eventTapEnabled": eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false,
                "lastAction": lastAction,
                "lastMouseFlags": String(lastMouseFlags, radix: 16),
                "lastModifierKey": lastModifierKey,
                "interceptedDrags": interceptedDrags,
                "successfulCaptures": successfulCaptures,
                "timestamp": Date().description
            ], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: folder.appendingPathComponent("status.json"), options: .atomic)
        } catch { NSLog("SilentShot status: %@", error.localizedDescription) }
    }

    private var triggerKeyCode: CGKeyCode {
        let configured = UserDefaults.standard.string(forKey: "TriggerKey") ?? "rightOption"
        return Self.supportedTriggerKeys[configured] ?? CGKeyCode(kVK_RightOption)
    }

    private static let supportedTriggerKeys: [String: CGKeyCode] = [
        "rightOption": CGKeyCode(kVK_RightOption),
        "leftOption": CGKeyCode(kVK_Option),
        "rightCommand": CGKeyCode(kVK_RightCommand),
        "leftCommand": CGKeyCode(kVK_Command),
        "rightControl": CGKeyCode(kVK_RightControl),
        "leftControl": CGKeyCode(kVK_Control),
        "rightShift": CGKeyCode(kVK_RightShift),
        "leftShift": CGKeyCode(kVK_Shift)
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent applications have no Dock icon, menu bar item, windows, or notifications.
        NSApp.setActivationPolicy(.accessory)
        if !UserDefaults.standard.bool(forKey: "HasShownSetup") {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "SilentShot 已启动"
            alert.informativeText = "请在系统设置 → 隐私与安全性中允许 SilentShot 的辅助功能和屏幕录制权限。授权后重新启动应用。\n\n使用：按住右 Option，鼠标左键拖动，先松开鼠标再松开 Option，随后按 Command-V 粘贴截图。\n\n应用在后台运行，没有窗口或菜单栏图标。可在活动监视器中退出 SilentShot。"
            alert.addButton(withTitle: "继续并申请权限")
            alert.runModal()
            UserDefaults.standard.set(true, forKey: "HasShownSetup")
        }
        requestSystemPermissions()
        screenCapturePermitted = CGPreflightScreenCaptureAccess()
        startEventTapWhenPermitted()
        recordStatus("已启动")
        if !AXIsProcessTrusted() || !screenCapturePermitted {
            DispatchQueue.main.async { [weak self] in self?.showStatus() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopEventTap()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showStatus()
        return false
    }

    private func showStatus() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "SilentShot 运行状态"
        alert.informativeText = "辅助功能：\(AXIsProcessTrusted() ? "已授权" : "未授权")\n屏幕录制：\(screenCapturePermitted ? "已授权" : "未授权")\n鼠标监听：\(eventTap != nil ? "已就绪" : "未就绪")\n已拦截拖动：\(interceptedDrags) 次\n已复制截图：\(successfulCaptures) 张\n最近状态：\(lastAction)\n\n如果设置中已经勾选，但这里仍未授权，请删除旧 SilentShot 条目，然后重新添加 /Applications/SilentShot.app 并授权，退出并重启应用。\n\n按住右 Option，左键拖动区域，松开鼠标后用 Command-V 粘贴。"
        alert.addButton(withTitle: "关闭")
        alert.addButton(withTitle: "退出应用")
        alert.addButton(withTitle: "辅助功能设置")
        alert.addButton(withTitle: "屏幕录制设置")
        let response = alert.runModal()
        if response == .alertSecondButtonReturn { NSApp.terminate(nil) }
        if response.rawValue == 1002 {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        if response.rawValue == 1003 {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    private func requestSystemPermissions() {
        let accessibilityOptions = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(accessibilityOptions)

        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
    }

    private func startEventTapWhenPermitted() {
        if AXIsProcessTrusted() { installEventTap() }
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.screenCapturePermitted = CGPreflightScreenCaptureAccess()
            if AXIsProcessTrusted() {
                self.installEventTap()
                if let tap = self.eventTap, !CGEvent.tapIsEnabled(tap: tap) {
                    self.dragStart = nil
                    CGEvent.tapEnable(tap: tap, enable: true)
                    self.recordStatus("监听已恢复")
                }
            }
            self.recordStatus(self.lastAction)
        }
    }

    private func installEventTap() {
        guard eventTap == nil else { return }

        let eventTypes: [CGEventType] = [
            .flagsChanged,
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp
        ]
        let mask = eventTypes.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << CGEventMask(type.rawValue))
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: userInfo
        ) else {
            recordStatus("鼠标监听创建失败")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        recordStatus("鼠标监听已就绪")
    }

    private func stopEventTap() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private static let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let app = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
        return app.handleEvent(type: type, event: event)
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            let changedKey = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            lastModifierKey = Int64(changedKey)
            if changedKey == triggerKeyCode {
                triggerPressed = isTriggerHeld(flags: event.flags)
                let pressed = triggerPressed
                DispatchQueue.main.async { [weak self] in
                    self?.recordStatus(pressed ? "检测到触发键按下" : "触发键已松开")
                }
            }
            return Unmanaged.passUnretained(event)

        case .leftMouseDown:
            lastMouseFlags = event.flags.rawValue
            let held = isTriggerHeld(flags: event.flags) || triggerPressed
            guard held, screenCapturePermitted else {
                DispatchQueue.main.async { [weak self] in
                    self?.recordStatus(held ? "触发键已识别，但屏幕录制权限未生效" : "鼠标按下时未检测到触发键")
                }
                return Unmanaged.passUnretained(event)
            }
            dragStart = event.location
            interceptedDrags += 1
            DispatchQueue.main.async { [weak self] in self?.recordStatus("开始拦截区域拖动") }
            return nil

        case .leftMouseDragged where dragStart != nil:
            return nil

        case .leftMouseUp:
            guard let start = dragStart else {
                return Unmanaged.passUnretained(event)
            }
            dragStart = nil
            let rect = Self.normalizedRect(from: start, to: event.location)
            if rect.width >= 2, rect.height >= 2 {
                DispatchQueue.main.async { [weak self] in
                    self?.captureToClipboard(rect: rect)
                }
            }
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private static func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ).integral
    }

    private func captureToClipboard(rect: CGRect) {
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            return
        }

        guard let cgImage = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            recordStatus("截图 API 未返回图片")
            return
        }

        let image = NSImage(cgImage: cgImage, size: rect.size)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.writeObjects([image]) {
            successfulCaptures += 1
            recordStatus("截图已复制到剪贴板")
        } else {
            recordStatus("写入剪贴板失败")
        }
    }
}
