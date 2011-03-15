%%% @hidden
%%% @author     Max Lapshin <max@maxidoors.ru> [http://erlyvideo.org]
%%% @copyright  2010 Max Lapshin
%%% @doc        SDP tests module
%%% @end
%%% @reference  See <a href="http://erlyvideo.org/rtp" target="_top">http://erlyvideo.org</a> for common information.
%%% @end
%%%
%%% This file is part of erlang-rtp.
%%%
%%% erlang-rtp is free software: you can redistribute it and/or modify
%%% it under the terms of the GNU General Public License as published by
%%% the Free Software Foundation, either version 3 of the License, or
%%% (at your option) any later version.
%%%
%%% erlang-rtp is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%% GNU General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with erlang-rtp.  If not, see <http://www.gnu.org/licenses/>.
%%%
%%%---------------------------------------------------------------------------------------
-module(sdp_tests).
-author('Max Lapshin <max@maxidoors.ru>').
-include_lib("eunit/include/eunit.hrl").
-include_lib("../include/video_frame.hrl").
-include_lib("../include/media_info.hrl").
-include_lib("../include/sdp.hrl").

-compile(export_all).

beward_sdp() ->
  <<"v=0
o=- 1275067839203788 1 IN IP4 0.0.0.0
s=Session streamed by \"nessyMediaServer\"
i=h264
t=0 0
a=tool:LIVE555 Streaming Media v2008.04.09
a=type:broadcast
a=control:*
a=range:npt=0-
a=x-qt-text-nam:Session streamed by \"nessyMediaServer\"
a=x-qt-text-inf:h264
m=video 0 RTP/AVP 99
c=IN IP4 0.0.0.0
a=rtpmap:99 H264/90000
a=fmtp:99 packetization-mode=28;profile-level-id=4D0028.; sprop-parameter-sets=J00AKI2NKAoAt2AtQEBAUAAAPoAADDUGhgBQAABZ9LvLjQwAoAAAs+l3lwT6LAA=,KO48gA==
a=control:track1
a=cliprect:0,0,1280,720
a=framerate:25.000000
m=audio 7878 RTP/AVP 8
a=rtpmap:8 PCMA/8000/1
a=control:track2">>.

%% Tests with rtsp_stream temporary broken due to replacement this record with media_desc and change its structure
beward_test() ->
  ?assertMatch(#media_info{
    flow_type = stream,
    options = [{connect, {inet4, "0.0.0.0"}}],
    video = [#stream_info{
      content = video,
      stream_id = 1,
      codec = h264,
      config = <<1,77,0,40,255,225,0,47,39,77,0,40,141,141,40,10,0,183,96,45,64,
                    64,64,80,0,0,62,128,0,12,53,6,134,0,80,0,0,89,244,187,203,141,
                    12,0,160,0,0,179,233,119,151,4,250,44,0,1,0,4,40,238,60,128>>, 
      params = #video_params{width = 1280, height = 720},
      timescale = 90
    }],
    audio = [#stream_info{
      content = audio,
      stream_id = 2,
      codec = pcma,
      config = undefined,
      params = #audio_params{channels = 1, sample_rate = 8000},
      timescale = 8
    }]
  }, sdp:decode(beward_sdp())).
  
  % ?assertEqual([{media_desc,video,undefined,0,
  %              [{payload,99,h264,90.0,undefined,undefined,[]}],
  %              "track1",
  %              <<40,238,60,128>>,
  %              <<39,77,0,40,141,141,40,10,0,183,96,45,64,64,64,80,0,0,62,128,0,12,53,6,134,0,
  %                80,0,0,89,244,187,203,141,12,0,160,0,0,179,233,119,151,4,250,44,0>>,
  %              undefined},
  %  {media_desc,audio,undefined,7878,
  %              [{payload,8,pcma,8.0,undefined,undefined,[]}],
  %              "track2",undefined,undefined,undefined}], sdp:decode(beward_sdp())).



quicktime_broadcaster_sdp() ->
<<"v=0
o=- 165 931665148 IN IP4 127.0.0.0
s=QuickTime
c=IN IP4 127.0.0.1
t=0 0
a=x-qt-text-an©:railsconf
a=range:npt=now-
a=isma-compliance:2,2.0,2
m=audio 0 RTP/AVP 96
b=AS:8
a=rtpmap:96 mpeg4-generic/8000/1
a=fmtp:96 profile-level-id=15;mode=AAC-hbr;sizelength=13;indexlength=3;indexdeltalength=3;config=1588
a=mpeg4-esid:101
a=control:trackid=1
m=video 0 RTP/AVP 97
b=AS:300
a=rtpmap:97 H264/90000
a=fmtp:97 packetization-mode=1;profile-level-id=4D400C;sprop-parameter-sets=J01ADKkYUI/LgDUGAQa2wrXvfAQ=,KN4JF6A=
a=mpeg4-esid:201
a=cliprect:0,0,120,160
a=framesize:97 160-120
a=control:trackid=2
">>.

