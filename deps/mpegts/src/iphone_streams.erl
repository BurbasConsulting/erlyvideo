%%% @author     Max Lapshin <max@maxidoors.ru> [http://erlyvideo.org]
%%% @copyright  2009 Max Lapshin
%%% @doc        One iphone stream. It is statefull and has life timeout
%%% @reference  See <a href="http://erlyvideo.org/" target="_top">http://erlyvideo.org/</a> for more information
%%% @end
%%%
%%% This file is part of erlyvideo.
%%% 
%%% erlyvideo is free software: you can redistribute it and/or modify
%%% it under the terms of the GNU General Public License as published by
%%% the Free Software Foundation, either version 3 of the License, or
%%% (at your option) any later version.
%%%
%%% erlyvideo is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%% GNU General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with erlyvideo.  If not, see <http://www.gnu.org/licenses/>.
%%%
%%%---------------------------------------------------------------------------------------
-module(iphone_streams).
-author('Max Lapshin <max@maxidoors.ru>').
-include_lib("erlmedia/include/video_frame.hrl").
-include("log.hrl").

-define(STREAM_TIME, ems:get_var(iphone_segment_size, 10000)).

%% External API
-export([start_link/1, find/3, segments/2, play/4, playlist/2, playlist/3]).

-export([save_counters/4, get_counters/3]).





start_link(Options) ->
  gen_cache:start_link([{local, ?MODULE}|Options]).


%%--------------------------------------------------------------------
%% @spec (Host, Name, Number) -> {ok,Pid}
%%
%% @doc Starting new iphone segment
%% @end
%%----------------------------------------------------------------------
find(Host, Name, Number) ->
  {Start, Count, _, Type} = segments(Host, Name),
  Options = case {Start + Count - 1,Type} of
    {Number,file} -> [{client_buffer,?STREAM_TIME*2}]; % Last segment of file doesn't require any end limit
    % {Number,_} -> [{client_buffer,0}]; % Only for last segment of stream timeshift we disable length and buffer
    _ -> [{client_buffer,?STREAM_TIME*2},{duration, ?STREAM_TIME}]
  end,
  if
    Number < Start ->
      {notfound, io_lib:format("Too small segment number: ~p/~p", [Number, Start])};
    Number >= Start + Count -> 
      {notfound, io_lib:format("Too large segment number: ~p/~p", [Number, Start+Count])};
    true ->
      {ok, _Pid} = media_provider:play(Host, Name, [{consumer,self()},{start, Number * ?STREAM_TIME}|Options])
  end.


playlist(Host, Name) ->
  playlist(Host, Name, []).

playlist(Host, Name, Options) ->
  {Start,Count,SegmentLength,Type} = segments(Host, Name),
  {ok, Media} = media_provider:open(Host, Name),
  Generator = proplists:get_value(generator, Options, fun(Duration, StreamName, Number) ->
    io_lib:format("#EXTINF:~p,~n/iphone/segments/~s/~p.ts~n", [Duration, StreamName, Number])
  end),
  
  SegmentListDirty = lists:map(fun(N) ->
    segment_info(Media, Name, N, Count, Generator)
  end, lists:seq(Start, Start + Count - 1)),
  SegmentList = lists:filter(fun(undefined) -> false;
                                (_) -> true end, SegmentListDirty),
  EndList = case Type of
    file -> "#EXT-X-ENDLIST\n";
    _ -> ""
  end,
  [
    "#EXTM3U\n",
    io_lib:format("#EXT-X-MEDIA-SEQUENCE:~p~n#EXT-X-TARGETDURATION:~p~n", [Start, round(SegmentLength)]),
    "#EXT-X-ALLOW-CACHE:YES\n",
    SegmentList,
    EndList
  ].


segment_info(Media, Name, Number, Count, Generator) when Count == Number + 1 ->
  {_Key, StartDTS} = ems_media:seek_info(Media, Number * ?STREAM_TIME),
  Info = ems_media:info(Media),
  Duration = proplists:get_value(length, Info, ?STREAM_TIME*Count),
  ?D({"Last segment", Number, StartDTS, Duration}),
  Generator(round((Duration - StartDTS)/1000), Name, Number);
  

segment_info(_MediaEntry, Name, Number, _Count, Generator) ->
  % case {PlayingFrom, PlayEnd} of
  %   {PlayingFrom, PlayEnd} when is_number(PlayingFrom) andalso is_number(PlayEnd) -> 
  %     SegmentLength = round((PlayEnd - PlayingFrom)/1000),
  %     io_lib:format("#EXTINF:~p,~n/iphone/segments/~s/~p.ts~n", [SegmentLength, Name, Number]);
  %   _Else -> 
  %     undefined
  % end.
  Generator(?STREAM_TIME div 1000, Name, Number).
  

segments(Host, Name) ->
  Info = media_provider:info(Host, Name),
  Type = proplists:get_value(type, Info),
  
  case Type of
    file ->
      file_segments(Info);
    _ ->
      timeshift_segments(Info)
  end.
  
file_segments(Info) ->
  Duration = proplists:get_value(length, Info, 0),
  Start = trunc(proplists:get_value(start, Info, 0) / ?STREAM_TIME),
  SegmentLength = ?STREAM_TIME div 1000,
  DurationLimit = 2*?STREAM_TIME,
  Count = if 
    Duration > DurationLimit -> round(Duration/?STREAM_TIME);
    true -> 1
  end,
  {Start,Count,SegmentLength,file}.


timeshift_segments(Info) ->
  Duration = proplists:get_value(length, Info, 0),
  StartTime = proplists:get_value(start, Info, 0),
  Start = trunc(StartTime / ?STREAM_TIME) + 1,
  SegmentLength = ?STREAM_TIME div 1000,
  DurationLimit = 5*?STREAM_TIME,
  Count = if
    Duration < DurationLimit -> 0;
    true -> trunc((Duration + StartTime)/?STREAM_TIME) - Start
  end,
  {Start,Count,SegmentLength,stream}.
  

play(Host, Name, Number, Req) ->
  case iphone_streams:find(Host, Name, Number) of
    {ok, PlayerPid} ->
      MS1 = erlang:now(),
      Counters = iphone_streams:get_counters(Host, Name, Number),
      MS2 = erlang:now(),
      NextCounters = mpegts_play:play(Name, PlayerPid, Req, [{buffered, true}], Counters),
      MS3 = erlang:now(),
      iphone_streams:save_counters(Host, Name, Number+1, NextCounters),
      MS4 = erlang:now(),
      ?D({end_iphone_segment, Name, Number, time, timer:now_diff(MS2,MS1) div 1000, timer:now_diff(MS3,MS2) div 1000, timer:now_diff(MS4,MS3) div 1000}),
      ok;
    {notfound, Reason} ->
      Req:respond(404, [{"Content-Type", "text/plain"}], "404 Page not found.\n ~p: ~s ~s\n", [Name, Host, Reason]);
    Reason ->
      Req:respond(500, [{"Content-Type", "text/plain"}], "500 Internal Server Error.~n Failed to start video player: ~p~n ~p", [Reason, Name])
  end.
  
  
  
save_counters(Host, Name, Number, Counters) ->
  gen_cache:set(?MODULE, {Host, Name, Number}, Counters).

get_counters(Host, Name, Number) ->
  gen_cache:get(?MODULE, {Host, Name, Number}, {0,0,0,0}).

