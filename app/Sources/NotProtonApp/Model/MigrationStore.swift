// Data for the Games pane: Windows games installed in CrossOver, games in the
// Mac Steam libraries, and the known save folders that can be copied across.

import Foundation

struct WindowsGame: Identifiable, Hashable, Sendable {
    let appID: String
    let name: String
    let installDir: String
    let bottle: String
    let bytes: Int64?

    var id: String { appID }
}

struct LibraryGame: Identifiable, Hashable, Sendable {
    let appID: String
    let name: String
    let libraryRoot: String

    var id: String { "\(libraryRoot)#\(appID)" }
}

struct SaveMove: Identifiable, Hashable, Sendable {
    let appID: String
    let gameName: String
    let source: URL
    let destinationRelativePath: String

    var id: String { "\(appID)#\(destinationRelativePath)" }
}

enum MigrationStore {

    struct CopyResult: Sendable {
        let copied: [SaveMove]
        let skippedNoPrefix: [SaveMove]
        let skippedMissingSource: [SaveMove]
    }

    static var bottlesRoot: URL {
        SupportPaths.applicationSupport.appending(path: "CrossOver/Bottles")
    }

    static func bottles() -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: bottlesRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func steamapps(in bottle: URL) -> URL {
        bottle.appending(path: "drive_c/Program Files (x86)/Steam/steamapps")
    }

    static func windowsGames() -> [WindowsGame] {
        var games: [WindowsGame] = []
        for bottle in bottles() {
            let steamapps = steamapps(in: bottle)
            let manifests = (try? FileManager.default.contentsOfDirectory(
                at: steamapps, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []
            for manifest in manifests where manifest.lastPathComponent.hasPrefix("appmanifest_") {
                let appID = manifest.lastPathComponent
                    .replacingOccurrences(of: "appmanifest_", with: "")
                    .replacingOccurrences(of: ".acf", with: "")
                guard let text = try? String(contentsOf: manifest, encoding: .utf8) else { continue }
                let name = field("name", in: text) ?? "App \(appID)"
                let installDir = field("installdir", in: text) ?? ""
                let bytes = installDir.isEmpty
                    ? nil
                    : sizeOfDirectory(steamapps.appending(path: "common").appending(path: installDir))
                games.append(WindowsGame(
                    appID: appID, name: name, installDir: installDir,
                    bottle: bottle.lastPathComponent, bytes: bytes
                ))
            }
        }
        return games.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func libraryGames() -> [LibraryGame] {
        var games: [LibraryGame] = []
        for library in PrefixStore.libraries() {
            let manifests = (try? FileManager.default.contentsOfDirectory(
                at: library.steamapps, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []
            for manifest in manifests where manifest.lastPathComponent.hasPrefix("appmanifest_") {
                let appID = manifest.lastPathComponent
                    .replacingOccurrences(of: "appmanifest_", with: "")
                    .replacingOccurrences(of: ".acf", with: "")
                guard let text = try? String(contentsOf: manifest, encoding: .utf8) else { continue }
                let name = field("name", in: text) ?? "App \(appID)"
                games.append(LibraryGame(
                    appID: appID, name: name, libraryRoot: library.root.path(percentEncoded: false)
                ))
            }
        }
        return games.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func saveMoves() -> [SaveMove] {
        let docs = SupportPaths.home.appending(path: "Documents")
        var candidates: [SaveMove] = []

        candidates.append(SaveMove(
            appID: "212680", gameName: "FTL: Faster Than Light",
            source: docs.appending(path: "My Games/FasterThanLight"),
            destinationRelativePath: "Documents/My Games/FasterThanLight"
        ))
        candidates.append(SaveMove(
            appID: "4346510", gameName: "Underkeep Demo",
            source: docs.appending(path: "Underkeep Demo"),
            destinationRelativePath: "Documents/Underkeep Demo"
        ))

        for bottle in bottles() {
            let profile = bottle.appending(path: "drive_c/users/crossover")
            candidates.append(SaveMove(
                appID: "212680", gameName: "FTL: Faster Than Light",
                source: profile.appending(path: "AppData/Roaming/FasterThanLight"),
                destinationRelativePath: "AppData/Roaming/FasterThanLight"
            ))
            candidates.append(SaveMove(
                appID: "2200120", gameName: "Mars Tactics Playtest",
                source: profile.appending(path: "AppData/LocalLow/Takibi Games/Mars Tactics"),
                destinationRelativePath: "AppData/LocalLow/Takibi Games/Mars Tactics"
            ))
            candidates.append(SaveMove(
                appID: "2898880", gameName: "Mecha Simultactics Alpha",
                source: profile.appending(path: "AppData/LocalLow/RJArcade/MechaSimultactics"),
                destinationRelativePath: "AppData/LocalLow/RJArcade/MechaSimultactics"
            ))
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.id).inserted }
    }

    static func prefixURL(for appID: String) -> URL? {
        for library in PrefixStore.libraries() {
            let pfx = library.compatdata.appending(path: appID).appending(path: "pfx")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: pfx.path(percentEncoded: false), isDirectory: &isDir),
                isDir.boolValue {
                return pfx
            }
        }
        return nil
    }

    static func copySaves(_ moves: [SaveMove], dryRun: Bool) throws -> CopyResult {
        var copied: [SaveMove] = []
        var noPrefix: [SaveMove] = []
        var missingSource: [SaveMove] = []

        for move in moves {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: move.source.path(percentEncoded: false), isDirectory: &isDir) else {
                missingSource.append(move)
                continue
            }
            guard let pfx = prefixURL(for: move.appID) else {
                noPrefix.append(move)
                continue
            }
            if !dryRun {
                let dest = pfx.appending(path: "drive_c/users/steamuser").appending(path: move.destinationRelativePath)
                try copyTree(from: move.source, to: dest)
            }
            copied.append(move)
        }

        return CopyResult(copied: copied, skippedNoPrefix: noPrefix, skippedMissingSource: missingSource)
    }

    // Recursive copy that merges into an existing destination, matching `cp -Rp`.
    private static func copyTree(from source: URL, to dest: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: source.path(percentEncoded: false), isDirectory: &isDir) else { return }

        if !isDir.boolValue {
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path(percentEncoded: false)) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: source, to: dest)
            return
        }

        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let children = (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for child in children {
            try copyTree(from: child, to: dest.appending(path: child.lastPathComponent))
        }
    }

    private static func field(_ key: String, in text: String) -> String? {
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "\"").map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if fields.count >= 2, fields[0] == key { return fields[1] }
        }
        return nil
    }

    private static func sizeOfDirectory(_ url: URL) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
        ) else { return nil }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey]) else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
