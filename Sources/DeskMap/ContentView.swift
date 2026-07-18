import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var monitor: SpaceMonitor
    @ObservedObject var l10n = L10n.shared
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        content
            .shadow(color: haloColor, radius: 1)
            .padding(.horizontal, monitor.compact ? 6 : 8)
            .padding(.vertical, monitor.compact ? 3 : 5)
            .background(
                Color(white: monitor.contrast ? 1 : 0).opacity(monitor.opacity),
                in: RoundedRectangle(cornerRadius: monitor.compact ? 7 : 9, style: .continuous)
            )
            .contextMenu {
                Button(l10n.t(.renameDesktop)) { monitor.beginEditing() }
                    .disabled(monitor.current.isFullscreen)
                Divider()
                Button(l10n.t(.desktopsSettings)) {
                    (NSApp.delegate as? AppDelegate)?.openDesktopsSettings()
                }
                Button(l10n.t(.uiSettings)) {
                    (NSApp.delegate as? AppDelegate)?.openUISettings()
                }
                Toggle(l10n.t(.compactWindow), isOn: Binding(
                    get: { monitor.compact },
                    set: { monitor.compact = $0 }
                ))
                Toggle(l10n.t(.indexOnly), isOn: Binding(
                    get: { monitor.indexOnly },
                    set: { monitor.indexOnly = $0 }
                ))
                Menu(l10n.t(.alignMenu)) {
                    Toggle(l10n.t(.alignLeft), isOn: Binding(
                        get: { !monitor.alignRight },
                        set: { _ in monitor.alignRight = false }
                    ))
                    Toggle(l10n.t(.alignRight), isOn: Binding(
                        get: { monitor.alignRight },
                        set: { _ in monitor.alignRight = true }
                    ))
                }
                Toggle(l10n.t(.alwaysOnTop), isOn: Binding(
                    get: { (NSApp.delegate as? AppDelegate)?.isPanelOnTop ?? true },
                    set: { (NSApp.delegate as? AppDelegate)?.setPanelOnTop($0) }
                ))
                Button(l10n.t(.hideWindow)) {
                    (NSApp.delegate as? AppDelegate)?.setPanelVisible(false)
                }
                Button(l10n.t(.about)) {
                    (NSApp.delegate as? AppDelegate)?.showAbout()
                }
                Divider()
                Button(l10n.t(.quit)) { NSApp.terminate(nil) }
            }
    }

    // MARK: - Цвета под прозрачность
    // Один бегунок: фон — чёрный (в Contrast — белый) с альфой 0..1, текст
    // подстраивается, чтобы был виден: на плотном фоне — противоположный фону,
    // на прозрачном — наоборот, всегда с обратной по тону обводкой.

    private var textWhite: Double {
        let ramp = min(1, monitor.opacity / 0.35)
        return monitor.contrast ? 1 - ramp : ramp
    }

    private var textColor: Color {
        Color(white: textWhite)
    }

    private var haloColor: Color {
        Color(white: 1 - textWhite).opacity(0.7)
    }

    // MARK: - Содержимое

    private var nameFont: Font {
        .system(size: monitor.compact ? 9 : 11, weight: .semibold)
    }

    // Показывается ли что-то, кроме номера (имя или поле ввода).
    private var showsTitle: Bool {
        monitor.editing || !monitor.indexOnly
    }

    // При правом выравнивании номер переезжает на правую сторону от заголовка.
    @ViewBuilder
    private var content: some View {
        HStack(spacing: monitor.compact ? 3 : 6) {
            if !monitor.alignRight {
                numberView
                if monitor.compact, showsTitle { compactSeparator }
            }
            if monitor.editing {
                editorField
            } else if !monitor.indexOnly {
                if let name = monitor.currentName {
                    titleText(clipped(name), dimmed: false)
                } else {
                    // Плейсхолдер-подсказка: тут появится имя, если кликнуть.
                    titleText(clipped(placeholderTitle), dimmed: true)
                }
            }
            if monitor.alignRight {
                if monitor.compact, showsTitle { compactSeparator }
                numberView
            }
        }
    }

    // Клик по номеру — меню перехода к десктопу (клик по остальному — переименование).
    private var numberView: some View {
        Group {
            if monitor.compact {
                Text(numberText)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(textColor)
            } else {
                numberBadge
            }
        }
        .onTapGesture {
            (NSApp.delegate as? AppDelegate)?.showGoToMenu()
        }
    }

    private var compactSeparator: some View {
        Text("|")
            .font(.system(size: 9, weight: .regular))
            .foregroundStyle(textColor.opacity(0.4))
    }

    private func titleText(_ text: String, dimmed: Bool) -> some View {
        Text(text)
            .font(nameFont)
            .foregroundStyle(textColor.opacity(dimmed ? 0.45 : 1))
    }

    private var editorField: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .font(nameFont)
            .foregroundStyle(textColor)
            .frame(width: monitor.compact ? 90 : 110)
            .focused($fieldFocused)
            .onSubmit { monitor.commitEditing(draft) }
            .onExitCommand { monitor.cancelEditing() }
            .onAppear {
                draft = monitor.currentName ?? ""
                fieldFocused = true
            }
    }

    private var numberBadge: some View {
        Text(numberText)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(textColor)
            .frame(minWidth: 14)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(textColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var numberText: String {
        if monitor.current.isFullscreen { return "⛶" }
        return monitor.current.number.map(String.init) ?? "…"
    }

    private var placeholderTitle: String {
        monitor.current.isFullscreen ? l10n.t(.fullscreen) : l10n.t(.desktop)
    }

    /// В компактном режиме имя подрезается до 15 символов, включая многоточие.
    /// Пробелы на месте разреза убираются — «Very Long ...» вместо «Very Long  ...».
    private func clipped(_ name: String) -> String {
        guard monitor.compact, name.count > 15 else { return name }
        var head = String(name.prefix(12))
        while let last = head.last, last.isWhitespace {
            head.removeLast()
        }
        return head + "..."
    }
}
