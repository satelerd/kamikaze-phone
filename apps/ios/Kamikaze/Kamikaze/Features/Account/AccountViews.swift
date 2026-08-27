import SwiftUI

/// Local-first account surface. The default implementation has no network
/// behavior; `ClerkAccountSurface` is the package-backed host used once Clerk
/// has been configured by the app composition root.
struct AccountView: View {
    private let isConfigured: Bool
    private let onManageAccount: () -> Void
    @State private var model: AccountViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        session: any AccountSession = UnconfiguredAccountSession(),
        isConfigured: Bool = false,
        onManageAccount: @escaping () -> Void = {}
    ) {
        self.isConfigured = isConfigured
        self.onManageAccount = onManageAccount
        _model = State(initialValue: AccountViewModel(session: session))
    }

    var body: some View {
        AccountSurfaceScaffold(
            ambient: model.snapshot.phase == .signedIn ? KamikazeTheme.volt : KamikazeTheme.ion
        ) {
            AccountHeader(
                eyebrow: model.snapshot.phase == .signedIn ? "IDENTITY ONLINE" : "OPTIONAL ACCOUNT",
                title: model.snapshot.phase == .signedIn ? "YOUR ACCOUNT." : "PLAY ON YOUR TERMS."
            )

            switch model.snapshot.phase {
            case .loading:
                AccountLoadingView()
            case .signedOut, .failed:
                AccountSignedOutView(
                    isConfigured: isConfigured,
                    isWorking: model.isWorking,
                    onApple: { Task { await model.signInWithApple() } },
                    onAuth: { route in Task { await model.presentAuth(route) } }
                )
            case .signedIn:
                if let identity = model.snapshot.identity {
                    AccountSignedInView(
                        identity: identity,
                        sync: model.snapshot.sync,
                        canRequestDeletion: model.snapshot.canRequestDeletion,
                        isWorking: model.isWorking,
                        onManageAccount: onManageAccount,
                        onSync: {},
                        onSignOut: { Task { await model.signOut() } },
                        onDeleteAccount: { Task { await model.requestDeleteAccount() } }
                    )
                } else {
                    AccountLoadingView()
                }
            }

            if let errorMessage = model.errorMessage {
                AccountErrorBanner(message: errorMessage, onDismiss: model.clearError)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.snapshot.phase)
        .task { await model.refresh() }
    }
}

/// A shared root makes the account card usable from Me/Profile, a sheet or a
/// future onboarding hand-off without duplicating the field and scroll rules.
struct AccountSurfaceScaffold<Content: View>: View {
    let ambient: Color
    @ViewBuilder let content: () -> Content

    init(ambient: Color, @ViewBuilder content: @escaping () -> Content) {
        self.ambient = ambient
        self.content = content
    }

    var body: some View {
        ZStack {
            ExperienceFieldBackground(ambient: ambient)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content()
                }
                .padding(20)
                .padding(.bottom, 54)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct AccountHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(KamikazeTheme.volt)
            Text(title)
                .font(.system(size: 38, weight: .black, design: .rounded))
                .tracking(-1.5)
                .foregroundStyle(KamikazeTheme.frost)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AccountLoadingView: View {
    var body: some View {
        GlassSurface(role: .instrumentHUD, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 11) {
                    ProgressView()
                        .tint(KamikazeTheme.ion)
                        .accessibilityLabel("Loading account")
                    Text("CHECKING ACCOUNT STATE")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.frost)
                }
                Text("Your local play state stays available while identity loads.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }
}

struct AccountSignedOutView: View {
    let isConfigured: Bool
    let isWorking: Bool
    let onApple: () -> Void
    let onAuth: (AccountAuthRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassSurface(role: .contentPanel, cornerRadius: 26) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(KamikazeTheme.ion)
                            .frame(width: 34, height: 38)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("OPTIONAL IDENTITY")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                            Text("Sign in when you want private sync or social sharing. Guest play never waits for an account.")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(KamikazeTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Button(action: onApple) {
                        HStack(spacing: 9) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 17, weight: .semibold))
                            Text(isWorking ? "CONNECTING TO APPLE…" : "SIGN IN WITH APPLE")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.volt)
                    .disabled(!isConfigured || isWorking)
                    .accessibilityHint(
                        isConfigured
                            ? "Uses Apple's secure identity flow."
                            : "Account setup is needed before sign-in is available."
                    )

                    HStack(spacing: 9) {
                        accountAuthButton(.signIn)
                        accountAuthButton(.signUp)
                    }

                    Label(
                        isConfigured
                            ? "Apple is the fast path. Email sign-in and sign-up stay separate below."
                            : "ACCOUNT SETUP NEEDED · Add a Clerk publishable key to enable sign-in.",
                        systemImage: isConfigured ? "lock.shield" : "wrench.and.screwdriver"
                    )
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(isConfigured ? KamikazeTheme.muted : KamikazeTheme.hazard)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }

            GlassSurface(role: .instrumentHUD, cornerRadius: 22) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "iphone.and.arrow.forward")
                        .foregroundStyle(KamikazeTheme.volt)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LOCAL PLAY IS ALWAYS READY")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                        Text("No camera, motion or replay data uploads just because an account exists. Each share asks for audience and consent.")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(KamikazeTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(15)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func accountAuthButton(_ route: AccountAuthRoute) -> some View {
        Button(route.title) {
            onAuth(route)
        }
        .font(.system(size: 10, weight: .black, design: .monospaced))
        .frame(maxWidth: .infinity, minHeight: 48)
        .adaptiveGlassButton(tint: KamikazeTheme.ion)
        .disabled(!isConfigured || isWorking)
        .accessibilityLabel(route.title)
    }
}

