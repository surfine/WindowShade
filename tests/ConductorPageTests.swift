import Foundation

@main struct ConductorPageTests {
    static func main() {
        var failures = 0
        func check(_ condition: Bool, _ message: String) {
            if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
        }
        let a = WS2.SessionKey(provider: .codex, id: "thread-a")
        let b = WS2.SessionKey(provider: .claudeCode, id: "thread-b")
        let rowA = ConductorPageSnapshot.Row(id: a, revision: 3, label: "甲")
        let rowB = ConductorPageSnapshot.Row(id: b, revision: 1, label: "乙")
        let first = ConductorPageSnapshot.assemble(sessions: [rowA, rowB], previousRows: [], previousListRevision: 0,
                                                   model: "fixture-a", effort: "medium", draft: "旧草稿")
        check(first.listRevision == 1, "a new list gets a revision")
        check(first.rows.map(\.id) == [a, b], "order follows the snapshot, not a reused index")
        let swapped = ConductorPageSnapshot.assemble(sessions: [rowB, rowA], previousRows: first.rows,
                                                     previousListRevision: first.listRevision,
                                                     model: "fixture-a", effort: "medium", draft: "旧草稿")
        let pickA = ConductorPageSnapshot.Selection(id: a, revision: 3, listRevision: swapped.listRevision)
        check(swapped.confirm(pickA), "reordering keeps the same session")
        check(swapped.rows.first?.id == b && pickA.id == a, "the first row can change without the saved choice following it")
        let replaced = ConductorPageSnapshot.assemble(
            sessions: [ConductorPageSnapshot.Row(id: a, revision: 4, label: "甲")],
            previousRows: swapped.rows, previousListRevision: swapped.listRevision,
            model: "fixture-a", effort: "medium", draft: "旧草稿")
        check(!replaced.confirm(pickA), "a new connection generation invalidates the old choice")
        check(replaced.listRevision != swapped.listRevision, "identity change bumps the list revision")
        let same = ConductorPageSnapshot.assemble(sessions: replaced.rows, previousRows: replaced.rows,
                                                  previousListRevision: replaced.listRevision,
                                                  model: "fixture-a", effort: "medium", draft: "新字")
        check(same.listRevision == replaced.listRevision, "the same identities keep the list revision")
        let live = ConductorPageSnapshot.Selection(id: a, revision: 4, listRevision: same.listRevision)
        switch same.freezeDraft(text: "半成品", hasMarkedText: true, selection: live) {
        case .failure(.markedText): check(same.draft == "新字", "unfinished input leaves the stored draft")
        default: check(false, "unfinished input leaves the stored draft")
        }
        guard case .success(let frozen) = same.freezeDraft(text: "定稿", hasMarkedText: false, selection: live) else {
            check(false, "a finished draft freezes the text, model, and effort")
            exit(1)
        }
        check(frozen.text == "定稿" && frozen.model == "fixture-a" && frozen.effort == "medium",
              "a finished draft freezes the text, model, and effort")
        let moved = ConductorPageSnapshot.assemble(sessions: same.rows, previousRows: same.rows,
                                                   previousListRevision: same.listRevision,
                                                   model: "other", effort: "medium", draft: "新字")
        switch moved.acceptDraft(frozen) {
        case .failure(.staleModel): check(true, "a model change after the press is refused")
        default: check(false, "a model change after the press is refused")
        }
        switch same.acceptDraft(frozen) {
        case .success(let accepted): check(accepted.text == "定稿", "an unchanged snapshot accepts the frozen text")
        default: check(false, "an unchanged snapshot accepts the frozen text")
        }
        let unknown = ConductorPageSnapshot.assemble(sessions: [], previousRows: [], previousListRevision: 0,
                                                     model: nil, effort: nil, draft: "")
        guard case .success(let bare) = unknown.freezeDraft(text: "只有文字", hasMarkedText: false, selection: nil) else {
            check(false, "a missing model stays missing")
            exit(1)
        }
        check(bare.model == nil && bare.effort == nil, "a missing model stays missing")
        let duplicate = ConductorPageSnapshot.Row(id: a, revision: 9, label: "重复")
        let cleaned = ConductorPageSnapshot.assemble(sessions: [rowA, duplicate, ConductorPageSnapshot.Row(id: .init(provider: .codex, id: ""), revision: 1, label: "空")],
                                                     previousRows: [], previousListRevision: 0,
                                                     model: nil, effort: nil, draft: "")
        check(cleaned.rows.count == 1 && cleaned.rows[0].revision == 3, "duplicate and empty session ids are dropped")
        check(ConductorPageSnapshot.acceptChoice("fixture-a", catalogue: ["fixture-a"]), "a listed model is accepted")
        check(!ConductorPageSnapshot.acceptChoice("invented", catalogue: ["fixture-a"]), "an unlisted model is refused")
        check(!ConductorPageSnapshot.acceptChoice("fixture-a", catalogue: []), "an empty catalogue does not accept a name")
        print(failures == 0 ? "all conductor page tests passed" : "\(failures) failure(s)")
        if failures != 0 { exit(1) }
    }
}
