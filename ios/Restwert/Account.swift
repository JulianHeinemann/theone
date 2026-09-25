import Foundation
import Observation
import Security
import UIKit

enum APIConfig {
    /// Railway-Backend. Für eigene Deployments hier anpassen.
    static let baseURL = URL(string: "https://api-production-9130.up.railway.app")!
}

struct APIUser: Codable, Equatable {
    let id: String
    let email: String
    let name: String
}

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Konto und Synchronisation. Ohne Konto bleibt alles lokal.
@MainActor
@Observable
final class Account {
    enum SyncState: Equatable { case idle, syncing, failed(String) }

    private(set) var user: APIUser?
    private(set) var syncState: SyncState = .idle
    private(set) var lastSync: Date?

    @ObservationIgnored private weak var store: Store?
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    private var serverUpdatedAt: String? {
        get { UserDefaults.standard.string(forKey: "serverUpdatedAt") }
        set { UserDefaults.standard.set(newValue, forKey: "serverUpdatedAt") }
    }

    var isLoggedIn: Bool { user != nil }

    init() {
        if let data = UserDefaults.standard.data(forKey: "apiUser") {
            user = try? JSONDecoder().decode(APIUser.self, from: data)
        }
        if Keychain.token == nil { user = nil }
        lastSync = UserDefaults.standard.object(forKey: "lastSync") as? Date
    }

    func attach(_ store: Store) {
        self.store = store
        store.onChange = { [weak self] in self?.schedulePush() }
    }

    // MARK: Auth

    func register(email: String, password: String, name: String) async throws {
        let res: AuthResponse = try await request("POST", "/api/auth/register", body: ["email": email, "password": password, "name": name])
        signIn(res)
        await syncNow()
    }

    func login(email: String, password: String) async throws {
        let res: AuthResponse = try await request("POST", "/api/auth/login", body: ["email": email, "password": password])
        signIn(res)
        await syncNow()
    }

    func logout() {
        pushTask?.cancel()
        Keychain.token = nil
        user = nil
        serverUpdatedAt = nil
        UserDefaults.standard.removeObject(forKey: "apiUser")
        syncState = .idle
    }

    func deleteAccount() async throws {
        let _: Empty = try await request("DELETE", "/api/me")
        logout()
    }

    private struct AuthResponse: Decodable { let token: String; let user: APIUser }
    private struct Empty: Decodable {}

    private func signIn(_ res: AuthResponse) {
        Keychain.token = res.token
        user = res.user
        if let data = try? JSONEncoder().encode(res.user) { UserDefaults.standard.set(data, forKey: "apiUser") }
    }

    // MARK: Sync

    private struct SyncGet: Decodable { let data: Store.SyncData?; let updatedAt: String? }
    private struct SyncPut: Decodable { let updatedAt: String }
    private struct Conflict: Decodable { let data: Store.SyncData; let updatedAt: String }

    /// Server holen, einmischen, eigenen Stand hochladen.
    func syncNow() async {
        guard isLoggedIn, let store else { return }
        syncState = .syncing
        do {
            let remote: SyncGet = try await request("GET", "/api/sync")
            if let data = remote.data { store.merge(data) }
            serverUpdatedAt = remote.updatedAt
            try await push()
            finish()
        } catch {
            syncState = .failed(error.localizedDescription)
        }
    }

    private func schedulePush() {
        guard isLoggedIn else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.syncState = .syncing
            do {
                try await self.push()
                self.finish()
            } catch {
                self.syncState = .failed(error.localizedDescription)
            }
        }
    }

    private func push(retry: Bool = true) async throws {
        guard let store else { return }
        var body: [String: Any] = ["data": try jsonObject(store.syncPayload()), "device": UIDevice.current.model]
        if let base = serverUpdatedAt { body["baseUpdatedAt"] = base }
        do {
            let res: SyncPut = try await request("PUT", "/api/sync", body: body)
            serverUpdatedAt = res.updatedAt
        } catch HTTPFailure.conflict(let data) where retry {
            // Anderes Gerät war schneller: einmischen und erneut senden
            let c = try Self.decoder.decode(Conflict.self, from: data)
            store.merge(c.data)
            serverUpdatedAt = c.updatedAt
            try await push(retry: false)
        }
    }

    private func finish() {
        lastSync = .now
        UserDefaults.standard.set(lastSync, forKey: "lastSync")
        syncState = .idle
    }

    // MARK: HTTP

    private enum HTTPFailure: Error { case conflict(Data) }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: Self.encoder.encode(value))
    }

    private func request<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> T {
        var req = URLRequest(url: APIConfig.baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = Keychain.token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError(message: "Keine Verbindung zum Server. Prüf dein Internet.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 409, path == "/api/sync" { throw HTTPFailure.conflict(data) }
        if status == 401, user != nil, !path.hasPrefix("/api/auth") { logout() }
        guard (200..<300).contains(status) else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw APIError(message: msg ?? "Serverfehler (\(status)).")
        }
        if status == 204 || data.isEmpty, let empty = Empty() as? T { return empty }
        return try Self.decoder.decode(T.self, from: data)
    }
}

// MARK: - Keychain

enum Keychain {
    private static let service = "de.restwert.app"
    private static let account = "api-token"

    static var token: String? {
        get {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
            var out: AnyObject?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
            SecItemDelete(base as CFDictionary)
            guard let newValue, let data = newValue.data(using: .utf8) else { return }
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
