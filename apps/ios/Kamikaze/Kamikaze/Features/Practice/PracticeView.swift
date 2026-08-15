import KamikazeMotionCore
import SwiftUI

@MainActor
@Observable
final class PracticeModel {
    private let summaryRepository: FileAttemptSummaryRepository
    private let reconciler: AttemptSummaryReconciler

    private(set) var progress = PracticeProgress(summaries: [])
    private(set) var isLoading = false

    init(rootDirectory: URL = AttemptStorageLocation.applicationRoot()) {
        let attempts = FileAttemptRepository(rootDirectory: rootDirectory)
        let analyses = FileAttemptAnalysisRepository(rootDirectory: rootDirectory)
        let summaries = FileAttemptSummaryRepository(rootDirectory: rootDirectory)
        summaryRepository = summaries
        reconciler = AttemptSummaryReconciler(
            attemptRepository: attempts,
            analysisRepository: analyses,
            summaryRepository: summaries
        )
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await reconciler.reconcile()
            progress = PracticeProgress(summaries: try await summaryRepository.all())
        } catch {
            // Progression is a derived view; on failure it simply stays stale.
        }
    }
}

struct PracticeView: View {
    @State private var model = PracticeModel()

    var body: some View {
        ZStack {
            KineticBackground(accent: KamikazeTheme.hazard)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    SectionKicker(text: "PRACTICE / SKILL LADDER")
                    Text("BUILD THE\nMUSCLE MEMORY.")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .tracking(-1.8)
                    Text("Progress is measured from saved attempts. Landing is confirmed by you, never guessed from FIT.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.muted)
                    ForEach(PracticeLibrary.pairs) { pair in
                        pairCard(pair)
                    }
                }
                .padding(20)
                .padding(.bottom, 100)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { Task { await model.refresh() } }
    }

    private func pairCard(_ pair: PracticePair) -> some View {
        let unlocked = model.progress.isPairUnlocked(pair)
        return GlassSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Text(String(format: "%02d", pair.order))
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .foregroundStyle(unlocked ? KamikazeTheme.volt : KamikazeTheme.muted)
                    Text(pair.title)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                    Spacer()
                    if model.progress.isPairMastered(pair) {
                        Text("MASTERED")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.volt)
                    } else if !pair.isDetectorReady {
                        Text("NEEDS DATA")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.hazard)
                    } else if !unlocked {
                        Image(systemName: "lock.fill").foregroundStyle(KamikazeTheme.muted)
                    }
                }
                trickRow(pair.primary, in: pair)
                Divider().overlay(.white.opacity(0.08))
                trickRow(pair.opposite, in: pair)
            }
            .padding(16)
        }
        .opacity(unlocked || !pair.isDetectorReady ? 1 : 0.55)
    }

    @ViewBuilder
    private func trickRow(_ node: PracticeTrickNode, in pair: PracticePair) -> some View {
        let reps = model.progress.qualifyingReps(for: node.trickID)
        let mastered = model.progress.isMastered(node.trickID)
        let unlocked = model.progress.isTrickUnlocked(node.trickID, in: pair)

        switch node.readiness {
        case .detectorReady:
            NavigationLink {
                PracticeLevelView(node: node, pair: pair)
            } label: {
                trickRowContent(node, reps: reps, mastered: mastered, locked: !unlocked)
            }
            .buttonStyle(.plain)
            .disabled(!unlocked)
        case .collectingEvidence:
            // No validated definition yet: collect labelled evidence instead
            // of pretending this run could be judged.
            NavigationLink {
                DebugMotionCaptureView()
            } label: {
                trickRowContent(node, reps: reps, mastered: false, locked: false, needsData: true)
            }
            .buttonStyle(.plain)
        }
    }

    private func trickRowContent(
        _ node: PracticeTrickNode,
        reps: Int,
        mastered: Bool,
        locked: Bool,
        needsData: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(node.trickID.displayName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text(needsData ? "COLLECT EVIDENCE IN TRICK LAB" : node.coachingCue.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(needsData ? KamikazeTheme.hazard : KamikazeTheme.muted)
                    .lineLimit(1)
            }
            Spacer()
            if mastered {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(KamikazeTheme.volt)
            } else if !needsData {
                repDots(reps)
            }
            Image(systemName: locked ? "lock.fill" : "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(KamikazeTheme.muted)
        }
        .contentShape(Rectangle())
    }

    private func repDots(_ reps: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0 ..< PracticeProgress.repsToUnlock, id: \.self) { index in
                Circle()
                    .fill(index < reps ? KamikazeTheme.volt : Color.white.opacity(0.14))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel("\(min(reps, PracticeProgress.repsToUnlock)) of \(PracticeProgress.repsToUnlock) qualifying reps")
    }
}
