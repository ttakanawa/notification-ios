import Foundation
import NotificationManagerApplication
import NotificationManagerDomain
import Observation

enum ReminderFormSection: Sendable, Equatable, CaseIterable {
    case basicInformation
    case dateAndTime
    case repeatRule
    case earlyReminder
    case organization
}

enum ReminderFormReadOnlyReason: Sendable, Equatable {
    case updateRequired
    case invalidSchedule
}

enum ReminderFormScheduleAccess: Sendable, Equatable {
    case editable
    case repair(issues: [ScheduleValidationIssue])
    case readOnly(ReminderFormReadOnlyReason)
}

enum SavedRepeatPresentation: Sendable, Equatable {
    case standard(localizedSummary: String)
    case custom(localizedSummary: String, canonicalEnglishDisclosure: String?)

    var localizedSummary: String {
        switch self {
        case let .standard(localizedSummary), let .custom(localizedSummary, _):
            localizedSummary
        }
    }

    var canonicalEnglishDisclosure: String? {
        guard case let .custom(_, disclosure) = self else { return nil }
        return disclosure
    }
}

struct ReminderFormActions: Sendable {
    let save: @Sendable (
        ReminderDraft,
        CapacityConsent,
        ExpiredScheduleConsent
    ) async throws -> SaveReminderOutcome
    let delete: @Sendable (UUID) async throws -> Void

    init(
        save: @escaping @Sendable (
            ReminderDraft,
            CapacityConsent,
            ExpiredScheduleConsent
        ) async throws -> SaveReminderOutcome,
        delete: @escaping @Sendable (UUID) async throws -> Void
    ) {
        self.save = save
        self.delete = delete
    }

    init(saveUseCase: SaveReminderUseCase, deleteUseCase: DeleteReminderUseCase) {
        save = { draft, capacityConsent, expiredScheduleConsent in
            try await saveUseCase.execute(
                draft: draft,
                capacityConsent: capacityConsent,
                expiredScheduleConsent: expiredScheduleConsent
            )
        }
        delete = { reminderID in
            try await deleteUseCase.execute(reminderID: reminderID)
        }
    }
}

enum ReminderFormFailure: Sendable, Equatable {
    case save
    case delete
}

enum ReminderFormFieldIssue: Sendable, Equatable {
    case titleRequired
    case titleTooLarge
    case notesTooLarge
    case urlInvalid
    case urlTooLarge
    case timeZoneRequired
    case timeZoneInvalid
    case repeatEndInvalid
    case repeatEndBeforeStart
}

enum EarlyReminderChoice: String, Sendable, Equatable, CaseIterable, Identifiable {
    case none
    case oneMinute
    case fiveMinutes
    case custom

    var id: String { rawValue }
}

enum ReminderFormSaveState: Sendable, Equatable {
    case idle
    case saving
    case requiresCapacityConfirmation(CapacityWarning)
    case requiresExpiredScheduleConfirmation(ExpiredScheduleWarning)
    case saved(UUID)
    case deleted
    case failed(ReminderFormFailure)
}

@MainActor
@Observable
final class ReminderFormModel {
    let sections = ReminderFormSection.allCases
    let scheduleAccess: ReminderFormScheduleAccess
    let canDelete: Bool
    let availableTags: [ReminderTagPresentation]

    private(set) var detachedDraft: ReminderDraft
    private(set) var currentLocalizedRepeatSummary: String?
    private(set) var currentRepeatWasCustom = false
    private(set) var canonicalEnglishDisclosure: String?
    private(set) var sourceDateText = ""
    private(set) var sourceTimeText = ""
    private(set) var repeatEndDateText = ""
    private(set) var repeatEndsOnDate = false
    private(set) var earlyReminderValueText = ""
    private(set) var earlyReminderChoice: EarlyReminderChoice = .none
    private(set) var customRepeatText = ""
    private(set) var isReplacingCustomRepeat = false
    private(set) var customRepeatState: CustomRepeatSessionState = .idle
    private(set) var previewNotifications: [PhysicalNotification] = []
    private(set) var showsPastEarlyWarning = false
    private(set) var isDeleteConfirmationPresented = false
    private(set) var saveState: ReminderFormSaveState = .idle

