import SwiftUI

// MARK: - Ask AI about this case (Pro)
//
// A follow-up chat the player opens after finishing a case to clear doubts.
// They pick ChatGPT (OpenAI) or Gemini; every message goes through the `ask-ai`
// Edge Function, which holds the API keys server-side. The finished case's
// details are sent as context so answers stay specific to what they just solved.
struct CaseDoubtChat: View {
    let clinicalCase: ClinicalCase
    @Environment(\.dismiss) private var dismiss

    enum Provider: String, CaseIterable, Identifiable {
        case chatgpt, gemini
        var id: String { rawValue }
        var label: String { self == .chatgpt ? "ChatGPT" : "Gemini" }
        var apiValue: String { self == .chatgpt ? "openai" : "gemini" }
        var icon: String { self == .chatgpt ? "bubble.left.and.text.bubble.right.fill" : "sparkles" }
    }

    @State private var provider: Provider = .chatgpt
    @State private var messages: [SupabaseService.AIMessage] = []
    @State private var input = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            AppBackground {
                VStack(spacing: 0) {
                    providerPicker
                    Divider().overlay(CX.hairline)
                    chatScroll
                    inputBar
                }
            }
            .navigationTitle("Ask AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: Pieces

    private var providerPicker: some View {
        VStack(spacing: 6) {
            Picker("AI", selection: $provider) {
                ForEach(Provider.allCases) { p in
                    Label(p.label, systemImage: p.icon).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.top, 10)
            Text("Ask about “\(clinicalCase.displayTitle)”. Educational only — not medical advice.")
                .font(CX.label(11)).foregroundStyle(CX.navySoft)
                .multilineTextAlignment(.center).padding(.horizontal, 16).padding(.bottom, 6)
        }
    }

    private var chatScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty { emptyState }
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, m in
                        bubble(m)
                    }
                    if sending { typingBubble.id("typing") }
                    if let error {
                        Text(error).font(CX.label(13)).foregroundStyle(CX.orange)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: sending) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            VixClip(anim: .writing, size: 120, fallback: .idea)
            Text("Still curious about this case?").font(CX.heading(18)).foregroundStyle(CX.navy)
            Text("Ask why a test mattered, how the diagnosis was reached, or what you'd do differently.")
                .font(CX.body(14)).foregroundStyle(CX.navySoft).multilineTextAlignment(.center)
            VStack(spacing: 8) {
                suggestion("Why was this the most likely diagnosis?")
                suggestion("Which test was most useful, and why?")
                suggestion("What should I read to understand this better?")
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 24)
    }

    private func suggestion(_ text: String) -> some View {
        Button { input = text; send() } label: {
            Text(text).font(CX.body(14)).foregroundStyle(CX.teal)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(CX.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CX.hairline, lineWidth: 1))
        }
        .disabled(sending)
    }

    private func bubble(_ m: SupabaseService.AIMessage) -> some View {
        let isUser = m.role == "user"
        return HStack {
            if isUser { Spacer(minLength: 40) }
            Text(m.content)
                .font(CX.body(15))
                .foregroundStyle(isUser ? .white : CX.navy)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(isUser ? AnyShapeStyle(CX.orangeButton) : AnyShapeStyle(Color.white),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isUser ? .clear : CX.hairline, lineWidth: 1))
                .textSelection(.enabled)
            if !isUser { Spacer(minLength: 40) }
        }
    }

    private var typingBubble: some View {
        HStack {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).tint(CX.teal)
                Text("\(provider.label) is thinking…").font(CX.label(13)).foregroundStyle(CX.navySoft)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CX.hairline, lineWidth: 1))
            Spacer(minLength: 40)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask a question…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.white, in: Capsule())
                .overlay(Capsule().stroke(CX.hairline, lineWidth: 1.5))
            Button { send() } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
                    .foregroundStyle(canSend ? CX.orange : CX.navySoft)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var canSend: Bool { !sending && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: Send

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        input = ""
        error = nil
        inputFocused = false
        messages.append(.init(role: "user", content: text))
        sending = true
        let context = Self.caseContext(clinicalCase)
        let history = messages
        Task {
            defer { sending = false }
            do {
                let reply = try await SupabaseService.shared.askAI(
                    provider: provider.apiValue, caseContext: context, messages: history)
                messages.append(.init(role: "assistant", content: reply))
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Try again."
            }
        }
    }

    /// "Heading:" followed by one "Name (tag): why" line per option that has a
    /// rationale authored. Empty when none do.
    private static func optionNotes(_ heading: String, _ options: [(String, String, String)]) -> [String] {
        let notes = options.filter { !$0.2.trimmed.isEmpty }.map { name, tag, why in
            "  \(name)\(tag.trimmed.isEmpty ? "" : " (\(tag))"): \(why)"
        }
        return notes.isEmpty ? [] : ["\(heading):"] + notes
    }

    /// A compact, self-contained description of the finished case for the tutor.
    static func caseContext(_ c: ClinicalCase) -> String {
        var lines: [String] = []
        lines.append("Title: \(c.displayTitle)")
        lines.append("Specialty: \(c.specialty)")
        lines.append("Patient: \(c.patientName), \(c.age), \(c.gender)")
        lines.append("Chief complaint: \(c.chiefComplaint)")
        for card in c.infoCards {
            // Sections are authored as flat bullets, grouped findings, or both.
            var parts = card.bullets
            parts += card.groups.map { "\($0.system): " + $0.findings.joined(separator: "; ") }
            if !parts.isEmpty { lines.append("\(card.title): " + parts.joined(separator: "; ")) }
        }
        if !c.tests.isEmpty {
            let t = c.tests.map { "\($0.name) → \($0.result)\($0.helpful ? " (key)" : "")" }.joined(separator: "; ")
            lines.append("Tests & results: \(t)")
        }
        if let dx = c.diagnoses.first(where: { $0.correct })?.name {
            lines.append("Correct diagnosis: \(dx)")
        }
        let otherDx = c.diagnoses.filter { !$0.correct }.map(\.name)
        if !otherDx.isEmpty { lines.append("Other options considered: \(otherDx.joined(separator: ", "))") }
        let goodTx = c.treatments.filter { $0.appropriate }.map(\.name)
        if !goodTx.isEmpty { lines.append("Appropriate treatments: \(goodTx.joined(separator: ", "))") }
        // The teaching now lives on each option, so hand the tutor those notes —
        // they're what the answer screen shows behind every button.
        lines.append(contentsOf: optionNotes("Why each diagnosis did or didn't fit",
                                             c.diagnoses.map { ($0.name, $0.tag, $0.rationale) }))
        lines.append(contentsOf: optionNotes("Test selection rationale",
                                             c.tests.map { ($0.name, $0.tag, $0.rationale) }))
        lines.append(contentsOf: optionNotes("Treatment rationale",
                                             c.treatments.map { ($0.name, $0.tag, $0.rationale) }))
        if let mi = c.mentorInsight, !mi.isEmpty {
            for (title, body) in mi.sections { lines.append("\(title): \(body)") }
        }
        if !c.outcomeBody.isEmpty { lines.append("Teaching summary: \(c.outcomeBody)") }
        return lines.joined(separator: "\n")
    }
}
