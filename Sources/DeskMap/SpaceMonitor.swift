import AppKit
import Combine

// Публичного API для Spaces в macOS нет — используем приватный SkyLight
// (те же вызовы, что у WhichSpace и yabai). Символы берём через dlsym,
// чтобы не зависеть от линковки приватного фреймворка.
private typealias MainConnectionFn = @convention(c) () -> UInt32
private typealias CopySpacesFn = @convention(c) (UInt32) -> Unmanaged<CFArray>?

private struct SkyLightAPI {
    let connection: UInt32
    let copySpaces: CopySpacesFn

    init?() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW
        ) else { return nil }
        guard let mainSym = dlsym(handle, "SLSMainConnectionID"),
              let copySym = dlsym(handle, "SLSCopyManagedDisplaySpaces")
        else { return nil }
        connection = unsafeBitCast(mainSym, to: MainConnectionFn.self)()
        copySpaces = unsafeBitCast(copySym, to: CopySpacesFn.self)
    }

    // Массив словарей по дисплеям: "Display Identifier", "Current Space", "Spaces".
    func managedDisplaySpaces() -> [[String: Any]] {
        copySpaces(connection)?.takeRetainedValue() as? [[String: Any]] ?? []
    }
}

struct SpaceInfo: Equatable {
    var number: Int?       // порядковый номер среди обычных десктопов (сквозной по дисплеям)
    var uuid: String?      // uuid текущего Space — ключ для пользовательского имени
    var isFullscreen: Bool // текущий Space — полноэкранное приложение, не десктоп
}

struct DesktopEntry: Identifiable, Equatable {
    let index: Int     // номер в стиле Mission Control
    let uuid: String
    var id: Int { index }
}

@MainActor
final class SpaceMonitor: ObservableObject {
    @Published private(set) var current = SpaceInfo(number: nil, uuid: nil, isFullscreen: false)
    @Published private(set) var desktops: [DesktopEntry] = []
    @Published var editing = false

    // Для стрелочного переключения (Ctrl+←/→ идёт по всем Spaces, включая
    // полноэкранные): позиция текущего Space в списке Spaces своего дисплея
    // и позиции всех десктопов этого дисплея по их номерам.
    @Published private(set) var currentPosition: Int?
    @Published private(set) var desktopPositions: [Int: Int] = [:]

    // Имена привязаны к стабильному uuid десктопа — переживают перестановку в Mission Control.
    @Published private(set) var names: [String: String] {
        didSet { UserDefaults.standard.set(names, forKey: "SpaceNames") }
    }

    // Имена «на будущее», ключ — номер ещё не существующего десктопа.
    // Как только десктоп с таким номером появляется, имя переезжает на его uuid.
    @Published private(set) var pendingNames: [String: String] {
        didSet { UserDefaults.standard.set(pendingNames, forKey: "PendingNames") }
    }

    // MARK: - Настройки вида (всё переживает перезапуск)

    @Published var compact: Bool {
        didSet { UserDefaults.standard.set(compact, forKey: "CompactMode") }
    }

    @Published var indexOnly: Bool {
        didSet { UserDefaults.standard.set(indexOnly, forKey: "IndexOnly") }
    }

    @Published var alignRight: Bool {
        didSet { UserDefaults.standard.set(alignRight, forKey: "AlignRight") }
    }

    // 0 — полностью прозрачный фон, 1 — полностью чёрный (в режиме Contrast — белый).
    @Published var opacity: Double {
        didSet { UserDefaults.standard.set(opacity, forKey: "PanelOpacity") }
    }

    // Contrast: обратная гамма — фон от прозрачного к белому, шрифт в противофазе.
    @Published var contrast: Bool {
        didSet { UserDefaults.standard.set(contrast, forKey: "ContrastMode") }
    }

    // Окошко висит на всех Spaces, но физически стоит на одном дисплее —
    // номер показываем для того дисплея, где оно сейчас находится.
    var screenProvider: () -> NSScreen? = { NSScreen.main }

    private let api = SkyLightAPI()
    private var timer: Timer?

    init() {
        let ud = UserDefaults.standard
        names = ud.dictionary(forKey: "SpaceNames") as? [String: String] ?? [:]
        pendingNames = ud.dictionary(forKey: "PendingNames") as? [String: String] ?? [:]
        compact = ud.bool(forKey: "CompactMode")
        indexOnly = ud.bool(forKey: "IndexOnly")
        alignRight = ud.bool(forKey: "AlignRight")
        opacity = ud.object(forKey: "PanelOpacity") as? Double ?? 0.35
        contrast = ud.bool(forKey: "ContrastMode")
    }

