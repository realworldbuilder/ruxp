import UIKit

/// Opens Discord as close to the channel as the device allows: the app when installed, else
/// the web, where Discord's own Universal Link takes over if the app appears later.
enum DiscordLinks {
    @MainActor
    static func open(_ ref: DiscordChannelRef) {
        UIApplication.shared.open(ref.appURL, options: [:]) { opened in
            if !opened { UIApplication.shared.open(ref.webURL) }
        }
    }

    @MainActor
    static func open(invite: URL) {
        UIApplication.shared.open(invite)
    }

    @MainActor
    static var isAppInstalled: Bool {
        UIApplication.shared.canOpenURL(URL(string: "discord://")!)
    }
}
