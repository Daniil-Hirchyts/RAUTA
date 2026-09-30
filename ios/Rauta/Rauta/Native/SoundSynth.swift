import AVFoundation

/// One note of something made on the spot, in the voice of the bundled cues: a
/// soft sine with a trace of harmonics.
struct SoundNote: Equatable {
    /// Seconds from the start of the phrase.
    var at: Double
    var frequency: Double
    /// How long it rings: the time it takes to fall to about a third.
    var decay: Double = 0.05
    var gain: Double = 1
    /// Where the pitch starts, as a ratio of the note it slides into. Under 1
    /// it rises into the note, over 1 it falls into it, and 1 does not slide.
    var bend: Double = 1
}

/// Turns notes into sound. The same recipe as the "Pure" set in
/// `scripts/sounds/packs.py`, so what is made here sits beside the files.
enum SoundSynth {
    private static let attack = 0.005
    private static let slide = 0.018

    /// How long a phrase takes to be heard out.
    static func length(_ notes: [SoundNote]) -> Double {
        notes.map { $0.at + attack + 5 * $0.decay }.max() ?? 0
    }

    /// The phrase as samples, its loudest note peaking near `level`.
    static func samples(_ notes: [SoundNote], level: Float, sampleRate: Double = 44_100) -> [Float] {
        let count = Int((length(notes) + 0.02) * sampleRate)
        guard count > 0 else { return [] }
        var out = [Float](repeating: 0, count: count)
        out.withUnsafeMutableBufferPointer { out in
            for note in notes {
                let first = Int(note.at * sampleRate)
                let frames = min(Int((attack + 5 * note.decay) * sampleRate), count - first)
                guard first >= 0, frames > 0 else { continue }
                // Each harmonic dies sooner than the one under it, so a note
                // opens bright and rounds off as it rings.
                let fall = exp(-1 / (note.decay * sampleRate))
                let fall2 = exp(-1 / (note.decay * 0.5 * sampleRate))
                let fall3 = exp(-1 / (note.decay * 0.3 * sampleRate))
                let settle = exp(-1 / (slide * sampleRate))
                var body = 1.0, second = 0.10, third = 0.03
                var offset = note.frequency * (note.bend - 1)
                var phase = 0.0
                // The last few milliseconds fade to nothing: no click where
                // the note is cut.
                let tail = Int(0.006 * sampleRate)
                for frame in 0..<frames {
                    let time = Double(frame) / sampleRate
                    let rise = time < attack ? 0.5 * (1 - cos(.pi * time / attack)) : 1
                    let close = frame > frames - tail ? Double(frames - frame) / Double(tail) : 1
                    let value = sin(phase) + second * sin(2 * phase) + third * sin(3 * phase)
                    out[first + frame] += Float(value * body * rise * close * note.gain) * level
                    phase += 2 * .pi * (note.frequency + offset) / sampleRate
                    offset *= settle
                    body *= fall
                    second *= fall2
                    third *= fall3
                }
            }
            // Notes landing together can add up past full scale.
            for index in 0..<count { out[index] = max(-0.98, min(0.98, out[index])) }
        }
        return out
    }

    static func buffer(_ notes: [SoundNote], level: Float, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let samples = samples(notes, level: level, sampleRate: format.sampleRate)
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }
}

/// What RAUTA's sounds are when they are made on the spot rather than played
/// from a file: a line it says, a thought while it works, a page arriving.
///
/// Every one is drawn afresh, so no two are the same, from a scale that keeps
/// them all in the family of the cues. The randomness is an argument, so what
/// comes out can be reasoned about without a speaker.
enum RautaPhrase {
    /// How a line is said: its register, its pace and which way it leans.
    enum Tone: Equatable {
        case plain
        /// Good news: higher, quicker, climbing.
        case bright
        /// Something refused or gone wrong: lower, slower, sinking.
        case low
        /// At work: a short even hum, the same note or its neighbour.
        case busy
    }

    /// A major pentatonic from E5 to A6: the key of the cues.
    static let voice: [Double] = [659.26, 739.99, 880.00, 987.77, 1108.73, 1318.51, 1479.98, 1760.00]
    /// G major pentatonic from D5 to D6: the key of the marimba that answers
    /// when the work is done.
    static let pondering: [Double] = [587.33, 659.26, 783.99, 880.00, 987.77, 1174.66]

    // MARK: Speaking

