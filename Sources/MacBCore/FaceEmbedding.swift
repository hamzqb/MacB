import Foundation

/// Pure vector maths behind face matching.
///
/// Nothing here touches the camera, the Keychain, or the disk, so the matching
/// rules — including the decision to reject a match — are provable in tests.
public enum FaceEmbedding {
    /// Cosine similarity in -1...1.
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for index in 0..<a.count {
            dot += a[index] * b[index]
            normA += a[index] * a[index]
            normB += b[index] * b[index]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }

    /// Unit vector, or nil when the vector has no length to normalise.
    public static func normalized(_ vector: [Float]) -> [Float]? {
        let norm = vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return nil }
        return vector.map { $0 / norm }
    }

    /// Normalise, average, then renormalise. A plain mean would let one
    /// large-magnitude sample dominate the template.
    public static func average(_ vectors: [[Float]]) -> [Float]? {
        guard let first = vectors.first, !first.isEmpty else { return nil }
        guard vectors.allSatisfy({ $0.count == first.count }) else { return nil }
        var sum = [Float](repeating: 0, count: first.count)
        var counted = 0
        for vector in vectors {
            guard let unit = normalized(vector) else { continue }
            for index in 0..<unit.count { sum[index] += unit[index] }
            counted += 1
        }
        guard counted > 0 else { return nil }
        return normalized(sum.map { $0 / Float(counted) })
    }
}

/// How strict a match has to be. The brief unlocks MacB's own private areas,
/// not the Mac, so the default leans strict rather than convenient.
public enum FaceMatchStrictness: String, Codable, CaseIterable, Sendable {
    case relaxed, balanced, strict

    public var threshold: Float {
        switch self {
        case .relaxed: return 0.30
        case .balanced: return 0.38
        case .strict: return 0.46
        }
    }

    public var title: String {
        switch self {
        case .relaxed: return "Esnek"
        case .balanced: return "Dengeli"
        case .strict: return "Sıkı"
        }
    }
}

public struct FaceMatchScore: Equatable, Sendable {
    public let identityID: UUID
    /// Similarity against the identity's averaged template.
    public let templateSimilarity: Float
    /// Similarity against the single closest sample, so averaging cannot hide a
    /// pose that matches well on its own.
    public let bestSampleSimilarity: Float

    public init(identityID: UUID, templateSimilarity: Float, bestSampleSimilarity: Float) {
        self.identityID = identityID
        self.templateSimilarity = templateSimilarity
        self.bestSampleSimilarity = bestSampleSimilarity
    }
}

public enum FaceMatcher {
    /// Scores every enabled identity recorded by the same embedder, best first.
    ///
    /// Samples produced by a different embedder are dropped rather than compared:
    /// two models' vectors are not in the same space, and comparing them would
    /// invent a similarity number that means nothing.
    public static func score(_ embedding: [Float],
                             against identities: [FaceIdentity],
                             embedderIdentifier: String) -> [FaceMatchScore] {
        identities.compactMap { identity -> FaceMatchScore? in
            guard identity.isEnabled,
                  identity.embedderIdentifier == embedderIdentifier,
                  let template = identity.template,
                  !identity.samples.isEmpty else { return nil }
            let templateSimilarity = FaceEmbedding.cosineSimilarity(embedding, template)
            let bestSample = identity.samples
                .map { FaceEmbedding.cosineSimilarity(embedding, $0.embedding) }
                .max() ?? templateSimilarity
            return FaceMatchScore(identityID: identity.id,
                                  templateSimilarity: templateSimilarity,
                                  bestSampleSimilarity: bestSample)
        }.sorted { $0.templateSimilarity > $1.templateSimilarity }
    }

    /// The winning identity, or nil when nothing clears the threshold.
    public static func bestMatch(_ embedding: [Float],
                                 against identities: [FaceIdentity],
                                 embedderIdentifier: String,
                                 strictness: FaceMatchStrictness) -> FaceMatchScore? {
        let threshold = strictness.threshold
        return score(embedding, against: identities, embedderIdentifier: embedderIdentifier)
            .first { $0.templateSimilarity >= threshold || $0.bestSampleSimilarity >= threshold }
    }
}
