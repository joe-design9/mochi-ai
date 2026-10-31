import Foundation

/// Backend configuration for the invite system — the ONLY place the
/// server endpoint and the public anon key live. Both are fixed
/// constants compiled into the app, never user-editable: there is
/// intentionally NO server/URL/host field anywhere in the UI
/// (standing user requirement — nobody wants to type a server
/// address). Activation stays exactly: invite code, nothing else.
///
/// The backend is a dedicated Supabase project ("mochiai", Frankfurt)
/// whose ONLY job is invite codes: three SECURITY DEFINER RPCs
/// (redeem_invite / create_invite / list_invites) over one table.
/// The anon key is the project's PUBLIC client key — it is meant to
/// be embedded in the app; the RPCs are the only granted surface.
enum BackendConfig {
    /// Supabase project endpoint (fixed).
    static let endpoint = "https://ngtndrfqoetncchteciq.supabase.co"

    /// Supabase anon (public) key.
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5ndG5kcmZxb2V0bmNjaHRlY2lxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM0NzE2NDMsImV4cCI6MjEwOTA0NzY0M30.q9EOlvYm2mnPrO9xoNI-nanJpxdoVqTuE587agMa9x8"

    /// True once real project values are compiled in. While
    /// unconfigured, every backend call fails as "offline" and the
    /// gate shows its retryable error instead of ever crashing or
    /// silently letting people in.
    static var isConfigured: Bool {
        !endpoint.hasPrefix("https://placeholder") && !anonKey.hasPrefix("placeholder")
    }
}