quicktime_broadcaster_test() ->
  ?assertMatch(#media_info{
    flow_type = stream,
    options = [{connect, {inet4, "127.0.0.1"}}],
    video = [#stream_info{
      content = video,
      stream_id = 2,
      codec = h264,
      config = <<1,77,0,12,255,225,0,20,39,77,64,12,169,24,80,143,203,128,53,6,1,6,182,194,
        181,239,124,4,1,0,5,40,222,9,23,160>>, 
      params = #video_params{width = 160, height = 128},
      timescale = 90,
      options = [{control,"trackid=2"}]
    }],
    audio = [#stream_info{
      content = audio,
      stream_id = 1,
      codec = aac,
      config = <<21,136>>,
      timescale = 8,
      options = [{control,"trackid=1"}]
    }]
  }, sdp:decode(quicktime_broadcaster_sdp())).


axis_m1011_sdp() ->
  <<"v=0
o=- 1273580251173374 1273580251173374 IN IP4 axis-00408ca51334.local
s=Media Presentation
e=NONE
c=IN IP4 0.0.0.0
b=AS:50000
t=0 0
a=control:*
a=range:npt=0.000000-
m=video 0 RTP/AVP 96
b=AS:50000
a=framerate:30.0
a=control:trackID=1
a=rtpmap:96 H264/90000
a=fmtp:96 packetization-mode=1; profile-level-id=420029; sprop-parameter-sets=Z0IAKeNQFAe2AtwEBAaQeJEV,aM48gA==">>.


axis_m1011_test() ->
  ?assertMatch(#media_info{
    flow_type = stream,
    options = [{connect, {inet4, "0.0.0.0"}}],
    video = [#stream_info{
      content = video,
      stream_id = 1,
      codec = h264,
      config = <<1,66,0,41,255,225,0,18,103,66,0,41,227,80,20,7,182,2,220,4,4,6,144,120,145,
        21,1,0,4,104,206,60,128>>, 
      params = #video_params{width = 640, height = 480},
      timescale = 90,
      options = [{control,"trackID=1"}]
    }],
    audio = []
  }, sdp:decode(axis_m1011_sdp())).


axis_p1311_sdp() ->
  <<"v=0
o=- 1269257289197834 1269257289197834 IN IP4 10.10.11.48
s=Media Presentation
e=NONE
c=IN IP4 0.0.0.0
b=AS:50032
t=0 0
a=control:rtsp://10.10.11.48:554/axis-media/media.amp?videocodec=h264
a=range:npt=0.000000-
m=video 0 RTP/AVP 96
b=AS:50000
a=framerate:30.0
a=control:rtsp://10.10.11.48:554/axis-media/media.amp/trackID=1?videocodec=h264
a=rtpmap:96 H264/90000
a=fmtp:96 packetization-mode=1; profile-level-id=420029; sprop-parameter-sets=Z0IAKeNQFAe2AtwEBAaQeJEV,aM48gA==
m=audio 0 RTP/AVP 97
b=AS:32
a=control:rtsp://10.10.11.48:554/axis-media/media.amp/trackID=2?videocodec=h264
a=rtpmap:97 mpeg4-generic/16000/1
a=fmtp:97 profile-level-id=15; mode=AAC-hbr;config=1408; SizeLength=13; IndexLength=3;IndexDeltaLength=3; Profile=1; bitrate=32000;">>.

axis_p1311_test() ->
  ?assertMatch(#media_info{
    flow_type = stream,
    options = [{connect, {inet4, "0.0.0.0"}}],
    video = [#stream_info{
      content = video,
      stream_id = 1,
      codec = h264,
      config = <<1,66,0,41,255,225,0,18,103,66,0,41,227,80,20,7,182,2,220,4,4,6,144,120,145,
        21,1,0,4,104,206,60,128>>, 
      params = #video_params{width = 640, height = 480},
      timescale = 90,
      options = [{control,"rtsp://10.10.11.48:554/axis-media/media.amp/trackID=1?videocodec=h264"}]
    }],
    audio = [#stream_info{
      content = audio,
      stream_id = 2,
      codec = aac,
      config = <<20,8>>,
      timescale = 16,
      options = [{control,"rtsp://10.10.11.48:554/axis-media/media.amp/trackID=2?videocodec=h264"}]
    }]
  }, sdp:decode(axis_p1311_sdp())).
  


