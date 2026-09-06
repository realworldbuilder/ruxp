import Foundation
import os

@Observable
@MainActor
final class WorkoutStore {
    private static let logger = Logger(subsystem: "com.whussey.ruxp", category: "WorkoutStore")

    private(set) var index: [WorkoutSessionIndex] = []

    private let fileManager = FileManager.default

    private var workoutsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("workouts", isDirectory: true)
    }

    private var indexFileURL: URL {
        workoutsDirectory.appendingPathComponent("index.json")
    }

    private static let currentIndexVersion = 2

    init() {
        ensureDirectoryExists(workoutsDirectory)
        loadIndex()
        migrateIndexIfNeeded()
    }

    // MARK: - Index

    func loadIndex() {
        guard fileManager.fileExists(atPath: indexFileURL.path) else {
            index = []
            return
        }
        do {
            let data = try Data(contentsOf: indexFileURL)
            index = try JSONDecoder().decode([WorkoutSessionIndex].self, from: data)
            index.sort { $0.startedAt > $1.startedAt }
        } catch {
            Self.logger.error("Failed to load index: \(error)")
            index = []
        }
    }

    private func saveIndex() {
        do {
            let data = try JSONEncoder().encode(index)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save index: \(error)")
        }
    }

    // MARK: - Session CRUD

    func saveSession(_ session: WorkoutSession) {
        let sessionDir = workoutsDirectory.appendingPathComponent(session.id.uuidString, isDirectory: true)
        ensureDirectoryExists(sessionDir)

        let sessionFile = sessionDir.appendingPathComponent("session.json")
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(session)
            try data.write(to: sessionFile, options: .atomic)
        } catch {
            Self.logger.error("Failed to save session: \(error)")
            return
        }

        let entry = WorkoutSessionIndex(from: session)
        if let existingIndex = index.firstIndex(where: { $0.id == session.id }) {
            index[existingIndex] = entry
        } else {
            index.insert(entry, at: 0)
        }
        index.sort { $0.startedAt > $1.startedAt }
        saveIndex()
    }

    func loadSession(id: UUID) -> WorkoutSession? {
        let sessionFile = workoutsDirectory
            .appendingPathComponent(id.uuidString, isDirectory: true)
            .appendingPathComponent("session.json")

        guard fileManager.fileExists(atPath: sessionFile.path) else { return nil }

        do {
            let data = try Data(contentsOf: sessionFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(WorkoutSession.self, from: data)
        } catch {
            Self.logger.error("Failed to load session \(id): \(error)")
            return nil
        }
    }

    func deleteSession(id: UUID) {
        let sessionDir = workoutsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try? fileManager.removeItem(at: sessionDir)
        index.removeAll { $0.id == id }
        saveIndex()
    }

    func deleteAllData() {
        if let contents = try? fileManager.contentsOfDirectory(
            at: workoutsDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) {
            for item in contents {
                try? fileManager.removeItem(at: item)
            }
        }
        index = []
        UserDefaults.standard.removeObject(forKey: "workoutIndexVersion")
        Self.logger.info("All workout data deleted")
    }

    func exportAllSessionsAsJSON() -> Data? {
        var sessions: [WorkoutSession] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for entry in index {
            let sessionFile = workoutsDirectory
                .appendingPathComponent(entry.id.uuidString, isDirectory: true)
                .appendingPathComponent("session.json")
            guard let data = try? Data(contentsOf: sessionFile),
                  let session = try? decoder.decode(WorkoutSession.self, from: data) else {
                continue
            }
            sessions.append(session)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(sessions)
    }

    // MARK: - Audio Files

    func storeAudioFile(from sourceURL: URL, momentID: UUID, workoutID: UUID) -> URL? {
        let audioDir = workoutsDirectory
            .appendingPathComponent(workoutID.uuidString, isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
        ensureDirectoryExists(audioDir)

        let destURL = audioDir.appendingPathComponent("\(momentID.uuidString).wav")
        do {
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destURL)
            return destURL
        } catch {
            Self.logger.error("Failed to store audio file: \(error)")
            return nil
        }
    }

    func audioFileURL(momentID: UUID, workoutID: UUID) -> URL {
        workoutsDirectory
            .appendingPathComponent(workoutID.uuidString, isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("\(momentID.uuidString).wav")
    }

    // MARK: - Legacy Migration

    func migrateFromLegacyTranscriptions() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let legacyFile = docs.appendingPathComponent("transcriptions.json")

        guard fileManager.fileExists(atPath: legacyFile.path) else { return }

        do {
            let data = try Data(contentsOf: legacyFile)
            let records = try JSONDecoder().decode([LegacyTranscriptionRecord].self, from: data)

            guard !records.isEmpty else {
                try? fileManager.removeItem(at: legacyFile)
                return
            }

            let moments = records.map { record in
                Moment(
                    id: record.id,
                    timestamp: record.timestamp,
                    transcript: record.text,
                    source: .phone,
                    tags: ["legacy"],
                    confidence: 1.0
                )
            }

            let sortedMoments = moments.sorted { $0.timestamp < $1.timestamp }
            let session = WorkoutSession(
                startedAt: sortedMoments.first?.timestamp ?? Date(),
                endedAt: sortedMoments.last?.timestamp ?? Date(),
                moments: sortedMoments
            )

            saveSession(session)

            // Remove legacy file after successful migration
            try fileManager.removeItem(at: legacyFile)
            Self.logger.info("Migrated \(records.count) legacy transcriptions")
        } catch {
            Self.logger.error("Failed to migrate legacy transcriptions: \(error)")
        }
    }

    // MARK: - Index Migration

    private func migrateIndexIfNeeded() {
        let currentVersion = UserDefaults.standard.integer(forKey: "workoutIndexVersion")
        guard currentVersion < Self.currentIndexVersion else { return }
        rebuildIndex()
        UserDefaults.standard.set(Self.currentIndexVersion, forKey: "workoutIndexVersion")
    }

    func rebuildIndex() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: workoutsDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        var rebuilt: [WorkoutSessionIndex] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for dir in contents where dir.hasDirectoryPath {
            let sessionFile = dir.appendingPathComponent("session.json")
            guard fileManager.fileExists(atPath: sessionFile.path),
                  let data = try? Data(contentsOf: sessionFile),
                  let session = try? decoder.decode(WorkoutSession.self, from: data) else {
                continue
            }
            rebuilt.append(WorkoutSessionIndex(from: session))
        }

        rebuilt.sort { $0.startedAt > $1.startedAt }
        index = rebuilt
        saveIndex()
        Self.logger.info("Rebuilt index with \(rebuilt.count) entries")
    }

    // MARK: - Helpers

    private func ensureDirectoryExists(_ url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
