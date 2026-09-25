import Foundation
import Observation
import Security
import UIKit
import RestwertKit

enum APIConfig {
    /// Railway-Backend. Für eigene Deployments hier anpassen.
    static let baseURL = URL(string: "https://api-production-9130.up.railway.app")!
}

struct APIUser: Codable, Equatable, Sendable {
    let id: String
    let email: String
    let name: String
}

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Konto und Synchronisation. Ohne Konto bleibt alles lokal.
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
        if Keychain.token != nil, let data = UserDefaults.standard.data(forKey: "apiUser") {
            user = try? JSONDecoder().decode(APIUser.self, from: data)
        }
        lastSync = UserDefaults.standard.object(forKey: "lastSync") as? Date
    }

    func attach(_ store: Store) {
        self.store = store
        store.onChange = { [weak self] in self?.schedulePush() }
    }

    // MARK: Anmeldung

    private struct Credentials: Encodable { let email: String; let password: String; var name: String? }
    private struct AuthResponse: Decodable { let token: String; let user: APIUser }
    private struct Empty: Codable {}

    func register(email: String, password: String, name: String) async throws {
        let res: AuthResponse = try await send("POST", "/api/auth/register", body: Credentials(email: email, password: password, name: name))
        signIn(res)
        await syncNow()
    }

    func login(email: String, password: String) async throws {
        let res: AuthResponse = try await send("POST", "/api/auth/login", body: Credentials(email: email, password: password))
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
        let _: Empty = try await send("DELETE", "/api/me", body: Optional<Empty>.none)
        logout()
    }

    private func signIn(_ res: AuthResponse) {
        Keychain.token = res.token
        user = res.user
        if let data = try? JSONEncoder().encode(res.user) { UserDefaults.standard.set(data, forKey: "apiUser") }
    }

    // MARK: Sync

    private struct SyncGet: Decodable { let data: SyncData?; let updatedAt: String? }
    private struct SyncPut: Encodable { let data: SyncData; let device: String; let baseUpdatedAt: String? }
    private struct SyncPutResponse: Decodable { let updatedAt: String }
    private struct Conflict: Decodable { let data: SyncData; let updatedAt: String }

    /// Server holen, einmischen, eigenen Stand hochladen.
    func syncNow() async {
        guard isLoggedIn, let store else { return }
        syncState = .syncing
        do {
            let remote: SyncGet = try await send("GET", "/api/sync", body: Optional<Empty>.none)
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
            syncState = .syncing
            do {
                try await push()
                finish()
            } catch {
                // Abgebrochen (neue Änderung oder Abmelden): kein Fehler anzeigen
                guard !Task.isCancelled else { return }
                syncState = .failed(error.localizedDescription)
            }
        }
    }

    private func push(retry: Bool = true) async throws {
        guard let store else { return }
        let body = SyncPut(data: store.syncPayload, device: UIDevice.current.model, baseUpdatedAt: serverUpdatedAt)
        do {
            let res: SyncPutResponse = try await send("PUT", "/api/sync", body: body)
            serverUpdatedAt = res.updatedAt
        } catch HTTPFailure.conflict(let data) where retry {
            // Ein anderes Gerät war schneller: einmischen und erneut senden
            let conflict = try APICoding.decoder.decode(Conflict.self, from: data)
            store.merge(conflict.data)
            serverUpdatedAt = conflict.updatedAt
            try await push(retry: false)
        }
    }

    private func finish() {
        let now = Date.now
        lastSync = now
        UserDefaults.standard.set(now, forKey: "lastSync")
        syncState = .idle
    }

    // MARK: HTTP

    private enum HTTPFailure: LocalizedError {
        case conflict(Data)
        var errorDescription: String? { "Auf einem anderen Gerät wurde inzwischen etwas geändert." }
    }

    private func send<Body: Encodable, Response: Decodable>(_ method: String, _ path: String, body: Body?) async throws -> Response {
        var req = URLRequest(url: APIConfig.baseURL.appending(path: path))
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = Keychain.token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try APICoding.encoder.encode(body) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError(message: "Keine Verbindung zum Server. Prüf dein Internet.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 409, path == "/api/sync" { throw HTTPFailure.conflict(data) }
        if status == 401, user != nil, !path.hasPrefix("/api/auth") { logout() }
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw APIError(message: message ?? "Serverfehler (\(status)).")
        }
        if data.isEmpty, let empty = Empty() as? Response { return empty }
        return try APICoding.decoder.decode(Response.self, from: data)
    }
}

// MARK: - Keychain

enum Keychain {
    private static let service = "de.restwert.app"
    private static let account = "api-token"

    static var token: String? {
        get {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                        kSecAttrAccount as String: account, kSecReturnData as String: true,
                                        kSecMatchLimit as String: kSecMatchLimitOne]
            var out: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                       kSecAttrAccount as String: account]
            SecItemDelete(base as CFDictionary)
            guard let newValue else { return }
            var add = base
            add[kSecValueData as String] = Data(newValue.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
