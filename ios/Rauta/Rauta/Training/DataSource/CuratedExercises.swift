import Foundation

nonisolated let CURATION_VERSION = "2.0.0"

nonisolated enum ExerciseReviewSource: String, Codable, Hashable, Sendable {
    case name, instructions
    case sampledFrames = "sampled_frames"
    case video
}

nonisolated let CORE_PROGRAMMING_FIELDS = [
    "exerciseType", "movementPatterns", "mechanics", "laterality", "tracking",
    "requiredEquipment", "setRoles", "classificationConfidence", "skill",
    "setupSeconds", "automaticProgramming",
]

/// One curated review of an exercise. `metadata` is a partial patch over the
/// inferred record, so it stays in loosely typed JSON until it is merged.
nonisolated struct CuratedExerciseReview: Sendable {
    var exerciseId: String
    var reviewedFrom: [ExerciseReviewSource]
    var reviewedFields: [String]
    var sourceExerciseFingerprint: String
    var mediaFingerprint: String?
    var metadata: [String: JSONValue]

    init?(_ value: JSONValue) {
        guard let object = value.objectValue,
              let exerciseId = object["exerciseId"]?.stringValue
        else { return nil }
        self.exerciseId = exerciseId
        self.reviewedFrom = (object["reviewedFrom"]?.arrayValue ?? [])
            .compactMap { $0.stringValue.flatMap(ExerciseReviewSource.init(rawValue:)) }
        self.reviewedFields = (object["reviewedFields"]?.arrayValue ?? [])
            .compactMap(\.stringValue)
        self.sourceExerciseFingerprint = object["sourceExerciseFingerprint"]?.stringValue ?? ""
        self.mediaFingerprint = object["mediaFingerprint"]?.stringValue
        self.metadata = object["metadata"]?.objectValue ?? [:]
    }

    var isFullyReviewed: Bool {
        let fields = Set(reviewedFields)
        return CORE_PROGRAMMING_FIELDS.allSatisfy { fields.contains($0) }
    }
}

nonisolated struct CurationFreshness {
    var sourceCurrent: Bool
    var mediaCurrent: Bool?
    var sourceFingerprintMissing: Bool
    var mediaFingerprintMissing: Bool
    var staleSource: Bool
    var staleMedia: Bool
}

