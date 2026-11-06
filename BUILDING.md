# RetroWave Music — how to build the APK

The app code is complete. It just needs to be compiled once by Flutter's
build tools (Gradle), which must run somewhere with normal networking.

## Option A — Codemagic (free, nothing to install)
1. Go to codemagic.io and sign in (Google or GitHub account).
2. Add this project (upload/connect the repo containing these files).
3. It detects codemagic.yaml automatically — start the
   "RetroWave Music - Android APK" workflow.
4. When it finishes, download app-release.apk from the build artifacts
   (a copy is also emailed to you). Open the APK on the phone and allow
   "install from this source" — it installs like any app.

## Option B — GitHub Actions (free)
1. Put these files in a GitHub repository (repo root = this folder,
   where pubspec.yaml is).
2. Go to the Actions tab and run "Build RetroWave APK"
   (or push to main — it starts automatically).
3. Download the "retrowave-music-apk" artifact from the finished run,
   unzip it, and install app-release.apk on the phone.

## Option C — Your own computer
1. Install Flutter: https://docs.flutter.dev/get-started/install
2. In this folder, run:
     flutter pub get
     flutter build apk --release
3. The APK appears at build/app/outputs/flutter-apk/app-release.apk
   Copy it to the phone and install.

Note: the release APK is signed with the standard debug key (fine for
personal testing and side-loading). A private upload key is only needed
later for the Play Store listing.
