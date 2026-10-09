// Video duration probing, platform-split: native uses video_player on a
// real file; web cannot probe locally, so the 60s rule is enforced
// server-side on complete (the contract re-checks there) and the UI states
// the limit up front.
export 'video_probe_stub.dart'
    if (dart.library.io) 'video_probe_io.dart';