    /// A line as RAUTA says it: a note or two for each of its first words, in
    /// their rhythm, ending the way the sentence does — up for a question, high
    /// for an exclamation, down for a full stop.
    static func spoken(_ text: String, tone: Tone = .plain, using rng: inout some RandomNumberGenerator) -> [SoundNote] {
        let pace: Double
        let range: ClosedRange<Int>
        let steps: [Int]
        switch tone {
        case .plain: (pace, range, steps) = (0.085, 0...5, [-2, -1, -1, 1, 1, 2])
        case .bright: (pace, range, steps) = (0.072, 1...6, [-1, 1, 1, 2, 2])
        case .low: (pace, range, steps) = (0.105, 0...3, [-2, -1, -1, 1])
        case .busy: (pace, range, steps) = (0.1, 1...4, [-1, 1])
        }

        let sentence = Sentence(text)
        // At work RAUTA hums rather than talks.
        let beats = tone == .busy
            ? Array(repeating: Sentence.Beat(gap: 1), count: Int.random(in: 2...3, using: &rng))
            : sentence.beats
        let ending = tone == .busy ? Sentence.Ending.trailing : sentence.ending

        var degree = min(range.upperBound, max(range.lowerBound,
            (range.lowerBound + range.upperBound) / 2 + Int.random(in: -1...1, using: &rng)))
        var notes: [SoundNote] = []
        var time = 0.0
        for (index, beat) in beats.enumerated() {
            let last = index == beats.count - 1
            var bend = Double.random(in: 0.955...1.045, using: &rng)
            if last, index > 0 {
                // The last note is placed against the one before it, so the
                // sentence ends the way it reads.
                switch ending {
                case .question:
                    degree = min(range.upperBound, degree + Int.random(in: 1...2, using: &rng))
                    bend = 0.9
                case .exclamation:
                    degree = min(range.upperBound, max(degree + 1, range.upperBound - 1))
                    bend = 1
                case .trailing:
                    bend = 1.02
                case .stop:
                    degree = max(range.lowerBound, degree - Int.random(in: 1...2, using: &rng))
                    bend = 1.06
                }
            } else if index > 0 {
                let step = steps.randomElement(using: &rng) ?? 1
                degree = min(range.upperBound, max(range.lowerBound, degree + step))
            }
            notes.append(SoundNote(
                at: time,
                frequency: voice[degree],
                decay: last ? .random(in: 0.1...0.13, using: &rng) : .random(in: 0.04...0.055, using: &rng),
                gain: last || index == 0 ? 0.95 : .random(in: 0.6...0.85, using: &rng),
                bend: bend
            ))
            time += pace * beat.gap * .random(in: 0.88...1.14, using: &rng)
        }
        return notes
    }

    /// The opening of a line, as the rhythm of its words.
    struct Sentence {
        enum Ending { case stop, question, exclamation, trailing }

        struct Beat: Equatable {
            /// How long until the next beat, in beats: shorter inside a word,
            /// longer after a comma.
            var gap: Double
        }

        private(set) var beats: [Beat] = []
        private(set) var ending: Ending = .stop

        private static let longest = 8

        init(_ text: String) {
            for word in text.split(whereSeparator: \.isWhitespace) {
                let syllables = Self.syllables(word)
                guard syllables > 0 else { continue }
                // A long word is two notes close together; a short one, one.
                if syllables >= 3, beats.count < Self.longest - 1 { beats.append(Beat(gap: 0.62)) }
                beats.append(Beat(gap: word.last.map { ",;:—–".contains($0) } == true ? 1.8 : 1))
                // How it ends is how the last word taken ends. A sentence of a
                // word or two — "Nice." — runs on into the next, after a breath.
                ending = Self.ending(of: word) ?? .stop
                if Self.ending(of: word) != nil {
                    if beats.count >= 3 { break }
                    beats[beats.count - 1].gap = 1.8
                }
                if beats.count >= Self.longest { break }
            }
            if beats.isEmpty { beats = [Beat(gap: 1), Beat(gap: 1)] }
        }

        private static func ending(of word: Substring) -> Ending? {
            switch word.last(where: { !"\"'”’)".contains($0) }) {
            case "?": return .question
            case "!": return .exclamation
            case "…": return .trailing
            case ".": return word.hasSuffix("...") ? .trailing : .stop
            default: return nil
            }
        }

        /// Runs of vowels, near enough; a number or a lone consonant still
        /// counts as one.
        private static func syllables(_ word: Substring) -> Int {
            var count = 0
            var inVowels = false
            var spoken = false
            for character in word.lowercased() {
                if character.isLetter || character.isNumber { spoken = true }
                let vowel = "aeiouyäöåéèüõ".contains(character)
                if vowel, !inVowels { count += 1 }
                inVowels = vowel
            }
            return spoken ? max(1, count) : 0
        }
    }

    // MARK: Touching

