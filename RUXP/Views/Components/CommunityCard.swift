import SwiftUI

/// The lobby's link to where the conversation lives. Chat is on Discord; lifting is here.
/// One button, one honest line, no Discord branding.
struct CommunityCard: View {
    let community: EventCommunity
    /// The player's choice from Settings; decides the one line under the button.
    var sharing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("COMMUNITY").eyebrow().foregroundStyle(Theme.textSecondary)
            if let discord = community.discord {
                Text("\(discord.displayLabel) · Discord")
                    .font(Theme.Fonts.title(16))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let host = community.host {
                    Text("PRESENTED BY \(host.name.uppercased())").eyebrow().foregroundStyle(Theme.violet)
                        .padding(.top, -4)
                }
                Text(sharing
                     ? "Moments you share land here. Sets never leave the phone."
                     : "Chat lives on Discord. Lifting lives here.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.textSecondary)
                SecondaryButton(title: "OPEN LIVE CHAT", icon: "bubble.left.and.bubble.right.fill") {
                    DiscordLinks.open(discord)
                }
                if let invite = discord.invite {
                    Button { DiscordLinks.open(invite: invite) } label: {
                        Text("Not in the server yet? Get an invite")
                            .font(Theme.Fonts.label)
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, -2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}
