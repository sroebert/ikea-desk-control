import Foundation
import Combine
import Logging

public enum KeychainItemClearMode {
    case never
    case atFirstStartup(store: UserDefaults? = nil)

    public static let atFirstStartup: Self = .atFirstStartup()
}

public enum KeychainItemAccessibility: Sendable {
    case whenPasscodeIsSet
    case whenUnlocked
    case afterFirstUnlock

    fileprivate var accessibleValue: CFString {
        switch self {
        case .whenPasscodeIsSet:
            return kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        case .whenUnlocked:
            return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .afterFirstUnlock:
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
    }
}

@propertyWrapper
public struct KeychainItem<Value: Codable & Sendable> {

    // MARK: - Private Vars

    private var subject: CurrentValueSubject<Value?, Never>

    private var changeSubscription: AnyCancellable?

    // MARK: - Lifecycle

    public init(
        _ key: String,
        accessibility: KeychainItemAccessibility = .afterFirstUnlock,
        clearMode: KeychainItemClearMode = .atFirstStartup
    ) {
        let manager = KeychainItemManager(key: key, accessibility: accessibility)
        Self.handle(clearMode, using: manager)

        subject = CurrentValueSubject(manager.get())
        changeSubscription = subject
            .dropFirst()
            .sink {
                manager.setAsync($0)
            }
    }

    private static func handle(_ clearMode: KeychainItemClearMode, using manager: KeychainItemManager) {
        switch clearMode {
        case .atFirstStartup(store: let store):
            let store = store ?? .standard

            // A `true` value is saved in UserDefaults to check whether the keychain item was used at least once.
            let key = "com_roebert_IKEADeskControl_KeychainItem_\(manager.key)"
            if !store.bool(forKey: key) {
                // If the boolean is `false` or missing, clear the keychain value.
                manager.clear()
            }

            store.set(true, forKey: key)

        case .never:
            break
        }
    }

    // MARK: - Property Wrapper

    public var wrappedValue: Value? {
        get {
            return subject.value
        }
        set {
            subject.send(newValue)
        }
    }

    public var projectedValue: AnyPublisher<Value?, Never> {
        return subject.eraseToAnyPublisher()
    }
}

private struct KeychainItemManager: @unchecked Sendable {

    // MARK: - Public Vars

    static let service = "com.roebert.IKEADeskControl.KeychainItem"

    let key: String
    let accessibility: KeychainItemAccessibility

    // MARK: - Private Vars

    fileprivate let queue = DispatchQueue(label: "com.roebert.IKEADeskControl.KeychainItem.queue")

    // MARK: - Lifecycle

    public init(
        key: String,
        accessibility: KeychainItemAccessibility
    ) {
        self.key = key
        self.accessibility = accessibility
    }

    // MARK: - Utils

    private func logError(_ message: String) {
        let logger = Logger(label: "com.roebert.IKEADeskControl.KeychainItem")
        logger.error(.init(stringLiteral: message))
    }

    private func createQuery(configure: ((inout [AnyHashable: Any]) -> Void)? = nil) -> CFDictionary {
        var query: [AnyHashable: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: key,
            kSecAttrAccessible: accessibility.accessibleValue
        ]
        configure?(&query)
        return query as CFDictionary
    }

    // MARK: - Value

    func get<Value: Codable>() -> Value? {
        do {
            if let data = load() {
                let decoder = PropertyListDecoder()
                return try decoder.decode(Value.self, from: data)
            }
        } catch {
            logError("Error decoding keychain item value: \(error)")
        }

        return nil
    }

    func setAsync<Value: Codable & Sendable>(_ value: Value?) {
        queue.async { [value] in
            set(value)
        }
    }

    func clear() {
        save(nil)
    }

    private func set<Value: Codable>(_ value: Value?) {
        guard let value = value else {
            save(nil)
            return
        }

        do {
            let encoder = PropertyListEncoder()
            let data = try encoder.encode(value)
            save(data)
        } catch {
            logError("Error encoding keychain item value: \(error)")
        }
    }

    // MARK: - Load

    private func load() -> Data? {
        let query = createQuery {
            $0[kSecReturnData] = true
            $0[kSecMatchLimit] = kSecMatchLimitOne
        }

        var result: AnyObject?
        guard SecItemCopyMatching(query, &result) == errSecSuccess else {
            return nil
        }

        return result as? Data
    }

    // MARK: - Save

    private func save(_ data: Data?) {
        // If the item already exists, update or remove it, otherwise add it
        let query = createQuery()
        let result: OSStatus
        if SecItemCopyMatching(query, nil) == errSecSuccess {
            if let data {
                result = SecItemUpdate(query, [
                    kSecValueData: data
                ] as CFDictionary)
            } else {
                result = SecItemDelete(query)
            }
        } else if let data {
            let addQuery = createQuery {
                $0[kSecValueData] = data
            }
            result = SecItemAdd(addQuery, nil)
        } else {
            result = errSecSuccess
        }

        if result != errSecSuccess {
            logError("Could not update keychain item value: \(result)")
        }
    }
}
