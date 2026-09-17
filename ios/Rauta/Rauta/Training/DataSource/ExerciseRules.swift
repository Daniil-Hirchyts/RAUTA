import Foundation

nonisolated let RULE_VERSION = "1.2.0"

/// Roles are explicit anatomical programming approximations, independent of
/// source weights.
nonisolated struct PatternRule {
    var match: Pattern
    var exclude: Pattern?
    var pattern: MovementPattern
    var direct: [MuscleId]
    var indirect: [MuscleId]
    var compound: Bool = false
    var familyId: String?
}

nonisolated let CLASSIFICATION_RULES: [PatternRule] = [
    PatternRule(
        match: Pattern(#"\b(calf|calves|heel) (raise|press)|calf.*raise"#),
        pattern: .calfRaise, direct: [.calves], indirect: []
    ),
    PatternRule(
        match: Pattern(#"\b(leg|hamstring) curl\b"#),
        pattern: .kneeFlexion, direct: [.hamstring], indirect: []
    ),
    PatternRule(
        match: Pattern(#"\bleg extension\b"#),
        pattern: .kneeExtension, direct: [.quadriceps], indirect: []
    ),
    PatternRule(
        match: Pattern(#"\b(hip|thigh).*abduct"#),
        pattern: .hipAbduction, direct: [.gluteal], indirect: []
    ),
    PatternRule(
        match: Pattern(#"\b(hip|thigh).*adduct"#),
        pattern: .hipAdduction, direct: [.adductors], indirect: []
    ),
    PatternRule(
        match: Pattern(#"\b(deadlift|good morning)\b"#),
        pattern: .hinge, direct: [.gluteal, .hamstring], indirect: [.lowerBack],
        compound: true
    ),
    PatternRule(
        match: Pattern(#"\b(lunge|split squat|step-up)\b"#),
        pattern: .lunge, direct: [.quadriceps, .gluteal], indirect: [],
        compound: true
    ),
    PatternRule(
        match: Pattern(#"\b(squat|leg press)\b"#),
        pattern: .squat, direct: [.quadriceps, .gluteal], indirect: [.adductors],
        compound: true
    ),
    PatternRule(
        match: Pattern(#"\b(hip thrusts?|glute bridges?|kickback)\b"#),
        pattern: .hipExtension, direct: [.gluteal], indirect: [.hamstring]
    ),
    PatternRule(
        match: Pattern(#"\b(bench press|chest press|push-up|push up|floor press)\b"#),
        pattern: .horizontalPush, direct: [.chest], indirect: [.triceps, .deltoids],
        compound: true, familyId: "horizontal_press"
    ),
    PatternRule(
        match: Pattern(#"\b(shoulder press|military press|overhead press|arnold press)\b"#),
        pattern: .verticalPush, direct: [.deltoids], indirect: [.triceps],
        compound: true
    ),
    PatternRule(
        match: Pattern(#"\b(pulldown|pull-down|pull-up|chin-up)\b"#),
        pattern: .verticalPull, direct: [.upperBack], indirect: [.biceps],
        compound: true
    ),
    PatternRule(
        match: Pattern(#"\brow\b"#),
        pattern: .horizontalPull, direct: [.upperBack], indirect: [.biceps, .deltoids],
        compound: true
    ),
    PatternRule(
        match: Pattern(#"\b(reverse fly|rear delt)\b"#),
        pattern: .horizontalPull, direct: [.deltoids], indirect: [.upperBack],
        familyId: "rear_delt_fly"
    ),
    PatternRule(
        match: Pattern(#"\b(fly|flye)\b"#),
        exclude: Pattern(#"\b(reverse fly|rear delt)\b"#),
        pattern: .horizontalPush, direct: [.chest], indirect: [],
        familyId: "chest_fly"
    ),
    PatternRule(
        match: Pattern(#"\b(triceps|tricep|pushdown|skull crusher)\b"#),
        pattern: .elbowExtension, direct: [.triceps], indirect: []
    ),
    PatternRule(
        match: Pattern(
            #"\b(biceps|bicep|hammer curl|concentration curl|preacher curl)\b|^(barbell|dumbbell|cable|band|ez barbell) (standing |seated )?curl\b"#
        ),
        pattern: .elbowFlexion, direct: [.biceps], indirect: []
    ),
    PatternRule(
        match: Pattern(#"\blateral raise\b"#),
        pattern: .shoulderAbduction, direct: [.deltoids], indirect: []
    ),
    PatternRule(
        match: Pattern(#"\b(crunch|sit-up|sit up)\b"#),
        pattern: .trunkFlexion, direct: [.abs], indirect: []
    ),
    PatternRule(
        match: Pattern(#"\b(back extension|hyperextension)\b"#),
        pattern: .trunkExtension, direct: [.lowerBack], indirect: [.gluteal]
    ),
    PatternRule(
        match: Pattern(#"\b(russian twist|wood chop)\b"#),
        pattern: .trunkRotation, direct: [.obliques], indirect: [.abs]
    ),
]

private nonisolated enum InferencePatterns {
    static let stretch = Pattern(#"\bstretch"#)
    static let isometric = Pattern(#"\b(isometric|static hold|hold)\b|\bplank\b"#)
    static let power = Pattern(#"\b(snatch|clean|jerk|jump|plyo|throw)\b"#)
    static let conditioning = Pattern(
        #"\b(run|running|bike|elliptical|stepmill|skierg|burpee|jumping jack|walk)\b"#
    )
    static let mobility = Pattern(#"\b(mobility|roll massage|foam roll)\b"#)
    static let complex = Pattern(
        #"\b(snatch|clean|jerk|jump|plyo|kipping|handstand|clap|pistol|bosu|throw|muscle-up|swing|zercher|jefferson|overhead squat|on knees|speed squat)\b"#
    )
    static let ambiguous = Pattern(
        #"\b(stretch|isometric|hold|static|assisted stretch|neck|wrist|finger|reverse grip curl|upright row|squat row|squatting row|pullover|sissy|behind neck)\b"#
    )
    static let partialRom = Pattern(#"\bpartial|\bhalf|\bquarter|3/4"#)

    static let bench = Pattern(#"bench"#)
    static let benchExcluded = Pattern(#"leverage|smith|sled"#)
    static let rack = Pattern(#"\brack\b"#)
    static let pullUpBar = Pattern(#"pull-up|chin-up|pull up bar|chin up bar"#)
    static let invertedRow = Pattern(#"inverted row"#)
    static let stabilityBall = Pattern(#"\b(stability ball|exercise ball)\b"#)
    static let chair = Pattern(#"\b(chair|stool)\b"#)
    static let stepSurface = Pattern(#"\b(step|box|platform)\b"#)
    static let stepName = Pattern(#"step-up|calf|elevated"#)
    static let anchor = Pattern(#"\b(anchor|attach|secure)\b"#)
    static let band = Pattern(#"band"#)
    static let partner = Pattern(#"\b(partner|assistance from someone)\b"#)
    static let towelOrStraps = Pattern(#"\b(towel|straps)\b"#)

    static let bandEquipment = Pattern(#"\bband\b"#)
    static let assistedName = Pattern(#"\bassisted\b"#)
    static let externalLoadEquipment = Pattern(
        #"^(barbell|dumbbell|cable|leverage machine|smith machine|sled machine|kettlebell|ez barbell|trap bar)$"#
    )
    static let runOrWalk = Pattern(#"\b(run|running|walk)\b"#)
    static let unilateral = Pattern(
        #"one arm|one leg|single arm|single leg|single-arm|single-leg|split squat"#
    )
    static let alternating = Pattern(#"alternat|lunge"#)
}

nonisolated enum ExerciseClassifier {
    static func inferMetadata(_ exercise: ExerciseSummary) -> ExerciseMetadata {
        let name = exercise.name.lowercased()
        let instructions = exercise.instructions.joined(separator: " ").lowercased()
        let text = name + " " + instructions

        let detectedType: ExerciseType
        if InferencePatterns.stretch.test(name) {
            detectedType = .stretch
        } else if InferencePatterns.isometric.test(name) {
            detectedType = .isometric
        } else if InferencePatterns.power.test(name) {
            detectedType = .power
        } else if InferencePatterns.conditioning.test(name) && exercise.primaryMuscle != .abs {
            detectedType = .conditioning
        } else if InferencePatterns.mobility.test(name) {
            detectedType = .mobility
        } else {
            detectedType = .unknown
        }

        let complex = InferencePatterns.complex.test(name)
        let ambiguous = InferencePatterns.ambiguous.test(name)
        let partialRom = InferencePatterns.partialRom.test(name)

        let rules = CLASSIFICATION_RULES.filter { rule in
            rule.match.test(name) && !(rule.exclude?.test(name) ?? false)
        }

        // A primary-muscle mismatch is reviewable data, never silently overridden.
        let matchesMuscle: Bool = {
            guard !rules.isEmpty, let primary = exercise.primaryMuscle else { return false }
            return rules.contains { ($0.direct + $0.indirect).contains(primary) }
        }()

        let ruleSupported = detectedType == .unknown
            && !rules.isEmpty
            && matchesMuscle
            && exercise.instructions.count >= 2
        let exerciseType: ExerciseType = ruleSupported ? .resistance : detectedType

        var equipment: Set<String> = [exercise.equipment]
        if InferencePatterns.bench.test(text) && !InferencePatterns.benchExcluded.test(exercise.equipment) {
            equipment.insert("bench")
        }
        if InferencePatterns.rack.test(text) && exercise.equipment == "barbell" {
            equipment.insert("rack")
        }
        if InferencePatterns.pullUpBar.test(text) && exercise.equipment == "body weight" {
            equipment.insert("pull-up bar")
        }
        if InferencePatterns.invertedRow.test(name) { equipment.insert("low bar") }
        if InferencePatterns.stabilityBall.test(text) { equipment.insert("stability ball") }
        if InferencePatterns.chair.test(text) { equipment.insert("chair") }
        if InferencePatterns.stepSurface.test(text) && InferencePatterns.stepName.test(name) {
            equipment.insert("step")
        }
        if InferencePatterns.anchor.test(text) && InferencePatterns.band.test(exercise.equipment) {
            equipment.insert("band anchor")
        }
        if InferencePatterns.partner.test(text) { equipment.insert("partner") }
        if InferencePatterns.towelOrStraps.test(name) {
            equipment.insert(name.contains("towel") ? "towel" : "suspension straps")
        }

        let tracking: TrackingMode = {
            if exerciseType == .isometric { return .timed }
            if exerciseType == .conditioning && InferencePatterns.runOrWalk.test(name) { return .distance }
            if InferencePatterns.bandEquipment.test(exercise.equipment) { return .bandResistance }
            if exercise.equipment == "body weight" { return .bodyweight }
            if exercise.equipment == "assisted"
                || (exercise.equipment == "leverage machine" && InferencePatterns.assistedName.test(name)) {
                return .assistance
            }
            if InferencePatterns.externalLoadEquipment.test(exercise.equipment) { return .externalLoad }
            return .unknown
        }()

        var roleByMuscle: [MuscleId: EffectiveSetRole] = [:]
        if ruleSupported {
            for rule in rules {
                for muscleId in rule.indirect where roleByMuscle[muscleId] == nil {
                    roleByMuscle[muscleId] = EffectiveSetRole(
                        muscleId: muscleId, role: .indirect, provenance: .rule
                    )
                }
                for muscleId in rule.direct {
                    roleByMuscle[muscleId] = EffectiveSetRole(
                        muscleId: muscleId, role: .direct, provenance: .rule
                    )
                }
            }
        }

        let patterns: [MovementPattern] = ruleSupported
            ? Array(Set(rules.map(\.pattern))).sorted { compareIds($0.rawValue, $1.rawValue) < 0 }
            : [.unknown]
        let families: [String] = ruleSupported
            ? Array(Set(rules.map { $0.familyId ?? $0.pattern.rawValue }))
            : []
        let familyId = families.count == 1 ? families[0] : nil

        let automaticProgramming: AutomaticProgramming = {
            if exerciseType != .resistance || !ruleSupported || ambiguous || tracking == .unknown {
                return .manualOnly
            }
            return complex || partialRom ? .specializedOnly : .allowed
        }()

        let classificationConfidence: Double = {
            if exerciseType == .resistance {
                if ambiguous { return 0.45 }
                return complex || partialRom ? 0.6 : 0.75
            }
            return detectedType != .unknown ? 0.9 : 0.2
        }()

        var tags: [String] = []
        if !matchesMuscle && !rules.isEmpty { tags.append("primary_mismatch") }
        if complex { tags.append("complex_unreviewed") }
        if partialRom { tags.append("partial_rom") }
        if patterns.count > 1 { tags.append("multi_pattern") }

        return ExerciseMetadata(
            exerciseId: exercise.id,
            exerciseType: exerciseType,
            movementPatterns: patterns,
            mechanics: ruleSupported ? (rules.contains(where: \.compound) ? .compound : .isolation) : .unknown,
            laterality: InferencePatterns.unilateral.test(name)
                ? .unilateral
                : (InferencePatterns.alternating.test(name) ? .alternating : .bilateral),
            tracking: tracking,
            requiredEquipment: equipment.sorted { compareIds($0, $1) < 0 },
            setRoles: roleByMuscle.values.sorted { compareIds($0.muscleId.rawValue, $1.muscleId.rawValue) < 0 },
            classificationConfidence: classificationConfidence,
            skill: complex ? .complex : (ruleSupported ? .basic : .unknown),
            setupSeconds: tracking == .externalLoad ? 60 : 30,
            tags: tags,
            automaticProgramming: automaticProgramming,
            familyId: familyId,
            variantOf: nil,
            duplicateOf: nil,
            provenance: .rule,
            reviewStatus: .ruleOnly,
            reviewedFields: [],
            ruleVersion: RULE_VERSION
        )
    }

    /// Every movement pattern `validateMetadata` accepts.
    static let validPatterns: Set<MovementPattern> = {
        var set = Set(CLASSIFICATION_RULES.map(\.pattern))
        let extras: [MovementPattern] = [
            .hipFlexion, .hipRotation, .shoulderFlexion, .shoulderExtension, .shoulderRotation,
            .scapularProtraction, .scapularRetraction, .scapularElevation, .scapularDepression,
            .wristFlexion, .wristExtension, .forearmRotation, .grip, .dorsiflexion,
            .trunkLateralFlexion, .antiExtension, .antiRotation,
            .neckFlexion, .neckExtension, .neckRotation,
            .carry, .locomotion, .jump, .throwing, .mobility, .balance, .wholeBody, .unknown,
        ]
        extras.forEach { set.insert($0) }
        return set
    }()
}
