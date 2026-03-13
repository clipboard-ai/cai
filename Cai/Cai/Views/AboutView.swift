import SwiftUI

/// About window content — shows app icon, name, version, description, and links.
struct AboutView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 20)

            // App icon
            Image("CaiLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Spacer().frame(height: 14)

            // App name + version
            Text("Cai")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.caiTextPrimary)

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.system(size: 11))
                .foregroundColor(.caiTextSecondary.opacity(0.6))
                .padding(.top, 2)

            Spacer().frame(height: 16)

            // Tagline
            Text("The private clipboard AI")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.caiTextPrimary)

            Spacer().frame(height: 8)

            // Description
            Text("Select text, press \u{2325}C, and run smart actions\npowered by local AI. Free, open source,\nand built with privacy in mind.")
                .font(.system(size: 12))
                .foregroundColor(.caiTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Spacer().frame(height: 18)

            // Links
            HStack(spacing: 16) {
                linkButton(title: "Website", icon: "globe", url: "https://getcai.app")
                linkButton(title: "GitHub", url: "https://github.com/clipboard-ai/cai") {
                    GitHubIcon(color: .caiPrimary)
                        .frame(width: 11, height: 11)
                }
            }

            Spacer().frame(height: 20)
        }
        .frame(width: 280)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("About Cai")
    }

    private func linkButton(title: String, icon: String, url: String) -> some View {
        linkButton(title: title, url: url) {
            Image(systemName: icon)
                .font(.system(size: 10))
        }
    }

    private func linkButton<Icon: View>(title: String, url: String, @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 4) {
                icon()
                Text(title)
                    .font(.system(size: 12))
            }
            .foregroundColor(.caiPrimary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