    var currentName: String? {
        current.uuid.flatMap { names[$0] }
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.spaceDidChange() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Создание/удаление/перестановка десктопов в Mission Control не шлёт
        // уведомлений — ловим редким опросом (вызов дешёвый).
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    private func spaceDidChange() {
        if editing { editing = false }
        refresh()
    }

    func refresh() {
        let displays = api?.managedDisplaySpaces() ?? []
        guard !displays.isEmpty else { return }

        let targetUUID = screenProvider().flatMap(Self.displayUUID)
        var counter = 0
        var allDesktops: [DesktopEntry] = []
        var perDisplay: [(identifier: String?, info: SpaceInfo, positions: [Int: Int], currentPos: Int?)] = []

        for display in displays {
            guard let currentDict = display["Current Space"] as? [String: Any],
                  let spaces = display["Spaces"] as? [[String: Any]]
            else { continue }
            let currentID = (currentDict["ManagedSpaceID"] as? NSNumber)?.int64Value
            var info = SpaceInfo(
                number: nil,
                uuid: currentDict["uuid"] as? String,
                isFullscreen: false
            )
            var positions: [Int: Int] = [:]
            var currentPos: Int?
            for (position, space) in spaces.enumerated() {
                let type = (space["type"] as? NSNumber)?.intValue ?? 0
                let isUserSpace = type == 0
                if isUserSpace {
                    counter += 1
                    positions[counter] = position
                    if let uuid = space["uuid"] as? String, !uuid.isEmpty {
                        allDesktops.append(DesktopEntry(index: counter, uuid: uuid))
                    }
                }
                if let id = (space["ManagedSpaceID"] as? NSNumber)?.int64Value, id == currentID {
                    currentPos = position
                    if isUserSpace {
                        info.number = counter
                    } else {
                        info.isFullscreen = true
                    }
                }
            }
            perDisplay.append((display["Display Identifier"] as? String, info, positions, currentPos))
        }

        guard !perDisplay.isEmpty else { return }
        adoptPendingNames(for: allDesktops)
        if allDesktops != desktops {
            desktops = allDesktops
        }
        let picked = perDisplay.first { $0.identifier != nil && $0.identifier == targetUUID }
            ?? perDisplay[0]
        if picked.info != current {
            current = picked.info
        }
        if picked.positions != desktopPositions {
            desktopPositions = picked.positions
        }
        if picked.currentPos != currentPosition {
            currentPosition = picked.currentPos
        }
    }

    // Появился десктоп с номером, для которого заранее задано имя, —
    // приклеиваем имя к его uuid и убираем из отложенных.
    private func adoptPendingNames(for desktops: [DesktopEntry]) {
        guard !pendingNames.isEmpty else { return }
        for desktop in desktops {
            guard let name = pendingNames[String(desktop.index)],
                  names[desktop.uuid] == nil
            else { continue }
            names[desktop.uuid] = name
            pendingNames.removeValue(forKey: String(desktop.index))
        }
    }

    // MARK: - Имена десктопов

    func setName(_ raw: String, forUUID uuid: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            names.removeValue(forKey: uuid)
        } else {
            names[uuid] = name
        }
    }

    func setPendingName(_ raw: String, forIndex index: Int) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            pendingNames.removeValue(forKey: String(index))
        } else {
            pendingNames[String(index)] = name
        }
    }

    func beginEditing() {
        guard current.uuid != nil, !current.isFullscreen else { return }
        editing = true
    }

    func commitEditing(_ draft: String) {
        if let uuid = current.uuid, !uuid.isEmpty {
            setName(draft, forUUID: uuid)
        }
        editing = false
    }

    func cancelEditing() {
        editing = false
    }

    // Только для оффскрин-рендера скриншотов README (scripts/make-screenshots.sh):
    // подставляет фейковое состояние, реальные данные не участвуют.
    func setScreenshotState(number: Int, name: String?) {
        current = SpaceInfo(number: number, uuid: "SCREENSHOT", isFullscreen: false)
        if let name {
            names["SCREENSHOT"] = name
        } else {
            names.removeValue(forKey: "SCREENSHOT")
        }
    }

    // MARK: - Дисплеи

    private static func displayUUID(_ screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? CGDirectDisplayID else { return nil }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
