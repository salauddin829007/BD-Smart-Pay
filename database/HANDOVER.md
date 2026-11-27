# BD Smart Pay Admin: handover and runbook

## What is in this package
| File | What it is | Where it goes |
|---|---|---|
| `index.html` | The admin page | repo: `docs/index.html` |
| `feature_control.sql`, `location_security.sql`, `upazila_village.sql` | Earlier features | Supabase SQL Editor (run in this order) |
| `server_pin.sql` | Server-side PIN check, **not tested on a real Postgres by me** | Supabase SQL Editor, try on a copy first |
| `scale_admin.sql` | Indexes + dashboard totals, **not tested on a real Postgres by me** | Supabase SQL Editor |
| `workflows/release.yml` | Signed release APK | repo: `.github/workflows/release.yml` |
| `workflows/backup.yml` | Weekly encrypted DB backup | repo: `.github/workflows/backup.yml` |

The admin page works even if a SQL file has not been run yet. It falls back to the old behaviour.

## Release APK (signed)
1. Create the signing key ONCE on your computer (needs Java):
   `keytool -genkeypair -v -keystore bdsmartpay-release.jks -alias bdsmartpay -keyalg RSA -keysize 2048 -validity 10000`
2. **Back up `bdsmartpay-release.jks` and its passwords in at least two safe places** (password manager + an offline copy). If you lose it you can never publish an update over the installed app.
3. Convert to text: `base64 -w0 bdsmartpay-release.jks` (macOS: `base64 -i bdsmartpay-release.jks`).
4. GitHub repo -> Settings -> Secrets and variables -> Actions -> New secret:
   - `ANDROID_KEYSTORE_B64` = the base64 text
   - `ANDROID_KEYSTORE_PASSWORD`
   - `ANDROID_KEY_ALIAS` = `bdsmartpay`
   - `ANDROID_KEY_PASSWORD` (optional, only if different from the keystore password)
5. Actions -> "Build BD Smart Pay Admin RELEASE APK (signed)" -> Run workflow.
6. The first release APK is signed with a different key than your old debug APKs, so uninstall the old app once. After that, every new release installs as an update (versionCode grows with every run).

Never commit the `.jks` file to the repo.

## Backups
1. Supabase -> Project Settings -> Database -> Connection string -> **Session pooler** (GitHub runners cannot use the IPv6-only direct host). Replace the password placeholder.
2. Secrets: `SUPABASE_DB_URL` = that string, `BACKUP_PASSPHRASE` = a long random passphrase (store it in your password manager).
3. Actions -> "Weekly encrypted database backup" -> Run workflow once to test. It then runs every Friday 20:00 UTC and keeps files 30 days.
4. **Test a restore at least once**: download the artifact, then
   `gpg -d backup-YYYY-MM-DD.sql.gz.gpg | gunzip | psql "<a NEW empty database url>"`.
   A backup that was never restored is not a backup.
5. The dump holds user data. Only trusted people should have access to the repo (artifacts are visible to collaborators). Also turn on Supabase's own daily backups (paid plans) or Point-in-Time Recovery if the app handles real money.

## Server-side PIN (what is done, what is left)
Done on the database side (`server_pin.sql`): `app_verify_pin(p_phone, p_pin)` checks the PIN on the server with bcrypt, locks the account after N wrong tries (`app_settings.max_pin_attempts`, default 5), and upgrades old sha256 hashes to bcrypt on the first good login. The admin page "Set new PIN" already calls `admin_set_pin` when it exists.

**Left: the user app must call it.** Replace the local hash comparison with:
```js
const r = await fetch(SB + '/rest/v1/rpc/app_verify_pin', {
  method: 'POST',
  headers: { apikey: KEY, 'Content-Type': 'application/json' },
  body: JSON.stringify({ p_phone: phone, p_pin: pin })
}).then(x => x.json());
// r = {ok:true} | {ok:false, reason:'wrong'|'locked'|'invalid', left:n}
```
Until the app does this, the old weak hash is still what protects PINs. Phase 2 (in the comments at the bottom of `server_pin.sql`) removes it.

## Balance and transactions in their own tables: NOT done, on purpose
Balances and transactions still live inside the `app_users.data` JSON. Moving real money data needs the user app's code and a rehearsal on a copy of the database. A wrong migration silently changes balances. Plan when the app file is available:
1. Tables: `wallets`, and an append-only `ledger_entries` (id, wallet, direction, amount `numeric(14,2)`, description, created_at, idempotency_key). Never update or delete ledger rows, only add reversing entries.
2. All money movement through ONE database function (for example `app_transfer`) that locks the rows, checks balance and limits, and writes both sides in one transaction.
3. Migrate on a copy, compare every user's old and new balance, and only then switch the app.

## Yearly checklist
- Update Capacitor and Android target SDK, rebuild, test on a real phone.
- Check Supabase and GitHub Actions notices (deprecations, Node/Java versions in the workflows).
- Do a backup restore test.
- Rotate admin passwords, review who is in the `admins` table, read the admin activity log.
- Re-read the money and payment rules that apply to you. If real money is involved in Bangladesh, ask a qualified adviser about licensing and compliance.
