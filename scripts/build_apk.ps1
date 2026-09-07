$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
dart run build_runner build --delete-conflicting-outputs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter analyze --no-fatal-infos
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter build apk --release
exit $LASTEXITCODE
