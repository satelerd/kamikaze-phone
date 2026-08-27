import SwiftUI

/// Product-facing shell for optional accounts and sync. The real backend and
/// persistent outbox exist in Cloud/, but authentication is deliberately not
/// faked: this prototype demonstrates the contract until Sign in with Apple
/// is connected to a selected OIDC provider.
struct CloudAccountPrototypeView: View {
    @State private var showsSignedInPreview = false
    @State private var syncAttempts = true
    @State private var syncProgress = true
    @State private var syncAppearance = true
    @State private var status = "LOCAL PLAY IS READY"

    var body: some View {
        ZStack {
            ExperienceFieldBackground(ambient: KamikazeTheme.ion)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("YOUR FLIPS.\nANY IPHONE.")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .tracking(-1.7)
                    Text("AN OPTIONAL ACCOUNT — NEVER A GATE TO PLAY")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.ion)

                    accountCard
                    syncCard
                    privacyCard

                    Text("PROTOTYPE · The Convex development backend and retry-safe local outbox are live. Sign in with Apple is intentionally not simulated as a real identity yet.")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .padding(.bottom, 50)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var accountCard: some View {
        GlassSurface(role: .contentPanel, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Image(systemName: showsSignedInPreview ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(showsSignedInPreview ? KamikazeTheme.volt : KamikazeTheme.ion)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(showsSignedInPreview ? "SAT · PREVIEW ACCOUNT" : "PLAYING AS GUEST")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                        Text(showsSignedInPreview ? "SYNC PREVIEW ACTIVE" : "EVERYTHING STAYS ON THIS IPHONE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.muted)
                    }
                    Spacer()
                }

                Button {
                    withAnimation(.snappy) {
                        showsSignedInPreview.toggle()
                        status = showsSignedInPreview ? "IDENTITY PREVIEW · NOT AUTHENTICATED" : "LOCAL PLAY IS READY"
                    }
                } label: {
                    Label(
                        showsSignedInPreview ? "RETURN TO GUEST" : "PREVIEW SIGN IN WITH APPLE",
                        systemImage: "apple.logo"
                    )
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .adaptiveGlassButton(prominent: !showsSignedInPreview, tint: KamikazeTheme.volt)
            }
            .padding(16)
        }
    }

    private var syncCard: some View {
        GlassSurface(role: .instrumentHUD, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("PRIVATE SYNC")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                    Spacer()
                    Text("0 PENDING")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.volt)
                }
                .padding(.bottom, 10)
                syncToggle("ATTEMPT SUMMARIES", detail: "Trick, score and timing — not raw motion.", value: $syncAttempts)
                Divider().overlay(.white.opacity(0.08))
                syncToggle("PRACTICE PROGRESS", detail: "Unlocks and mastery across devices.", value: $syncProgress)
                Divider().overlay(.white.opacity(0.08))
                syncToggle("PHONE STYLE", detail: "Equipped model, color and cosmetic choices.", value: $syncAppearance)

                Button("SYNC NOW") {
                    status = showsSignedInPreview ? "OUTBOX READY · AUTH CONNECTION NEXT" : "SIGN IN ONLY WHEN YOU WANT SYNC"
                }
                .font(.system(size: 11, weight: .black, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 48)
                .adaptiveGlassButton(tint: KamikazeTheme.ion)
                .padding(.top, 12)

                Text(status)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 9)
            }
            .padding(16)
        }
    }

    private var privacyCard: some View {
        GlassSurface(role: .contentPanel, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("YOU CONTROL THE HEAVY STUFF")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                privacyRow("RAW MOTION", value: "DEVICE ONLY", color: KamikazeTheme.volt)
                privacyRow("CAMERA SOURCES", value: "DEVICE ONLY", color: KamikazeTheme.volt)
                privacyRow("REPLAY VIDEO", value: "UPLOAD BY CHOICE", color: KamikazeTheme.ion)
                privacyRow("PUBLIC POST", value: "PUBLISH BY CHOICE", color: KamikazeTheme.hazard)
            }
            .padding(16)
        }
    }

    private func syncToggle(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 10, weight: .black, design: .rounded))
                Text(detail)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.muted)
            }
        }
        .tint(KamikazeTheme.volt)
        .frame(minHeight: 58)
    }

    private func privacyRow(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(color)
        }
        .font(.system(size: 8, weight: .black, design: .monospaced))
    }
}
