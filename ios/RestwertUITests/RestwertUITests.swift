import XCTest

/// UI-Tests der wichtigsten Wege im Simulator: Einstieg mit Anmeldeseite, Vorder- und Rückseite scannen,
/// und Barrierefreiheits-Prüfung (Apple-Audit) der Hauptbildschirme.
/// Aufruf aus ios/:  xcodebuild test -project Restwert.xcodeproj -scheme RestwertUITests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
@MainActor
final class RestwertUITests: XCTestCase {
    /// Testbilder liegen im Repo; der Simulator liest sie direkt vom Mac.
    private static let testImages = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "docs/evaluation/testgutscheine")

    nonisolated(unsafe) static var screen = ""
    private let base = ["-uiTestFreshData", "YES", "-onboarded", "YES", "-appLock", "NO", "-codeLock", "NO", "-pinLock", "NO", "-askedNotifyAfterSave", "YES"]

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }

    /// „Überspringen“ überspringt die Erklärseiten, nicht die Anmeldung; „Später“ führt weiter zum ersten Gutschein.
    func testOnboardingSkipLandsOnSignInThenLater() {
        let app = launch(["-onboarded", "NO"])
        app.buttons["Überspringen"].tap()
        XCTAssertTrue(app.staticTexts["Melde dich\nmit Apple an."].waitForExistence(timeout: 5)
                      || app.buttons["Später"].waitForExistence(timeout: 5))
        app.buttons["Später"].tap()
        // Letzte Seite: Hauptknopf „Gutschein hinzufügen“ und „Erstmal umschauen“.
        XCTAssertTrue(app.buttons["Erstmal umschauen"].waitForExistence(timeout: 5), app.debugDescription)
    }

    /// Geschenkkarte: Vorderseite (Laden, 25 €), dann „Nächstes Foto ist die Rückseite“ (Nummer, PIN, Datum).
    /// Ergebnis: 25 € von vorn, nicht „aufladbar bis 500 €“ von hinten; Kartennummer und PIN von hinten.
    func testFrontAndBackAreMerged() {
        let front = Self.testImages.appending(path: "v17-karte-vorne.jpg").path
        let back = Self.testImages.appending(path: "v18-karte-hinten.jpg").path
        let app = launch(base + ["-demoImportBatch", "\(front)|\(back)"])
        let next = app.buttons["Nächstes Foto ist die Rückseite"]
        XCTAssertTrue(next.waitForExistence(timeout: 60), "Rückseiten-Knopf fehlt")
        next.tap()
        XCTAssertTrue(app.staticTexts["Rückseite hinzugefügt"].waitForExistence(timeout: 60))
        // Kacheln sind für VoiceOver zusammengefasst („Guthaben, 25,00 €“): per Teiltext suchen.
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '25,00'")).firstMatch.exists,
                      "Guthaben von der Vorderseite erwartet")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '500,00'")).firstMatch.exists)
        let number = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '6280'")).firstMatch
        XCTAssertTrue(number.exists, "Kartennummer von der Rückseite erwartet")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'PIN'")).firstMatch.exists)
        // Bis zum Ende: hinzufügen, speichern – der Gutschein steht mit 25 € in der Liste.
        // Der breite Knopf im Ergebnis (nicht der gleichnamige Tab „Hinzufügen“ der Tab-Leiste).
        let add = app.buttons.matching(NSPredicate(format: "label == 'Hinzufügen'")).allElementsBoundByIndex
            .first { $0.frame.width > 250 && $0.isHittable }
        XCTAssertNotNil(add, app.debugDescription)
        add?.tap()
        let save = app.buttons["Speichern"]
        XCTAssertTrue(save.waitForExistence(timeout: 15), app.debugDescription)
        // Barcode nicht gelesen: Die App fragt nach der Art (bewusst kein stiller Vorschlag) – hier Code 128.
        let choose = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Bitte wählen'")).firstMatch
        if choose.waitForExistence(timeout: 3) {
            choose.tap()
            // Menütexte nutzen geschützte Leerzeichen: per Teiltext suchen.
            let code128 = app.buttons.matching(NSPredicate(format: "label CONTAINS '128'")).firstMatch
            XCTAssertTrue(code128.waitForExistence(timeout: 5), app.debugDescription)
            code128.tap()
        }
        save.tap()
        // Bestätigung „„Buchhandlung Seitenweise“ gespeichert“: der Gutschein ist angelegt.
        let saved = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Seitenweise' AND label CONTAINS 'gespeichert'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "Gutschein wurde nicht gespeichert")
    }

    // MARK: Barrierefreiheit (Apple-Audit: Kontrast, Beschriftungen, Trefferflächen, Dynamic Type, Abschneiden)

    func testAccessibilityAuditStart() throws {
        Self.screen = "start"
        let app = launch(base)
        XCTAssertTrue(app.staticTexts["Guthaben"].waitForExistence(timeout: 10))
        // Erst prüfen, wenn Einblendungen und Animationen fertig sind (sonst misst der Audit Zwischenbilder).
        sleep(2)
        try app.performAccessibilityAudit(for: .all, Self.knownIssues)
    }

    func testAccessibilityAuditSettings() throws {
        Self.screen = "settings"
        let app = launch(base + ["-demoScreen", "settings"])
        XCTAssertTrue(app.staticTexts["Schutz"].waitForExistence(timeout: 10))
        // Erst prüfen, wenn Einblendungen und Animationen fertig sind (sonst misst der Audit Zwischenbilder).
        sleep(2)
        try app.performAccessibilityAudit(for: .all, Self.knownIssues)
    }

    func testAccessibilityAuditCheckout() throws {
        Self.screen = "checkout"
        let app = launch(base + ["-demoScreen", "checkout"])
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
        // Erst prüfen, wenn Einblendungen und Animationen fertig sind (sonst misst der Audit Zwischenbilder).
        sleep(2)
        try app.performAccessibilityAudit(for: .all, Self.knownIssues)
    }

    func testAccessibilityAuditSettingsXL() throws {
        Self.screen = "settings"
        let app = launch(base + ["-demoScreen", "settings", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        XCTAssertTrue(app.staticTexts["Schutz"].waitForExistence(timeout: 10))
        sleep(2)
        try app.performAccessibilityAudit(for: .all, Self.knownIssues)
    }

    // MARK: Sehr große Schrift (Bedienungshilfen XL): Kontrast, Beschriftungen, Trefferflächen, abgeschnittener Text

    func testAccessibilityAuditStartXL() throws {
        Self.screen = "start"
        let app = launch(base + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        XCTAssertTrue(app.staticTexts["Guthaben"].waitForExistence(timeout: 10))
        sleep(2)
        try app.performAccessibilityAudit(for: .all, Self.knownIssues)
    }

    func testAccessibilityAuditCheckoutXL() throws {
        Self.screen = "checkout"
        let app = launch(base + ["-demoScreen", "checkout", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
        // „PIN zeigen“ bei größter Schrift ohne Scrollen erreichbar (über der Knopfleiste).
        XCTAssertTrue(app.buttons["PIN zeigen"].isHittable, "PIN zeigen bei XL nicht erreichbar")
        sleep(2)
        try app.performAccessibilityAudit(for: .all, Self.knownIssues)
    }

    /// Bewusst hingenommene Befunde des Audits (mit Begründung), alle anderen lassen den Test scheitern.
    @MainActor private static func knownIssues(_ issue: XCUIAccessibilityAuditIssue) throws -> Bool {
        // Systemelemente (Tab-Leiste, Suchfeld, Statusleiste) gehören nicht der App.
        if let element = issue.element, element.elementType == .tabBar || element.elementType == .searchField
            || element.elementType == .statusBar { return true }
        // Bewusst: Guthabenkarte und „Läuft bald ab“ wachsen nur bis Bedienungshilfen-Stufe 1, damit der Kasse-Knopf
        // bei größter Schrift über der Tab-Leiste bleibt (Wunsch aus den Beta-Runden). Das meldet der Audit als „teilweise“.
        if issue.auditType == .dynamicType, issue.compactDescription.contains("partially"),
           screen == "start" || screen == "checkout" { return true }
        // Logo-Kürzel („MK“) sind Bildzeichen in fester Größe; der Ladenname daneben wächst mit.
        if issue.auditType == .dynamicType, issue.element?.identifier == "merchantMark" { return true }
        // Inhalte unter der schwebenden Tab-Leiste und in ihrer Kanten-Weichzeichnung (iOS 26 blendet den Inhalt
        // darüber aus, zusammen ≈ 160 pt vom unteren Rand) misst der Audit gegen Glas bzw. Verlauf, nicht gegen die App.
        if issue.auditType == .contrast, screen != "checkout", let frame = issue.element?.frame,
           frame.maxY > XCUIApplication().frame.maxY - 160 { return true }
        // Kontrastbefund ohne Element: kommt und geht mit dem Glas der Tab-Leiste (Hintergrund darunter wechselt);
        // nicht zuordenbar. Befunde mit Element (echte App-Texte) lassen den Test weiter scheitern.
        if issue.auditType == .contrast, issue.element == nil { return true }
        // Kasse: Die Striche des Barcodes hält die Texterkennung des Audits für Text (ohne zugehöriges Element);
        // der Barcode ist als „Barcode groß zeigen“ beschriftet, die Ziffern darunter sind echter Text.
        if screen == "checkout", issue.auditType == .textClipped || issue.compactDescription.contains("inaccessible text"),
           issue.element == nil { return true }
        return false
    }
}
