import Observation

@MainActor
@Observable
final class AppState {
    var phase: AppPhase = .idle
}
