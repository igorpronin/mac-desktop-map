import AppKit
import ApplicationServices

// Переключение десктопов. Публичного API нет; надёжный путь — синтетические
// нажатия системных шорткатов Mission Control (нужно разрешение Accessibility).
// Если в Системных настройках включён шорткат «Switch to Desktop N» — жмём его,
// иначе доходим до цели стрелками Ctrl+←/→ (они включены по умолчанию).
enum SpaceSwitcher {
    @MainActor
    static func switchTo(index: Int, monitor: SpaceMonitor) {
        guard index != monitor.current.number else { return }
        NSLog("SpaceSwitcher: go to %d, trusted=%d", index, AXIsProcessTrusted() ? 1 : 0)
        guard AXIsProcessTrusted() else {
            // Системный диалог сам ведёт пользователя в Настройки → Accessibility.
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            return
        }
        if let combo = directHotkey(for: index) {
            NSLog("SpaceSwitcher: direct hotkey key=%d flags=0x%llx", combo.keyCode, combo.flags.rawValue)
            post(keyCode: combo.keyCode, flags: combo.flags)
            return
        }
        // Стрелки ходят по всем Spaces подряд, включая полноэкранные, —
        // шагаем по позициям в списке Spaces, а не по номерам десктопов.
        guard let from = monitor.currentPosition,
              let to = monitor.desktopPositions[index],
              from != to
        else { return }
        stepwise(from: from, to: to)
    }

    // «Switch to Desktop N»: symbolic hotkey id 118 соответствует десктопу 1.
    private static func directHotkey(for index: Int) -> (keyCode: CGKeyCode, flags: CGEventFlags)? {
        guard index <= 16 else { return nil }
        guard let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
                .dictionary(forKey: "AppleSymbolicHotKeys"),
              let entry = hotkeys[String(117 + index)] as? [String: Any],
              (entry["enabled"] as? NSNumber)?.boolValue == true,
              let value = entry["value"] as? [String: Any],
              let params = value["parameters"] as? [NSNumber],
              params.count >= 3
        else { return nil }
        let keyCode = params[1].uint16Value
        guard keyCode != 0xFFFF else { return nil }
        let mods = params[2].uintValue
        var flags = CGEventFlags()
        if mods & NSEvent.ModifierFlags.shift.rawValue != 0 { flags.insert(.maskShift) }
        if mods & NSEvent.ModifierFlags.control.rawValue != 0 { flags.insert(.maskControl) }
        if mods & NSEvent.ModifierFlags.option.rawValue != 0 { flags.insert(.maskAlternate) }
        if mods & NSEvent.ModifierFlags.command.rawValue != 0 { flags.insert(.maskCommand) }
        if mods & NSEvent.ModifierFlags.function.rawValue != 0 { flags.insert(.maskSecondaryFn) }
        if mods & NSEvent.ModifierFlags.numericPad.rawValue != 0 { flags.insert(.maskNumericPad) }
        return (CGKeyCode(keyCode), flags)
    }

    private static func stepwise(from: Int, to: Int) {
        let keyCode: CGKeyCode = to > from ? 124 : 123 // → : ←
        let steps = abs(to - from)
        // Железные стрелки несут флаги Fn и NumPad, и шорткат Mission Control
        // записан с Fn (0x840000) — без этих флагов система комбо не узнаёт.
        let flags: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
        NSLog("SpaceSwitcher: stepwise %d -> %d (%d steps)", from, to, steps)
        Task.detached {
            for _ in 0..<steps {
                post(keyCode: keyCode, flags: flags)
                // Пауза, чтобы система успевала начать анимацию каждого шага.
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    private static let modifierKeys: [(flag: CGEventFlags, key: CGKeyCode)] = [
        (.maskControl, 59), (.maskShift, 56), (.maskAlternate, 58), (.maskCommand, 55),
    ]

    // Mission Control не реагирует на синтетическую клавишу с выставленными
    // флагами: модификаторы надо «нажимать» и «отпускать» отдельными
    // flagsChanged-событиями до и после самой клавиши.
    private static func post(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)

        func send(_ key: CGKeyCode, down: Bool, flags: CGEventFlags, isModifier: Bool) {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            if isModifier {
                event?.type = .flagsChanged
            }
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
            usleep(8000)
        }

        // Модификаторные КЛАВИШИ (ctrl/shift/opt/cmd) нажимаются отдельными
        // flagsChanged-событиями; флаги Fn/NumPad клавишей не являются —
        // они просто выставлены на самом событии стрелки, как у железа.
        let mods = modifierKeys.filter { flags.contains($0.flag) }
        var held = CGEventFlags()
        for (flag, key) in mods {
            held.insert(flag)
            send(key, down: true, flags: held, isModifier: true)
        }
        send(keyCode, down: true, flags: flags, isModifier: false)
        send(keyCode, down: false, flags: flags, isModifier: false)
        for (flag, key) in mods.reversed() {
            held.remove(flag)
            send(key, down: false, flags: held, isModifier: true)
        }
    }
}
