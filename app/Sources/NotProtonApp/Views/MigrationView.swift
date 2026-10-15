// The Games pane: lists CrossOver and Steam library games and copies known saves.

import SwiftUI

struct MigrationView: View {

    @Environment(MigrationModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if !model.hasLoaded {
                ProgressView("Looking for games")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .navigationTitle("Games")
        .safeAreaInset(edge: .bottom) {
            if let outcome = model.outcome {
                StatusRow(title: "Migration", value: outcome, tone: tone(for: model.outcomeKind))
                    .padding(12)
                    .background(.regularMaterial)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle("Dry run", isOn: $model.dryRun)
                    .toggleStyle(.checkbox)
                    .help("Preview the save copy without writing anything.")
                Button(model.isCopying ? "Copying…" : "Copy Saves") {
                    Task { await model.migrate() }
                }
                .disabled(model.isCopying || model.saveMoves.isEmpty)
            }
        }
        .task { if !model.hasLoaded { await model.load() } }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                instructions
                windowsSection
                librarySection
                savesSection
            }
            .padding()
        }
    }

    private var instructions: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text("Windows games installed through CrossOver can run here without re-downloading: copy the game folder and its appmanifest into a Steam library, force the compatibility tool on the game, then copy your saves into each game's prefix.")
                    .foregroundStyle(.secondary)
                Text("Saves are copied, never moved — CrossOver is left untouched.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label("About", systemImage: "info.circle")
        }
    }

    private var windowsSection: some View {
        GroupBox {
            if model.windowsGames.isEmpty {
                Text("No Windows games found in CrossOver.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.windowsGames) { game in
                        HStack {
                            Text(game.name)
                            Spacer()
                            Text(game.appID)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            if let bytes = game.bytes {
                                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(4)
            }
        } label: {
            Label("CrossOver Windows games", systemImage: "externaldrive")
        }
    }

    private var librarySection: some View {
        GroupBox {
            if model.libraryGames.isEmpty {
                Text("No games found in Steam libraries.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.libraryGames) { game in
                        HStack {
                            Text(game.name)
                            Spacer()
                            Text(game.appID)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(4)
            }
        } label: {
            Label("Steam library", systemImage: "books.vertical")
        }
    }

    private var savesSection: some View {
        GroupBox {
            if model.saveMoves.isEmpty {
                Text("No known save folders to copy.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.saveMoves) { move in
                        HStack(alignment: .firstTextBaseline) {
                            Text(move.gameName)
                                .fontWeight(.medium)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(move.source.path(percentEncoded: false))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down")
                                        .foregroundStyle(.secondary)
                                    Text(move.destinationRelativePath)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
                .padding(4)
            }
        } label: {
            Label("Known saves", systemImage: "doc.on.doc")
        }
    }

    private func tone(for kind: MigrationModel.OutcomeKind) -> StatusTone? {
        switch kind {
        case .ok: return .ok
        case .warning: return .warning
        case .error: return .bad
        }
    }
}
