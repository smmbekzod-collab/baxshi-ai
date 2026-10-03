#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --flavor user --target lib/main.dart --dart-define=API_BASE_URL="${API_BASE_URL:-https://api.example.invalid}"
flutter build apk --debug --flavor admin --target lib/main_admin.dart --dart-define=API_BASE_URL="${API_BASE_URL:-https://api.example.invalid}"
