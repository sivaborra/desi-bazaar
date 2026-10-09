/// Web (and other non-io platforms): no local probing. The 60s rule is
/// enforced server-side on complete; the UI states the limit up front.
class _ProbeUnsupported implements Exception {
  @override
  String toString() => 'local duration probing is not supported on this platform';
}

Future<Duration> probeVideoDuration(String path) async =>
    throw _ProbeUnsupported();
