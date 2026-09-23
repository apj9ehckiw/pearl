import Foundation
import LocalAuthentication
import Security

enum BiometricStoreError: LocalizedError {
    case unavailable
    case storage
    case missing
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable: return "请先在设备设置中启用密码和面容 ID 或触控 ID。"
        case .storage: return "无法在本机钥匙串中保存解锁凭据。"
        case .missing: return "生物识别凭据已失效。请用钱包密码解锁后重新启用。"
        case .cancelled: return "已取消生物识别验证。"
        }
    }
}

// The wallet password is kept only in a device-bound, passcode-dependent item.
// Changing the enrolled biometrics invalidates this item. The nonsecret opt-in
// flag lives in UserDefaults so the locked screen need not query a protected item.
actor BiometricStore {
    static let shared = BiometricStore()
    private let service = "app.pearlwallet.ios.biometric-unlock"

    static func availableName() -> String? {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        switch context.biometryType {
        case .faceID: return "面容 ID"
        case .touchID: return "触控 ID"
        default: return "生物识别"
        }
    }

    private func identity(_ network: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: network,
         kSecAttrSynchronizable as String: false]
    }

    func save(_ password: String, network: String) throws {
        guard Self.availableName() != nil else { throw BiometricStoreError.unavailable }
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, &accessError) else {
            throw BiometricStoreError.storage
        }
        _ = SecItemDelete(identity(network) as CFDictionary)
        var attributes = identity(network)
        attributes[kSecAttrAccessControl as String] = access
        attributes[kSecValueData as String] = Data(password.utf8)
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
            throw BiometricStoreError.storage
        }
    }

    func read(network: String, reason: String) throws -> String {
        guard Self.availableName() != nil else { throw BiometricStoreError.unavailable }
        let context = LAContext()
        context.localizedFallbackTitle = ""
        var query = identity(network)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        query[kSecUseOperationPrompt as String] = reason
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecUserCanceled { throw BiometricStoreError.cancelled }
        guard status == errSecSuccess, let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw BiometricStoreError.missing
        }
        return password
    }

    func remove(network: String) {
        _ = SecItemDelete(identity(network) as CFDictionary)
    }
}