struct AccountSignedInView: View {
    let identity: AccountIdentity
    let sync: AccountSyncSnapshot
    let canRequestDeletion: Bool
    let isWorking: Bool
    let onManageAccount: () -> Void
    let onSync: () -> Void
    let onSignOut: () -> Void
    let onDeleteAccount: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassSurface(role: .contentPanel, cornerRadius: 26) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 13) {
                        AccountAvatarView(identity: identity, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(identity.displayName)
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if let emailAddress = identity.emailAddress, !emailAddress.isEmpty {
                                Text(emailAddress)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(KamikazeTheme.muted)
                                    .lineLimit(1)
                            } else {
                                Text("EMAIL NOT SHARED")
                                    .font(.system(size: 10, weight: .black, design: .monospaced))
                                    .foregroundStyle(KamikazeTheme.muted)
                            }
                            Label(
                                identity.isEmailVerified ? "EMAIL VERIFIED" : "VERIFY EMAIL IN ACCOUNT",
                                systemImage: identity.isEmailVerified ? "checkmark.seal" : "exclamationmark.shield"
                            )
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(identity.isEmailVerified ? KamikazeTheme.volt : KamikazeTheme.hazard)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 8) {
                        AccountTag(title: identity.provider.title, tint: KamikazeTheme.ion)
                        AccountTag(title: "ID \(identity.id.prefix(8))", tint: KamikazeTheme.muted)
                    }

                    Button(action: onManageAccount) {
                        Label("MANAGE ACCOUNT", systemImage: "person.crop.circle")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .adaptiveGlassButton(tint: KamikazeTheme.ion)
                    .accessibilityHint("Opens Clerk's profile, security and sign-out controls.")
                }
                .padding(16)
            }

            AccountSyncCard(sync: sync, onSync: onSync)

            GlassSurface(role: .contentPanel, cornerRadius: 22) {
                VStack(spacing: 0) {
                    Button(action: onSignOut) {
                        accountActionRow(
                            title: isWorking ? "SIGNING OUT…" : "SIGN OUT",
                            detail: "Keep playing locally on this phone.",
                            iconName: "rectangle.portrait.and.arrow.right",
                            tint: KamikazeTheme.hazard
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)

                    Divider().overlay(.white.opacity(0.08))

                    Button(action: onDeleteAccount) {
                        accountActionRow(
                            title: "DELETE ACCOUNT · FUTURE",
                            detail: canRequestDeletion
                                ? "This action will be irreversible."
                                : "Backend deletion and retention policy are not connected yet.",
                            iconName: "person.crop.circle.badge.minus",
                            tint: KamikazeTheme.muted
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canRequestDeletion || isWorking)
                    .accessibilityHint("Account deletion is not available in this prototype.")
                }
                .padding(.horizontal, 16)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Signed-in account for \(identity.accessibilitySummary)")
    }

    private func accountActionRow(
        title: String,
        detail: String,
        iconName: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 23, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(title.contains("FUTURE") ? KamikazeTheme.muted : KamikazeTheme.frost)
                Text(detail)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(KamikazeTheme.muted.opacity(0.65))
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

struct AccountSyncCard: View {
    let sync: AccountSyncSnapshot
    let onSync: () -> Void

    var body: some View {
        GlassSurface(role: .instrumentHUD, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Label("PRIVATE SYNC", systemImage: sync.state.iconName)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(sync.state == .ready ? KamikazeTheme.volt : KamikazeTheme.ion)
                    Spacer()
                    Text(sync.state.title)
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.muted)
                }
                Text(sync.detail)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.frost)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(KamikazeTheme.muted)
                    Text("Scores, trick labels and progression sync privately. Raw sensor data and camera files stay on this iPhone.")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(action: onSync) {
                    Label(sync.state == .syncing ? "SYNCING…" : "SYNC NOW", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .adaptiveGlassButton(tint: KamikazeTheme.ion)
                .disabled(sync.state == .syncing || sync.state == .needsAuthentication)
            }
            .padding(15)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Private sync. \(sync.state.title). \(sync.detail)")
    }
}

struct AccountAvatarView: View {
    let identity: AccountIdentity
    var size: CGFloat = 56
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Circle()
                .fill(reduceTransparency ? KamikazeTheme.pitch : Color.white.opacity(0.04))
            if let imageURL = identity.imageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().stroke(KamikazeTheme.ion.opacity(0.7), lineWidth: 1) }
        .accessibilityLabel("Profile picture for \(identity.displayName)")
    }

    private var initials: some View {
        Text(identity.initials)
            .font(.system(size: size * 0.28, weight: .black, design: .rounded))
            .foregroundStyle(KamikazeTheme.frost)
    }
}

private struct AccountTag: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(tint.opacity(0.1), in: Capsule(style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

struct AccountErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        GlassSurface(role: .contentPanel, cornerRadius: 20) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(KamikazeTheme.hazard)
                Text(message)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.frost)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(KamikazeTheme.muted)
                .accessibilityLabel("Dismiss account message")
            }
            .padding(14)
        }
        .accessibilityElement(children: .contain)
    }
}
