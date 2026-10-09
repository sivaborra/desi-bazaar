// Central test setup for the Desi Bazaar widget suite.
//
// Every test file imports this and uses it — no duplicated font loaders,
// no ad-hoc HttpOverrides juggling, no stray global state.
//
// Contents:
// - [ensureTestFont]      deterministic font for text rendering in tests
// - [useRealHttp]         opt out of the test binding's HTTP mock
// - [ensureBackend]       probe the slice backend, fail with instructions
// - [withPhoneViewport]   run a body at a real phone viewport, then reset
// - [pumpSettled]         bounded settle for animation-heavy screens
// - [resetTestGlobals]    call from tearDownAll
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
/// Backend the live tests talk to. Start it fresh before running:
///   cd vertical-slice && .venv/bin/uvicorn app:app --port 8100
const testBackendBaseUrl = 'http://localhost:8100';

/// Widget tests render text as black boxes unless a real font is loaded.
/// Loads the bundled test font asset (assets/fonts/TestRoboto.ttf, OFL —
/// see assets/fonts/OFL-NOTE.txt) under the 'Roboto' family name so default
/// Material text styles resolve to readable glyphs.
///
/// No host OS font paths: tests must not depend on /usr/share/fonts or any
/// other machine-specific location.
///
/// Caveat (honest): glyphs come from the bundled test font, not the real
/// Roboto — screenshots are proof-of-execution, not cross-machine golden
/// masters.
Future<void> ensureTestFont() async {
  final bytes = await rootBundle.load('assets/fonts/TestRoboto.ttf');
  final loader = FontLoader('Roboto')..addFont(Future.value(bytes));
  await loader.load();
}

/// The flutter_test binding replaces HttpClient with a mock that 400s every
/// request. Call this inside a test to restore genuine backend access.
void useRealHttp() {
  HttpOverrides.global = null;
}

/// Probe the slice backend. Returns normally when it answers, otherwise
/// throws with the exact command to start it — never a bare connection
/// error.
Future<void> ensureBackend() async {
  // The flutter_test binding mocks HttpClient (400s everything) — clear it
  // before probing, same as useRealHttp() does inside tests.
  HttpOverrides.global = null;
  try {
    final r = await http
        .get(Uri.parse('$testBackendBaseUrl/v1/listings'),
            headers: {'X-Principal': 'buyer-rohan'})
        .timeout(const Duration(seconds: 5));
    if (r.statusCode == 200) return;
    throw StateError('Backend answered ${r.statusCode}, expected 200.');
  } catch (e) {
    throw StateError(
        'Slice backend not reachable at $testBackendBaseUrl ($e). Start it fresh:\n'
        '  cd vertical-slice && .venv/bin/uvicorn app:app --port 8100');
  }
}

/// Run [body] at a real phone viewport (logical [size], 3x DPR), then
/// restore the test surface. Replaces the old no-op _phoneSize().
Future<void> withPhoneViewport(
    WidgetTester tester, Size size, Future<void> Function() body) async {
  final view = tester.view;
  final oldSize = view.physicalSize;
  final oldRatio = view.devicePixelRatio;
  view.devicePixelRatio = 3.0;
  view.physicalSize = Size(size.width * 3.0, size.height * 3.0);
  addTearDown(() {
    view.devicePixelRatio = oldRatio;
    view.physicalSize = oldSize;
  });
  await body();
}

/// Phone viewports covered by the suite (logical pixels).
const phoneViewports = [
  Size(390, 844), // iPhone-class
  Size(412, 915), // Pixel-class
];

/// Reset globals a test may have touched. Call from tearDownAll in files
/// that call [useRealHttp].
void resetTestGlobals() {
  HttpOverrides.global = null;
}

/// Bounded replacement for [WidgetTester.pumpAndSettle].
///
/// pumpAndSettle hangs forever when a screen has an animation that never
/// settles (loading spinners, shimmer). This pumps a fixed number of frames
/// instead — enough for the UI to reach its resting state — then stops.
/// BUG-008: screenshot tests timed out on pumpAndSettle in every environment
/// tried; bounded pumps are deterministic.
Future<void> pumpSettled(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
