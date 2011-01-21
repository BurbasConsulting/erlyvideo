%%% @author     Max Lapshin <max@maxidoors.ru> [http://erlyvideo.org]
%%% @copyright  2010 Max Lapshin
%%% @doc        RTP decoder module
%%% @end
%%% @reference  See <a href="http://erlyvideo.org/ertp" target="_top">http://erlyvideo.org</a> for common information.
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
-module(rtp_server).
-author('Max Lapshin <max@maxidoors.ru>').

-include_lib("erlmedia/include/h264.hrl").
-include_lib("erlmedia/include/video_frame.hrl").
-include("sdp.hrl").
-include("rtp.hrl").
-include("log.hrl").


-define(RTCP_SR_INTERVAL, 5000).
-define(RTCP_RR_INTERVAL, 5000).

%% API
-export([
         start_link/1,
         play/3,
         listen_ports/4,
         add_stream/4,
         stop/1
        ]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2, code_change/3]).


-export([encode/2, encode/4]).

-record(ports_desc, {
          proto        :: tcp | udp,
          addr         :: term(),
          port_rtp     :: integer(),
          port_rtcp    :: integer(),
          socket_rtp   :: term(),
          socket_rtcp  :: term()
         }).

-record(interleaved_desc, {
          socket_owner    :: pid(),
          channel_rtp     :: integer(),
          channel_rtcp    :: integer()
         }).

-record(desc, {
          method    ::  #ports_desc{} | #interleaved_desc{},
          track_control,
          state,
          acc = []  :: list()
         }).


-record(state, {
          type      :: consumer | producer,
          audio     :: #desc{},
          video     :: #desc{},
          media     :: pid(),
          stream_id :: any(),
          parent    :: pid(),
          tc_fun    :: function(),
          rtcp_send = false :: boolean()
         }).

%% Gen server process does control RTP-stream.
start_link(Args) ->
  Parent = self(),
  gen_server:start_link(?MODULE, [Args, Parent], []).

init([{Type, Opts}, Parent]) ->
  process_flag(trap_exit, true),
  Media = proplists:get_value(media, Opts),
  StreamId = proplists:get_value(stream_id, Opts),
  erlang:monitor(process, Parent),
  random:seed(now()),
  {ok, #state{type = Type,
              media = Media,
              stream_id = StreamId,
              parent = Parent}}.


handle_call({play, Fun, Media}, _From,
            #state{type = RtpType,
                   audio = AudioDesc,
                   video = VideoDesc,
                   media = OldMedia} = State) ->
  ?DBG("DS: Play", []),
  ?DBG("Media: ~p, Old Media: ~p", [Media, OldMedia]),
  Info = [{Track, Seq-1, RtpTime-1} ||
           #desc{track_control = Track,
                 state = #base_rtp{sequence = Seq,
                                   timecode = RtpTime}} <- [AudioDesc, VideoDesc],
         is_integer(Seq), is_integer(RtpTime)],
  Fun(),
  if RtpType == producer ->
      self() ! {send_sr, [audio, video], []},
      timer:send_interval(?RTCP_SR_INTERVAL, {send_sr, [audio, video], []});
     true -> pass
  end,
  %%timer:send_interval(100, {dump_pack}),
  {reply, {ok, Info}, State};

handle_call({listen_ports,
             #media_desc{type = Type,
                         payloads = [#payload{num = PTnum,
                                              codec = _Codec,
                                              clock_map = ClockMap}|_],
                         track_control = TCtl},
             Proto, Method}, _From,
           #state{type = RtpType} = State) ->
  Timecode = if RtpType == consumer -> undefined; true -> init_rnd_timecode() end,
  BaseRTP = #base_rtp{codec = PTnum,
                      media = Type,
                      clock_map = ClockMap,
                      sequence = init_rnd_seq(),
                      base_timecode = Timecode,
                      timecode = Timecode,
                      base_wall_clock = 0,
                      wall_clock = 0,
                      last_sr = get_date(),
                      stream_id = init_rnd_ssrc()},
  case Method of
    ports ->
      OP = open_ports(Type),
      ?DBG("OP: ~p", [OP]),
      {RTP, RTPSocket, RTCP, RTCPSocket} = OP,
      gen_udp:controlling_process(RTPSocket, self()),
      gen_udp:controlling_process(RTCPSocket, self()),
      Result = {RTP, RTCP},
      MethodDesc = #ports_desc{
        proto = Proto,
        socket_rtp = RTPSocket,
        socket_rtcp = RTCPSocket
       };
    interleaved ->
      Result = ok,
      MethodDesc = #interleaved_desc{}
  end,
  NewState =
    case Type of
      audio ->
        State#state{audio = #desc{method = MethodDesc,
                                  track_control = TCtl,
                                  state = BaseRTP}};
      video ->
        State#state{video = #desc{method = MethodDesc,
                                  track_control = TCtl,
                                  state = BaseRTP}}
    end,
  ?DBG("NewState:~n~p", [NewState]),
  {reply, {ok, {Method, Result}}, NewState};

