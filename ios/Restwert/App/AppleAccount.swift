import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

/// Optionale Anmeldung mit Apple – nur ein Profil auf diesem Gerät, kein Konto bei uns und kein Server.
/// Gespeichert werden die anonyme Apple-Nutzerkennung (Schlüsselbund, nur dieses Gerät) und der Vorname
/// (App-Einstellungen), den Apple nur bei der allerersten Anmeldung mitliefert. Ältere Stände hatten die E-Mail;
/// sie wird noch angezeigt, falls vorhanden, aber nicht mehr angefragt. Gutscheine bleiben auf dem Gerät und im eigenen iCloud.
@Observable
final class AppleAccount {
    static let shared = AppleAccount()

    private(set) var userID: String?
    private(set) var name: String
    private(set) var email: String
    /// Letzter Fehler zum Anzeigen (Abbruch durch den Nutzer ist kein Fehler).
    var error: String?

    var isSignedIn: Bool { userID != nil }

    /// Anzeigename: Vorname, sonst E-Mail, sonst neutral.
    var displayName: String {
        if !name.isEmpty { return name }
        if !email.isEmpty { return email }
        return "Apple-Konto"
    }

    private static let keychainAccount = "apple-user-id"
    private static let nameKey = "appleAccountName"
    private static let emailKey = "appleAccountEmail"
    /// Namen früherer Anmeldungen je Apple-Kennung: Apple liefert den Namen nur beim allerersten Mal.
    /// Ohne diese Merkliste stünde nach Abmelden und erneutem Anmelden nur noch „Apple-Konto“ da.
    private static let knownNamesKey = "appleAccountKnownNames"

    private init() {
        userID = Self.readUserID()
        name = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
        email = UserDefaults.standard.string(forKey: Self.emailKey) ?? ""
    }

    /// Anfrage für den „Mit Apple anmelden“-Knopf: nur der Name (für die Begrüßung). Keine E-Mail –
    /// Restwert schreibt niemandem und braucht sie nicht (Datensparsamkeit).
    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
    }

    func handle(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            userID = credential.user
            Self.writeUserID(credential.user)
            // Apple liefert Name und E-Mail nur bei der ersten Anmeldung; später gilt der gemerkte Name.
            // Nur der Vorname (so steht es im Einstieg); den Nachnamen braucht die Begrüßung nicht.
            let given = credential.fullName?.givenName ?? credential.fullName?.familyName ?? ""
            if !given.isEmpty { rename(given) }
            else if name.isEmpty, let known = Self.knownNames[Self.hashed(credential.user)] { rename(known) }
            if let mail = credential.email, !mail.isEmpty { email = mail; UserDefaults.standard.set(mail, forKey: Self.emailKey) }
            error = nil
        case .failure(let err):
            if (err as? ASAuthorizationError)?.code == .canceled { return }
            error = "Anmeldung mit Apple hat nicht geklappt. Bitte später erneut versuchen."
        }
    }

    /// Name selbst setzen oder ändern (Einstellungen). Leer = wieder „Apple-Konto“.
    func rename(_ new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        name = trimmed
        UserDefaults.standard.set(trimmed, forKey: Self.nameKey)
        if let id = userID {
            var known = Self.knownNames
            known[Self.hashed(id)] = trimmed.isEmpty ? nil : trimmed
            UserDefaults.standard.set(known, forKey: Self.knownNamesKey)
        }
    }

    /// `forget`: auch den gemerkten Namen löschen („Alles löschen“, Anmeldung in iOS widerrufen).
    func signOut(forget: Bool = false) {
        if forget { UserDefaults.standard.removeObject(forKey: Self.knownNamesKey) }
        userID = nil
        name = ""
        email = ""
        Self.deleteUserID()
        UserDefaults.standard.removeObject(forKey: Self.nameKey)
        UserDefaults.standard.removeObject(forKey: Self.emailKey)
    }

    /// Beim Start: Hat der Nutzer die Anmeldung in den iOS-Einstellungen widerrufen, hier abmelden.
    func refreshCredentialState() async {
        guard let id = userID else { return }
        let state = await withCheckedContinuation { (cont: CheckedContinuation<ASAuthorizationAppleIDProvider.CredentialState, Never>) in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: id) { state, _ in cont.resume(returning: state) }
        }
        if state == .revoked || state == .notFound { signOut(forget: true) }
    }

    /// Merkliste nur mit Prüfsumme der Kennung: die Apple-Kennung selbst liegt ausschließlich im Schlüsselbund.
    private static func hashed(_ id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static var knownNames: [String: String] {
        UserDefaults.standard.dictionary(forKey: knownNamesKey) as? [String: String] ?? [:]
    }

    // MARK: Schlüsselbund (nur dieses Gerät, nicht im iCloud-Schlüsselbund)

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "de.restwert.app.apple",
         kSecAttrAccount as String: keychainAccount]
    }

    private static func readUserID() -> String? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeUserID(_ id: String) {
        deleteUserID()
        var q = query()
        q[kSecValueData as String] = Data(id.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    private static func deleteUserID() {
        SecItemDelete(query() as CFDictionary)
    }
}

/// Offizieller „Mit Apple anmelden“-Knopf im Stil der App: 56 pt hoch wie der Hauptknopf, gleiche Rundung,
/// Schwarz im Hellen und Weiß im Dunkeln (wie alle Hauptaktionen).
struct AppleSignInButton: View {
    var onSuccess: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            AppleAccount.shared.configure(request)
        } onCompletion: { result in
            withAnimation(.snappy) { AppleAccount.shared.handle(result) }
            if AppleAccount.shared.isSignedIn { onSuccess() }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        // Der Systemknopf zeichnet Text und Logo selbst und verträgt keine riesige Höhe: fest wie der Hauptknopf.
        .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
        .clipShape(.rect(cornerRadius: Layout.buttonRadius, style: .continuous))
        // Nach Abmelden → Anmelden neu aufbauen, sonst behält der Systemknopf alten Zustand.
        .id(colorScheme)
    }
}
