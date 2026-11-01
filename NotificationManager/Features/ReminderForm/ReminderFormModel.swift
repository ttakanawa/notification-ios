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
        case .standard(let localizedSummary), .custom(let localizedSummary, _):
            localizedSummary
        }
    }

    var canonicalEnglishDisclosure: String? {
        guard case .custom(_, let disclosure) = self else { return nil }
        return disclosure
    }
}

struct ReminderFormActions: Sendable {
    let save:
        @Sendable (
            ReminderDraft,
            CapacityConsent,
            ExpiredScheduleConsent
        ) async throws -> SaveReminderOutcome
    let delete: @Sendable (UUID) async throws -> Void

    init(
        save:
            @escaping @Sendable (
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
    case thirtySeconds
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

enum CustomRepeatAppleIntelligenceStatus: Sendable, Equatable {
    case checking
    case available
    case unavailable(AssistedRepeatUnavailableReason)
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
    private(set) var repeatEndsOnDate = false
    private(set) var earlyReminderChoice: EarlyReminderChoice = .none
    private(set) var customRepeatText = ""
    private(set) var isReplacingCustomRepeat = false
    private(set) var customRepeatState: CustomRepeatSessionState = .idle
    private(set) var customRepeatAppleIntelligenceStatus: CustomRepeatAppleIntelligenceStatus =
        .checking
    private(set) var isInterpretingWithAppleIntelligence = false
    private(set) var previewNotifications: [PhysicalNotification] = []
    private(set) var showsPastEarlyWarning = false
    private(set) var isDeleteConfirmationPresented = false
    private(set) var saveState: ReminderFormSaveState = .idle

    @ObservationIgnored private let actions: ReminderFormActions
    @ObservationIgnored private let previewNow: Date
    @ObservationIgnored private let recurrenceEnvironment: any RecurrenceEnvironment
    @ObservationIgnored private let assistedRepeatInterpreter: any AssistedRepeatInterpreting
    @ObservationIgnored private let localizedRepeatSummary: @Sendable (ScheduleDefinition) -> String
    @ObservationIgnored private let pickerFallbackTimeZone: TimeZone
    @ObservationIgnored private var customRepeatSession: CustomRepeatSession?
    @ObservationIgnored private var customSubmissionGeneration: UInt64 = 0
    @ObservationIgnored private var activeAppleIntelligenceRequests = 0
    @ObservationIgnored private var appleIntelligenceStatusRefreshGeneration: UInt64 = 0
    @ObservationIgnored private var editRevision: UInt64 = 0
    @ObservationIgnored private var saveOperationGeneration: UInt64 = 0
    @ObservationIgnored private var capacityConsent: CapacityConsent = .notProvided
    @ObservationIgnored private var expiredScheduleConsent: ExpiredScheduleConsent = .notProvided
    @ObservationIgnored private var confirmedExpiredSaveRevision: UInt64?
    @ObservationIgnored private var confirmedDeleteIsPending = false
    @ObservationIgnored private var scheduleHasEditIntent = false
    @ObservationIgnored private let requiresReplacementBeforeSave: Bool
    @ObservationIgnored private var baseline: ReminderFormBaseline?

    init(
        newReminderID: UUID,
        now: Date,
        actions: ReminderFormActions,
        availableTags: [ReminderTagPresentation] = [],
        defaultTimeZone: TimeZone = .current,
        recurrenceEnvironment: any RecurrenceEnvironment = FoundationRecurrenceEnvironment(),
        assistedRepeatInterpreter: any AssistedRepeatInterpreting = NoAssistedRepeatInterpreter(),
        localizedRepeatSummary: @escaping @Sendable (ScheduleDefinition) -> String = {
            CanonicalRepeatFormatter().string(for: $0.rule)
        }
    ) {
        let timeZone = Self.validatedPickerFallbackTimeZone(defaultTimeZone)
        let adapter = SourceWallClockDateAdapter(timeZone: timeZone)
        guard let source = adapter.nextWholeHour(after: now) else {
            preconditionFailure("Foundation could not find the next whole hour")
        }
        let schedule = ScheduleDefinition(
            source: source,
            rule: .none,
            end: .never,
            early: nil
        )
        var initialDraft = ReminderDraft(id: newReminderID, now: now)
        initialDraft.source = source
        initialDraft.scheduleChange = .replace(schedule)
        detachedDraft = initialDraft
        scheduleAccess = .editable
        canDelete = false
        self.availableTags = availableTags
        self.actions = actions
        previewNow = now
        self.recurrenceEnvironment = recurrenceEnvironment
        self.assistedRepeatInterpreter = assistedRepeatInterpreter
        self.localizedRepeatSummary = localizedRepeatSummary
        pickerFallbackTimeZone = timeZone
        requiresReplacementBeforeSave = true
        refreshPreview()
    }

    init(
        snapshot: ReminderSnapshot,
        savedRepeatPresentation: SavedRepeatPresentation?,
        now: Date,
        actions: ReminderFormActions,
        availableTags: [ReminderTagPresentation] = [],
        defaultTimeZone: TimeZone = .current,
        recurrenceEnvironment: any RecurrenceEnvironment = FoundationRecurrenceEnvironment(),
        assistedRepeatInterpreter: any AssistedRepeatInterpreting = NoAssistedRepeatInterpreter(),
        localizedRepeatSummary: @escaping @Sendable (ScheduleDefinition) -> String = {
            CanonicalRepeatFormatter().string(for: $0.rule)
        }
    ) {
        let initialDraft = ReminderDraft(snapshot: snapshot)
        detachedDraft = initialDraft
        if case .onDate = initialDraft.end {
            repeatEndsOnDate = true
        }
        earlyReminderChoice = Self.earlyReminderChoice(for: initialDraft.early)
        canDelete = true
        self.availableTags = availableTags
        self.actions = actions
        previewNow = now
        self.recurrenceEnvironment = recurrenceEnvironment
        self.assistedRepeatInterpreter = assistedRepeatInterpreter
        self.localizedRepeatSummary = localizedRepeatSummary
        pickerFallbackTimeZone = Self.validatedPickerFallbackTimeZone(defaultTimeZone)
        currentLocalizedRepeatSummary = savedRepeatPresentation?.localizedSummary
        if case .custom = savedRepeatPresentation {
            currentRepeatWasCustom = true
        } else if RepeatPreset(rule: initialDraft.rule) == nil {
            currentRepeatWasCustom = true
        }
        canonicalEnglishDisclosure = savedRepeatPresentation?.canonicalEnglishDisclosure

        switch snapshot.schedule {
        case .valid:
            scheduleAccess = .editable
            requiresReplacementBeforeSave = false
        case .domainInvalid(_, _, let issues):
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
        baseline = ReminderFormBaseline(
            draft: detachedDraft,
            editableContent: currentEditableContent,
            currentLocalizedRepeatSummary: currentLocalizedRepeatSummary,
            currentRepeatWasCustom: currentRepeatWasCustom,
            canonicalEnglishDisclosure: canonicalEnglishDisclosure
        )
    }

    var title: String {
        get { detachedDraft.title }
        set {
            guard newValue != detachedDraft.title else { return }
            detachedDraft.title = newValue
            resetSaveStateAfterEdit()
        }
    }

    var notes: String? {
        get { detachedDraft.notes }
        set {
            guard newValue != detachedDraft.notes else { return }
            detachedDraft.notes = newValue
            resetSaveStateAfterEdit()
        }
    }

    var urlString: String? {
        get { detachedDraft.urlString }
        set {
            guard newValue != detachedDraft.urlString else { return }
            detachedDraft.urlString = newValue
            resetSaveStateAfterEdit()
        }
    }

    var enabled: Bool {
        get { detachedDraft.enabled }
        set {
            guard newValue != detachedDraft.enabled else { return }
            detachedDraft.enabled = newValue
            resetSaveStateAfterEdit()
        }
    }

    var tagIDs: Set<UUID> {
        get { detachedDraft.tagIDs }
        set {
            guard newValue != detachedDraft.tagIDs else { return }
            detachedDraft.tagIDs = newValue
            resetSaveStateAfterEdit()
        }
    }

    func commitTagRemoval(_ tagID: UUID) {
        guard detachedDraft.tagIDs.remove(tagID) != nil else { return }
        if var baseline {
            baseline.draft.tagIDs.remove(tagID)
            baseline.editableContent.tagIDs.remove(tagID)
            self.baseline = baseline
        }
        resetSaveStateAfterEdit()
    }

    var sourceDate: SourceDate? {
        get { detachedDraft.date }
        set {
            guard canEditSchedule, newValue != detachedDraft.date else { return }
            detachedDraft.date = newValue
            refreshAnchorDependentPreset()
            scheduleFieldChanged()
            refreshRepeatSummaryAfterSourceDateEdit()
        }
    }

    var sourceTime: SourceTime? {
        get { detachedDraft.time }
        set {
            guard canEditSchedule, newValue != detachedDraft.time else { return }
            detachedDraft.time = newValue
            scheduleFieldChanged()
        }
    }

    var timeZoneIdentifier: String? {
        get { detachedDraft.timeZoneIdentifier }
        set {
            guard canEditSchedule,
                newValue != detachedDraft.timeZoneIdentifier
            else {
                return
            }
            detachedDraft.timeZoneIdentifier = newValue
            scheduleFieldChanged()
        }
    }

    var repeatRule: RepeatRule {
        get { detachedDraft.rule }
        set {
            guard canEditSchedule else { return }
            guard
                newValue != detachedDraft.rule
                    || isReplacingCustomRepeat
                    || currentRepeatWasCustom
            else {
                return
            }
            detachedDraft.rule = newValue
            if newValue == .none {
                detachedDraft.end = .never
                repeatEndsOnDate = false
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
            guard canEditSchedule, newValue != detachedDraft.end else { return }
            detachedDraft.end = newValue
            switch newValue {
            case .never:
                repeatEndsOnDate = false
            case .onDate:
                repeatEndsOnDate = true
            }
            scheduleFieldChanged()
        }
    }

    var earlyReminder: EarlyReminder? {
        get { detachedDraft.early }
        set {
            guard canEditSchedule, newValue != detachedDraft.early else { return }
            detachedDraft.early = newValue
            earlyReminderChoice = Self.earlyReminderChoice(for: newValue)
            scheduleFieldChanged()
        }
    }

    var earlyReminderAmountChoices: [Int] {
        guard let early = detachedDraft.early else { return [] }
        return EarlyReminderAmountOptions.values(for: early)
    }

    var canEditMetadata: Bool { true }

    var scheduleFieldsAreEditable: Bool { canEditSchedule }

    var pickerTimeZone: TimeZone {
        guard let identifier = detachedDraft.timeZoneIdentifier,
            let timeZone = TimeZone(identifier: identifier)
        else {
            return pickerFallbackTimeZone
        }
        return timeZone
    }

    var sourceDatePickerValue: Date? {
        guard let sourceDate else { return nil }
        return SourceWallClockDateAdapter(timeZone: pickerTimeZone).instant(
            date: sourceDate,
            time: SourceTime(hour: 12, minute: 0)
        )
    }

    var sourceTimePickerValue: Date? {
        guard let sourceTime else { return nil }
        return SourceWallClockDateAdapter(timeZone: pickerTimeZone).instant(
            date: SourceDate(year: 2001, month: 1, day: 1),
            time: sourceTime
        )
    }

    var repeatEndDatePickerValue: Date? {
        guard case .onDate(let value) = repeatEnd else { return nil }
        return SourceWallClockDateAdapter(timeZone: pickerTimeZone).instant(
            date: value,
            time: SourceTime(hour: 12, minute: 0)
        )
    }

    var missingPickerDefaultValue: Date {
        let adapter = SourceWallClockDateAdapter(timeZone: pickerTimeZone)
        return adapter.instant(
            date: sourceDate ?? adapter.sourceDate(from: previewNow),
            time: sourceTime ?? adapter.sourceTime(from: previewNow)
        ) ?? previewNow
    }

    var hasChanges: Bool {
        guard let baseline else { return false }
        return currentEditableContent != baseline.editableContent
    }

    var titleFieldIssue: ReminderFormFieldIssue? {
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

    var repeatEndDateFieldIssue: ReminderFormFieldIssue? {
        guard repeatEndsOnDate else {
            return repeatEnd == .never ? nil : .repeatEndInvalid
        }
        guard case .onDate(let value) = repeatEnd else { return .repeatEndInvalid }
        guard let start = sourceDate else { return nil }
        return (value.year, value.month, value.day) < (start.year, start.month, start.day)
            ? .repeatEndBeforeStart
            : nil
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
        return
            (try? ReminderDraftValidator().validate(
                detachedDraft,
                replacementScheduleData: Data([1])
            )) != nil
    }

    func updateSourceDate(from value: Date) {
        sourceDate = SourceWallClockDateAdapter(timeZone: pickerTimeZone)
            .sourceDate(from: value)
    }

    func updateSourceTime(from value: Date) {
        sourceTime = SourceWallClockDateAdapter(timeZone: pickerTimeZone)
            .sourceTime(from: value)
    }

    func updateRepeatEndDate(from value: Date) {
        guard canEditSchedule, repeatEndsOnDate else { return }
        repeatEnd = .onDate(
            SourceWallClockDateAdapter(timeZone: pickerTimeZone).sourceDate(from: value)
        )
    }

    func updateEarlyReminderAmount(_ amount: Int) {
        guard canEditSchedule,
            let current = detachedDraft.early,
            amount != current.value,
            EarlyReminderAmountOptions.standardRange(for: current.unit).contains(amount)
        else {
            return
        }
        detachedDraft.early = EarlyReminder(
            value: amount,
            unit: current.unit,
            mainEnabled: current.mainEnabled
        )
        earlyReminderChoice = .custom
        scheduleFieldChanged()
    }

    func updateEarlyReminderUnit(_ unit: EarlyReminderUnit) {
        guard canEditSchedule,
            let current = detachedDraft.early,
            unit != current.unit
        else {
            return
        }
        let amount = EarlyReminderAmountOptions.clamped(current.value, for: unit)
        detachedDraft.early = EarlyReminder(
            value: amount,
            unit: unit,
            mainEnabled: current.mainEnabled
        )
        earlyReminderChoice = .custom
        scheduleFieldChanged()
    }

    func updateMainNotificationEnabled(_ enabled: Bool) {
        guard canEditSchedule,
            let current = detachedDraft.early,
            enabled != current.mainEnabled
        else {
            return
        }
        detachedDraft.early = EarlyReminder(
            value: current.value,
            unit: current.unit,
            mainEnabled: enabled
        )
        scheduleFieldChanged()
    }

    func applyEarlyReminderChoice(_ choice: EarlyReminderChoice) {
        guard canEditSchedule, choice != earlyReminderChoice else { return }
        let mainEnabled = detachedDraft.early?.mainEnabled ?? true
        switch choice {
        case .none:
            detachedDraft.early = nil
        case .thirtySeconds:
            detachedDraft.early = EarlyReminder(
                value: 30,
                unit: .seconds,
                mainEnabled: mainEnabled
            )
        case .oneMinute:
            detachedDraft.early = EarlyReminder(
                value: 1,
                unit: .minutes,
                mainEnabled: mainEnabled
            )
        case .fiveMinutes:
            detachedDraft.early = EarlyReminder(
                value: 5,
                unit: .minutes,
                mainEnabled: mainEnabled
            )
        case .custom:
            if detachedDraft.early == nil {
                detachedDraft.early = EarlyReminder(value: 5, unit: .minutes)
            }
        }
        earlyReminderChoice = choice
        scheduleFieldChanged()
    }

    @discardableResult
    func applyRepeatPreset(_ preset: NotificationManagerDomain.RepeatPreset) -> Bool {
        if preset == .weekly || preset == .biweekly, detachedDraft.date == nil {
            return false
        }
        let factorySource =
            detachedDraft.source
            ?? SourceWallClock(
                year: detachedDraft.date?.year ?? 2001,
                month: detachedDraft.date?.month ?? 1,
                day: detachedDraft.date?.day ?? 1,
                hour: detachedDraft.time?.hour ?? 0,
                minute: detachedDraft.time?.minute ?? 0,
                timeZoneIdentifier: detachedDraft.timeZoneIdentifier ?? "Africa/Abidjan"
            )
        guard
            let rule = try? PresetRepeatRuleFactory().rule(
                for: preset,
                source: factorySource
            )
        else {
            return false
        }
        repeatRule = rule
        return true
    }

    func setRepeatEndsOnDate(_ enabled: Bool) {
        guard canEditSchedule,
            detachedDraft.rule != .none,
            enabled != repeatEndsOnDate
        else {
            return
        }
        repeatEndsOnDate = enabled
        if !enabled {
            detachedDraft.end = .never
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
        guard isReplacingCustomRepeat, input != customRepeatText else { return }
        customRepeatText = input
        customRepeatState = .idle
        customRepeatSession = nil
        customSubmissionGeneration &+= 1
        resetSaveStateAfterEdit()
    }

    func submitCustomRepeat() async {
        await submitCustomRepeat(mode: .automatic)
    }

    func interpretCustomRepeatWithAppleIntelligence() async {
        activeAppleIntelligenceRequests += 1
        isInterpretingWithAppleIntelligence = true
        defer {
            activeAppleIntelligenceRequests -= 1
            isInterpretingWithAppleIntelligence =
                activeAppleIntelligenceRequests > 0
        }
        await submitCustomRepeat(mode: .assistedOnly)
    }

    func refreshCustomRepeatAppleIntelligenceStatus() async {
        appleIntelligenceStatusRefreshGeneration &+= 1
        let generation = appleIntelligenceStatusRefreshGeneration
        customRepeatAppleIntelligenceStatus = .checking
        let availability = await assistedRepeatInterpreter.availability()
        guard !Task.isCancelled,
            generation == appleIntelligenceStatusRefreshGeneration
        else { return }

        switch availability {
        case .available:
            customRepeatAppleIntelligenceStatus = .available
        case .unavailable(let reason):
            customRepeatAppleIntelligenceStatus = .unavailable(reason)
        }
    }

    private func submitCustomRepeat(mode: CustomRepeatResolutionMode) async {
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
            let outcome = try await session.submit(customRepeatText, mode: mode)
            guard generation == customSubmissionGeneration else { return }
            if case .applied(let state) = outcome {
                customRepeatState = state
            }
        } catch {
            guard generation == customSubmissionGeneration else { return }
            customRepeatState = .failed(.generation)
        }
    }

    func selectCustomRepeatSuggestion(_ suggestion: String) async {
        guard case .awaitingSuggestions(let suggestions) = customRepeatState,
            suggestions.contains(suggestion)
        else {
            return
        }
        updateCustomRepeatText(suggestion)
        await submitCustomRepeat()
    }

    func confirmCustomRepeat() async {
        guard let customRepeatSession,
            let schedule = await customRepeatSession.confirm(),
            case .awaitingConfirmation(let preview) = customRepeatState
        else {
            return
        }

        detachedDraft.source = schedule.source
        detachedDraft.rule = schedule.rule
        detachedDraft.end = schedule.end
        detachedDraft.early = schedule.early
        earlyReminderChoice = Self.earlyReminderChoice(for: schedule.early)
        switch schedule.end {
        case .never:
            repeatEndsOnDate = false
        case .onDate:
            repeatEndsOnDate = true
        }
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

    func discardChanges() {
        guard let baseline else { return }
        customSubmissionGeneration &+= 1
        editRevision &+= 1
        customRepeatSession = nil
        customRepeatState = .idle
        detachedDraft = baseline.draft
        repeatEndsOnDate = baseline.editableContent.repeatEndsOnDate
        earlyReminderChoice = baseline.editableContent.earlyReminderChoice
        isReplacingCustomRepeat = baseline.editableContent.isReplacingCustomRepeat
        customRepeatText = baseline.editableContent.customRepeatText
        currentLocalizedRepeatSummary = baseline.currentLocalizedRepeatSummary
        currentRepeatWasCustom = baseline.currentRepeatWasCustom
        canonicalEnglishDisclosure = baseline.canonicalEnglishDisclosure
        scheduleHasEditIntent = false
        isDeleteConfirmationPresented = false
        confirmedDeleteIsPending = false
        saveState = .idle
        capacityConsent = .notProvided
        expiredScheduleConsent = .notProvided
        confirmedExpiredSaveRevision = nil
        refreshPreview()
    }

    private var canEditSchedule: Bool {
        if case .readOnly = scheduleAccess { false } else { true }
    }

    private var currentEditableContent: ReminderFormEditableContent {
        ReminderFormEditableContent(
            title: detachedDraft.title,
            notes: detachedDraft.notes,
            urlString: detachedDraft.urlString,
            enabled: detachedDraft.enabled,
            tagIDs: detachedDraft.tagIDs,
            sourceDate: detachedDraft.date,
            sourceTime: detachedDraft.time,
            timeZoneIdentifier: detachedDraft.timeZoneIdentifier,
            repeatRule: detachedDraft.rule,
            repeatEnd: detachedDraft.end,
            repeatEndsOnDate: repeatEndsOnDate,
            earlyReminder: detachedDraft.early,
            earlyReminderChoice: earlyReminderChoice,
            isReplacingCustomRepeat: isReplacingCustomRepeat,
            currentRepeatWasCustom: currentRepeatWasCustom,
            customRepeatText: customRepeatText
        )
    }

    private var metadataIsValid: Bool {
        let candidate = detachedDraft
        if case .replace = candidate.scheduleChange {
            return
                (try? ReminderDraftValidator().validate(
                    candidate,
                    replacementScheduleData: Data([1])
                )) != nil
        }
        return (try? ReminderDraftValidator().validateMetadataOnly(candidate)) != nil
    }

    private var scheduleInputFieldsAreValid: Bool {
        guard canEditSchedule else { return true }
        return repeatEndDateFieldIssue == nil
    }

    private func refreshAnchorDependentPreset() {
        guard !currentRepeatWasCustom, let date = detachedDraft.date else { return }
        let preset: NotificationManagerDomain.RepeatPreset
        switch detachedDraft.rule {
        case .weekly(interval: 1, weekdaySetKind: .explicit, let weekdays)
        where weekdays.count == 1:
            preset = .weekly
        case .weekly(interval: 2, weekdaySetKind: .explicit, let weekdays)
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
        currentLocalizedRepeatSummary = localizedRepeatSummary(
            ScheduleDefinition(
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
            detachedDraft.scheduleChange = .replace(
                ScheduleDefinition(
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
        case .replace(let replacement):
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
        saveOperationGeneration &+= 1
        let submittedSaveOperationGeneration = saveOperationGeneration
        saveState = .saving
        let submittedDraft = detachedDraft
        do {
            let outcome = try await actions.save(
                submittedDraft,
                capacityConsent,
                expiredScheduleConsent
            )
            guard submittedSaveOperationGeneration == saveOperationGeneration else {
                return false
            }
            guard submittedRevision == editRevision else {
                saveState = .idle
                capacityConsent = .notProvided
                expiredScheduleConsent = .notProvided
                return false
            }
            switch outcome {
            case .saved(let id):
                saveState = .saved(id)
                return true
            case .requiresCapacityConfirmation(let warning):
                saveState = .requiresCapacityConfirmation(warning)
                return false
            case .requiresExpiredScheduleConfirmation(let warning):
                saveState = .requiresExpiredScheduleConfirmation(warning)
                return false
            }
        } catch {
            guard submittedSaveOperationGeneration == saveOperationGeneration else {
                return false
            }
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

    private static func validatedPickerFallbackTimeZone(_ timeZone: TimeZone) -> TimeZone {
        TimeZone.knownTimeZoneIdentifiers.contains(timeZone.identifier)
            ? timeZone
            : TimeZone(identifier: "GMT")!
    }

    private static func earlyReminderChoice(for early: EarlyReminder?) -> EarlyReminderChoice {
        switch early {
        case nil:
            .none
        case .some(let value) where value.value == 30 && value.unit == .seconds:
            .thirtySeconds
        case .some(let value) where value.value == 1 && value.unit == .minutes:
            .oneMinute
        case .some(let value) where value.value == 5 && value.unit == .minutes:
            .fiveMinutes
        case .some:
            .custom
        }
    }
}

private struct ReminderFormEditableContent: Equatable {
    let title: String
    let notes: String?
    let urlString: String?
    let enabled: Bool
    var tagIDs: Set<UUID>
    let sourceDate: SourceDate?
    let sourceTime: SourceTime?
    let timeZoneIdentifier: String?
    let repeatRule: RepeatRule
    let repeatEnd: RepeatEnd
    let repeatEndsOnDate: Bool
    let earlyReminder: EarlyReminder?
    let earlyReminderChoice: EarlyReminderChoice
    let isReplacingCustomRepeat: Bool
    let currentRepeatWasCustom: Bool
    let customRepeatText: String
}

private struct ReminderFormBaseline {
    var draft: ReminderDraft
    var editableContent: ReminderFormEditableContent
    let currentLocalizedRepeatSummary: String?
    let currentRepeatWasCustom: Bool
    let canonicalEnglishDisclosure: String?
}

private struct NoAssistedRepeatInterpreter: AssistedRepeatInterpreting {
    func availability() async -> AssistedRepeatAvailability {
        .unavailable(.platformUnsupported)
    }

    func interpret(_ input: String) async throws -> RepeatCandidate {
        throw AssistedRepeatInterpretationError.generation
    }
}