handle_call({add_stream,
             #media_desc{type = Type,
                         connect = Connect,
                         port = RemotePort,
                         track_control = TCtl} = MS,
             {Method, Params}, Extra}, _From,
            #state{audio = AudioDesc,
                   video = VideoDesc} = State) ->
  ?DBG("DS: Add Stream:~n~p~n~p, ~p, ~p", [MS, Method, Params, Extra]),

  [BaseMethod] = [M || #desc{method = M} <- [AudioDesc, VideoDesc]],
  case Method of
    ports ->
      case Params of
        {Addr, PortRTP_p, PortRTCP_p} ->
          ConnAddr = Addr,
          PortRTP = PortRTP_p,
          PortRTCP = PortRTCP_p;
        _ ->
          ConnAddr =
            case Connect of
              {inet4, Address} -> Address;
              _ -> undefined
            end,
          if is_number(RemotePort) andalso (RemotePort>0) ->
              PortRTP = RemotePort,
              PortRTCP = RemotePort+1;
             true ->
              PortRTP = undefined,
              PortRTCP = undefined
          end
      end,

      MethodDesc = BaseMethod#ports_desc{
                     addr = ConnAddr,
                     port_rtp = PortRTP,
                     port_rtcp = PortRTCP};
    interleaved ->
      {SocketOwner, ChanRTP, ChanRTCP} = Params,
      MethodDesc = BaseMethod#interleaved_desc{
                     socket_owner = SocketOwner,
                     channel_rtp = ChanRTP,
                     channel_rtcp = ChanRTCP}
  end,
  TCFun = compose_tc_fun(Extra),
  NewState =
    case Type of
      audio ->
        State#state{audio = AudioDesc#desc{method = MethodDesc,
                                           track_control = TCtl},
                    tc_fun = TCFun};
      video ->
        State#state{video = VideoDesc#desc{method = MethodDesc,
                                           track_control = TCtl},
                    tc_fun = TCFun}
    end,
  ?DBG("NewState:~n~p", [NewState]),
  {reply, ok, NewState};

handle_call({stop}, _From, State) ->
  ?DBG("Stop RTP Process ~p", [self()]),
  {stop, normal, ok, State};
handle_call(Request, _From, State) ->
  ?DBG("Unknown call: ~p", [Request]),
  Error = {unknown_call, Request},
  {stop, Error, {error, Error}, State}.

handle_cast(Msg, State) ->
  Error = {unknown_cast, Msg},
  {stop, Error, State}.

