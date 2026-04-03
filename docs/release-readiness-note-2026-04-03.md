# Release Readiness Note

Date: 2026-04-03

## Closed in code

- Android release package name and Firebase Android client now match `com.boskale.sportsapp`.
- Debug signing was removed from the release path. Release builds now use a real keystore only when `android/key.properties` or `ANDROID_KEYSTORE_*` env vars are supplied.
- Web K-Coin purchases were disabled until a verified web checkout exists. Client-side free coin grant was removed.
- RevenueCat now fails closed when platform keys are missing and uses the non-deprecated purchase API.
- AdMob test rewarded IDs were removed from release code paths. Ads stay disabled unless real IDs are provided.
- Web Firebase initialization now fails closed if `FIREBASE_WEB_API_KEY` or `FIREBASE_WEB_APP_ID` is missing.
- Mini-game auth now sends both `accessToken` and `refreshToken`; the web game validates message origin before accepting auth.
- Mini-game web -> app messaging now posts only to the detected host origin instead of wildcard targets.
- Private room join no longer attempts to create a duplicate room row when a hidden private room is joined via PIN/deep link.
- `gamification-api-bridge` now requires configured HTTPS backend URL and secret.
- Feedback screenshots are stored as private storage paths; admin dashboard now resolves signed URLs on demand.
- App Group constants were updated to `group.com.boskale.sportsapp`.

## Verification completed

- `flutter analyze`
  Result: no errors, 35 remaining info-level lints.
- `flutter test`
  Result: passed, 46 tests.
- `flutter build apk --release --dart-define-from-file=.env`
  Result: passed.
  Important artifact: `build/app/outputs/apk/release/app-release-unsigned.apk`
- `flutter build web --wasm --release --dart-define-from-file=.env`
  Result: passed.
- `npm run build` in `sports_games_web`
  Result: passed.
- `npm run build` in `admin_dashboard`
  Result: passed.

## Still required before store submission

- Provide a real Android release keystore via `android/key.properties` or:
  - `ANDROID_KEYSTORE_PATH`
  - `ANDROID_KEYSTORE_PASSWORD`
  - `ANDROID_KEY_ALIAS`
  - `ANDROID_KEY_PASSWORD`
- Set a real Android AdMob app ID with `ADMOB_ANDROID_APP_ID`.
- Set real rewarded ad unit IDs:
  - `ADMOB_ANDROID_REWARDED_ID`
  - `ADMOB_IOS_REWARDED_ID`
- Set real RevenueCat keys:
  - `REVENUECAT_GOOGLE_KEY`
  - `REVENUECAT_APPLE_KEY`
- For Flutter web Firebase, set:
  - `FIREBASE_WEB_API_KEY`
  - `FIREBASE_WEB_APP_ID`
  - optionally `FIREBASE_WEB_MESSAGING_SENDER_ID`
  - optionally `FIREBASE_WEB_PROJECT_ID`
- If web push notifications will be used, replace the placeholder values in `web/firebase-messaging-sw.js` with the real web Firebase config.
- Add the real iOS `GoogleService-Info.plist` for bundle id `com.boskale.sportsapp`.
- Set `ADMOB_APPLICATION_ID` in `ios/Flutter/Release.xcconfig`.
- In Supabase Edge Function secrets, set:
  - `GAMIFICATION_API_URL` to an HTTPS endpoint
  - `GAMIFICATION_API_SECRET`
- In Xcode capabilities, confirm App Group is configured as `group.com.boskale.sportsapp`.

## Notes

- Root web deploy workflow now uses `--dart-define-from-file=.env`.
- `.env.example` was extended with the new release-time variables.