    @ObservationIgnored private let actions: ReminderFormActions
    @ObservationIgnored private let previewNow: Date
    @ObservationIgnored private let recurrenceEnvironment: any RecurrenceEnvironment
    @ObservationIgnored private let assistedRepeatInterpreter: any AssistedRepeatInterpreting
    @ObservationIgnored private let localizedRepeatSummary: @Sendable (ScheduleDefinition) -> String
    @ObservationIgnored private var customRepeatSession: CustomRepeatSession?
    @ObservationIgnored private var customSubmissionGeneration: UInt64 = 0
    @ObservationIgnored private var editRevision: UInt64 = 0
    @ObservationIgnored private var capacityConsent: CapacityConsent = .notProvided
    @ObservationIgnored private var expiredScheduleConsent: ExpiredScheduleConsent = .notProvided
    @ObservationIgnored private var confirmedExpiredSaveRevision: UInt64?
    @ObservationIgnored private var confirmedDeleteIsPending = false
    @ObservationIgnored private var scheduleHasEditIntent = false
    @ObservationIgnored private let requiresReplacementBeforeSave: Bool

    init(
        newReminderID: UUID,
        now: Date,
        actions: ReminderFormActions,
        availableTags: [ReminderTagPresentation] = [],
        recurrenceEnvironment: any RecurrenceEnvironment = FoundationRecurrenceEnvironment(),
        assistedRepeatInterpreter: any AssistedRepeatInterpreting = NoAssistedRepeatInterpreter(),
        localizedRepeatSummary: @escaping @Sendable (ScheduleDefinition) -> String = {
            CanonicalRepeatFormatter().string(for: $0.rule)
        }
    ) {
        detachedDraft = ReminderDraft(id: newReminderID, now: now)
        scheduleAccess = .editable
        canDelete = false
        self.availableTags = availableTags
        self.actions = actions
        previewNow = now
        self.recurrenceEnvironment = recurrenceEnvironment
        self.assistedRepeatInterpreter = assistedRepeatInterpreter
        self.localizedRepeatSummary = localizedRepeatSummary
        requiresReplacementBeforeSave = true
    }

    init(
        snapshot: ReminderSnapshot,
        savedRepeatPresentation: SavedRepeatPresentation?,
        now: Date,
        actions: ReminderFormActions,
        availableTags: [ReminderTagPresentation] = [],
        recurrenceEnvironment: any RecurrenceEnvironment = FoundationRecurrenceEnvironment(),
        assistedRepeatInterpreter: any AssistedRepeatInterpreting = NoAssistedRepeatInterpreter(),
        localizedRepeatSummary: @escaping @Sendable (ScheduleDefinition) -> String = {
            CanonicalRepeatFormatter().string(for: $0.rule)
        }
    ) {
        let initialDraft = ReminderDraft(snapshot: snapshot)
        detachedDraft = initialDraft
        sourceDateText = Self.format(initialDraft.date)
        sourceTimeText = Self.format(initialDraft.time)
        if case let .onDate(date) = initialDraft.end {
            repeatEndDateText = Self.format(date)
            repeatEndsOnDate = true
        }
        earlyReminderValueText = initialDraft.early.map { String($0.value) } ?? ""
        earlyReminderChoice = Self.earlyReminderChoice(for: initialDraft.early)
        canDelete = true
        self.availableTags = availableTags
        self.actions = actions
        previewNow = now
        self.recurrenceEnvironment = recurrenceEnvironment
        self.assistedRepeatInterpreter = assistedRepeatInterpreter
        self.localizedRepeatSummary = localizedRepeatSummary
        currentLocalizedRepeatSummary = savedRepeatPresentation?.localizedSummary
        if case .custom = savedRepeatPresentation {
            currentRepeatWasCustom = true
        }
        canonicalEnglishDisclosure = savedRepeatPresentation?.canonicalEnglishDisclosure

        switch snapshot.schedule {
        case .valid:
            scheduleAccess = .editable
            requiresReplacementBeforeSave = false
        case let .domainInvalid(_, _, issues):
            scheduleAccess = .repair(issues: issues)
            requiresReplacementBeforeSave = true
        case .unsupportedFuture:
            scheduleAccess = .readOnly(.updateRequired)
            requiresReplacementBeforeSave = false
        case .corrupt:
            scheduleAccess = .readOnly(.invalidSchedule)
            requiresReplacementBeforeSave = false
        }

        refreshPreview()
    }

