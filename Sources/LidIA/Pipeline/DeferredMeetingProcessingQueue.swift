import Foundation

actor DeferredMeetingProcessingQueue {
    static let shared = DeferredMeetingProcessingQueue()

    private let defaultsKey = "meetingProcessingQueue.v1"

    func enqueue(_ meetingID: UUID) {
        var queue = loadQueue()
        if !queue.contains(meetingID) {
            queue.append(meetingID)
            saveQueue(queue)
        }
    }

    func remove(_ meetingID: UUID) {
        var queue = loadQueue()
        queue.removeAll { $0 == meetingID }
        saveQueue(queue)
    }

    func all() -> [UUID] {
        loadQueue()
    }

    func clear() {
        saveQueue([])
    }

    private func loadQueue() -> [UUID] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else {
            return []
        }
        return ids
    }

    private func saveQueue(_ queue: [UUID]) {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
