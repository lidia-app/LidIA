import Testing
import Foundation
@testable import LidIA

/// Tests for ChatThreadStore's in-memory thread management logic.
/// These tests exercise the thread CRUD operations without SwiftData
/// (no modelContext configured, so persistence calls are no-ops).
@Suite("ChatThreadStore")
struct ChatThreadStoreTests {

    // MARK: - Thread Creation

    @MainActor
    @Test("ensureActiveThreadExists creates a thread when none active")
    func createThread() {
        let store = ChatThreadStore()
        #expect(store.threads.isEmpty)
        #expect(store.activeThreadID == nil)

        store.ensureActiveThreadExists(initialPrompt: "Hello world", scope: .allMeetings)

        #expect(store.threads.count == 1)
        #expect(store.activeThreadID != nil)
        #expect(store.activeThreadID == store.threads.first?.id)
    }

    @MainActor
    @Test("ensureActiveThreadExists does not create duplicate when thread already active")
    func noDoubleCreate() {
        let store = ChatThreadStore()
        store.ensureActiveThreadExists(initialPrompt: "First", scope: .allMeetings)
        let firstID = store.activeThreadID

        store.ensureActiveThreadExists(initialPrompt: "Second", scope: .allMeetings)

        #expect(store.threads.count == 1)
        #expect(store.activeThreadID == firstID)
    }

    @MainActor
    @Test("Thread title is derived from initial prompt")
    func threadTitleFromPrompt() {
        let store = ChatThreadStore()
        store.ensureActiveThreadExists(initialPrompt: "What happened in yesterday's standup meeting?", scope: .allMeetings)

        let thread = store.threads.first
        #expect(thread != nil)
        // makeThreadTitle takes first 8 words
        #expect(thread!.title.contains("What"))
        #expect(thread!.title.contains("standup"))
    }

    @MainActor
    @Test("Empty prompt results in 'New chat' title")
    func emptyPromptTitle() {
        let store = ChatThreadStore()
        store.ensureActiveThreadExists(initialPrompt: "", scope: .allMeetings)

        #expect(store.threads.first?.title == "New chat")
    }

    // MARK: - Thread Deletion

    @MainActor
    @Test("deleteThread removes the thread")
    func deleteThread() {
        let store = ChatThreadStore()
        store.ensureActiveThreadExists(initialPrompt: "Test", scope: .allMeetings)
        let thread = store.threads.first!

        store.deleteThread(thread)

        #expect(store.threads.isEmpty)
    }

    @MainActor
    @Test("Deleting active thread clears activeThreadID")
    func deleteActiveThread() {
        let store = ChatThreadStore()
        store.ensureActiveThreadExists(initialPrompt: "Test", scope: .allMeetings)
        let thread = store.threads.first!
        #expect(store.activeThreadID == thread.id)

        store.deleteThread(thread)

        #expect(store.activeThreadID == nil)
    }

    @MainActor
    @Test("Deleting non-active thread preserves activeThreadID")
    func deleteNonActiveThread() {
        let store = ChatThreadStore()

        // Create first thread
        store.ensureActiveThreadExists(initialPrompt: "First", scope: .allMeetings)
        let firstThread = store.threads.first!

        // Create second thread by clearing active and creating new
        store.startNewThread()
        store.ensureActiveThreadExists(initialPrompt: "Second", scope: .allMeetings)
        let activeID = store.activeThreadID

        // Delete the first (non-active) thread
        store.deleteThread(firstThread)

        #expect(store.activeThreadID == activeID)
        #expect(store.threads.count == 1)
    }

    // MARK: - Thread Opening

    @MainActor
    @Test("openThread sets activeThreadID and returns messages")
    func openThread() {
        let store = ChatThreadStore()
        store.ensureActiveThreadExists(initialPrompt: "Test", scope: .allMeetings)
        let thread = store.threads.first!

        store.startNewThread()
        #expect(store.activeThreadID == nil)

        let messages = store.openThread(thread)
        #expect(store.activeThreadID == thread.id)
        #expect(messages.isEmpty) // new thread has no messages
    }

    @MainActor
    @Test("openThread by ID returns nil for unknown ID")
    func openThreadUnknownID() {
        let store = ChatThreadStore()
        let result = store.openThread(id: UUID())
        #expect(result == nil)
    }

    @MainActor
    @Test("openThread by ID works for valid ID")
    func openThreadValidID() {
        let store = ChatThreadStore()
        store.ensureActiveThreadExists(initialPrompt: "Test", scope: .allMeetings)
        let threadID = store.threads.first!.id

        store.startNewThread()
        let result = store.openThread(id: threadID)
        #expect(result != nil)
        #expect(store.activeThreadID == threadID)
    }

