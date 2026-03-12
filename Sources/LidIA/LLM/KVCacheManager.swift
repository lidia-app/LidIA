import Foundation
import MLX
import MLXLMCommon
import Synchronization
import os

/// Manages KV cache persistence across LLM requests for local MLX models.
///
/// Two-tier architecture:
/// - **Hot (GPU memory):** Active conversation caches stay resident. Follow-up messages
///   only process new tokens — the shared prefix (system prompt + meeting context) is cached.
/// - **Cold (SSD):** When hot tier is full, evicted caches serialize to disk. Restoring
///   from SSD (~100ms) is much faster than reprocessing (~3s).
///
/// Cache keys are computed from `(modelID, contextHash)` where contextHash is derived
/// from the system prompt + meeting context. Same meeting = same prefix = cache hit.
///
/// Thread-safe via Mutex — all mutable state is protected by a single lock.
final class KVCacheManager: Sendable {

    private static let logger = Logger(subsystem: "io.lidia.app", category: "KVCacheManager")

    // MARK: - Types

    struct CacheKey: Hashable, Sendable {
        let modelID: String
        let contextHash: UInt64
    }

    /// Wraps [any KVCache] for storage outside of ModelContainer.perform{} blocks.
    /// Safe because access is serialized: KVCacheManager methods are only called
    /// from within perform{} or sequentially by MLXLocalClient.
    final class CacheEntry: @unchecked Sendable {
        var cache: [any KVCache]
        /// Number of tokens processed into this cache (prefix length).
        var tokenCount: Int
        var lastAccessed: Date

        init(cache: [any KVCache], tokenCount: Int) {
            self.cache = cache
            self.tokenCount = tokenCount
            self.lastAccessed = Date()
        }
    }

    // MARK: - Synchronized State

    /// All mutable state is collected into a single struct and protected by a Mutex.
    private struct State {
        /// Hot cache: keyed by (modelID, contextHash), holds GPU-resident KV caches.
        var hotCache: [CacheKey: CacheEntry] = [:]
        /// Access order for LRU eviction.
        var accessOrder: [CacheKey] = []
        /// Manifest tracking cold-tier entries.
        var coldManifest: [CacheKey: ColdEntry] = [:]
    }

    private let state = Mutex(State())

    /// Maximum number of hot cache entries (GPU memory).
    private let maxHotEntries = 2

    // MARK: - Cold Tier

