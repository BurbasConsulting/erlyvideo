-define(FRAMES_BUFFER, 15).
-define(REORDER_FRAMES, 10).
-define(DEFAULT_TIMEOUT, 30000).
-define(TIMEOUT, 10000).

-define(SERVER_NAME, "Erlyvideo").

-record(rtsp_socket, {
  callback,
  direction,
  buffer = <<>>,
  addr,
  port,
  url,
  auth = "",
  frames = [],
  socket,
  options,
  rtp_streams = {},
  control_map,
  media         :: pid(),
  media_info,
  rtp           :: pid(),
  rtp_ref       :: reference(),
  sent_audio_config = false,
  audio_rtp_stream,
  video_rtp_stream,
  state,
  pending,
  pending_reply = ok,
  seq = 0,
  timeout = ?DEFAULT_TIMEOUT,
  session
}).