    var title: String {
        get { detachedDraft.title }
        set {
            detachedDraft.title = newValue
            resetSaveStateAfterEdit()
        }
    }

    var notes: String? {
        get { detachedDraft.notes }
        set {
            detachedDraft.notes = newValue
            resetSaveStateAfterEdit()
        }
    }

    var urlString: String? {
        get { detachedDraft.urlString }
        set {
            detachedDraft.urlString = newValue
            resetSaveStateAfterEdit()
        }
    }

    var enabled: Bool {
        get { detachedDraft.enabled }
        set {
            detachedDraft.enabled = newValue
            resetSaveStateAfterEdit()
        }
    }

    var tagIDs: Set<UUID> {
        get { detachedDraft.tagIDs }
        set {
            detachedDraft.tagIDs = newValue
            resetSaveStateAfterEdit()
        }
    }

    var sourceDate: SourceDate? {
        get { detachedDraft.date }
        set {
            guard canEditSchedule else { return }
            detachedDraft.date = newValue
            sourceDateText = Self.format(newValue)
            refreshAnchorDependentPreset()
            scheduleFieldChanged()
            refreshRepeatSummaryAfterSourceDateEdit()
        }
    }

    var sourceTime: SourceTime? {
        get { detachedDraft.time }
        set {
            guard canEditSchedule else { return }
            detachedDraft.time = newValue
            sourceTimeText = Self.format(newValue)
            scheduleFieldChanged()
        }
    }

    var timeZoneIdentifier: String? {
        get { detachedDraft.timeZoneIdentifier }
        set {
            guard canEditSchedule else { return }
            detachedDraft.timeZoneIdentifier = newValue
            scheduleFieldChanged()
        }
    }

    var repeatRule: RepeatRule {
        get { detachedDraft.rule }
        set {
            guard canEditSchedule else { return }
            detachedDraft.rule = newValue
            if newValue == .none {
                detachedDraft.end = .never
                repeatEndsOnDate = false
                repeatEndDateText = ""
            }
            isReplacingCustomRepeat = false
            customRepeatText = ""
            currentLocalizedRepeatSummary = nil
            currentRepeatWasCustom = false
            canonicalEnglishDisclosure = nil
            scheduleFieldChanged()
        }
    }

    var repeatEnd: RepeatEnd {
        get { detachedDraft.end }
        set {
            guard canEditSchedule else { return }
            detachedDraft.end = newValue
            switch newValue {
            case .never:
                repeatEndsOnDate = false
                repeatEndDateText = ""
            case let .onDate(date):
                repeatEndsOnDate = true
                repeatEndDateText = Self.format(date)
            }
            scheduleFieldChanged()
        }
    }

    var earlyReminder: EarlyReminder? {
        get { detachedDraft.early }
        set {
            guard canEditSchedule else { return }
            detachedDraft.early = newValue
            earlyReminderValueText = newValue.map { String($0.value) } ?? ""
            earlyReminderChoice = Self.earlyReminderChoice(for: newValue)
            scheduleFieldChanged()
        }
    }

    var canEditMetadata: Bool { true }

    var scheduleFieldsAreEditable: Bool { canEditSchedule }

