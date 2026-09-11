import XCTest
@testable import MacBCore

/// The matching rules that decide whether a face opens a private area.
/// Everything here is pure, so the security-relevant refusals are provable.
final class FaceUnlockTests: XCTestCase {
    private func identity(_ embedder: String = "model-a",
                          vectors: [[Float]] = [[1, 0, 0]]) -> FaceIdentity {
        FaceIdentity(name: "Ben",
                     samples: vectors.map { FaceSample(embedding: $0, pose: .center, quality: 0.9) },
                     embedderIdentifier: embedder)
    }

    func testTemplateIsTheNormalisedMean() {
        let template = FaceEmbedding.average([[1, 0, 0], [0, 900, 0]])
        let unwrapped = try! XCTUnwrap(template)
        XCTAssertEqual(FaceEmbedding.cosineSimilarity(unwrapped, [1, 0, 0]),
                       FaceEmbedding.cosineSimilarity(unwrapped, [0, 1, 0]), accuracy: 0.001)
        let length = unwrapped.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        XCTAssertEqual(length, 1, accuracy: 0.001)
    }

    func testDegenerateVectorsScoreZero() {
        XCTAssertEqual(FaceEmbedding.cosineSimilarity([1, 0], [1, 0, 0]), 0)
        XCTAssertEqual(FaceEmbedding.cosineSimilarity([], []), 0)
        XCTAssertNil(FaceEmbedding.average([]))
        XCTAssertNil(FaceEmbedding.normalized([0, 0, 0]))
    }

    func testSamplesFromAnotherEmbedderAreNeverCompared() {
        let stored = identity()
        XCTAssertTrue(FaceMatcher.score([1, 0, 0], against: [stored], embedderIdentifier: "model-b").isEmpty)
        XCTAssertNil(FaceMatcher.bestMatch([1, 0, 0], against: [stored],
                                           embedderIdentifier: "model-b", strictness: .relaxed))
    }

    func testDisabledIdentityCannotUnlock() {
        var stored = identity()
        stored.isEnabled = false
        XCTAssertNil(FaceMatcher.bestMatch([1, 0, 0], against: [stored],
                                           embedderIdentifier: "model-a", strictness: .relaxed))
    }

    func testStrangerStaysOutAtEveryStrictness() {
        let stored = identity()
        for strictness in FaceMatchStrictness.allCases {
            XCTAssertNil(FaceMatcher.bestMatch([-1, 0, 0], against: [stored],
                                               embedderIdentifier: "model-a", strictness: strictness),
                         "An opposite face matched at \(strictness.rawValue)")
        }
        XCTAssertNotNil(FaceMatcher.bestMatch([1, 0, 0], against: [stored],
                                              embedderIdentifier: "model-a", strictness: .strict))
    }

    func testStrictnessOnlyGetsHarder() {
        let ordered: [FaceMatchStrictness] = [.relaxed, .balanced, .strict]
        for index in 1..<ordered.count {
            XCTAssertGreaterThan(ordered[index].threshold, ordered[index - 1].threshold)
        }
    }

    func testEnrollmentNeedsAllNinePoses() {
        var stored = FaceIdentity(name: "Ben", embedderIdentifier: "model-a")
        XCTAssertFalse(stored.isComplete)
        XCTAssertEqual(stored.missingPoses.count, 9)
        for pose in FacePose.allCases {
            stored.samples.append(FaceSample(embedding: [1, 0, 0], pose: pose, quality: 0.9))
        }
        XCTAssertTrue(stored.isComplete)
        XCTAssertTrue(stored.missingPoses.isEmpty)
    }

    func testPoseAcceptsOnlyItsOwnAngle() {
        XCTAssertTrue(FacePose.left.accepts(yaw: -0.42, pitch: 0))
        XCTAssertFalse(FacePose.left.accepts(yaw: 0.42, pitch: 0))
        XCTAssertFalse(FacePose.up.accepts(yaw: 0, pitch: -0.30))
        XCTAssertTrue(FacePose.center.accepts(yaw: 0.1, pitch: -0.1))
    }

    func testAreaIsGuardedOnlyWhenEnabledAndSelected() {
        var settings = FaceUnlockSettings()
        XCTAssertFalse(settings.guards(.clipboard))
        settings.isEnabled = true
        XCTAssertTrue(settings.guards(.clipboard))
        XCTAssertFalse(settings.guards(.camera))
        XCTAssertEqual(settings.strictness, .strict)
        XCTAssertFalse(settings.allowsExperimentalModel)
    }

    func testSettingsSurviveARoundTrip() throws {
        var settings = FaceUnlockSettings()
        settings.isEnabled = true
        settings.protectedAreas = Set(ProtectedArea.allCases)
        settings.idleRelockSeconds = 900
        let restored = try JSONDecoder().decode(FaceUnlockSettings.self,
                                                from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored, settings)
    }
}
