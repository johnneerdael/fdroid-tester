## Just run the script and follow the instructions

### This fork

Adds screenshots while you use the app (`s` + Enter, embedded when the report
is posted), Android TV apps, PCAPdroid's root mode on rooted devices (`--vpn`
keeps the VPN) and `--apk FILE` for a local APK, and fixes the check marks on
macOS. Each is offered upstream as its own pull request. `tests/run.sh` runs
the script against fixture APKs and a fake device. It needs bash 4.4+, Python 3.6+,
`unzip`, `sha256sum` or `shasum`, and, in the Android SDK at `ANDROID_HOME`, the build-tools (for `aapt2`) and one
SDK Platform (for its `android.jar`).
