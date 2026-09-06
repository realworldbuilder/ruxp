import WatchKit

final class ExtendedSessionManager: NSObject, ObservableObject {
    private var session: WKExtendedRuntimeSession?

    func startSession() {
        guard session == nil else { return }
        let newSession = WKExtendedRuntimeSession()
        newSession.delegate = self
        newSession.start()
        session = newSession
    }

    func endSession() {
        session?.invalidate()
        session = nil
    }
}

extension ExtendedSessionManager: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: (any Error)?
    ) {
        session = nil
    }

    func extendedRuntimeSessionDidStart(
        _ extendedRuntimeSession: WKExtendedRuntimeSession
    ) {}

    func extendedRuntimeSessionWillExpire(
        _ extendedRuntimeSession: WKExtendedRuntimeSession
    ) {}
}
