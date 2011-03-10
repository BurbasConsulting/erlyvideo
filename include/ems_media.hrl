-define(DEFAULT_GLUE_DELTA, 25).

-record(ems_media, {
  url,
  name,
  host,
  module,
  state,
  type,
  options,
  video_config,
  audio_config,
  metadata,
  clients,
  waiting_for_config = [],
  frame_number = 0,
  source,
  source_ref,
  storage,
  format,
  
  last_gop = undefined,
  
  transcoder,
  trans_state,

  created_at,
  last_dts = 0,
  ts_delta,
  glue_delta,
  
  source_timeout,
  source_timeout_ref,

  clients_timeout,
  clients_timeout_ref,
  
  retry_count = 0,
  retry_limit = 100
}).
