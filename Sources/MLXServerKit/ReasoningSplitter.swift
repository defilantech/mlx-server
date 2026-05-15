import Foundation

/// How the server separates a model's thinking output from its answer.
public enum ReasoningMode: String, Sendable {
    /// Start in the answer; a literal `<think>` opens a reasoning block and
    /// `</think>` closes it. Safe for non-reasoning models (no markers ever
    /// appear, so everything stays in the answer).
    case auto
    /// Start already inside reasoning — the chat template prefilled the
    /// opening `<think>`, so generated output begins mid-thought. `</think>`
    /// switches to the answer. Use for Qwen3.5 / Qwen3.6.
    case prefilled
    /// No splitting; all output is the answer.
    case off
}

/// Streaming splitter that classifies model output into reasoning vs. answer
/// text by tracking `<think>` / `</think>` markers.
///
/// Marker-safe across chunk boundaries: a partial marker at a chunk edge is
/// held back until the next chunk completes (or fails to complete) it.
struct ReasoningSplitter {
    /// Text classified out of a `push` or `flush` call.
    struct Split: Equatable {
        var reasoning = ""
        var content = ""
    }

    private static let openMarker = "<think>"
    private static let closeMarker = "</think>"

    private enum Phase { case reasoning, content }
    private var phase: Phase
    /// True while a `<think>` opener could still appear.
    private var watchingForOpen: Bool
    private let mode: ReasoningMode
    /// Holds a possible partial marker straddling a chunk boundary.
    private var pending = ""

    init(mode: ReasoningMode) {
        self.mode = mode
        switch mode {
        case .auto:
            phase = .content
            watchingForOpen = true
        case .prefilled:
            phase = .reasoning
            watchingForOpen = false
        case .off:
            phase = .content
            watchingForOpen = false
        }
    }

    /// The marker currently being scanned for, or `nil` when none applies.
    private var activeMarker: String? {
        if watchingForOpen { return Self.openMarker }
        if phase == .reasoning { return Self.closeMarker }
        return nil
    }

    /// Feed a chunk of model output; returns the text split by phase.
    mutating func push(_ text: String) -> Split {
        var split = Split()
        guard mode != .off else {
            split.content = text
            return split
        }

        var work = pending + text
        pending = ""

        while let marker = activeMarker {
            if let range = work.range(of: marker) {
                emit(String(work[work.startIndex..<range.lowerBound]), into: &split)
                work = String(work[range.upperBound...])
                advancePhase(after: marker)
            } else {
                // No complete marker — emit everything except a trailing
                // suffix that could be the start of the marker.
                let hold = partialMarkerSuffixLength(of: work, marker: marker)
                emit(String(work.dropLast(hold)), into: &split)
                pending = String(work.suffix(hold))
                return split
            }
        }

        // No active marker: the answer phase with nothing left to find.
        emit(work, into: &split)
        return split
    }

    /// Emit any held-back text once generation has finished.
    mutating func flush() -> Split {
        var split = Split()
        emit(pending, into: &split)
        pending = ""
        return split
    }

    private func emit(_ text: String, into split: inout Split) {
        guard !text.isEmpty else { return }
        switch phase {
        case .reasoning: split.reasoning += text
        case .content: split.content += text
        }
    }

    private mutating func advancePhase(after marker: String) {
        phase = (marker == Self.openMarker) ? .reasoning : .content
        watchingForOpen = false
    }

    /// Length of the longest suffix of `text` that is a proper prefix of `marker`.
    private func partialMarkerSuffixLength(of text: String, marker: String) -> Int {
        var length = min(text.count, marker.count - 1)
        while length > 0 {
            if marker.hasPrefix(text.suffix(length)) {
                return length
            }
            length -= 1
        }
        return 0
    }
}
