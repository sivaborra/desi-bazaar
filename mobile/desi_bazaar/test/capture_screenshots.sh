#!/bin/bash
# Capture screenshots (writes goldens, compares nothing).
# The slice backend must be running fresh: cd vertical-slice && .venv/bin/uvicorn app:app --port 8100
set -e
cd "$(dirname "$0")/.."
env -u https_proxy -u http_proxy -u HTTPS_PROXY -u HTTP_PROXY \
    -u ALL_PROXY -u all_proxy \
    flutter test test/screenshot_test.dart test/media_ads_shots_test.dart --update-goldens
echo "Captured. Inspect test/goldens/ and screenshots/ before promoting."