handle_info({Event, Types, Args},
            #state{audio = AudioDesc,
                   video = VideoDesc} = State)
  when Event =:= send_sr orelse
       Event =:= send_rr ->
  AllDescs = [{audio, AudioDesc}, {video, VideoDesc}],
  StateRes =
  [fun(#desc{method = MDesc, state = BaseRTP}) ->
       case Event of
         send_sr ->
           {BaseRTP1, RTCP_SR} = encode(sender_report, BaseRTP),
           {BaseRTP_End, RTCP_SD} = encode(source_description, BaseRTP1),
           RTCP = <<RTCP_SR/binary, RTCP_SD/binary>>%%;
         %% send_rr ->
         %%   {_, LocalStreamId} = Args,
         %%   {BaseRTP1, RTCP_RR} = encode({receiver_report, LocalStreamId}, BaseRTP),
         %%   {BaseRTP_End, RTCP_SD} = encode(source_description, BaseRTP1),
         %%   RTCP = <<RTCP_RR/binary, RTCP_SD/binary>>
       end,

       case MDesc of
         #ports_desc{addr = Addr, socket_rtcp = RTCPSocket, port_rtcp = PortRTCP} ->
           case Event of
             send_sr -> Port = PortRTCP;
             send_rr -> {Port, _} = Args
           end,
           %%?DBG("Send UDP: ~p(~p), ~p, ~p", [RTCPSocket, inet:port(RTCPSocket), Addr, Port]),
           send_udp(RTCPSocket, Addr, Port, RTCP);
         #interleaved_desc{socket_owner = SocketOwner, channel_rtcp = ChanRTCP} ->
           send_interleaved(SocketOwner, ChanRTCP, {rtcp, RTCP})
       end,
       {T, BaseRTP_End};
      (_) ->
       pass
   end(Desc) || {T, Desc} <- [{T, proplists:get_value(T, AllDescs)} || T <- Types]],
  NewState =
    lists:foldl(fun({audio, NewBaseRTP}, #state{audio = ADesc} = St) ->
                    St#state{audio = ADesc#desc{state = NewBaseRTP}};
                   ({video, NewBaseRTP}, #state{video = VDesc} = St) ->
                    St#state{video = VDesc#desc{state = NewBaseRTP}};
                   (_, St) -> St
                end, State, StateRes),
  {noreply, NewState};

handle_info(#video_frame{content = audio, flavor = frame,
                         dts = DTS, pts = PTS,
                         codec = Codec, sound = {_Channel, _Size, _Rate},
                         body = Body} = Frame,
            #state{audio = #desc{acc = Acc} = AudioDesc,
                   tc_fun = TCFun} = State) ->
  ?DBG("Audio: ~n~p", [Frame]),
  case AudioDesc of
    #desc{method = MDesc, state = BaseRTP, acc = Acc} ->
      if (DTS == 0) and (Acc == []) ->
          NewState = State#state{audio = AudioDesc#desc{acc = Body}};
         true ->
          %%?DBG("DS: Audio Frame(~p) (pl ~p):~n~p", [self(), iolist_size(Body), Body]),
          NBody = iolist_to_binary([Acc, Body]),
          {NewBaseRTP, RTPs} = encode(rtp, TCFun(DTS, PTS, BaseRTP), Codec, NBody),
          case MDesc of
            #ports_desc{addr = Addr, socket_rtp = RTPSocket, port_rtp = PortRTP} ->
              ?DBG("RTP to ~p:~p :~n~p", [Addr, PortRTP, RTPs]),
              send_udp(RTPSocket, Addr, PortRTP, RTPs);
            #interleaved_desc{socket_owner = SocketOwner, channel_rtp = ChanRTP, channel_rtcp = _ChanRTCP} ->
              send_interleaved(SocketOwner, ChanRTP, {rtp, RTPs})
          end,
          NewState = State#state{audio = AudioDesc#desc{state = NewBaseRTP, acc = []}}
      end;
    _ ->
      NewState = State
  end,
  {noreply, NewState};

handle_info(#video_frame{content = audio, flavor = config} = Frame,
            #state{} = State) ->
  %% Ignore
  ?DBG("Audio: ~n~p", [Frame]),
  {noreply, State};

handle_info(#video_frame{content = metadata} = Frame,
            #state{} = State) ->
  %% Ignore
  ?DBG("Audio: ~n~p", [Frame]),
  {noreply, State};

handle_info(#video_frame{content = video, flavor = Flavor,
                         dts = DTS, pts = PTS,
                         codec = Codec, body = Body} = _Frame,
            #state{video = VideoDesc,
                   tc_fun = TCFun} = State) ->
  %%?DBG("DS: Video Frame(~p)", [DTS]),
  case VideoDesc of
    #desc{method = MDesc, state = #base_rtp{} = BaseRTP, acc = Acc} ->
      %%?DBG("DS: Video Frame(~p):~n~p", [self(), _Frame]),
      %%?DBG("VideoDesc: ~p", [VideoDesc]),
      %%?DBG("Video Frame(~p):~n~p", [self(), Frame]),
      %% Send Video
      %%?DBG("ACC:~n~p", [Acc]),
      case Flavor of
        config ->
          case h264:unpack_config(Body) of
            {FrameLength, [_SPS, _PPS]} ->
              NewState = State#state{video = VideoDesc#desc{state = BaseRTP#base_rtp{framelens = FrameLength}}};
            _ ->
              NewState = State
          end;
        %% config ->
        %%   case h264:unpack_config(Body) of
        %%     {FrameLength, [SPS, PPS]} ->
        %%       NewAcc = Acc ++ [SPS, PPS],
        %%       %%?DBG("NewAcc: ~p", [NewAcc]),
        %%       NewState = State#state{video = VideoDesc#desc{state = BaseRTP#base_rtp{framelens = FrameLength}, acc = NewAcc}};
        %%     _ ->
        %%       <<_:64,Data/binary>> = Body,
        %%       NewAcc = Acc ++ [Data],
        %%       NewState = State#state{video = VideoDesc#desc{acc = NewAcc}}
        %%   end;
        KF when ((KF == keyframe) or (KF == frame)) ->
          if length(Acc) > 0 ->
              Data = [{config, Acc}, {KF, Body}];
             true ->
              Data = {KF, Body}
          end,
          {NewBaseRTP, RTPs} = encode(rtp, TCFun(DTS, PTS, BaseRTP), Codec, Data),
          case MDesc of
            #ports_desc{addr = Addr, socket_rtp = RTPSocket, port_rtp = PortRTP} ->
              %%?DBG("RTPs to ~p:~p~n~p", [Addr, PortRTP, RTPs]),
              send_udp(RTPSocket, Addr, PortRTP, RTPs);
            #interleaved_desc{socket_owner = SocketOwner, channel_rtp = ChanRTP, channel_rtcp = _ChanRTCP} ->
              send_interleaved(SocketOwner, ChanRTP, {rtp, RTPs})
          end,
          NewState = State#state{video = VideoDesc#desc{state = NewBaseRTP, acc = []}}
      end;
    _ ->
      NewState = State
  end,
  {noreply, NewState};

handle_info({udp, SSocket, SAddr, SPort, Data},
            #state{audio = AudioDesc,
                   video = VideoDesc,
                   stream_id = StreamId,
                   media = Media} = State) ->
  {AudioRTCPSock, AudioRTPSock} =
    if is_record(AudioDesc, desc) ->
        {(AudioDesc#desc.method)#ports_desc.socket_rtcp, (AudioDesc#desc.method)#ports_desc.socket_rtp};
       true ->
        {undefined, undefined}
    end,
  {VideoRTCPSock, VideoRTPSock} =
    if is_record(VideoDesc, desc) ->
        {(VideoDesc#desc.method)#ports_desc.socket_rtcp, (VideoDesc#desc.method)#ports_desc.socket_rtp};
       true ->
        {undefined, undefined}
    end,

  case SSocket of
    AudioRTCPSock ->
      %%?DBG("Audio RTCP", []),
      do_audio_rtcp,
      NewState = State;
    AudioRTPSock ->
      NewBaseRTP = do_audio_rtp({udp, SAddr, SPort, Data}, AudioDesc, Media, StreamId),
      NewAudioDesc = AudioDesc#desc{state = NewBaseRTP},
      NewState = State#state{audio = NewAudioDesc, rtcp_send = true};
    VideoRTCPSock ->
      %%?DBG("Video RTCP", []),
      do_video_rtcp,
      NewState = State;
    VideoRTPSock ->
      %%?DBG("Video RTP", []),
      do_video_rtp,
      NewState = State;
    _Other ->
      ?DBG("Error: Other case: ~p, ~p, ~p", [SSocket, AudioDesc, VideoDesc]),
      NewState = State,
      error
  end,
  {noreply, NewState};

handle_info({interleaved, rtp, RTP}, State) ->
  ?DBG("Interleaved RTP: ~p", [RTP]),
  {noreply, State};
handle_info({interleaved, rtcp, RTCP}, State) ->
  ?DBG("Interleaved RTCP: ~p", [RTCP]),
  {noreply, State};

handle_info({dump_mq}, State) ->
  ?DBG("Queue Len: ~p", [erlang:process_info(self(), message_queue_len)]),
  {noreply, State};
handle_info({dump_pack}, #state{video = #desc{state = #base_rtp{packets = P}}} = State) ->
  {_A1, A2, A3} = now(),
  S = (A2*1000000) + A3,
  io:format("~b    ~b~n", [S, P]),
  {noreply, State};
handle_info({ems_stream, _, play_complete, _}, State) ->
  {stop, normal, State};
handle_info(Info, State) ->
  ?DBG("Unknown info:~n~p", [Info]),
  Error = {unknown_info, Info},
  {stop, Error, State}.

terminate(Reason, #state{audio = AD, video = MD}) ->
  ?DBG("RTP Process ~p terminates: ~p:~n~p~n~p", [self(), Reason, AD, MD]),

  [fun(#desc{method = #ports_desc{socket_rtp = S1, socket_rtcp = S2}})
       when is_port(S1), is_port(S2) ->
       gen_udp:close(S1), gen_udp:close(S2);
      (_) -> pass
   end(D) || D <- [AD, MD]].

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% API
play(Pid, Fun, Media) when is_function(Fun) ->
  gen_server:call(Pid, {play, Fun, Media}).

listen_ports(Pid, #media_desc{} = Stream, Proto, Method) ->
  gen_server:call(Pid, {listen_ports, Stream, Proto, Method}).

add_stream(Pid, #media_desc{} = Stream, {Method, Params}, Extra) ->
  gen_server:call(Pid, {add_stream, Stream, {Method, Params}, Extra}).

stop(Pid) ->
  gen_server:call(Pid, {stop}).

send_udp(Socket, Addr, Port, RTPs) ->
  F = fun(P) ->
          gen_udp:send(Socket, Addr, Port, P)
      end,
  send_rtp(F, RTPs).

send_interleaved(SockOwner, Channel, {Type, RTPs}) ->
  F = fun(P) ->
          SockOwner ! {interleaved, Channel, {Type, P}}
      end,
  send_rtp(F, RTPs).

send_rtp(F, RTP) when is_binary(RTP) ->
  F(RTP);
send_rtp(F, RTPs) when is_list(RTPs) ->
  [begin
     if is_list(R) ->
         [F(Rr) || Rr <- R];
        true ->
         F(R)
     end
   end || R <- RTPs].

open_ports(audio) ->
  try_rtp(8000);

open_ports(video) ->
  try_rtp(5000).

try_rtp(40000) ->
  error;

try_rtp(Port) ->
  case gen_udp:open(Port, [binary, {active, true}, {recbuf, 1048576}]) of
    {ok, RTPSocket} ->
      try_rtcp(Port, RTPSocket);
    {error, _} ->
      try_rtp(Port + 2)
  end.

try_rtcp(RTP, RTPSocket) ->
  RTCP = RTP+1,
  case gen_udp:open(RTCP, [binary, {active, true}]) of
    {ok, RTCPSocket} ->
      {RTP, RTPSocket, RTCP, RTCPSocket};
    {error, _} ->
      gen_udp:close(RTPSocket),
      try_rtp(RTP + 2)
  end.

%
%  0                   1                   2                   3
%  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
%  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
%  |V=2|P|X|  CC   |M|     PT      |       sequence number         |
%  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
%  |                           timestamp                           |
%  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
%  |           synchronization source (SSRC) identifier            |
%  +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
%  |            contributing source (CSRC) identifiers             |
%  |                             ....                              |
%  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+



ts_to_timecode(DTS, #base_rtp{clock_map = ClockMap, base_timecode = BaseTimecode, base_wall_clock = BaseDTS} = State) ->
  NewTC = round((DTS - BaseDTS)*ClockMap) + BaseTimecode,
  State#base_rtp{timecode = NewTC, wall_clock = round(DTS)}.

timecode_to_ts(TC, #base_rtp{clock_map = ClockMap, base_timecode = BaseTC, base_wall_clock = BaseWC} = _State) ->
  %%?DBG("TC: ~p, BaseTC: ~p, ClockMap: ~p, BaseWC: ~p", [TC, BaseTC, ClockMap, BaseWC]),
  (((TC - BaseTC)/ClockMap)+BaseWC)*1000.

compose_tc_fun({rtsp, Headers}) ->
  UA = proplists:get_value('User-Agent', Headers),
  case UA of
    <<"MPlayer", _/binary>> ->
      fun(DTS, _PTS, BaseRTP) -> ts_to_timecode(DTS, BaseRTP) end;
    <<"LibVLC", _/binary>> ->
      fun(_DTS, PTS, BaseRTP) -> ts_to_timecode(PTS, BaseRTP) end;
    _ ->
      fun(DTS, _PTS, BaseRTP) -> ts_to_timecode(DTS, BaseRTP) end
  end;
compose_tc_fun(_) ->
  fun(DTS, _PTS, BaseRTP) -> ts_to_timecode(DTS, BaseRTP) end.


%% This part of Sender Report is useless to me, however not to forget, I've added parsing
%% decode_sender_reports(0, <<_FractionLost, _Lost:24, _MaxSeq:32, _Jitter:32, _LSR:32, _DLSR:32>>) ->
%% decode_sender_reports(_, _) ->
%%   _Delay = _DLSR / 65.536,
%%   ?D({sr, FractionLost, Lost, MaxSeq, Jitter, LSR, DLSR, round(Delay)}),
%%   ok.


%%----------------------------------------------------------------------
%% @spec (receiver_report, RtpState) -> Data::binary()
%%
%% @doc Creates different RTCP packets
%%
%% http://webee.technion.ac.il/labs/comnet/netcourse/CIE/RFC/1889/20.htm
%%
%% or google:  RTCP Receiver Report
%% @end
%%----------------------------------------------------------------------

-define(RTP_SIZE, 1100).

encode(rtp, BaseRTP, Codec, Data) ->
  case Codec of
    pcm_le ->
      {NewBaseRTP, Packs} = compose_rtp(BaseRTP, l2b(Data), ?RTP_SIZE);
    mp3 ->
      Size = size(Data),
      %% Add support of frames with size more than 14 bit
      %% (set continuating flag, split to several RTP: http://tools.ietf.org/html/rfc5219#section-4.2)
      ADU =
        if Size < 16#40 ->                           % more than 6 bit
            <<0:1,0:1,Size:6>>;
           Size < 16#4000 ->
            <<0:1,1:1,Size:14>>;
           true ->
            ?DBG("Error: big frame", []),
            <<>>
        end,
      MP3 = <<ADU/binary, Data/binary>>,
      {NewBaseRTP, Packs} = compose_rtp(BaseRTP, MP3);
    %% mp3 ->
    %%   MPEG = <<0:16,0:16,Data/binary>>,
    %%   {NewBaseRTP, Packs} = compose_rtp(BaseRTP, MPEG);
    aac ->
      AH = 16#00,
      ASsize = 16#10,                           % TODO: size of > 16#ff
      DataSize = bit_size(Data),
      Size = <<DataSize:2/big-integer-unit:8>>,
      AS = <<ASsize:8, Size/binary>>,
      Header = <<AH:8,AS/binary>>,
      AAC = <<Header/binary,Data/binary>>,
      {NewBaseRTP, Packs} = compose_rtp(BaseRTP#base_rtp{marker = true}, AAC);
    speex ->
      SPEEX = <<Data/binary, 16#7f:8 >>,        % Padding?
      {NewBaseRTP, Packs} = compose_rtp(BaseRTP#base_rtp{marker = false}, SPEEX);
    h264 ->
      Fun =
        fun({config, [SPS, PPS]}, {BRtp, Accum}) ->
            {BR1, [Pack1]} = compose_rtp(BRtp, SPS),
            {BR2, [Pack2]} = compose_rtp(BR1#base_rtp{marker = false}, PPS),
            {BR2, [Pack2, Pack1 | Accum]};
           ({KF, Frame}, {BRtp, Accum}) when KF =:= frame;
                                           KF =:= keyframe ->
            {BaseRTP1, RevPacks} =
              lists:foldl(fun({M, F}, {BR, Acc}) ->
                              {NewBR, Ps} = compose_rtp(BR#base_rtp{marker = M}, F, 1387),
                              {NewBR, [Ps | Acc]}
                          end, {BRtp, Accum},
                          split_h264_frame(BaseRTP#base_rtp.framelens, Frame)),
            {BaseRTP1#base_rtp{marker = false}, RevPacks}
        end,
      if is_list(Data) ->
          {NewBaseRTP, RevPacks} = lists:foldl(Fun, {BaseRTP, []}, Data),
          Packs = lists:reverse(RevPacks);
         true ->
          {NewBaseRTP, RevPacks} = Fun(Data, {BaseRTP, []}),
          Packs = lists:reverse(RevPacks)
      end;
    mpeg4 ->
      {NewBaseRTP, Packs} = compose_rtp(BaseRTP, Data, 1388);
    _ ->
      {NewBaseRTP, Packs} = compose_rtp(BaseRTP, Data) % STUB
  end,
  {NewBaseRTP, Packs}.

split_h264_frame(FLS, Frame) ->
  split_h264_frame(FLS, Frame, []).

split_h264_frame(_FLS, <<>>, Acc) ->
  lists:reverse(Acc);
split_h264_frame(FLS, Frame, Acc) ->
  Len = (8*FLS),
  <<Size:Len, FrameRest/binary>> = Frame,
  <<D:Size/binary-unit:8, Rest/binary>> = FrameRest,
  M = (Rest =:= <<>>),
  split_h264_frame(FLS, Rest, [{M, D} | Acc]).


make_rtp_pack(#base_rtp{codec = PayloadType,
                        sequence = Sequence,
                        timecode = Timestamp,
                        stream_id = SSRC}, Marker, Payload) ->
  Version = 2,
  Padding = 0,
  Extension = 0,
  CSRC = 0,
  % ?D({rtp,Sequence,PayloadType,Timestamp}),
  <<Version:2, Padding:1, Extension:1, CSRC:4, Marker:1, PayloadType:7, Sequence:16, Timestamp:32, SSRC:32, Payload/binary>>.


%% Compose one RTP-packet from whole Data
compose_rtp(Base, Data) ->
  compose_rtp(Base, Data, undefined, [], undefined).

%% Compose number of RTP-packets from splitten Data to Size
compose_rtp(Base, Data, Size)
  when is_integer(Size) ->
  compose_rtp(Base, Data, Size, [], undefined).

compose_rtp(Base, <<>>, _, Acc, _) -> % Return new Sequence ID and list of RTP-binaries
  %%?DBG("New Sequence: ~p", [Sequence]),
  {Base#base_rtp{marker = false}, lists:reverse(Acc)};
compose_rtp(#base_rtp{sequence = Sequence, marker = _Marker,
                      packets = Packets, bytes = Bytes} = Base, Data, Size, Acc, Nal)
  when (is_integer(Size) andalso (size(Data) > Size)) ->
  <<P:Size/binary,Rest/binary>> = Data,
  Start = if Acc == [] -> 1; true -> 0 end,
  End = 0,
  {PFrag, NewNal} = fragment_nal(P, Nal, Start, End),
  M = 0,
  Pack = make_rtp_pack(Base, M, PFrag),
  compose_rtp(Base#base_rtp{sequence = inc_seq(Sequence),
                            packets = inc_packets(Packets, 1),
                            bytes = inc_bytes(Bytes, size(Pack))}, Rest, Size, [Pack | Acc], NewNal);
compose_rtp(#base_rtp{sequence = Sequence, marker = Marker,
                      packets = Packets, bytes = Bytes} = Base, Data, Size, Acc, Nal) ->
  if Marker -> M = 1; true -> M = 0 end,
  ResData =
    if ((Acc == []) or (Nal == undefined)) ->
        Data;
       true ->
        Start = 0, End = 1,
        {FN, _Nal} = fragment_nal(Data, Nal, Start, End),
        FN
    end,
  Pack = make_rtp_pack(Base, M, ResData),
  compose_rtp(Base#base_rtp{sequence = inc_seq(Sequence),
                            packets = inc_packets(Packets, 1),
                            bytes = inc_bytes(Bytes, size(Pack))}, <<>>, Size, [Pack | Acc], Nal).

fragment_nal(Data, Nal, S, E) ->
  if (S == 1) orelse (Nal == undefined) ->
      <<_:1, NRI:2, Type:5, Payload/binary>> = Data;
     true ->
      {NRI, Type} = Nal,
      Payload = Data
  end,
  FUInd = <<0:1, NRI:2, 28:5>>,
  R = 0,
  FUHeader = <<S:1, E:1, R:1, Type:5>>,
  PFrag = <<FUInd/binary, FUHeader/binary, Payload/binary>>,
  {PFrag, {NRI, Type}}.


init_rnd_seq() ->
  random:uniform(16#FFFE) + 1.

init_rnd_ssrc() ->
  random:uniform(16#FFFFFFFF).

init_rnd_timecode() ->
  Range = 1000000000,
  random:uniform(Range) + Range.

inc_seq(S) ->
  (S+1) band 16#FFFF.

inc_packets(S, V) ->
  (S+V) band 16#FFFFFFFF.

inc_bytes(S, V) ->
  (S+V) band 16#FFFFFFFF.


l2b(List) when is_list(List) ->
  [l2b(B) || B <- List];
l2b(Bin) when is_binary(Bin) ->
    l2b(Bin, []).

l2b(<<>>, Acc) ->
    iolist_to_binary(lists:reverse(Acc));
l2b(<<A:2/little-unit:8,Rest/binary>>, Acc) ->
    l2b(Rest, [<<A:2/big-unit:8>> | Acc]).


encode({receiver_report, LocalStreamId},
       #base_rtp{stream_id = StreamId,
                 sequence = Sequence,
                 last_sr = {MSW, LSW}, % Get offset from 1900
                 wall_clock = _WallClock} = State) ->
  Count = 1,
  FractionLost = 0,
  LostPackets = 0,
  MaxSeq =
    case Sequence of
      undefined -> 0;
      MS -> MS
    end,
  Jitter = 0,
  %%MSW = ((WallClock div 1000) + ?YEARS_70 + AddMSW) band 16#FFFFFFFF,
  %%LSW = ((WallClock rem 1000) + AddLSW)*1000*1000,
  ?D({rr, StreamId, MaxSeq, MSW, LSW}),

  Packet = <<StreamId:32, FractionLost:8, LostPackets:24, MaxSeq:32, Jitter:32, MSW:32, 0:32>>,
  Length = trunc(size(Packet)/4)+1,
  Header = <<2:2, 0:1, Count:5, ?RTCP_RR, Length:16>>,
  {State, <<Header/binary,LocalStreamId:32,Packet/binary>>};

encode(sender_report,
       #base_rtp{stream_id = StreamId,
                 media = _Type,
                 timecode = Timecode,
                 base_timecode = _BaseTimecode,
                 wall_clock = WallClock,
                 base_wall_clock = _BaseWallClock,
                 last_sr = {AddMSW, AddLSW}, % Get offset from 1900
                 packets = SPC,
                 bytes = SOC} = State) ->
  Count = 0,
  MSW = ((WallClock div 1000) + ?YEARS_70 + AddMSW) band 16#FFFFFFFF,
  LSW = ((WallClock rem 1000) + AddLSW)*1000*1000,
  %%?D({sr, StreamId,Timecode,WallClock,SPC,SOC}),
  Packet = <<StreamId:32, MSW:32, LSW:32, Timecode:32, SPC:32, SOC:32>>,
  Length = trunc(size(Packet)/4),
  Header = <<2:2, 0:1, Count:5, ?RTCP_SR, Length:16>>,
  {State, <<Header/binary,Packet/binary>>};

encode(source_description, #base_rtp{stream_id = StreamId} = State) ->

  Des = [
         {?SDES_CNAME, <<"localhost">>},
         {?SDES_TOOL, <<"Erlyvideo">>}
        ],

  SDES = lists:foldl(fun({Type, Value}, Acc) ->
                         <<Acc/binary, Type:8, (size(Value)):8, Value/binary>>
                     end, <<>>, Des),
  Packet = <<StreamId:32, SDES/binary>>,
  Count = 1,
  Length = trunc(size(Packet)/4)+1,
  Header = <<2:2, 0:1, Count:5, ?RTCP_SD, Length:16>>,
  {State, <<Header/binary,Packet/binary>>}.

get_date() ->
  {A1, A2, A3} = now(),
  {A1*1000000 + A2 + ?YEARS_70, A3 * 1000}.

do_audio_rtp({udp, _SAddr, _SPort, Data}, AudioDesc, Media, StreamId) ->
%%  ?DBG("Data From ~p:~p:~n~p", [SAddr, SPort, Data]),
  <<_Version:2, _Padding:1, _Extension:1, _CSRC:4, _Marker:1, _PayloadType:7,
    Sequence:16, Timestamp:32, SSRC:32, Payload/binary>> = Data,
%%  ?DBG("PayloadType: ~p, Sequence: ~p, Timestamp: ~p, SSRC: ~p, Payload:~n~p~nAudio:~n~p~nMedia: ~p",
%%       [PayloadType, Sequence, Timestamp, SSRC, Payload, AudioDesc, Media]),
  BaseRTP = AudioDesc#desc.state,
  NewBaseRTP =
    (if BaseRTP#base_rtp.base_timecode =/= undefined ->
         BaseRTP;
        true ->
         BaseRTP#base_rtp{base_timecode = Timestamp}
     end)#base_rtp{timecode = Timestamp,
                   stream_id = SSRC,
                   sequence = Sequence},
  DTS = timecode_to_ts(Timestamp, NewBaseRTP),
  AF = #video_frame{
    content = audio,
    dts     = DTS,
    pts     = DTS,
    body    = Payload,
    stream_id = StreamId,
    codec	  = speex,
    flavor  = frame,
    sound	  = {mono, bit16, rate44}
   },
  %%?DBG("AudioFrame:~n~p", [AF]),
  if is_pid(Media) ->
      Media ! AF;
     true -> pass
  end,
  NewBaseRTP#base_rtp{wall_clock = round(DTS)}.
