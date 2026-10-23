# Backend

FrameTrail uses Supabase Auth, PostgreSQL and one Supabase Edge Function. There is no separate Cloudflare Worker or application server. The native app calls bounded HTTPS APIs directly through URLSession actors.

## Authentication and storage

Email/password authentication produces access and refresh tokens stored in the device Keychain. Passwords are never persisted by the app. Verified accounts use isolated offline files; guest data remains separate. Session refresh is serialized, and account changes invalidate pending operations.

PostgreSQL stores one `library_items` row per user/title. Authenticated reads require owner RLS. Direct table writes are revoked; the `put_library_item` RPC checks the caller, payload size and expected revision. Conflicting revisions require explicit resolution in the app. Deletions leave empty tombstones so an older device cannot silently recreate a deleted title.

The cloud projection contains metadata, progress, ratings and saved impressions, including selected short excerpts and saved compilations. Full source texts and conversations stay on the device. Server rows are capped at 512 KiB; client reads paginate three rows within a 2 MiB transport limit.

The `delete-account` Edge Function independently validates the bearer token with Auth, then deletes that authenticated user using a server-only administrative credential. Client-provided account identifiers are never trusted. Foreign-key cascading removes the owner's library rows.

## Deploy your own instance

1. Create a Supabase project. Keep email confirmation enabled. Configure SMTP for public registration; the built-in mail service is restricted to organization members.
2. Apply the SQL files in `supabase/migrations` in filename order. They establish the table, owner policies, versioned RPC and capacity limit.
3. Deploy `supabase/functions/delete-account`. Its gateway JWT verification is disabled because the function validates the current token through Auth itself. Supabase supplies the server environment; never bundle a privileged key in the app.
4. Replace `projectURL` and `publishableKey` in `FrameTrail/Supabase.plist` with your project's public configuration. The published beta uses its owner's closed-beta instance in Frankfurt.
5. Run native service/store tests. For deployed integration tests, `scripts/test_cloud.py --accounts PRIVATE_FILE.json` needs two **disposable confirmed** email/password accounts. It permanently deletes those test accounts on completion. Keep the private fixture outside the repository and remove it afterward.

## Apple and Google sign-in

The first beta exposes email/password sign-in. Social providers are not configured or advertised as available. Adding them also requires external provider configuration; the Supabase public key alone cannot enable them.

Google requires an OAuth client, consent configuration and authorized redirects in Google Cloud, plus provider configuration in Supabase. Native Apple sign-in requires an Apple Developer identifier with the relevant capability and compatible signing. Re-signing for sideloading needs separate device verification. Provider secrets belong on the backend, never in app settings or the IPA.

Official setup: [Google](https://supabase.com/docs/guides/auth/social-sign-in/auth-google), [Apple](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple).