    /// The small sounds of touching the app: a tick for a choice, a note that
    /// climbs as things are picked, a pair up or down as something opens or
    /// closes. Quiet, and like everything here, never quite the same twice.
    enum Touch: Equatable {
        /// A choice made: a chip, a segment, a day.
        case tick
        /// A button pressed.
        case tap
        /// A step forward that commits to something.
        case press
        /// Something weighty: a workout about to start.
        case thud
        case on, off
        /// An item joined a selection that now holds this many, or left one
        /// that still does. The note climbs and falls with the count.
        case pick(Int), drop(Int)
        /// A value nudged up or down.
        case up, down
        /// A page or sheet opened over this one, or closed back to it.
        case open, close
        case send
        case delete
        case success

        /// When one tap sets off several — a button that also opens a page —
        /// only the one that says most is heard.
        var rank: Int {
            switch self {
            case .tick: return 1
            case .tap: return 2
            case .up, .down: return 3
            case .on, .off: return 4
            case .press: return 5
            case .pick, .drop, .thud: return 6
            case .open, .close: return 7
            case .send, .delete: return 8
            case .success: return 9
            }
        }
    }

    /// The notes of a touch, and how loud its loudest is.
    static func touch(_ touch: Touch, using rng: inout some RandomNumberGenerator) -> (notes: [SoundNote], level: Float) {
        func pair(_ first: Int, _ second: Int, gap: Double, fade: Double = 1) -> [SoundNote] {
            [
                SoundNote(at: 0, frequency: voice[first], decay: .random(in: 0.025...0.032, using: &rng), gain: 0.75),
                SoundNote(at: gap * .random(in: 0.9...1.1, using: &rng), frequency: voice[second],
                          decay: .random(in: 0.05...0.06, using: &rng), gain: fade),
            ]
        }
        switch touch {
        case .tick:
            return ([SoundNote(at: 0, frequency: voice[Int.random(in: 2...4, using: &rng)],
                               decay: .random(in: 0.016...0.022, using: &rng))], 0.09)
        case .tap:
            return ([SoundNote(at: 0, frequency: voice[Int.random(in: 0...2, using: &rng)],
                               decay: .random(in: 0.03...0.04, using: &rng), bend: 0.95)], 0.11)
        case .press:
            let degree = Int.random(in: 1...3, using: &rng)
            return (pair(degree, degree + 1, gap: 0.045), 0.13)
        case .thud:
            return ([
                SoundNote(at: 0, frequency: 440, decay: .random(in: 0.07...0.09, using: &rng), bend: 1.25),
                SoundNote(at: 0, frequency: voice[0], decay: 0.04, gain: 0.4),
            ], 0.17)
        case .on:
            return (pair(2, 4, gap: 0.045), 0.12)
        case .off:
            return (pair(4, 2, gap: 0.045, fade: 0.6), 0.1)
        case .pick(let count):
            return ([SoundNote(at: 0, frequency: voice[(max(count, 1) - 1) % voice.count],
                               decay: .random(in: 0.045...0.055, using: &rng), bend: 0.93)], 0.14)
        case .drop(let count):
            return ([SoundNote(at: 0, frequency: voice[max(count, 0) % voice.count],
                               decay: .random(in: 0.035...0.045, using: &rng), gain: 0.8, bend: 1.07)], 0.11)
        case .up:
            return ([SoundNote(at: 0, frequency: voice[4], decay: .random(in: 0.018...0.024, using: &rng), bend: 0.96)], 0.09)
        case .down:
            return ([SoundNote(at: 0, frequency: voice[2], decay: .random(in: 0.018...0.024, using: &rng), bend: 1.04)], 0.09)
        case .open:
            return (pair(1, 3, gap: 0.04), 0.1)
        case .close:
            return (pair(3, 1, gap: 0.04, fade: 0.65), 0.085)
        case .send:
            return ([SoundNote(at: 0, frequency: voice[5], decay: .random(in: 0.06...0.08, using: &rng), bend: 0.72)], 0.13)
        case .delete:
            return ([
                SoundNote(at: 0, frequency: voice[2], decay: 0.04, gain: 0.85, bend: 1.08),
                SoundNote(at: .random(in: 0.065...0.08, using: &rng), frequency: voice[0], decay: 0.08, bend: 1.08),
            ], 0.13)
        case .success:
            let shapes = [[2, 4], [2, 4, 5], [0, 2, 4]]
            let shape = shapes.randomElement(using: &rng) ?? shapes[0]
            var time = 0.0
            let notes = shape.enumerated().map { index, degree in
                let last = index == shape.count - 1
                let note = SoundNote(at: time, frequency: voice[degree], decay: last ? 0.12 : 0.045,
                                     gain: last ? 1 : 0.75)
                time += .random(in: 0.065...0.08, using: &rng)
                return note
            }
            return (notes, 0.15)
        }
    }

    // MARK: Working