    // MARK: - startNewThread

    @MainActor
    @Test("startNewThread clears activeThreadID")
    func startNewThread() {
        let store = ChatThreadStore()
        store.ensureActiveThreadExists(initialPrompt: "Test", scope: .allMeetings)
        #expect(store.activeThreadID != nil)

        store.startNewThread()
        #expect(store.activeThreadID == nil)
    }

    // MARK: - syncActiveThread

    @MainActor
    @Test("syncActiveThread updates messages on active thread")
    func syncMessages() {
        let store = ChatThreadStore()
        store.ensureActiveThreadExists(initialPrompt: "Test", scope: .allMeetings)

        let msg = ChatBarMessage(role: .user, text: "Hello")
        store.syncActiveThread(messages: [msg], scope: .allMeetings)

        #expect(store.threads.first?.messages.count == 1)
        #expect(store.threads.first?.messages.first?.text == "Hello")
    }

    @MainActor
    @Test("syncActiveThread updates title from 'New chat' when first user message arrives")
    func syncUpdatesTitle() {
        let store = ChatThreadStore()
        store.ensureActiveThreadExists(initialPrompt: "", scope: .allMeetings)
        #expect(store.threads.first?.title == "New chat")

        let msg = ChatBarMessage(role: .user, text: "What are my action items from today?")
        store.syncActiveThread(messages: [msg], scope: .allMeetings)

        let title = store.threads.first?.title ?? ""
        #expect(title != "New chat")
        #expect(title.contains("action"))
    }

    @MainActor
    @Test("syncActiveThread is no-op when no active thread")
    func syncNoActiveThread() {
        let store = ChatThreadStore()
        // No active thread
        let msg = ChatBarMessage(role: .user, text: "Hello")
        store.syncActiveThread(messages: [msg], scope: .allMeetings)
        // Should not crash, threads still empty
        #expect(store.threads.isEmpty)
    }

    // MARK: - recentThreads

    @MainActor
    @Test("recentThreads returns threads sorted by updatedAt descending")
    func recentThreadsSorted() {
        let store = ChatThreadStore()

        // Create two threads with different timestamps
        store.ensureActiveThreadExists(initialPrompt: "Older", scope: .allMeetings)
        store.startNewThread()
        store.ensureActiveThreadExists(initialPrompt: "Newer", scope: .allMeetings)

        let recent = store.recentThreads
        #expect(recent.count == 2)
        #expect(recent.first?.updatedAt ?? .distantPast >= recent.last?.updatedAt ?? .distantFuture)
    }

    // MARK: - Scope

    @MainActor
    @Test("Thread preserves scope from creation")
    func threadPreservesScope() {
        let store = ChatThreadStore()
        store.ensureActiveThreadExists(initialPrompt: "Notes query", scope: .myNotes)

        #expect(store.threads.first?.scope == .myNotes)
    }

    @MainActor
    @Test("syncActiveThread can update scope")
    func syncUpdatesScope() {
        let store = ChatThreadStore()
        store.ensureActiveThreadExists(initialPrompt: "Test", scope: .allMeetings)
        #expect(store.threads.first?.scope == .allMeetings)

        store.syncActiveThread(messages: [], scope: .selectedMeeting)
        #expect(store.threads.first?.scope == .selectedMeeting)
    }
}

// MARK: - makeThreadTitle Tests

@Suite("ChatBarViewModel.makeThreadTitle")
struct MakeThreadTitleTests {

    @MainActor
    @Test("Produces headline from first 8 words")
    func first8Words() {
        let title = ChatBarViewModel.makeThreadTitle(from: "one two three four five six seven eight nine ten")
        let words = title.split(separator: " ")
        #expect(words.count == 8)
    }

    @MainActor
    @Test("Returns 'New chat' for empty input")
    func emptyInput() {
        #expect(ChatBarViewModel.makeThreadTitle(from: "") == "New chat")
    }

    @MainActor
    @Test("Returns 'New chat' for whitespace-only input")
    func whitespaceOnlyInput() {
        #expect(ChatBarViewModel.makeThreadTitle(from: "   ") == "New chat")
    }

    @MainActor
    @Test("Short input is kept as-is")
    func shortInput() {
        let title = ChatBarViewModel.makeThreadTitle(from: "Quick question")
        #expect(title == "Quick question")
    }
}
