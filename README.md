# Readeck Flutter

This is an Android client application for [Readeck].  

Features:
- simple, compact design
- **text to speech**: read articles, even offline (multiple language supported)
- **offline** read support
- **summarization via AI** (optional; supports: Azure OpenAI APIs)

<img src="screenshots/readeck-unread.png" width="220" alt="Bookmarks screen">
<img src="screenshots/readeck-article.png" width="220" alt="Article screen">

## Development setup

Install dependencies:
```bash
flutter pub get
```

Run tests:
```bash
flutter test
```

If you need to confirm the available devices first:
```bash
flutter devices
```

Build and run on Android:
```bash
# Start an emulator or connect an Android device, then run:
flutter run -d android # or the id of your device

# Or: build the APK and then run
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Run a local version of Readeck:
```bash
docker run --rm -p 8000:8000 -v readeck-data:/readeck codeberg.org/readeck/readeck:latest
```

 [readeck]: https://readeck.org