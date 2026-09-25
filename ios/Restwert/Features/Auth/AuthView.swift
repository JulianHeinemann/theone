import SwiftUI
import RestwertKit

/// Anmelden oder Konto erstellen. Ohne Konto bleibt alles auf dem Gerät.
struct AuthView: View {
    @Environment(Account.self) private var account
    @Environment(\.dismiss) private var dismiss
    var isFirstRun = false
    var onDone: () -> Void = {}

    enum Mode: String, CaseIterable { case register = "Konto erstellen", login = "Anmelden" }
    enum Field { case name, email, password }

    @State private var mode: Mode = .register
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @State private var shake = 0
    @FocusState private var focus: Field?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Picker("Modus", selection: $mode.animation(.snappy)) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 8) {
                    if mode == .register {
                        box("Name (optional)") {
                            TextField("Wie sollen wir dich nennen?", text: $name)
                                .textContentType(.givenName).focused($focus, equals: .name)
                                .submitLabel(.next).onSubmit { focus = .email }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    box("E-Mail") {
                        TextField("du@beispiel.de", text: $email)
                            .textContentType(.emailAddress).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focus, equals: .email).submitLabel(.next).onSubmit { focus = .password }
                    }
                    box(mode == .register ? "Passwort (mind. 8 Zeichen)" : "Passwort") {
                        SecureField("••••••••", text: $password)
                            .textContentType(mode == .register ? .newPassword : .password)
                            .focused($focus, equals: .password).submitLabel(.go)
                            .onSubmit { Task { await submit() } }
                    }
                }
                .modifier(Shake(animatableData: CGFloat(shake)))

                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.bad)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Button { Task { await submit() } } label: {
                    HStack(spacing: 10) {
                        if busy { ProgressView().tint(.white) }
                        Text(mode.rawValue).contentTransition(.interpolate)
                    }
                }
                .buttonStyle(.primary)
                .disabled(busy)

                if isFirstRun {
                    Button("Ohne Konto weiter") { onDone() }
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity).padding(.top, 4)
                    Text("Du kannst später jederzeit in den Einstellungen ein Konto anlegen.")
                        .font(.system(size: 13)).foregroundStyle(Color.muted)
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }
                Link("Datenschutz", destination: APIConfig.baseURL.appending(path: "datenschutz"))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.muted).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .pageBackground()
        .sensoryFeedback(.error, trigger: shake)
        .toolbar {
            if !isFirstRun {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: mode == .register ? "icloud.and.arrow.up" : "person.crop.circle.badge.checkmark")
                .font(.system(size: 26, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 58, height: 58)
                .glassEffect(.regular.tint(Color.brandYellow), in: .rect(cornerRadius: 18, style: .continuous))
            Text(mode == .register ? "Gutscheine auf allen Geräten." : "Willkommen zurück.")
                .font(.system(size: 38, weight: .heavy)).kerning(-1)
                .contentTransition(.opacity)
            Text("Mit Konto sind deine Gutscheine gesichert und auf iPhone und iPad gleich. Fotos und PINs bleiben nur auf deinem Gerät.")
                .font(.system(size: 15)).foregroundStyle(Color.ink2)
        }
        .padding(.top, isFirstRun ? 30 : 0)
    }

    private func box<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.muted)
            content().font(.system(size: 16, weight: .semibold))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: .rect(cornerRadius: 16, style: .continuous))
    }

    private func submit() async {
        focus = nil
        busy = true
        defer { busy = false }
        do {
            if mode == .register {
                try await account.register(email: email, password: password, name: name)
            } else {
                try await account.login(email: email, password: password)
            }
            withAnimation { error = nil }
            onDone()
            if !isFirstRun { dismiss() }
        } catch {
            withAnimation(.snappy) { self.error = error.localizedDescription }
            withAnimation(.linear(duration: 0.4)) { shake += 1 }
        }
    }
}
