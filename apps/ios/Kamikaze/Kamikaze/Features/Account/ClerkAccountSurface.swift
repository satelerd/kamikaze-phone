import SwiftUI

// The account feature remains buildable in targets that have not added Clerk
// yet. Once ClerkKit and ClerkKitUI are linked, this host is the only adapter
// that knows about their concrete types.
#if canImport(ClerkKit) && canImport(ClerkKitUI)
import ClerkKit
import ClerkKitUI

/// Package-backed account host. Pass `KamikazeIdentityConfiguration.clerk`
/// from the app composition root; a nil value deliberately renders the same
/// signed-out surface with disabled actions and a clear setup message.
struct ClerkAccountSurface: View {
    private let configuredClerk: Clerk?

    init(clerk: Clerk?) {
        configuredClerk = clerk
    }

    var body: some View {
        if let configuredClerk {
            ClerkConfiguredAccountSurface()
                .environment(configuredClerk)
        } else {
            AccountView(
                session: UnconfiguredAccountSession(),
                isConfigured: false
            )
        }
    }
}

private struct ClerkConfiguredAccountSurface: View {
    @Environment(Clerk.self) private var clerk
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var authRoute: AccountAuthRoute?
    @State private var profileIsPresented = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        AccountSurfaceScaffold(
            ambient: clerk.user == nil ? KamikazeTheme.ion : KamikazeTheme.volt
        ) {
            AccountHeader(
                eyebrow: clerk.user == nil ? "OPTIONAL ACCOUNT" : "IDENTITY ONLINE",
                title: clerk.user == nil ? "PLAY ON YOUR TERMS." : "YOUR ACCOUNT."
            )

            if !clerk.isLoaded {
                AccountLoadingView()
            } else if let user = clerk.user {
                AccountSignedInView(
                    identity: accountIdentity(from: user),
                    sync: .ready,
                    canRequestDeletion: false,
                    isWorking: isWorking,
                    onManageAccount: { profileIsPresented = true },
                    onSignOut: signOut,
                    onDeleteAccount: {
                        errorMessage = AccountSessionError.deletionNotAvailable.localizedDescription
                    }
                )
            } else {
                AccountSignedOutView(
                    isConfigured: true,
                    isWorking: isWorking,
                    onApple: signInWithApple,
                    onAuth: { authRoute = $0 }
                )
            }

            if let errorMessage {
                AccountErrorBanner(
                    message: errorMessage,
                    onDismiss: { self.errorMessage = nil }
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: clerk.user?.id)
        .sheet(item: $authRoute) { route in
            AccountAuthSheet(route: route)
        }
        .sheet(isPresented: $profileIsPresented) {
            AccountProfileSheet()
        }
        .prefetchClerkImages()
    }

    private func signInWithApple() {
        runClerkOperation {
            _ = try await clerk.auth.signInWithApple()
        }
    }

    private func signOut() {
        runClerkOperation {
            try await clerk.auth.signOut()
        }
    }

    private func runClerkOperation(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await operation()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func accountIdentity(from user: User) -> AccountIdentity {
        let name = [user.firstName, user.lastName]
            .compactMap { value in
                guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return value
            }
            .joined(separator: " ")
        let emailAddress = user.primaryEmailAddress?.emailAddress ?? user.emailAddresses.first?.emailAddress
        let imageURL = user.imageUrl.isEmpty ? nil : URL(string: user.imageUrl)

        return AccountIdentity(
            id: user.id,
            displayName: name.isEmpty ? (user.username ?? "KAMIKAZE RIDER") : name,
            emailAddress: emailAddress,
            imageURL: imageURL,
            provider: .clerk,
            isEmailVerified: user.hasVerifiedEmailAddress
        )
    }
}

private struct AccountAuthSheet: View {
    let route: AccountAuthRoute

    var body: some View {
        ZStack {
            KamikazeTheme.pitch.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("KAMIKAZE ACCOUNT")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.volt)
                    Text(route.title)
                        .font(.system(size: 25, weight: .black, design: .rounded))
                        .foregroundStyle(KamikazeTheme.frost)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)

                GlassSurface(role: .contentPanel, cornerRadius: 24) {
                    AuthView(mode: route.clerkMode, isDismissible: true)
                        .frame(maxWidth: .infinity, minHeight: 470)
                }
                .padding(.horizontal, 10)
            }
            .padding(.bottom, 8)
        }
        .presentationBackground(KamikazeTheme.pitch)
        .presentationDragIndicator(.visible)
    }
}

private struct AccountProfileSheet: View {
    var body: some View {
        ZStack {
            KamikazeTheme.pitch.ignoresSafeArea()
            UserProfileView(isDismissible: true)
        }
        .presentationBackground(KamikazeTheme.pitch)
        .presentationDragIndicator(.visible)
    }
}

private extension AccountAuthRoute {
    var clerkMode: AuthView.Mode {
        switch self {
        case .signInOrUp: .signInOrUp
        case .signIn: .signIn
        case .signUp: .signUp
        }
    }
}
#endif
