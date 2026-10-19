# Flutter app

Flutter 3.41.0 / Dart 3.11 client for the Spring Boot API, with scoped duties, email OTP, record pagination, student CSV import and cloakroom QR scanning.

```sh
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/api
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8080/api
```

The URL must include `/api`. Android emulators reach the host at `10.0.2.2`; physical devices need an accessible server address. Debug Android permits local HTTP. Release builds require HTTPS. Camera permission descriptions are configured for Android and iOS.

The Android application ID and iOS bundle ID are `in.hostelcc.app`. For an Android release, copy `android/key.properties.example` to `android/key.properties` and supply your own private keystore. Release builds fail if signing is missing; they do not fall back to debug signing.

```sh
flutter build apk --release --dart-define=API_BASE_URL=https://your-host/api
```

Keystores, signing properties, cookies and environment secrets must stay out of version control. iOS builds require macOS and Apple signing credentials. Physical camera and signed store-release testing remain deployment/device checks.