axis_server_sdp() ->
  <<"v=0
o=- 1266472632763124 1266472632763124 IN IP4 192.168.4.1
s=Media Presentation
e=NONE
c=IN IP4 0.0.0.0
b=AS:50000
t=0 0
a=control:*
a=range:npt=0.000000-
m=video 0 RTP/AVP 96
b=AS:50000
a=framerate:25.0
a=control:trackID=1
a=rtpmap:96 H264/90000
a=fmtp:96 packetization-mode=1; profile-level-id=420029; sprop-parameter-sets=Z0IAKeNQFAe2AtwEBAaQeJEV,aM48gA==">>.

axis_server_test() ->
  ?assertMatch(#media_info{
    flow_type = stream,
    options = [{connect, {inet4, "0.0.0.0"}}],
    video = [#stream_info{
      content = video,
      stream_id = 1,
      codec = h264,
      config = <<1,66,0,41,255,225,0,18,103,66,0,41,227,80,20,7,182,2,220,4,4,6,144,120,145,
        21,1,0,4,104,206,60,128>>, 
      params = #video_params{width = 640, height = 480},
      timescale = 90,
      options = [{control,"trackID=1"}]
    }],
    audio = []
  }, sdp:decode(axis_server_sdp())).
  
% D-Link is an IP-camera, not AVC-camera. ertsp doesn't currently support it.
% http://github.com/erlyvideo/erlyvideo/issues/issue/5
dlink_dcs_2121_test1() ->
  ?assertEqual([{media_desc,video,
               {inet4,"0.0.0.0"},
               0,
               [{payload,96,mp4v,90.0,undefined,undefined,[]}],
               "trackID=1",undefined,undefined,undefined},
   {media_desc,audio,
               {inet4,"0.0.0.0"},
               0,
               [{payload,0,pcmu,8.0,undefined,undefined,[]}],
               "trackID=2",undefined,undefined,undefined}], sdp:decode(<<"v=0\r\no=CV-RTSPHandler 1123412 0 IN IP4 10.48.135.130\r\ns=D-Link DCS-2121\r\nc=IN IP4 0.0.0.0\r\nt=0 0\r\na=charset:Shift_JIS\r\na=range:npt=now-\r\na=control:*\r\na=etag:1234567890\r\nm=video 0 RTP/AVP 96\r\nb=AS:18\r\na=rtpmap:96 MP4V-ES/90000\r\na=control:trackID=1\r\na=fmtp:96 profile-level-id=1;config=000001B001000001B509000001000000012000C488BA98514043C1443F;decode_buf=76800\r\na=sendonly\r\nm=audio 0 RTP/AVP 0\r\na=rtpmap:0 PCMU/8000\r\na=control:trackID=2\r\na=sendonly\r\n">>)).



darwinss_test1() ->
  ?assertEqual([{media_desc,video,undefined,10000,
               [{payload,96,h264,90.0,undefined,undefined,[]}],
               undefined,undefined,undefined,undefined}], sdp:decode(<<"v=0\r\no=- 1188340656180883 1 IN IP4 224.1.2.3\r\ns=Session streamed by GStreamer\r\ni=server.sh\r\nt=0 0\r\na=tool:GStreamer\r\na=type:broadcast\r\nm=video 10000 RTP/AVP 96\r\nc=IN IP4 224.1.2.3\r\na=rtpmap:96 H264/90000\r\na=framerate:30">>)).

darwin_sdp() ->
  <<"v=0
o=StreamingServer 3485077701 1211414520000 IN IP4 129.85.244.160
s=/evolution/coyne.mov
u=http:///
e=admin@
c=IN IP4 0.0.0.0
b=AS:876
t=0 0
a=control:*
a=range:npt=0-3973.80667
m=video 0 RTP/AVP 96
b=AS:734
a=rtpmap:96 H264/90000
a=control:trackID=1
a=cliprect:0,0,360,480
a=range:npt=0-3973.8071
a=fmtp:96 packetization-mode=1;profile-level-id=42E016;sprop-parameter-sets=Z0LAFpZ0DwX/LgCBAAALuwACvyC0YAw4BJd73weEQjU=,aN48gA==
m=audio 0 RTP/AVP 97
b=AS:142
a=rtpmap:97 MP4A-LATM/48000/2
a=control:trackID=2
a=range:npt=0-3973.8240
a=fmtp:97 profile-level-id=15;object=2;cpresent=0;config=400023203FC0
">>.