    var titleFieldIssue: ReminderFormFieldIssue? {
        if detachedDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .titleRequired
        }
        if detachedDraft.title.utf8.count > ReminderLimits.titleBytes {
            return .titleTooLarge
        }
        return nil
    }

    var notesFieldIssue: ReminderFormFieldIssue? {
        guard let notes = detachedDraft.notes,
              notes.utf8.count > ReminderLimits.notesBytes
        else {
            return nil
        }
        return .notesTooLarge
    }

    var urlFieldIssue: ReminderFormFieldIssue? {
        guard let input = detachedDraft.urlString, !input.isEmpty else { return nil }
        guard let canonical = try? CanonicalHTTPURL(input) else { return .urlInvalid }
        if canonical.string.utf8.count > ReminderLimits.urlBytes { return .urlTooLarge }
        return nil
    }

    var timeZoneFieldIssue: ReminderFormFieldIssue? {
        guard canEditSchedule else { return nil }
        guard let identifier = detachedDraft.timeZoneIdentifier,
              !identifier.isEmpty
        else {
            return scheduleHasEditIntent ? .timeZoneRequired : nil
        }
        return TimeZone.knownTimeZoneIdentifiers.contains(identifier)
            && TimeZone(identifier: identifier) != nil
            ? nil
            : .timeZoneInvalid
    }

    var sourceDateTextIsValid: Bool {
        guard !sourceDateText.isEmpty else { return !scheduleHasEditIntent }
        guard let value = Self.parseSourceDate(sourceDateText),
              detachedDraft.date == value
        else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: value.year, month: value.month, day: value.day)
        guard let date = calendar.date(from: components) else { return false }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        return resolved.year == value.year
            && resolved.month == value.month
            && resolved.day == value.day
    }

    var sourceTimeTextIsValid: Bool {
        guard !sourceTimeText.isEmpty else { return !scheduleHasEditIntent }
        guard let value = Self.parseSourceTime(sourceTimeText),
              detachedDraft.time == value
        else {
            return false
        }
        return (0...23).contains(value.hour) && (0...59).contains(value.minute)
    }

    var earlyReminderValueTextIsValid: Bool {
        guard let early = detachedDraft.early else { return earlyReminderValueText.isEmpty }
        return Int(earlyReminderValueText) == early.value
            && (1...9_999).contains(early.value)
    }

    var repeatEndDateTextIsValid: Bool {
        repeatEndDateFieldIssue == nil
    }

    var repeatEndDateFieldIssue: ReminderFormFieldIssue? {
        guard repeatEndsOnDate else {
            return repeatEndDateText.isEmpty ? nil : .repeatEndInvalid
        }
        guard let value = Self.parseSourceDate(repeatEndDateText),
              Self.isValid(value),
              case let .onDate(endDate) = detachedDraft.end,
              value == endDate
        else {
            return .repeatEndInvalid
        }
        guard let start = detachedDraft.date else { return nil }
        if (value.year, value.month, value.day) < (start.year, start.month, start.day) {
            return .repeatEndBeforeStart
        }
        return nil
    }

    var canSaveWithoutReplacingSchedule: Bool {
        guard detachedDraft.originalScheduleData != nil,
              !requiresReplacementBeforeSave,
              !scheduleHasEditIntent,
              !isReplacingCustomRepeat,
              scheduleInputFieldsAreValid,
              case .preserveOriginal = detachedDraft.scheduleChange
        else {
            return false
        }
        return metadataIsValid
    }

    var canSave: Bool {
        guard saveState != .saving,
              scheduleInputFieldsAreValid,
              metadataIsValid
        else {
            return false
        }
        if canSaveWithoutReplacingSchedule { return true }
        guard case .replace = detachedDraft.scheduleChange else { return false }
        if detachedDraft.originalScheduleData == nil && previewNotifications.isEmpty {
            return false
        }
        return (try? ReminderDraftValidator().validate(
            detachedDraft,
            replacementScheduleData: Data([1])
        )) != nil
    }

    func updateSourceDateText(_ input: String) {
        guard canEditSchedule else { return }
        sourceDateText = input
        detachedDraft.date = Self.parseSourceDate(input)
        refreshAnchorDependentPreset()
        scheduleFieldChanged()
        refreshRepeatSummaryAfterSourceDateEdit()
    }

    func updateSourceTimeText(_ input: String) {
        guard canEditSchedule else { return }
        sourceTimeText = input
        detachedDraft.time = Self.parseSourceTime(input)
        scheduleFieldChanged()
    }

    func updateEarlyReminderValueText(_ input: String) {
        guard canEditSchedule, let current = detachedDraft.early else { return }
        earlyReminderValueText = input
        if let value = Int(input) {
            detachedDraft.early = EarlyReminder(
                value: value,
                unit: current.unit,
                mainEnabled: current.mainEnabled
            )
        }
        earlyReminderChoice = .custom
        scheduleFieldChanged()
    }

    func updateEarlyReminderUnit(_ unit: EarlyReminderUnit) {
        guard canEditSchedule, let current = detachedDraft.early else { return }
        detachedDraft.early = EarlyReminder(
            value: current.value,
            unit: unit,
            mainEnabled: current.mainEnabled
        )
        earlyReminderChoice = .custom
        scheduleFieldChanged()
    }

    func updateMainNotificationEnabled(_ enabled: Bool) {
        guard canEditSchedule, let current = detachedDraft.early else { return }
        detachedDraft.early = EarlyReminder(
            value: current.value,
            unit: current.unit,
            mainEnabled: enabled
        )
        scheduleFieldChanged()
    }

    func applyEarlyReminderChoice(_ choice: EarlyReminderChoice) {
        guard canEditSchedule else { return }
        let mainEnabled = detachedDraft.early?.mainEnabled ?? true
        switch choice {
        case .none:
            detachedDraft.early = nil
            earlyReminderValueText = ""
        case .oneMinute:
            detachedDraft.early = EarlyReminder(
                value: 1,
                unit: .minutes,
                mainEnabled: mainEnabled
            )
            earlyReminderValueText = "1"
        case .fiveMinutes:
            detachedDraft.early = EarlyReminder(
                value: 5,
                unit: .minutes,
                mainEnabled: mainEnabled
            )
            earlyReminderValueText = "5"
        case .custom:
            if detachedDraft.early == nil {
                detachedDraft.early = EarlyReminder(value: 5, unit: .minutes)
                earlyReminderValueText = "5"
            }
        }
        earlyReminderChoice = choice
        scheduleFieldChanged()
    }

    @discardableResult
    func applyRepeatPreset(_ preset: NotificationManagerDomain.RepeatPreset) -> Bool {
        if (preset == .weekly || preset == .biweekly), detachedDraft.date == nil {
            return false
        }
        let factorySource = detachedDraft.source ?? SourceWallClock(
            year: detachedDraft.date?.year ?? 2001,
            month: detachedDraft.date?.month ?? 1,
            day: detachedDraft.date?.day ?? 1,
            hour: detachedDraft.time?.hour ?? 0,
            minute: detachedDraft.time?.minute ?? 0,
            timeZoneIdentifier: detachedDraft.timeZoneIdentifier ?? "Africa/Abidjan"
        )
        guard let rule = try? PresetRepeatRuleFactory().rule(
            for: preset,
            source: factorySource
        ) else {
            return false
        }
        repeatRule = rule
        return true
    }

    func setRepeatEndsOnDate(_ enabled: Bool) {
        guard canEditSchedule, detachedDraft.rule != .none else { return }
        repeatEndsOnDate = enabled
        if enabled {
            repeatEndDateText = ""
        } else {
            detachedDraft.end = .never
            repeatEndDateText = ""
        }
        scheduleFieldChanged()
    }

    func updateRepeatEndDateText(_ input: String) {
        guard canEditSchedule, repeatEndsOnDate else { return }
        repeatEndDateText = input
        if let date = Self.parseSourceDate(input), Self.isValid(date) {
            detachedDraft.end = .onDate(date)
        }
        scheduleFieldChanged()
    }

    func beginCustomReplacement() {
        guard canEditSchedule else { return }
        isReplacingCustomRepeat = true
        customRepeatText = ""
        customRepeatState = .idle
        customRepeatSession = nil
        customSubmissionGeneration &+= 1
        previewNotifications = []
        showsPastEarlyWarning = false
        detachedDraft.scheduleChange = .preserveOriginal
        resetSaveStateAfterEdit()
    }

    func updateCustomRepeatText(_ input: String) {
        guard isReplacingCustomRepeat else { return }
        customRepeatText = input
        customRepeatState = .idle
        customRepeatSession = nil
        customSubmissionGeneration &+= 1
        resetSaveStateAfterEdit()
    }

    func submitCustomRepeat() async {
        guard isReplacingCustomRepeat,
              scheduleInputFieldsAreValid,
              !customRepeatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let source = detachedDraft.source
        else {
            return
        }

        customSubmissionGeneration &+= 1
        let generation = customSubmissionGeneration
        let session = CustomRepeatSession(
            resolver: CustomRepeatInputResolver(
                source: source,
                end: detachedDraft.end,
                early: detachedDraft.early,
                assistedInterpreter: assistedRepeatInterpreter
            ),
            reminderID: detachedDraft.id,
            now: { [previewNow] in previewNow },
            recurrenceEnvironment: recurrenceEnvironment
        )
        customRepeatSession = session

        do {
            let outcome = try await session.submit(customRepeatText)
            guard generation == customSubmissionGeneration else { return }
            if case let .applied(state) = outcome {
                customRepeatState = state
            }
        } catch {
            guard generation == customSubmissionGeneration else { return }
            customRepeatState = .failed(.generation)
        }
    }

    func selectCustomRepeatSuggestion() async {
        guard case let .awaitingSuggestion(suggestion) = customRepeatState else {
            return
        }
        updateCustomRepeatText(suggestion)
        await submitCustomRepeat()
    }

    func confirmCustomRepeat() async {
        guard let customRepeatSession,
              let schedule = await customRepeatSession.confirm(),
              case let .awaitingConfirmation(preview) = customRepeatState
        else {
            return
        }

        detachedDraft.source = schedule.source
        detachedDraft.rule = schedule.rule
        detachedDraft.end = schedule.end
        detachedDraft.early = schedule.early
        earlyReminderChoice = Self.earlyReminderChoice(for: schedule.early)
        sourceDateText = Self.format(detachedDraft.date)
        sourceTimeText = Self.format(detachedDraft.time)
        switch schedule.end {
        case .never:
            repeatEndsOnDate = false
            repeatEndDateText = ""
        case let .onDate(date):
            repeatEndsOnDate = true
            repeatEndDateText = Self.format(date)
        }
        earlyReminderValueText = schedule.early.map { String($0.value) } ?? ""
        detachedDraft.scheduleChange = .replace(schedule)
        customRepeatState = .confirmed(preview)
        isReplacingCustomRepeat = false
        currentLocalizedRepeatSummary = localizedRepeatSummary(schedule)
        currentRepeatWasCustom = true
        canonicalEnglishDisclosure = preview.canonicalEnglish
        refreshPreview()
        resetSaveStateAfterEdit()
    }

    @discardableResult
    func save() async -> Bool {
        capacityConsent = .notProvided
        expiredScheduleConsent = .notProvided
        confirmedExpiredSaveRevision = nil
        return await performSave()
    }

    @discardableResult
    func confirmCapacitySave() async -> Bool {
        guard case .requiresCapacityConfirmation = saveState else { return false }
        capacityConsent = .acknowledged
        return await performSave()
    }

    func consumeExpiredScheduleConfirmation() -> Bool {
        guard case .requiresExpiredScheduleConfirmation = saveState,
              confirmedExpiredSaveRevision == nil
        else {
            return false
        }
        expiredScheduleConsent = .acknowledged
        confirmedExpiredSaveRevision = editRevision
        saveState = .saving
        return true
    }

    @discardableResult
    func performConfirmedExpiredScheduleSave() async -> Bool {
        guard let confirmedRevision = confirmedExpiredSaveRevision else { return false }
        confirmedExpiredSaveRevision = nil
        guard confirmedRevision == editRevision else {
            saveState = .idle
            capacityConsent = .notProvided
            expiredScheduleConsent = .notProvided
            return false
        }
        saveState = .idle
        return await performSave()
    }

    @discardableResult
    func confirmExpiredSave() async -> Bool {
        guard consumeExpiredScheduleConfirmation() else { return false }
        return await performConfirmedExpiredScheduleSave()
    }

    func requestDeleteConfirmation() {
        guard canDelete, saveState != .saving else { return }
        isDeleteConfirmationPresented = true
    }

    func cancelDeleteConfirmation() {
        isDeleteConfirmationPresented = false
    }

    func consumeDeleteConfirmation() -> Bool {
        guard isDeleteConfirmationPresented,
              canDelete,
              saveState != .saving
        else {
            return false
        }
        isDeleteConfirmationPresented = false
        confirmedDeleteIsPending = true
        saveState = .saving
        return true
    }

    @discardableResult
    func performConfirmedDelete() async -> Bool {
        guard confirmedDeleteIsPending else { return false }
        confirmedDeleteIsPending = false
        do {
            try await actions.delete(detachedDraft.id)
            saveState = .deleted
            return true
        } catch {
            saveState = .failed(.delete)
            return false
        }
    }

    @discardableResult
    func confirmDelete() async -> Bool {
        guard consumeDeleteConfirmation() else { return false }
        return await performConfirmedDelete()
    }

    func dismissPendingConfirmation() {
        guard saveState != .saving else { return }
        saveState = .idle
        capacityConsent = .notProvided
        expiredScheduleConsent = .notProvided
        confirmedExpiredSaveRevision = nil
    }

    private var canEditSchedule: Bool {
        if case .readOnly = scheduleAccess { false } else { true }
    }

    private var metadataIsValid: Bool {
        let candidate = detachedDraft
        if case .replace = candidate.scheduleChange {
            return (try? ReminderDraftValidator().validate(
                candidate,
                replacementScheduleData: Data([1])
            )) != nil
        }
        return (try? ReminderDraftValidator().validateMetadataOnly(candidate)) != nil
    }

    private var scheduleInputFieldsAreValid: Bool {
        guard canEditSchedule else { return true }

        let dateIsValid = if sourceDateText.isEmpty {
            detachedDraft.date == nil
        } else {
            sourceDateTextIsValid
        }
        let timeIsValid = if sourceTimeText.isEmpty {
            detachedDraft.time == nil
        } else {
            sourceTimeTextIsValid
        }
        return dateIsValid
            && timeIsValid
            && repeatEndDateTextIsValid
            && earlyReminderValueTextIsValid
    }

    private func refreshAnchorDependentPreset() {
        guard !currentRepeatWasCustom, let date = detachedDraft.date else { return }
        let preset: NotificationManagerDomain.RepeatPreset
        switch detachedDraft.rule {
        case let .weekly(interval: 1, weekdaySetKind: .explicit, weekdays)
            where weekdays.count == 1:
            preset = .weekly
        case let .weekly(interval: 2, weekdaySetKind: .explicit, weekdays)
            where weekdays.count == 1:
            preset = .biweekly
        default:
            return
        }
        let source = SourceWallClock(
            year: date.year,
            month: date.month,
            day: date.day,
            hour: detachedDraft.time?.hour ?? 0,
            minute: detachedDraft.time?.minute ?? 0,
            timeZoneIdentifier: detachedDraft.timeZoneIdentifier ?? "Africa/Abidjan"
        )
        if let rule = try? PresetRepeatRuleFactory().rule(for: preset, source: source) {
            detachedDraft.rule = rule
        }
    }

    private func refreshRepeatSummaryAfterSourceDateEdit() {
        guard let source = detachedDraft.source else {
            currentLocalizedRepeatSummary = nil
            if currentRepeatWasCustom { canonicalEnglishDisclosure = nil }
            return
        }
        currentLocalizedRepeatSummary = localizedRepeatSummary(ScheduleDefinition(
            source: source,
            rule: detachedDraft.rule,
            end: detachedDraft.end,
            early: detachedDraft.early
        ))
        if currentRepeatWasCustom { canonicalEnglishDisclosure = nil }
    }

    private func scheduleFieldChanged() {
        guard canEditSchedule else { return }
        scheduleHasEditIntent = true
        if isReplacingCustomRepeat {
            customRepeatState = .idle
            customRepeatSession = nil
            customSubmissionGeneration &+= 1
        }
        if let source = detachedDraft.source {
            detachedDraft.scheduleChange = .replace(ScheduleDefinition(
                source: source,
                rule: detachedDraft.rule,
                end: detachedDraft.end,
                early: detachedDraft.early
            ))
        } else {
            detachedDraft.scheduleChange = .preserveOriginal
        }
        refreshPreview()
        resetSaveStateAfterEdit()
    }

    private func refreshPreview() {
        guard scheduleInputFieldsAreValid else {
            previewNotifications = []
            showsPastEarlyWarning = false
            return
        }

        let schedule: ScheduleDefinition?
        switch detachedDraft.scheduleChange {
        case let .replace(replacement):
            schedule = replacement
        case .preserveOriginal:
            if case .editable = scheduleAccess,
               !requiresReplacementBeforeSave,
               let source = detachedDraft.source
            {
                schedule = ScheduleDefinition(
                    source: source,
                    rule: detachedDraft.rule,
                    end: detachedDraft.end,
                    early: detachedDraft.early
                )
            } else {
                schedule = nil
            }
        }

        guard let schedule,
              let result = try? NextNotificationProvider().nextPhysicalNotifications(
                  for: detachedDraft.id,
                  schedule: schedule,
                  after: previewNow,
                  limit: 3,
                  environment: recurrenceEnvironment
              )
        else {
            previewNotifications = []
            showsPastEarlyWarning = false
            return
        }
        previewNotifications = result.notifications
        showsPastEarlyWarning = result.didSkipPastEarly
    }

    private func resetSaveStateAfterEdit() {
        editRevision &+= 1
        guard saveState != .saving else { return }
        saveState = .idle
        capacityConsent = .notProvided
        expiredScheduleConsent = .notProvided
        confirmedExpiredSaveRevision = nil
    }

    private func performSave() async -> Bool {
        guard canSave else { return false }
        let submittedRevision = editRevision
        saveState = .saving
        let submittedDraft = detachedDraft
        do {
            let outcome = try await actions.save(
                submittedDraft,
                capacityConsent,
                expiredScheduleConsent
            )
            guard submittedRevision == editRevision else {
                saveState = .idle
                capacityConsent = .notProvided
                expiredScheduleConsent = .notProvided
                return false
            }
            switch outcome {
            case let .saved(id):
                saveState = .saved(id)
                return true
            case let .requiresCapacityConfirmation(warning):
                saveState = .requiresCapacityConfirmation(warning)
                return false
            case let .requiresExpiredScheduleConfirmation(warning):
                saveState = .requiresExpiredScheduleConfirmation(warning)
                return false
            }
        } catch {
            guard submittedRevision == editRevision else {
                saveState = .idle
                capacityConsent = .notProvided
                expiredScheduleConsent = .notProvided
                return false
            }
            saveState = .failed(.save)
            return false
        }
    }

    private static func format(_ value: SourceDate?) -> String {
        guard let value else { return "" }
        return String(format: "%04d-%02d-%02d", value.year, value.month, value.day)
    }

    private static func format(_ value: SourceTime?) -> String {
        guard let value else { return "" }
        return String(format: "%02d:%02d", value.hour, value.minute)
    }

    private static func parseSourceDate(_ input: String) -> SourceDate? {
        let values = input.split(separator: "-", omittingEmptySubsequences: false)
        guard values.count == 3,
              let year = Int(values[0]),
              let month = Int(values[1]),
              let day = Int(values[2])
        else {
            return nil
        }
        return SourceDate(year: year, month: month, day: day)
    }

    private static func parseSourceTime(_ input: String) -> SourceTime? {
        let values = input.split(separator: ":", omittingEmptySubsequences: false)
        guard values.count == 2,
              let hour = Int(values[0]),
              let minute = Int(values[1])
        else {
            return nil
        }
        return SourceTime(hour: hour, minute: minute)
    }

    private static func isValid(_ value: SourceDate) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: value.year, month: value.month, day: value.day)
        guard let date = calendar.date(from: components) else { return false }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        return resolved.year == value.year
            && resolved.month == value.month
            && resolved.day == value.day
    }

    private static func earlyReminderChoice(for early: EarlyReminder?) -> EarlyReminderChoice {
        switch early {
        case nil:
            .none
        case let .some(value) where value.value == 1 && value.unit == .minutes:
            .oneMinute
        case let .some(value) where value.value == 5 && value.unit == .minutes:
            .fiveMinutes
        case .some:
            .custom
        }
    }
}

private struct NoAssistedRepeatInterpreter: AssistedRepeatInterpreting {
    func availability() async -> AssistedRepeatAvailability {
        .unavailable(.platformUnsupported)
    }

    func interpret(_ input: String) async throws -> RepeatCandidate {
        throw AssistedRepeatInterpretationError.generation
    }
}
