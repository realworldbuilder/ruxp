import Foundation

final class StoryReadTracker {
    static let shared = StoryReadTracker()
    private let userDefaults = UserDefaults.standard
    private let readStoriesKey = "readInsightStories"
    private let contentHashKey = "insightStoryContentHashes"

    private init() {}

    func isRead(_ storyIdentifier: String) -> Bool {
        let readStories = userDefaults.stringArray(forKey: readStoriesKey) ?? []
        return readStories.contains(storyIdentifier)
    }

    func hasContentChanged(for storyIdentifier: String, newHash: Int) -> Bool {
        let hashes = userDefaults.dictionary(forKey: contentHashKey) as? [String: Int] ?? [:]
        guard let storedHash = hashes[storyIdentifier] else { return true }
        return storedHash != newHash
    }

    func isUnread(_ storyIdentifier: String, contentHash: Int) -> Bool {
        if !isRead(storyIdentifier) { return true }
        return hasContentChanged(for: storyIdentifier, newHash: contentHash)
    }

    func markAsRead(_ storyIdentifier: String, contentHash: Int) {
        var readStories = userDefaults.stringArray(forKey: readStoriesKey) ?? []
        if !readStories.contains(storyIdentifier) {
            readStories.append(storyIdentifier)
            userDefaults.set(readStories, forKey: readStoriesKey)
        }
        var hashes = userDefaults.dictionary(forKey: contentHashKey) as? [String: Int] ?? [:]
        hashes[storyIdentifier] = contentHash
        userDefaults.set(hashes, forKey: contentHashKey)
    }

    func markAsRead(_ storyIdentifier: String) {
        var readStories = userDefaults.stringArray(forKey: readStoriesKey) ?? []
        if !readStories.contains(storyIdentifier) {
            readStories.append(storyIdentifier)
            userDefaults.set(readStories, forKey: readStoriesKey)
        }
    }
}
