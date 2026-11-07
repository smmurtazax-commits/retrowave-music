/// Background playback setup state (build #14).
///
/// The background plugin's handler failed to start on the user's
/// phone in every early build, and because the failure was silent,
/// it took all playback down with it. Now the setup result is kept
/// in the open: [bgReady] says whether lock-screen / notification
/// controls are live, and [bgError] holds the refusal in plain
/// text for the Settings screen. In-app playback never depends on
/// this — the player uses tagged sources only when [bgReady], and
/// the proven plain sources otherwise.
bool bgReady = false;
String? bgError;
