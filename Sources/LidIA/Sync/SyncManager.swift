import Foundation
import SwiftData
import os

// MARK: - Notification

extension Notification.Name {
    static let meetingDidFinishProcessing = Notification.Name("meetingDidFinishProcessing")
}

// MARK: - SyncManager

/// Coordinates device sync: owns the HTTP client, polls for remote changes,
/// applies them to SwiftData, and pushes local changes.
@MainActor
@Observable
final class SyncManager {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "SyncManager")

    private var syncClient: SyncHTTPClient?
    private var modelContext: ModelContext?
    private var isRunning = false
    private var pollTask: Task<Void, Never>?

    private var didInitialPush = false

    func configure(settings: AppSettings, modelContext: ModelContext) {
        self.modelContext = modelContext

        guard settings.syncEnabled,
              !settings.syncServerURL.isEmpty,
              !settings.syncAuthToken.isEmpty else {
            stop()
            return
        }

        let client = SyncHTTPClient(
            serverURL: settings.syncServerURL,
            token: settings.syncAuthToken
        )
        self.syncClient = client

        guard !isRunning else { return }
        isRunning = true

        pollTask = Task { [weak self] in
            // Push all existing data on first connect
            if self?.didInitialPush == false {
                self?.didInitialPush = true
                await self?.pushAllExisting()
            }

            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(30))
            }
        }

        Self.logger.info("Sync started: \(settings.syncServerURL)")
    }

    /// Push all existing meetings and action items to the server on first sync.
    private func pushAllExisting() async {
        guard let client = syncClient, let context = modelContext else { return }

        do {
            let meetings = try context.fetch(FetchDescriptor<Meeting>())
            let completed = meetings.filter { $0.status == .complete }
            Self.logger.info("Initial push: \(completed.count) meetings")

            for meeting in completed {
                let dto = SyncMeetingDTO(from: meeting)
                await client.postJSON(path: "meetings", body: dto)

                for item in meeting.actionItems {
                    let itemDTO = SyncActionItemDTO(from: item)
                    await client.postJSON(path: "action-items", body: itemDTO)
                }
            }

            // Push orphan action items (not linked to a meeting)
            let allItems = try context.fetch(FetchDescriptor<ActionItem>())
            let orphans = allItems.filter { $0.meeting == nil }
            for item in orphans {
                let dto = SyncActionItemDTO(from: item)
                await client.postJSON(path: "action-items", body: dto)
            }

            // Push SOUL.md and MEMORY.md if they exist
            let lidiaDir = NSHomeDirectory() + "/.lidia"
            for filename in ["SOUL.md", "MEMORY.md"] {
                let path = "\(lidiaDir)/\(filename)"
                if let content = try? String(contentsOfFile: path, encoding: .utf8), !content.isEmpty {
                    await client.putJSON(path: "files/\(filename)", body: ["content": content])
                }
            }

            Self.logger.info("Initial push complete")
        } catch {
            Self.logger.error("Initial push failed: \(error)")
        }
    }

    func pushMeeting(_ meeting: Meeting) {
        guard isRunning, let client = syncClient else { return }
        let dto = SyncMeetingDTO(from: meeting)
        Task {
            let success = await client.postJSON(path: "meetings", body: dto)
            if success {
                Self.logger.debug("Pushed meeting: \(meeting.title)")
            }
        }
    }

    func pushActionItem(_ item: ActionItem) {
        guard isRunning, let client = syncClient else { return }
        let dto = SyncActionItemDTO(from: item)
        Task {
            let success = await client.postJSON(path: "action-items", body: dto)
            if success {
                Self.logger.debug("Pushed action item: \(item.title)")
            }
        }
    }

    func pushFile(name: String, content: String) {
        guard isRunning, let client = syncClient else { return }
        Task {
            await client.putJSON(path: "files/\(name)", body: ["content": content])
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        syncClient = nil
        isRunning = false
    }

    // MARK: - Poll & Apply

    private func poll() async {
        guard let client = syncClient, let context = modelContext else { return }

        guard let response = await client.sync() else { return }

        // Apply meetings
        for syncMeeting in response.meetings {
            applyMeeting(syncMeeting, in: context)
        }
        for deletedID in response.deletedMeetingIDs {
            if let uuid = UUID(uuidString: deletedID),
               let meeting = fetchMeeting(id: uuid, in: context) {
                context.delete(meeting)
            }
        }

        // Apply action items
        for syncItem in response.actionItems {
            applyActionItem(syncItem, in: context)
        }
        for deletedID in response.deletedActionItemIDs {
            if let uuid = UUID(uuidString: deletedID),
               let item = fetchActionItem(id: uuid, in: context) {
                context.delete(item)
            }
        }

        // Apply files
        if let files = response.files {
            for (name, content) in files {
                applyFile(name: name, content: content)
            }
        }

        do {
            try context.save()
            Self.logger.info("Sync applied: \(response.meetings.count) meetings, \(response.actionItems.count) items")
        } catch {
            Self.logger.error("Failed to save sync: \(error)")
        }
    }

    private func applyMeeting(_ sync: SyncMeetingDTO, in context: ModelContext) {
        guard let uuid = UUID(uuidString: sync.id) else { return }

        if let meeting = fetchMeeting(id: uuid, in: context) {
            meeting.title = sync.title
            meeting.date = Date(timeIntervalSince1970: Double(sync.date) / 1000)
            meeting.duration = sync.duration
            meeting.refinedTranscript = sync.refinedTranscript
            meeting.summary = sync.summary
            meeting.status = MeetingStatus(rawValue: sync.status) ?? .complete
            meeting.notes = sync.notes
            meeting.folder = sync.folder
            meeting.audioFilePath = sync.audioFilePath
            meeting.userEditedTranscript = sync.userEditedTranscript
            meeting.userEditedSummary = sync.userEditedSummary
            meeting.calendarEventID = sync.calendarEventID
            meeting.calendarAttendees = decodeAttendees(sync.calendarAttendees)
            meeting.templateID = sync.templateID.flatMap(UUID.init(uuidString:))
        } else {
            let meeting = Meeting(
                title: sync.title,
                date: Date(timeIntervalSince1970: Double(sync.date) / 1000),
                duration: sync.duration,
                refinedTranscript: sync.refinedTranscript,
                summary: sync.summary,
                status: MeetingStatus(rawValue: sync.status) ?? .complete,
                audioFilePath: sync.audioFilePath,
                userEditedTranscript: sync.userEditedTranscript,
                userEditedSummary: sync.userEditedSummary,
                calendarEventID: sync.calendarEventID,
                calendarAttendees: decodeAttendees(sync.calendarAttendees),
                templateID: sync.templateID.flatMap(UUID.init(uuidString:)),
                notes: sync.notes,
                folder: sync.folder
            )
            meeting.id = uuid
            context.insert(meeting)
        }
    }

    private func applyActionItem(_ sync: SyncActionItemDTO, in context: ModelContext) {
        guard let uuid = UUID(uuidString: sync.id) else { return }

        if let item = fetchActionItem(id: uuid, in: context) {
            item.title = sync.title
            item.assignee = sync.assignee
            item.deadline = sync.deadline
            item.deadlineDate = sync.deadlineDate.map { Date(timeIntervalSince1970: Double($0) / 1000) }
            item.isCompleted = sync.isCompleted != 0
            if let meetingIDStr = sync.meetingID, let meetingUUID = UUID(uuidString: meetingIDStr) {
                if item.meeting?.id != meetingUUID {
                    item.meeting = fetchMeeting(id: meetingUUID, in: context)
                }
            }
        } else {
            let item = ActionItem(
                title: sync.title,
                assignee: sync.assignee,
                deadline: sync.deadline,
                deadlineDate: sync.deadlineDate.map { Date(timeIntervalSince1970: Double($0) / 1000) },
                isCompleted: sync.isCompleted != 0
            )
            item.id = uuid
            context.insert(item)
            if let meetingIDStr = sync.meetingID, let meetingUUID = UUID(uuidString: meetingIDStr) {
                item.meeting = fetchMeeting(id: meetingUUID, in: context)
            }
        }
    }

    private func applyFile(name: String, content: String) {
        let dir = NSHomeDirectory() + "/.lidia"
        let path = "\(dir)/\(name)"
        let dirURL = URL(fileURLWithPath: dir)

        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        Self.logger.debug("Applied file: \(name)")
    }

    // MARK: - Fetch Helpers

    private func fetchMeeting(id: UUID, in context: ModelContext) -> Meeting? {
        var descriptor = FetchDescriptor<Meeting>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchActionItem(id: UUID, in context: ModelContext) -> ActionItem? {
        var descriptor = FetchDescriptor<ActionItem>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func decodeAttendees(_ json: String?) -> [String]? {
        guard let json, !json.isEmpty,
              let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return arr
    }
}

// MARK: - Sync HTTP Client

/// Lightweight HTTP client for the lidia-sync server.
private actor SyncHTTPClient {
    private let serverURL: URL
    private let token: String
    private var lastSyncTime: Int64 = 0

    init(serverURL: String, token: String) {
        self.serverURL = URL(string: serverURL) ?? URL(string: "http://localhost")!
        self.token = token
    }

    func sync() async -> SyncResponseDTO? {
        guard var components = URLComponents(url: serverURL.appendingPathComponent("sync"), resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "since", value: String(lastSyncTime))]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let syncResponse = try JSONDecoder().decode(SyncResponseDTO.self, from: data)
            lastSyncTime = syncResponse.serverTime
            return syncResponse
        } catch {
            return nil
        }
    }

    func postJSON<T: Encodable>(path: String, body: T) async -> Bool {
        var request = URLRequest(url: serverURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    @discardableResult
    func putJSON<T: Encodable>(path: String, body: T) async -> Bool {
        var request = URLRequest(url: serverURL.appendingPathComponent(path))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

// MARK: - Sync DTOs

/// Matches the lidia-sync Go API response format.
private struct SyncResponseDTO: Codable, Sendable {
    let serverTime: Int64
    let meetings: [SyncMeetingDTO]
    let actionItems: [SyncActionItemDTO]
    let deletedMeetingIDs: [String]
    let deletedActionItemIDs: [String]
    let files: [String: String]?
    let settings: [String: String]?

    enum CodingKeys: String, CodingKey {
        case serverTime = "server_time"
        case meetings
        case actionItems = "action_items"
        case deletedMeetingIDs = "deleted_meeting_ids"
        case deletedActionItemIDs = "deleted_action_item_ids"
        case files
        case settings
    }
}

private struct SyncMeetingDTO: Codable, Sendable {
    let id: String
    let title: String
    let date: Int64
    let duration: Double
    let rawTranscript: String
    let refinedTranscript: String
    let summary: String
    let status: String
    let notes: String
    let folder: String?
    let audioFilePath: String?
    let userEditedTranscript: String?
    let userEditedSummary: String?
    let calendarEventID: String?
    let calendarAttendees: String?
    let templateID: String?
    let updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id, title, date, duration, summary, status, notes, folder
        case rawTranscript = "raw_transcript"
        case refinedTranscript = "refined_transcript"
        case audioFilePath = "audio_file_path"
        case userEditedTranscript = "user_edited_transcript"
        case userEditedSummary = "user_edited_summary"
        case calendarEventID = "calendar_event_id"
        case calendarAttendees = "calendar_attendees"
        case templateID = "template_id"
        case updatedAt = "updated_at"
    }

    init(from meeting: Meeting) {
        self.id = meeting.id.uuidString
        self.title = meeting.title
        self.date = Int64(meeting.date.timeIntervalSince1970 * 1000)
        self.duration = meeting.duration
        self.rawTranscript = ""
        self.refinedTranscript = meeting.refinedTranscript
        self.summary = meeting.summary
        self.status = meeting.status.rawValue
        self.notes = meeting.notes
        self.folder = meeting.folder
        self.audioFilePath = meeting.audioFilePath
        self.userEditedTranscript = meeting.userEditedTranscript
        self.userEditedSummary = meeting.userEditedSummary
        self.calendarEventID = meeting.calendarEventID
        self.calendarAttendees = meeting.calendarAttendees.flatMap {
            try? JSONEncoder().encode($0)
        }.flatMap { String(data: $0, encoding: .utf8) }
        self.templateID = meeting.templateID?.uuidString
        self.updatedAt = Int64(Date.now.timeIntervalSince1970 * 1000)
    }
}

private struct SyncActionItemDTO: Codable, Sendable {
    let id: String
    let meetingID: String?
    let title: String
    let assignee: String?
    let deadline: String?
    let deadlineDate: Int64?
    let isCompleted: Int64
    let updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id, title, assignee, deadline
        case meetingID = "meeting_id"
        case deadlineDate = "deadline_date"
        case isCompleted = "is_completed"
        case updatedAt = "updated_at"
    }

    init(from item: ActionItem) {
        self.id = item.id.uuidString
        self.meetingID = item.meeting?.id.uuidString
        self.title = item.title
        self.assignee = item.assignee
        self.deadline = item.deadline
        self.deadlineDate = item.deadlineDate.map { Int64($0.timeIntervalSince1970 * 1000) }
        self.isCompleted = item.isCompleted ? 1 : 0
        self.updatedAt = Int64(Date.now.timeIntervalSince1970 * 1000)
    }
}