darwin_test1() ->
  ?assertEqual([{media_desc,video,
               {inet4,"0.0.0.0"},
               0,
               [{payload,96,h264,90.0,undefined,undefined,[]}],
               "trackID=1",
               <<104,222,60,128>>,
               <<103,66,192,22,150,116,15,5,255,46,0,129,0,0,11,
                              187,0,2,191,32,180,96,12,56,4,151,123,223,7,132,66,53>>,
               undefined},
   {media_desc,audio,
               {inet4,"0.0.0.0"},
               0,
               [{payload,97,mp4a,48.0,undefined,undefined,[]}],
               "trackID=2",undefined,undefined,
               <<64,0,35,32,63,192>>}], sdp:decode(darwin_sdp())).


sanyo_hd2300_sdp() ->
  <<"v=0
o=- 15007197427132687974 15007197427562184703 IN IP4 213.88.16.13
s=Media presentation
c=IN IP4 0.0.0.0
b=AS:1950
t=0 0
m=video 0 RTP/AVP 100
b=AS:1950
a=framerate:25.0
a=quality:4
a=control:trackID=1
a=rtpmap:100 H264/90000
a=fmtp:100 profile-level-id=42e01e; Reso=640:360; Scanning=0; TVSystem=pal; CameraMode=hd; BitRateMode=vbr; Gop=30; AspectRatio=16:9; packetization-mode=1; sprop-parameter-sets=Z0LwHpGwKAv+XAW4KAgKAAAH0gABhqEIAAAAAAA=,aM44gA==
m=data 0 RTP/AVP 111
a=rtpmap:111 octet-stream/1
a=fmtp:111 Mac=08007b88d4ec; Model=VCC-HD2300P; TargetBitRate=975; FirmVer=010202; CameraSeries=2;
">>.

  sanyo_hd2300_test1() ->
    ?assertEqual([{media_desc,video,
                 {inet4,"0.0.0.0"},
                 0,
                 [{payload,100,h264,90.0,undefined,undefined,[]}],
                 "trackID=1",
                 <<104,206,56,128>>,
                 <<103,66,240,30,145,176,40,11,254,92,5,184,40,8,10,0,0,7,
                   210,0,1,134,161,8,0,0,0,0,0>>,
                 undefined}], sdp:decode(sanyo_hd2300_sdp())).
    


some_random_sdp() ->
  <<"v=0
o=- 234234 546456 IN IP4 10.11.12.13
s=Test
c=IN IP4 10.11.12.13
t=0 0
a=tool:LIVE555 Streaming Media v2008.04.09
a=type:broadcast
a=control:*
a=range:npt=0-
m=video 1500 RTP/AVP 8
a=control:trackID=1
a=rtpmap:8 PCMA/90000
m=audio 1600 RTP/AVP 97
a=control:trackID=2
a=rtpmap:97 MP4A-LATM/48000
">>.



encode_avc_test() ->
  ?assertEqual(<<"m=video 0 RTP/AVP 96\r
a=control:trackID=1\r
a=rtpmap:96 H264/90000\r
a=fmtp:96 packetization-mode=1;profile-level-id=42E029;sprop-parameter-sets=Z0IAKeNQFAe2AtwEBAaQeJEV,aM48gA==\r
">>, 
  sdp:encode(#stream_info{
    content = video,
    stream_id = 1,
    codec = h264,
    config = <<1,66,0,41,255,225,0,18,103,66,0,41,227,80,20,7,182,2,220,4,4,6,144,120,145,
      21,1,0,4,104,206,60,128>>, 
    params = #video_params{width = 640, height = 480},
    timescale = 1000
  })).

encoder_test1() ->
  Sess =
    #session_desc{version = <<"0">>,
                  originator = #sdp_o{username = <<"-">>,
                                      sessionid = <<"234234">>,
                                      version = <<"546456">>,
                                      netaddrtype = inet4,
                                      address = "10.11.12.13"},
                  name = <<"Test">>,
                  connect = {inet4,"10.11.12.13"},
                  attrs = [
                           {tool, "LIVE555 Streaming Media v2008.04.09"},
                           {type, "broadcast"},
                           {control, "*"},
                           {range, "npt=0-"}
                          ]},
  MediaV = #stream_info{
    content = video,
    options = [{connect, {inet4, "10.11.12.13"}}, {port, 1500}, {control, <<"trackID=1">>}],
    codec = pcma,
    timescale = 90,
    stream_id = 1,
    params = #video_params{}
  },
  MediaA = #stream_info{
    content = audio,
    options = [{connect, {inet4, "10.11.12.13"}}, {port, 1600}, {control, <<"trackID=2">>}],
    codec = aac,
    stream_id = 2,
    timescale = 48,
    params = #audio_params{channels = 2, sample_rate = 48000},
    config = <<14,23>>
  },
  ?assertEqual(some_random_sdp(), sdp:encode(Sess, #media_info{audio = [MediaA], video = [MediaV]})).
