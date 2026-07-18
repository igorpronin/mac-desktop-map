import SwiftUI

// Окно «Desktops settings»: все имена десктопов сразу.
// Строки за пределами существующих десктопов — «имена на будущее»:
// десктоп, созданный с таким номером, получит это имя автоматически.
struct DesktopsSettingsView: View {
    @ObservedObject var monitor: SpaceMonitor
    @ObservedObject var l10n = L10n.shared
    @State private var extraRows = 0

    private var rowCount: Int {
        let maxPending = monitor.pendingNames.keys.compactMap(Int.init).max() ?? 0
        return max(max(monitor.desktops.count, maxPending), 1) + extraRows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(1...rowCount, id: \.self) { index in
                        row(index: index)
                    }
                }
            }

            Button(l10n.t(.add)) { extraRows += 1 }
        }
        .padding(16)
        .frame(width: 320, height: 400)
    }

    @ViewBuilder
    private func row(index: Int) -> some View {
        HStack(spacing: 8) {
            Text(String(index))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(index == monitor.current.number ? Color.accentColor : Color.secondary)
                .frame(width: 26, alignment: .trailing)
            TextField(l10n.t(.desktop), text: binding(for: index))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        if index <= monitor.desktops.count {
            // Существующий десктоп: имя привязано к его uuid.
            let uuid = monitor.desktops[index - 1].uuid
            return Binding(
                get: { monitor.names[uuid] ?? "" },
                set: { monitor.setName($0, forUUID: uuid) }
            )
        }
        // Ещё не созданный десктоп: имя ждёт его появления под этим номером.
        return Binding(
            get: { monitor.pendingNames[String(index)] ?? "" },
            set: { monitor.setPendingName($0, forIndex: index) }
        )
    }
}

// Окно «UI settings»: внешний вид окошка — непрозрачность и контраст.
struct UISettingsView: View {
    @ObservedObject var monitor: SpaceMonitor
    @ObservedObject var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(l10n.t(.opacity))
                Slider(value: $monitor.opacity, in: 0...1)
            }
            Toggle(l10n.t(.contrast), isOn: $monitor.contrast)
        }
        .padding(16)
        .frame(width: 320)
    }
}
