import XCTest
@testable import Yap

final class FluidProgressTests: XCTestCase {

    func testDownloadPhaseFillsWholeBar() {
        XCTAssertEqual(FluidCatalog.displayProgress(fraction: 0, isCompiling: false), 0)
        XCTAssertEqual(FluidCatalog.displayProgress(fraction: 0.25, isCompiling: false), 0.5, accuracy: 1e-9)
        XCTAssertEqual(FluidCatalog.displayProgress(fraction: 0.5, isCompiling: false), 1.0, accuracy: 1e-9)
    }

    func testCompilingIsIndeterminate() {
        XCTAssertLessThan(FluidCatalog.displayProgress(fraction: 0.75, isCompiling: true), 0)
    }

    func testProgressNeverGoesBackwards() {
        XCTAssertEqual(FluidCatalog.merge(current: 0.6, next: 0.4), 0.6)
        XCTAssertEqual(FluidCatalog.merge(current: 0.4, next: 0.6), 0.6)
    }

    func testStaysPreparingOnceCompilationStarts() {
        // Later loadModels passes re-report the download phase at 50% (→ 1.0 here).
        XCTAssertLessThan(FluidCatalog.merge(current: -1, next: 1.0), 0)
        XCTAssertLessThan(FluidCatalog.merge(current: 0.9, next: -1), 0)
    }

    /// Replays the progress sequence FluidAudio 0.18.0 emitted for a cold
    /// Parakeet v3 download (captured from a live run, condensed).
    /// Each pair is (fractionCompleted, isCompiling).
    func testRecordedSequenceIsMonotonicThenPreparing() {
        let raw: [(Double, Bool)] = [
            (0, false), (0.01, false), (0.24, false), (0.49, false), (0.5, false),
            (0.5, true), (1.0, true),
            (0.5, false), (0.5, true), (1.0, true),
            (0.5, false), (0.5, true), (1.0, true),
        ]

        var shown = 0.0
        var history: [Double] = []
        for (fraction, compiling) in raw {
            shown = FluidCatalog.merge(
                current: shown,
                next: FluidCatalog.displayProgress(fraction: fraction, isCompiling: compiling))
            history.append(shown)
        }

        let downloading = history.prefix { $0 >= 0 }
        XCTAssertEqual(Array(downloading), downloading.sorted(), "bar must never move backwards")
        XCTAssertEqual(downloading.last ?? 0, 1.0, accuracy: 1e-9)
        XCTAssertTrue(history.dropFirst(downloading.count).allSatisfy { $0 < 0 }, "must stay in preparing state")
    }
}

// MARK: - Completing pre-0.16 Parakeet installs

final class FluidLegacyInstallTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FluidLegacyInstallTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func touch(_ relativePath: String) throws {
        let url = dir.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }

    private func makeFolder(_ name: String, skipping skipped: String? = nil) throws {
        for file in FluidCatalog.modelFolderFiles where file != skipped {
            try touch("\(name)/\(file)")
        }
    }

    /// What FluidAudio before 0.16 left on disk after a finished download.
    private func makeLegacyInstall() throws {
        try touch("parakeet_vocab.json")
        for name in ["Preprocessor", "Encoder", "Decoder", "JointDecision"] {
            try makeFolder("\(name).mlmodelc")
        }
    }

    func testCompleteLegacyInstallIsCompleted() throws {
        try makeLegacyInstall()
        XCTAssertTrue(FluidCatalog.canCompleteLegacyInstall(at: dir))
    }

    func testPartialNewJointFolderIsStillCompleted() throws {
        try makeLegacyInstall()
        try makeFolder("JointDecisionv3.mlmodelc", skipping: "weights/weight.bin")
        XCTAssertTrue(FluidCatalog.canCompleteLegacyInstall(at: dir))
    }

    func testUpToDateInstallIsLeftAlone() throws {
        try makeLegacyInstall()
        try makeFolder("JointDecisionv3.mlmodelc")
        XCTAssertFalse(FluidCatalog.canCompleteLegacyInstall(at: dir))
    }

    /// The encoder weights are ~445 MB; an interrupted download must not be resumed silently.
    func testInterruptedDownloadMissingEncoderWeightsIsLeftAlone() throws {
        try touch("parakeet_vocab.json")
        try makeFolder("Preprocessor.mlmodelc")
        try makeFolder("Encoder.mlmodelc", skipping: "weights/weight.bin")
        try makeFolder("Decoder.mlmodelc")
        XCTAssertFalse(FluidCatalog.canCompleteLegacyInstall(at: dir))
    }

    func testMissingVocabularyIsLeftAlone() throws {
        try makeLegacyInstall()
        try FileManager.default.removeItem(at: dir.appendingPathComponent("parakeet_vocab.json"))
        XCTAssertFalse(FluidCatalog.canCompleteLegacyInstall(at: dir))
    }

    func testNoInstallIsLeftAlone() {
        XCTAssertFalse(FluidCatalog.canCompleteLegacyInstall(at: dir))
        XCTAssertFalse(FluidCatalog.canCompleteLegacyInstall(at: dir.appendingPathComponent("missing")))
    }
}
