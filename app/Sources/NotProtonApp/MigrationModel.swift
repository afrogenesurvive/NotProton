// State that drives the Games pane.

import Foundation
import Observation

@MainActor
@Observable
final class MigrationModel {

    enum OutcomeKind { case ok, warning, error }

    private(set) var windowsGames: [WindowsGame] = []
    private(set) var libraryGames: [LibraryGame] = []
    private(set) var saveMoves: [SaveMove] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var isCopying = false
    private(set) var outcome: String?
    private(set) var outcomeKind: OutcomeKind = .ok

    var dryRun = true

    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        let (win, lib) = await Task.detached {
            (MigrationStore.windowsGames(), MigrationStore.libraryGames())
        }.value
        windowsGames = win
        libraryGames = lib
        saveMoves = MigrationStore.saveMoves()
    }

    func forgetOutcome() {
        outcome = nil
    }

    func migrate() async {
        isCopying = true
        defer { isCopying = false }
        let dry = dryRun
        do {
            let result = try await Task.detached {
                try MigrationStore.copySaves(MigrationStore.saveMoves(), dryRun: dry)
            }.value
            (outcome, outcomeKind) = Self.summarize(result, dryRun: dry)
        } catch {
            outcome = "Copy failed: \(error.localizedDescription)"
            outcomeKind = .error
        }
    }

    private static func summarize(_ result: MigrationStore.CopyResult, dryRun: Bool) -> (String, OutcomeKind) {
        if dryRun {
            let pending = result.skippedNoPrefix.count
            let suffix = pending > 0 ? " \(pending) need a prefix first (launch the game once)." : ""
            return ("Dry run: \(result.copied.count) save folder(s) would be copied.\(suffix)", .ok)
        }
        var parts: [String] = ["Copied \(result.copied.count) save folder(s)."]
        if !result.skippedNoPrefix.isEmpty {
            parts.append("\(result.skippedNoPrefix.count) skipped (no prefix yet — launch the game once).")
        }
        if !result.skippedMissingSource.isEmpty {
            parts.append("\(result.skippedMissingSource.count) skipped (source not found).")
        }
        let kind: OutcomeKind = (result.skippedNoPrefix.isEmpty && result.skippedMissingSource.isEmpty) ? .ok : .warning
        return (parts.joined(separator: " "), kind)
    }
}
