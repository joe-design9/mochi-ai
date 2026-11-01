# Nova — Supabase backend ("mochiai" project)

The project hosts two things:

1. **Invite codes** (since v2.4.0): table `invite_codes` + the RPCs
   `redeem_invite` / `create_invite` / `list_invites`. Unchanged.
2. **AI proxy** (since v3.0.0): the Edge Functions in this folder.
   The normal app build ships without a user API key; chat and live
   calls run through these functions, which hold the only Gemini key.

## Functions

| Function | Called by | Purpose |
|---|---|---|
| `chat` | app (text chat) | verifies activation, calls Gemini `generateContent`, returns `{ reply }` |
| `live-token` | app (call mode) | verifies activation, mints a Gemini Live ephemeral token (v1alpha `authTokens`, single use, 30 min), returns `{ token, expire_time }` |

Activation rule (both): an install is activated when a row in
`invite_codes` has `used_by_install = <install_id>`, or the install
id is listed in the `OWNER_INSTALL_IDS` secret (owner's own
grandfathered installs that predate the invite system).

## Deploy (owner, via Supabase dashboard or CLI)

```sh
supabase functions deploy chat
supabase functions deploy live-token
supabase secrets set GEMINI_API_KEY=<google-ai-studio-key>
# optional:
supabase secrets set OWNER_INSTALL_IDS=<install-id-1>,<install-id-2>
supabase secrets set GEMINI_MODEL=gemini-3.8-flash   # this is the default
```

`SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` are provided by the
Edge runtime automatically. The functions return
`503 server_not_configured` with a clear German message until
`GEMINI_API_KEY` is set — the app shows that message in the chat
instead of failing silently.

An install's ID is shown in the app under Bibliothek → Über Nova
(tap to copy), so the owner can add their own installs to
`OWNER_INSTALL_IDS`.
