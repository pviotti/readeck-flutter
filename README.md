# Readeck Flutter

This is a [Flutter] client application for [Readeck].

:construction: At the moment, this application:
- only targets Linux and Android.
- covers only a limited subset of Readeck functionalities

## Development setup

Install dependencies:
```bash
flutter pub get
```

If you need to confirm the available devices first:
```bash
flutter devices
```

Build and run on Linux:
```bash
flutter build linux
flutter run -d linux
```

Build and run on Android:
```bash
# Start an emulator or connect an Android device, then run:
flutter run -d android

# Or: build the APK and then run
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

 [flutter]: https://flutter.dev/
 [readeck]: https://readeck.org