    private let coldCacheDir: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("lidia-kv", isDirectory: true)
    }()

    /// Maximum cold tier size in bytes (500 MB).
    private let maxColdBytes: Int = 500 * 1024 * 1024

    struct ColdEntry: Codable {
        let filename: String
        var lastAccessed: Date
        var sizeBytes: Int
    }

    // MARK: - Init

    init() {
        loadColdManifest()
    }

    // MARK: - Public API

    /// Look up a hot cache entry for the given key. Returns nil on miss.
    func getHot(_ key: CacheKey) -> CacheEntry? {
        state.withLock { s in
            guard let entry = s.hotCache[key] else { return nil }
            entry.lastAccessed = Date()
            s.accessOrder.removeAll { $0 == key }
            s.accessOrder.append(key)
            Self.logger.info("KV cache hot hit: \(key.modelID) ctx=\(key.contextHash)")
            return entry
        }
    }

    /// Try to restore a cache from the cold tier. Returns nil if not found on disk.
    func getCold(_ key: CacheKey) -> CacheEntry? {
        let coldEntry: ColdEntry? = state.withLock { s in
            s.coldManifest[key]
        }
        guard let cold = coldEntry else { return nil }
        let url = coldCacheDir.appendingPathComponent(cold.filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            state.withLock { _ = $0.coldManifest.removeValue(forKey: key) }
            return nil
        }

        do {
            let (cache, _) = try loadPromptCache(url: url)
            let tokenCount = cache.first?.offset ?? 0
            let entry = CacheEntry(cache: cache, tokenCount: tokenCount)

            // Promote to hot
            storeHot(key, entry: entry)

            // Remove from cold
            try? FileManager.default.removeItem(at: url)
            state.withLock { _ = $0.coldManifest.removeValue(forKey: key) }
            saveColdManifest()

            Self.logger.info("KV cache cold hit: \(key.modelID) ctx=\(key.contextHash), \(tokenCount) tokens restored")
            return entry
        } catch {
            Self.logger.error("Failed to load cold cache: \(error)")
            return nil
        }
    }

    /// Store a cache entry in the hot tier, evicting oldest if at capacity.
    func storeHot(_ key: CacheKey, entry: CacheEntry) {
        state.withLock { s in
            // Evict oldest if at capacity
            if s.hotCache.count >= self.maxHotEntries && s.hotCache[key] == nil {
                Self.evictOldestHot(state: &s, coldCacheDir: self.coldCacheDir, maxColdBytes: self.maxColdBytes)
            }

            s.hotCache[key] = entry
            s.accessOrder.removeAll { $0 == key }
            s.accessOrder.append(key)
            Self.logger.debug("KV cache stored hot: \(key.modelID) ctx=\(key.contextHash), \(entry.tokenCount) tokens")
        }
    }

    /// Evict all hot caches (e.g., under memory pressure).
    func evictAllHot() {
        let entries: [(CacheKey, CacheEntry)] = state.withLock { s in
            let result = Array(s.hotCache)
            s.hotCache.removeAll()
            s.accessOrder.removeAll()
            return result
        }
        for (key, entry) in entries {
            evictToCold(key: key, entry: entry)
        }
        Self.logger.info("All hot caches evicted")
    }

    /// Evict hot caches without saving to cold (extreme memory pressure).
    func dropAllHot() {
        state.withLock { s in
            s.hotCache.removeAll()
            s.accessOrder.removeAll()
        }
        Self.logger.info("All hot caches dropped (no cold save)")
    }

    /// Clear everything — hot and cold.
    func clearAll() {
        state.withLock { s in
            s.hotCache.removeAll()
            s.accessOrder.removeAll()
            s.coldManifest.removeAll()
        }
        try? FileManager.default.removeItem(at: coldCacheDir)
        Self.logger.info("All KV caches cleared")
    }

    // MARK: - Cache Key Computation

    /// Compute a cache key from model ID and the prefix context string.
    /// The prefix is typically: system prompt + meeting context (everything before
    /// conversation history and the user's current message).
    static func cacheKey(modelID: String, prefix: String) -> CacheKey {
        CacheKey(modelID: modelID, contextHash: fnv1a(prefix))
    }

    // MARK: - Private: Hot Tier Management

    /// Evict the oldest hot entry to cold. Called inside withLock.
    private static func evictOldestHot(state s: inout State, coldCacheDir: URL, maxColdBytes: Int) {
        guard let oldestKey = s.accessOrder.first else { return }
        if let entry = s.hotCache.removeValue(forKey: oldestKey) {
            // Evict to cold outside the lock is not feasible here since we need
            // the state, so we do a minimal cold write inline.
            Self.evictToColdInline(key: oldestKey, entry: entry, state: &s, coldCacheDir: coldCacheDir, maxColdBytes: maxColdBytes)
        }
        s.accessOrder.removeFirst()
    }

    /// Inline cold eviction that operates on the State struct directly (called inside withLock).
    private static func evictToColdInline(key: CacheKey, entry: CacheEntry, state s: inout State, coldCacheDir: URL, maxColdBytes: Int) {
        if !FileManager.default.fileExists(atPath: coldCacheDir.path) {
            try? FileManager.default.createDirectory(at: coldCacheDir, withIntermediateDirectories: true)
        }

        let filename = "\(key.modelID.replacingOccurrences(of: "/", with: "_"))_\(key.contextHash).safetensors"
        let url = coldCacheDir.appendingPathComponent(filename)

        do {
            try savePromptCache(url: url, cache: entry.cache, metadata: [
                "modelID": key.modelID,
                "contextHash": String(key.contextHash),
                "tokenCount": String(entry.tokenCount),
            ])
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            s.coldManifest[key] = ColdEntry(filename: filename, lastAccessed: entry.lastAccessed, sizeBytes: size)
            Self.enforceColdSizeLimitInline(state: &s, coldCacheDir: coldCacheDir, maxColdBytes: maxColdBytes)
            Self.logger.info("Evicted to cold: \(key.modelID) ctx=\(key.contextHash), \(size) bytes")
        } catch {
            Self.logger.error("Failed to save cold cache: \(error)")
        }
    }

    private static func enforceColdSizeLimitInline(state s: inout State, coldCacheDir: URL, maxColdBytes: Int) {
        var totalSize = s.coldManifest.values.reduce(0) { $0 + $1.sizeBytes }
        guard totalSize > maxColdBytes else { return }

        let sorted = s.coldManifest.sorted { $0.value.lastAccessed < $1.value.lastAccessed }
        for (key, entry) in sorted {
            guard totalSize > maxColdBytes else { break }
            let url = coldCacheDir.appendingPathComponent(entry.filename)
            try? FileManager.default.removeItem(at: url)
            totalSize -= entry.sizeBytes
            s.coldManifest.removeValue(forKey: key)
            Self.logger.debug("Cold eviction: removed \(entry.filename)")
        }
    }

    // MARK: - Private: Cold Tier Management (outside lock)

    private func evictToCold(key: CacheKey, entry: CacheEntry) {
        ensureColdDir()

        let filename = "\(key.modelID.replacingOccurrences(of: "/", with: "_"))_\(key.contextHash).safetensors"
        let url = coldCacheDir.appendingPathComponent(filename)

        do {
            try savePromptCache(url: url, cache: entry.cache, metadata: [
                "modelID": key.modelID,
                "contextHash": String(key.contextHash),
                "tokenCount": String(entry.tokenCount),
            ])
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            state.withLock { s in
                s.coldManifest[key] = ColdEntry(filename: filename, lastAccessed: entry.lastAccessed, sizeBytes: size)
            }
            saveColdManifest()
            enforceColdSizeLimit()
            Self.logger.info("Evicted to cold: \(key.modelID) ctx=\(key.contextHash), \(size) bytes")
        } catch {
            Self.logger.error("Failed to save cold cache: \(error)")
        }
    }

    private func enforceColdSizeLimit() {
        state.withLock { s in
            Self.enforceColdSizeLimitInline(state: &s, coldCacheDir: coldCacheDir, maxColdBytes: maxColdBytes)
        }
        saveColdManifest()
    }

    private func ensureColdDir() {
        if !FileManager.default.fileExists(atPath: coldCacheDir.path) {
            try? FileManager.default.createDirectory(at: coldCacheDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Cold Manifest Persistence

    private var manifestURL: URL {
        coldCacheDir.appendingPathComponent("manifest.json")
    }

    private func saveColdManifest() {
        ensureColdDir()
        let codable: [CodableManifestEntry] = state.withLock { s in
            s.coldManifest.map { (key, entry) in
                CodableManifestEntry(
                    modelID: key.modelID,
                    contextHash: key.contextHash,
                    filename: entry.filename,
                    lastAccessed: entry.lastAccessed,
                    sizeBytes: entry.sizeBytes
                )
            }
        }
        if let data = try? JSONEncoder().encode(codable) {
            try? data.write(to: manifestURL)
        }
    }

    private func loadColdManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
              let entries = try? JSONDecoder().decode([CodableManifestEntry].self, from: data) else { return }
        state.withLock { s in
            for entry in entries {
                let key = CacheKey(modelID: entry.modelID, contextHash: entry.contextHash)
                s.coldManifest[key] = ColdEntry(filename: entry.filename, lastAccessed: entry.lastAccessed, sizeBytes: entry.sizeBytes)
            }
        }
    }

    private struct CodableManifestEntry: Codable {
        let modelID: String
        let contextHash: UInt64
        let filename: String
        let lastAccessed: Date
        let sizeBytes: Int
    }

    // MARK: - Hash

    /// FNV-1a 64-bit hash for fast, low-collision context hashing.
    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }
}