    /// One thought while RAUTA works: a note that wanders from the one before,
    /// now and then with a second just above it.
    static func thought(after degree: inout Int, using rng: inout some RandomNumberGenerator) -> [SoundNote] {
        let step = [-2, -1, 1, 1, 2].randomElement(using: &rng) ?? 1
        degree = min(pondering.count - 1, max(0, degree + step))
        var notes = [SoundNote(
            at: 0,
            frequency: pondering[degree],
            decay: .random(in: 0.16...0.24, using: &rng),
            gain: .random(in: 0.7...1, using: &rng)
        )]
        if Int.random(in: 0..<3, using: &rng) == 0, degree + 1 < pondering.count {
            notes.append(SoundNote(
                at: .random(in: 0.11...0.14, using: &rng),
                frequency: pondering[degree + 1],
                decay: 0.12,
                gain: 0.55
            ))
        }
        return notes
    }

    // MARK: Pages

    /// A page arriving, its cards rising one after another: three or four
    /// notes climbing, from a different place each time.
    static func arrival(using rng: inout some RandomNumberGenerator) -> [SoundNote] {
        var degree = Int.random(in: 0...2, using: &rng)
        let count = Int.random(in: 3...4, using: &rng)
        var time = 0.0
        return (0..<count).map { index in
            let last = index == count - 1
            let note = SoundNote(
                at: time,
                frequency: voice[degree],
                decay: last ? 0.2 : 0.09,
                gain: 0.55 + 0.45 * Double(index) / Double(count - 1)
            )
            time += .random(in: 0.065...0.085, using: &rng)
            degree = min(voice.count - 2, degree + Int.random(in: 1...2, using: &rng))
            return note
        }
    }

    /// The next step of something timed — the warm-up moving on: two notes,
    /// the second a little way above the first.
    static func step(using rng: inout some RandomNumberGenerator) -> [SoundNote] {
        let degree = Int.random(in: 1...3, using: &rng)
        return [
            SoundNote(at: 0, frequency: voice[degree], decay: 0.1, gain: 0.85),
            SoundNote(at: .random(in: 0.12...0.15, using: &rng), frequency: voice[degree + 2], decay: 0.26, gain: 1),
        ]
    }

    /// One step further through a run of pages: a note that slides up into
    /// place, higher the further along it is.
    static func progress(_ index: Int, using rng: inout some RandomNumberGenerator) -> [SoundNote] {
        [SoundNote(
            at: 0,
            frequency: voice[min(voice.count - 2, max(0, index))],
            decay: .random(in: 0.06...0.08, using: &rng),
            gain: 1,
            bend: .random(in: 0.9...0.94, using: &rng)
        )]
    }

    /// The app opening: stray dots coming on, quicker and louder as the ring
    /// closes; a warm pair as RAUTA appears; five small steps up as its name
    /// rises; and a soft drop as it lands in its seat.
    static func launch(arrival: Double, landing: Double, using rng: inout some RandomNumberGenerator) -> [SoundNote] {
        var notes: [SoundNote] = []
        let dots = Int.random(in: 5...7, using: &rng)
        for dot in 0..<dots {
            let along = Double(dot) / Double(dots)
            notes.append(SoundNote(
                at: 0.15 + (arrival - 0.25) * (1 - pow(1 - along, 1.8)),
                frequency: voice[Int.random(in: 3...7, using: &rng)],
                decay: 0.03,
                gain: 0.22 + 0.3 * along
            ))
        }

        let answer = [2, 4, 5].randomElement(using: &rng) ?? 2
        notes += [
            SoundNote(at: arrival, frequency: 440, decay: 0.45, gain: 1),
            SoundNote(at: arrival, frequency: voice[0], decay: 0.4, gain: 0.7),
            SoundNote(at: arrival + 0.13, frequency: voice[answer], decay: 0.42, gain: 0.85),
        ]

        var degree = Int.random(in: 0...2, using: &rng)
        for letter in 0..<5 {
            notes.append(SoundNote(at: arrival + 0.35 + 0.06 * Double(letter), frequency: voice[degree], decay: 0.035, gain: 0.3))
            degree += 1
        }

        notes.append(SoundNote(at: landing - 0.08, frequency: voice[0], decay: 0.09, gain: 0.6, bend: 1.5))
        return notes
    }
}

extension RautaPhrase.Tone {
    /// How RAUTA says a line it is showing, from how it looks saying it.
    init(reaction: RautaReaction?, mood: RautaMood?) {
        switch reaction {
        case .celebrate, .laugh, .wink, .relieved: self = .bright
        case .frustrated, .recoil, .wobble: self = .low
        case .gearUp: self = .busy
        default: self = mood == .working || mood == .thinking ? .busy : .plain
        }
    }
}
