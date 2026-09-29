import SwiftUI
import AuthenticationServices
import Security

/// Optionale Anmeldung mit Apple – nur ein Profil auf diesem Gerät, kein Konto bei uns und kein Server.
/// Gespeichert werden die anonyme Apple-Nutzerkennung (Schlüsselbund, nur dieses Gerät) und Name/E-Mail,
/// die Apple nur bei der allerersten Anmeldung mitliefert. Gutscheine bleiben auf dem Gerät und im eigenen iCloud.
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

    private init() {
        userID = Self.readUserID()
        name = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
        email = UserDefaults.standard.string(forKey: Self.emailKey) ?? ""
    }

    /// Anfrage für den „Mit Apple anmelden“-Knopf: Name und E-Mail (Apple zeigt sie nur beim ersten Mal an).
    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    func handle(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            userID = credential.user
            Self.writeUserID(credential.user)
            // Apple liefert Name und E-Mail nur bei der ersten Anmeldung; später bleibt das Gespeicherte.
            let given = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
            if !given.isEmpty { name = given; UserDefaults.standard.set(given, forKey: Self.nameKey) }
            if let mail = credential.email, !mail.isEmpty { email = mail; UserDefaults.standard.set(mail, forKey: Self.emailKey) }
            error = nil
        case .failure(let err):
            if (err as? ASAuthorizationError)?.code == .canceled { return }
            error = "Anmeldung mit Apple hat nicht geklappt. Bitte später erneut versuchen."
        }
    }

    func signOut() {
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
        if state == .revoked || state == .notFound { signOut() }
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