nonisolated enum CuratedExercises {
    private static let store: (reviews: [String: CuratedExerciseReview], media: [String: String]) = {
        let reviews = (BundledData.json("exercise-metadata.curated.complete")?.arrayValue ?? [])
            .compactMap(CuratedExerciseReview.init)
        let media = (BundledData.json("exercise-media-fingerprints")?.objectValue ?? [:])
            .compactMapValues(\.stringValue)
        return (Dictionary(reviews.map { ($0.exerciseId, $0) }, uniquingKeysWith: { _, last in last }), media)
    }()

    static func review(_ exerciseId: String) -> CuratedExerciseReview? {
        store.reviews[exerciseId]
    }

    static func currentMediaFingerprint(_ exerciseId: String) -> String? {
        store.media[exerciseId]
    }

    static func sourceExerciseFingerprint(_ exercise: ExerciseSummary) -> String {
        fingerprint(.object([
            "id": .string(exercise.id),
            "name": .string(exercise.name),
            "instructions": .array(exercise.instructions.map(JSONValue.string)),
            "equipment": .string(exercise.equipment),
            "primaryMuscle": exercise.primaryMuscle.map { JSONValue.string($0.rawValue) } ?? .null,
            "muscles": .array(exercise.muscles.map { .string($0.rawValue) }),
            "muscleWeights": .array(exercise.muscleWeights.map(JSONValue.number)),
        ]))
    }

    static func freshness(
        _ review: CuratedExerciseReview,
        _ exercise: ExerciseSummary,
        mediaFingerprint: String? = nil
    ) -> CurationFreshness {
        let media = mediaFingerprint ?? currentMediaFingerprint(exercise.id)
        let needsMedia = review.reviewedFrom.contains(.sampledFrames) || review.reviewedFrom.contains(.video)
        let currentSource = sourceExerciseFingerprint(exercise)
        let sourceFingerprintMissing = review.sourceExerciseFingerprint.isEmpty
        let mediaFingerprintMissing = needsMedia && (review.mediaFingerprint?.isEmpty ?? true)
        let sourceCurrent = !sourceFingerprintMissing && review.sourceExerciseFingerprint == currentSource
        let mediaCurrent: Bool? = needsMedia
            ? (!mediaFingerprintMissing && media != nil && review.mediaFingerprint == media)
            : nil

        return CurationFreshness(
            sourceCurrent: sourceCurrent,
            mediaCurrent: mediaCurrent,
            sourceFingerprintMissing: sourceFingerprintMissing,
            mediaFingerprintMissing: mediaFingerprintMissing,
            staleSource: !sourceFingerprintMissing && !sourceCurrent,
            staleMedia: needsMedia && !mediaFingerprintMissing && mediaCurrent == false
        )
    }

    /// The inferred record with any curated review merged over it, exactly the
    /// way the TypeScript spread did.
    static func resolveMetadata(_ exercise: ExerciseSummary) -> ExerciseMetadata {
        let inferred = ExerciseClassifier.inferMetadata(exercise)
        guard let review = review(exercise.id) else { return inferred }

        let state = freshness(review, exercise)
        let staleSource = state.staleSource || state.sourceFingerprintMissing
        let staleMedia = state.staleMedia || state.mediaFingerprintMissing
        let fullyReviewed = review.isFullyReviewed && !staleSource && !staleMedia

        let reviewStatus: ReviewStatus = {
            if staleSource { return staleMedia ? .staleSourceAndMediaReview : .staleSourceReview }
            if staleMedia { return .staleMediaReview }
            return fullyReviewed ? .fullyReviewed : .partiallyReviewed
        }()

        var merged = inferred.jsonTree.objectValue ?? [:]
        for (key, value) in review.metadata { merged[key] = value }
        merged["exerciseId"] = .string(exercise.id)

        var tags = Set<String>()
        if !fullyReviewed { tags.formUnion(inferred.tags) }
        tags.formUnion((review.metadata["tags"]?.arrayValue ?? []).compactMap(\.stringValue))
        if staleSource { tags.insert("stale_source_review") }
        if staleMedia { tags.insert("stale_media_review") }
        merged["tags"] = .array(tags.sorted { compareIds($0, $1) < 0 }.map(JSONValue.string))

        if staleSource || staleMedia {
            merged["automaticProgramming"] = .string(AutomaticProgramming.manualOnly.rawValue)
        } else if review.metadata["automaticProgramming"] == nil {
            merged["automaticProgramming"] = .string(inferred.automaticProgramming.rawValue)
        }

        let provenance: MetadataProvenance = fullyReviewed
            ? curatedProvenance(review.reviewedFrom)
            : .curated
        merged["provenance"] = .string(provenance.rawValue)
        merged["reviewStatus"] = .string(reviewStatus.rawValue)
        merged["reviewedFields"] = .array(
            review.reviewedFields.sorted { compareIds($0, $1) < 0 }.map(JSONValue.string)
        )
        merged["ruleVersion"] = .string("\(RULE_VERSION)+curation-\(CURATION_VERSION)")

        return JSONCoding.value(.object(merged), as: ExerciseMetadata.self) ?? inferred
    }

    private static func curatedProvenance(_ reviewedFrom: [ExerciseReviewSource]) -> MetadataProvenance {
        let video = reviewedFrom.contains(.video)
        let sampledFrames = reviewedFrom.contains(.sampledFrames)
        let text = reviewedFrom.contains(.name) || reviewedFrom.contains(.instructions)
        if video { return text ? .curatedVideoAndText : .curatedVideo }
        if sampledFrames { return text ? .curatedSampledFramesAndText : .curatedSampledFrames }
        return .curatedText
    }
}
