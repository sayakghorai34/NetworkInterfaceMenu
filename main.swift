import Cocoa
import Security
import SystemConfiguration

struct NetService {
    let serviceName: String
    let hardwarePort: String
    let device: String
    let isActive: Bool
    let hasIPv4: Bool
    let hasIPv6: Bool
    let ipv4: String?
    let router: String?

    var hasUsableRouter: Bool {
        guard let router else { return false }
        let value = router.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !value.isEmpty && value != "none" && value != "(null)"
    }

    var isSelectable: Bool {
        hasIPv4 || hasIPv6
    }

    var iconName: String {
        let h = hardwarePort.lowercased()

        if h.contains("wi-fi") || h.contains("wifi") {
            return "wifi"
        }

        if h.contains("iphone") {
            return "iphone"
        }

        if h.contains("thunderbolt") {
            return "bolt.horizontal.circle"
        }

        if h.contains("ethernet") {
            return "cable.connector"
        }

        if h.contains("bridge") {
            return "point.3.connected.trianglepath.dotted"
        }

        return "network"
    }

    var friendlyName: String {
        "\(hardwarePort) (\(device))"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var store: SCDynamicStore?
    private var isSwitchInProgress = false
    private let switchQueue = DispatchQueue(label: "NetworkInterfaceMenu.switch", qos: .userInitiated)
    private let keychainService = "NetworkInterfaceMenu.AdminPassword"
    private let keychainAccount = NSUserName()

    private let preferredServiceOrder = [
        "Thunderbolt Bridge",
        "Wi-Fi",
        "iPhone USB"
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        setupNetworkWatcher()
        updateMenu()
    }

    private func runCommand(_ path: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private func shellQuote(_ text: String) -> String {
        return "'\(text.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private func currentDefaultInterface() -> String {
        guard let dict = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let iface = dict["PrimaryInterface"] as? String else {
            return "?"
        }

        return iface
    }

    private func currentDefaultGateway() -> String {
        guard let dict = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let router = dict["Router"] as? String else {
            return "Unknown"
        }

        return router
    }

    private func parseNumberedServiceName(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("("),
              let closeParen = trimmed.firstIndex(of: ")") else {
            return nil
        }

        let numberPart = trimmed[trimmed.index(after: trimmed.startIndex)..<closeParen]
        guard !numberPart.isEmpty,
              numberPart.allSatisfy({ $0.isNumber }) else {
            return nil
        }

        let service = trimmed[trimmed.index(after: closeParen)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return service.isEmpty ? nil : service
    }

    private func currentServiceOrder() -> [String] {
        let output = runCommand("/usr/sbin/networksetup", ["-listnetworkserviceorder"])
        var services: [String] = []

        for line in output.components(separatedBy: .newlines) {
            if let service = parseNumberedServiceName(line) {
                services.append(service)
            }
        }

        return services
    }

    private func allServices() -> [NetService] {
        let hardwareOutput = runCommand("/usr/sbin/networksetup", ["-listallhardwareports"])
        let serviceOrderOutput = runCommand("/usr/sbin/networksetup", ["-listnetworkserviceorder"])

        var serviceByDevice: [String: String] = [:]
        var currentService: String?

        for line in serviceOrderOutput.components(separatedBy: .newlines) {
            if let service = parseNumberedServiceName(line) {
                currentService = service
                continue
            }

            if line.contains("Device:"), let service = currentService, !service.isEmpty {
                let parts = line.components(separatedBy: "Device:")
                if parts.count > 1 {
                    let device = parts[1]
                        .replacingOccurrences(of: ")", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if !device.isEmpty {
                        serviceByDevice[device] = service
                    }
                }
            }
        }

        var result: [NetService] = []

        var hardwarePort: String?
        var device: String?

        func flush() {
            guard let hp = hardwarePort,
                  let dev = device,
                  let service = serviceByDevice[dev] else {
                return
            }

            let ifconfig = runCommand("/sbin/ifconfig", [dev])
            let active = ifconfig.contains("status: active")
            let hasIPv4 = ifconfig.contains("\n\tinet ")
            let hasIPv6 = ifconfig.contains("\n\tinet6 ")

            var ipv4: String?
            for line in ifconfig.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("inet ") {
                    let parts = trimmed.components(separatedBy: .whitespaces)
                    if parts.count > 1 {
                        ipv4 = parts[1]
                    }
                }
            }

            let info = runCommand("/usr/sbin/networksetup", ["-getinfo", service])
            var router: String?
            for line in info.components(separatedBy: .newlines) {
                if line.hasPrefix("Router:") {
                    router = line
                        .replacingOccurrences(of: "Router:", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }

            result.append(
                NetService(
                    serviceName: service,
                    hardwarePort: hp,
                    device: dev,
                    isActive: active,
                    hasIPv4: hasIPv4,
                    hasIPv6: hasIPv6,
                    ipv4: ipv4,
                    router: router
                )
            )
        }

        for line in hardwareOutput.components(separatedBy: .newlines) {
            if line.hasPrefix("Hardware Port:") {
                flush()
                hardwarePort = line.replacingOccurrences(of: "Hardware Port:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                device = nil
            } else if line.hasPrefix("Device:") {
                device = line.replacingOccurrences(of: "Device:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        flush()

        let order = currentServiceOrder()

        return result.sorted {
            let a = order.firstIndex(of: $0.serviceName) ?? Int.max
            let b = order.firstIndex(of: $1.serviceName) ?? Int.max
            return a < b
        }
    }

    private func image(_ name: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        img?.isTemplate = true
        return img
    }

    private func updateStatusTitleOnly(currentIface: String, services: [NetService]) {
        let current = services.first { $0.device == currentIface }

        guard let button = statusItem.button else {
            return
        }

        let title = isSwitchInProgress ? "◐ Switching" : "● \(currentIface)"
        let attributed = NSMutableAttributedString(string: title)

        attributed.addAttribute(
            .foregroundColor,
            value: isSwitchInProgress ? NSColor.systemOrange : NSColor.systemGreen,
            range: NSRange(location: 0, length: 1)
        )

        attributed.addAttribute(
            .foregroundColor,
            value: NSColor.labelColor,
            range: NSRange(location: 2, length: max(0, title.count - 2))
        )

        button.attributedTitle = attributed

        if let current {
            button.image = image(current.iconName)
        } else {
            button.image = image("network")
        }

        button.imagePosition = .imageLeft
    }

    private func updateMenu() {
        let currentIface = currentDefaultInterface()
        let gateway = currentDefaultGateway()
        let services = allServices()
        updateStatusTitleOnly(currentIface: currentIface, services: services)

        let menu = NSMenu()

        let header = NSMenuItem(title: "Network Interface", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let activeLine = NSMenuItem(
            title: "Active: \(currentIface)  ·  Gateway: \(gateway)",
            action: nil,
            keyEquivalent: ""
        )
        activeLine.isEnabled = false
        activeLine.image = image("checkmark.circle.fill")
        menu.addItem(activeLine)

        if isSwitchInProgress {
            let switchingLine = NSMenuItem(
                title: "Switching interface...",
                action: nil,
                keyEquivalent: ""
            )
            switchingLine.isEnabled = false
            switchingLine.image = image("hourglass")
            menu.addItem(switchingLine)
        }

        menu.addItem(NSMenuItem.separator())

        for service in services {
            let isCurrent = service.device == currentIface

            let statusText: String
            if isCurrent {
                statusText = "● Active"
            } else if service.isSelectable && !service.hasUsableRouter {
                statusText = "No Gateway"
            } else if service.isSelectable {
                statusText = "Available"
            } else {
                statusText = "Unavailable"
            }

            let ipText = service.ipv4 ?? "No IPv4"
            let title = "\(service.device) . \(service.hardwarePort)  ·  \(statusText)  ·  \(ipText)"

            let item = NSMenuItem(
                title: title,
                action: (service.isSelectable && !isSwitchInProgress) ? #selector(serviceClicked(_:)) : nil,
                keyEquivalent: ""
            )

            item.representedObject = service.serviceName
            item.isEnabled = service.isSelectable && !isSwitchInProgress
            item.image = image(service.iconName)

            if isCurrent {
                item.state = .on
            }

            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let restore = NSMenuItem(
            title: "Restore Preferred Order",
            action: #selector(restorePreferredOrderClicked),
            keyEquivalent: ""
        )
        restore.image = image("arrow.up.arrow.down.circle")
        menu.addItem(restore)

        let refresh = NSMenuItem(
            title: "Refresh",
            action: #selector(refreshClicked),
            keyEquivalent: "r"
        )
        refresh.image = image("arrow.clockwise")
        menu.addItem(refresh)

        let settings = NSMenuItem(
            title: "Open Network Settings",
            action: #selector(openNetworkSettingsClicked),
            keyEquivalent: ","
        )
        settings.image = image("gearshape")
        menu.addItem(settings)

        let forgetSavedPassword = NSMenuItem(
            title: "Forget Saved Admin Password",
            action: #selector(forgetSavedAdminPasswordClicked),
            keyEquivalent: ""
        )
        forgetSavedPassword.image = image("key.slash")
        forgetSavedPassword.isEnabled = hasSavedAdminPassword()
        menu.addItem(forgetSavedPassword)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(
            title: "Quit NetworkInterfaceMenu",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        quit.image = image("power")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func showAdminError(_ text: String) {
        let show = {
            let alert = NSAlert()
            alert.messageText = "Network switch failed"
            alert.informativeText = text.isEmpty ? "Unknown error" : text
            alert.alertStyle = .warning
            alert.runModal()
        }

        if Thread.isMainThread {
            show()
        } else {
            DispatchQueue.main.sync(execute: show)
        }
    }

    private func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }

    private func hasSavedAdminPassword() -> Bool {
        loadSavedAdminPassword() != nil
    }

    private func loadSavedAdminPassword() -> String? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8),
              !password.isEmpty else {
            return nil
        }

        return password
    }

    private func saveAdminPassword(_ password: String) -> Bool {
        guard let data = password.data(using: .utf8) else {
            return false
        }

        var query = keychainQuery()
        let attrs = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)

        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus != errSecItemNotFound {
            return false
        }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecAttrLabel as String] = "NetworkInterfaceMenu Admin Password"
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    private func forgetSavedAdminPassword() {
        let query = keychainQuery()
        SecItemDelete(query as CFDictionary)
    }

    private func promptForAdminPassword(errorText: String?) -> (password: String, saveToKeychain: Bool)? {
        let alert = NSAlert()
        alert.messageText = "Administrator Password Required"
        alert.informativeText = errorText ?? "Enter your macOS admin password."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 56))

        let passwordField = NSSecureTextField(frame: .zero)
        passwordField.translatesAutoresizingMaskIntoConstraints = false
        passwordField.placeholderString = "Password"

        let saveCheckbox = NSButton(checkboxWithTitle: "Remember in Keychain", target: nil, action: nil)
        saveCheckbox.translatesAutoresizingMaskIntoConstraints = false
        saveCheckbox.state = .on

        accessoryView.addSubview(passwordField)
        accessoryView.addSubview(saveCheckbox)

        NSLayoutConstraint.activate([
            passwordField.topAnchor.constraint(equalTo: accessoryView.topAnchor),
            passwordField.leadingAnchor.constraint(equalTo: accessoryView.leadingAnchor),
            passwordField.trailingAnchor.constraint(equalTo: accessoryView.trailingAnchor),
            passwordField.heightAnchor.constraint(equalToConstant: 24),

            saveCheckbox.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 8),
            saveCheckbox.leadingAnchor.constraint(equalTo: accessoryView.leadingAnchor),
            saveCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: accessoryView.trailingAnchor),
            saveCheckbox.bottomAnchor.constraint(equalTo: accessoryView.bottomAnchor)
        ])

        alert.accessoryView = accessoryView

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        guard response == .alertFirstButtonReturn else {
            return nil
        }

        let password = passwordField.stringValue
        if password.isEmpty {
            return nil
        }

        return (password, saveCheckbox.state == .on)
    }

    private func promptForAdminPasswordThreadSafe(errorText: String?) -> (password: String, saveToKeychain: Bool)? {
        if Thread.isMainThread {
            return promptForAdminPassword(errorText: errorText)
        }

        var result: (password: String, saveToKeychain: Bool)?
        DispatchQueue.main.sync {
            result = self.promptForAdminPassword(errorText: errorText)
        }
        return result
    }

    private func runSudoCommand(_ command: String, password: String) -> (success: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-k", "-S", "-p", "", "/bin/sh", "-c", command]

        let outputPipe = Pipe()
        let inputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.standardInput = inputPipe

        do {
            try process.run()

            if let passwordData = "\(password)\n".data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(passwordData)
            }
            try? inputPipe.fileHandleForWriting.close()

            process.waitUntilExit()

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus == 0, output)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func isAuthenticationFailure(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("incorrect password")
            || lower.contains("sorry, try again")
            || lower.contains("authentication failed")
            || lower.contains("a password is required")
    }

    private func runAdminScript(_ command: String) -> Bool {
        if let savedPassword = loadSavedAdminPassword() {
            let savedRun = runSudoCommand(command, password: savedPassword)
            if savedRun.success {
                return true
            }
            if isAuthenticationFailure(savedRun.output) {
                forgetSavedAdminPassword()
            } else {
                showAdminError(savedRun.output)
                return false
            }
        }

        var errorText: String?

        for _ in 0..<3 {
            guard let credentials = promptForAdminPasswordThreadSafe(errorText: errorText) else {
                return false
            }

            let run = runSudoCommand(command, password: credentials.password)
            if run.success {
                if credentials.saveToKeychain {
                    _ = saveAdminPassword(credentials.password)
                } else {
                    forgetSavedAdminPassword()
                }
                return true
            }

            if isAuthenticationFailure(run.output) {
                errorText = "Password was not accepted. Try again."
                continue
            }

            showAdminError(run.output)
            return false
        }

        showAdminError("Authentication failed after multiple attempts.")
        return false
    }

    private func applyServiceOrder(_ orderedServices: [String]) -> Bool {
        let existing = currentServiceOrder()

        var finalOrder: [String] = []

        for service in orderedServices {
            if existing.contains(service), !finalOrder.contains(service) {
                finalOrder.append(service)
            }
        }

        for service in existing {
            if !finalOrder.contains(service) {
                finalOrder.append(service)
            }
        }

        let quoted = finalOrder.map { shellQuote($0) }.joined(separator: " ")

        let command = """
        /usr/sbin/networksetup -ordernetworkservices \(quoted)
        /usr/sbin/networksetup -detectnewhardware
        """

        return runAdminScript(command)
    }

    private func switchToService(_ serviceName: String) {
        if isSwitchInProgress {
            return
        }

        isSwitchInProgress = true
        DispatchQueue.main.async {
            self.updateMenu()
        }

        switchQueue.async {
            let existing = self.currentServiceOrder()

            var newOrder: [String] = [serviceName]

            for service in existing {
                if service != serviceName {
                    newOrder.append(service)
                }
            }

            let quotedOrder = newOrder.map { self.shellQuote($0) }.joined(separator: " ")
            let quotedService = self.shellQuote(serviceName)
            let command = """
            /usr/sbin/networksetup -ordernetworkservices \(quotedOrder)
            /usr/sbin/networksetup -setnetworkserviceenabled \(quotedService) off
            sleep 1
            /usr/sbin/networksetup -setnetworkserviceenabled \(quotedService) on
            /usr/sbin/networksetup -detectnewhardware
            """
            let didApply = self.runAdminScript(command)

            DispatchQueue.main.async {
                guard didApply else {
                    self.isSwitchInProgress = false
                    self.updateMenu()
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self.isSwitchInProgress = false
                    self.updateMenu()

                    let selected = self.allServices().first { $0.serviceName == serviceName }

                    if let selected,
                       selected.hasUsableRouter,
                       self.currentDefaultInterface() != selected.device {
                        let alert = NSAlert()
                        alert.messageText = "Interface did not become active"
                        alert.informativeText = """
                        macOS accepted the service-order change, but the default route is still \(self.currentDefaultInterface()).

                        This can happen if the selected interface is not fully active, or corporate MDM/network policy overrides the route.
                        """
                        alert.alertStyle = .informational
                        alert.runModal()
                    }
                }
            }
        }
    }

    @objc private func serviceClicked(_ sender: NSMenuItem) {
        guard let serviceName = sender.representedObject as? String else {
            return
        }

        switchToService(serviceName)
    }

    @objc private func restorePreferredOrderClicked() {
        if isSwitchInProgress {
            return
        }

        isSwitchInProgress = true
        updateMenu()

        switchQueue.async {
            _ = self.applyServiceOrder(self.preferredServiceOrder)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.isSwitchInProgress = false
                self.updateMenu()
            }
        }
    }

    @objc private func refreshClicked() {
        updateMenu()
    }

    @objc private func openNetworkSettingsClicked() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")!)
    }

    @objc private func forgetSavedAdminPasswordClicked() {
        forgetSavedAdminPassword()
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }

    private func setupNetworkWatcher() {
        var context = SCDynamicStoreContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        store = SCDynamicStoreCreate(
            nil,
            "NetworkInterfaceMenu" as CFString,
            { _, _, info in
                guard let info = info else { return }

                let app = Unmanaged<AppDelegate>
                    .fromOpaque(info)
                    .takeUnretainedValue()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    app.updateMenu()
                }
            },
            &context
        )

        guard let store else {
            return
        }

        let keys = [
            "State:/Network/Global/IPv4" as CFString,
            "State:/Network/Global/IPv6" as CFString
        ] as CFArray

        let patterns = [
            "State:/Network/Interface/.*/IPv4" as CFString,
            "State:/Network/Interface/.*/IPv6" as CFString,
            "State:/Network/Interface/.*/Link" as CFString
        ] as CFArray

        SCDynamicStoreSetNotificationKeys(store, keys, patterns)

        if let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0) {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
