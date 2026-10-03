import Foundation

/// 指挥页的显示快照。下标只在组装时用一次，按钮上留下的是会话身份和代次。
struct ConductorPageSnapshot: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        let id: WS2.SessionKey
        let revision: UInt64
        let label: String
    }
    struct Selection: Equatable, Sendable {
        let id: WS2.SessionKey
        let revision: UInt64
        let listRevision: UInt64
    }
    struct DraftFreeze: Equatable, Sendable {
        let text: String
        let model: String?
        let effort: String?
        let selection: Selection?
    }
    enum Refusal: Error, Equatable, Sendable {
        case markedText, staleSession, staleModel, staleEffort
    }

    let rows: [Row]
    let listRevision: UInt64
    let model: String?
    let effort: String?
    let draft: String

    static func assemble(sessions: [Row], previousRows: [Row], previousListRevision: UInt64,
                         model: String?, effort: String?, draft: String) -> Self {
        var seen = Set<WS2.SessionKey>()
        let rows = sessions.filter { row in
            row.id.isValid && row.label.utf8.count <= 512 && seen.insert(row.id).inserted
        }
        let sameIdentity = rows.count == previousRows.count && zip(rows, previousRows).allSatisfy {
            $0.id == $1.id && $0.revision == $1.revision
        }
        let listRevision: UInt64
        if sameIdentity {
            listRevision = previousListRevision
        } else if previousListRevision < .max {
            listRevision = previousListRevision &+ 1
        } else {
            listRevision = previousListRevision
        }
        return .init(rows: rows, listRevision: listRevision, model: model, effort: effort, draft: draft)
    }

    func confirm(_ selection: Selection) -> Bool {
        selection.listRevision == listRevision &&
            rows.contains { $0.id == selection.id && $0.revision == selection.revision }
    }

    func acceptSelection(_ selection: Selection) -> Result<Selection, Refusal> {
        confirm(selection) ? .success(selection) : .failure(.staleSession)
    }

    func freezeDraft(text: String, hasMarkedText: Bool, selection: Selection?) -> Result<DraftFreeze, Refusal> {
        if hasMarkedText { return .failure(.markedText) }
        if let selection, !confirm(selection) { return .failure(.staleSession) }
        return .success(.init(text: text, model: model, effort: effort, selection: selection))
    }

    func acceptDraft(_ frozen: DraftFreeze) -> Result<DraftFreeze, Refusal> {
        if frozen.model != model { return .failure(.staleModel) }
        if frozen.effort != effort { return .failure(.staleEffort) }
        if let selection = frozen.selection, !confirm(selection) { return .failure(.staleSession) }
        return .success(frozen)
    }

    /// 空字符串和目录里没有的名字都不算选中。缺目录时不另造一个。
    static func acceptChoice(_ id: String, catalogue: Set<String>) -> Bool {
        !id.isEmpty && id.utf8.count <= 512 && catalogue.contains(id)
    }
}
