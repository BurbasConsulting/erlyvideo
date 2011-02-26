%%% @author     Max Lapshin <max@maxidoors.ru> [http://erlyvideo.org]
%%% @copyright  2009-2010 Max Lapshin
%%% @doc        Client of erlyvideo license server
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
-module(ems_license_client).
-author('Max Lapshin <max@maxidoors.ru>').
-behaviour(gen_server).

-include_lib("kernel/include/file.hrl").
-include("log.hrl").

-define(TIMEOUT, 20*60000).
-define(LICENSE_TABLE, license_storage).

%% External API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([ping/0, ping/1, applications/0, restore/0]).
-export([writeable_cache_dir/0]).


-record(client, {
  license,
  timeout,
  key,
  storage_opened = false,
  memory_applications = []
}).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).


ping() ->
  ?MODULE ! ping,
  ok.
  
ping([sync]) ->
  gen_server:call(?MODULE, ping, 60000).
  
applications() ->
  gen_server:call(?MODULE, applications).

restore() ->
  gen_server:call(?MODULE, restore).

%%%------------------------------------------------------------------------
%%% Callback functions from gen_server
%%%------------------------------------------------------------------------

%%----------------------------------------------------------------------
%% @spec (Port::integer()) -> {ok, State}           |
%%                            {ok, State, Timeout}  |
%%                            ignore                |
%%                            {stop, Reason}
%%
%% @doc Called by gen_server framework at process startup.
%%      Create listening socket.
%% @end
%%----------------------------------------------------------------------


init([]) ->
  State = #client{timeout = ?TIMEOUT},
  State1 = case open_license_storage() of
    {error, Reason} ->
      ems_log:error(license_client, "License client couldn't open license_storage: ~p", [Reason]),
      State;
    {ok, license_storage} ->
      dets:insert_new(?LICENSE_TABLE, {saved_apps, []}),
      State#client{storage_opened = true}
  end,
  {ok, State1}.

%%-------------------------------------------------------------------------
%% @spec (Request, From, State) -> {reply, Reply, State}          |
%%                                 {reply, Reply, State, Timeout} |
%%                                 {noreply, State}               |
%%                                 {noreply, State, Timeout}      |
%%                                 {stop, Reason, Reply, State}   |
%%                                 {stop, Reason, State}
%% @doc Callback for synchronous server calls.  If `{stop, ...}' tuple
%%      is returned, the server is stopped and `terminate/2' is called.
%% @end
%% @private
%%-------------------------------------------------------------------------
handle_call(ping, _From, State) ->
  State1 = make_request_internal(State),
  {reply, ok, State1};

handle_call(applications, _From, #client{memory_applications = Mem, storage_opened = false} = State) ->
  {reply, Mem, State};

handle_call(restore, _From, #client{storage_opened = false} = State) ->
  {reply, {error, no_storage}, State};
  
handle_call(restore, _From, #client{storage_opened = true} = State) ->
  {reply, {ok, restore_license_code()}, State};

handle_call(Request, _From, State) ->
  {stop, {unknown_call, Request}, State}.


%%-------------------------------------------------------------------------
%% @spec (Msg, State) ->{noreply, State}          |
%%                      {noreply, State, Timeout} |
%%                      {stop, Reason, State}
%% @doc Callback for asyncrous server calls.  If `{stop, ...}' tuple
%%      is returned, the server is stopped and `terminate/2' is called.
%% @end
%% @private
%%-------------------------------------------------------------------------
handle_cast(_Msg, State) ->
  {stop, {unknown_cast, _Msg}, State}.

%%-------------------------------------------------------------------------
%% @spec (Msg, State) ->{noreply, State}          |
%%                      {noreply, State, Timeout} |
%%                      {stop, Reason, State}
%% @doc Callback for messages sent directly to server's mailbox.
%%      If `{stop, ...}' tuple is returned, the server is stopped and
%%      `terminate/2' is called.
%% @end
%% @private
%%-------------------------------------------------------------------------
handle_info(ping, State) ->
  State1 = make_request_internal(State),
  {noreply, State1};

handle_info(_Info, State) ->
  {stop, {unknown_info, _Info}, State}.

%%-------------------------------------------------------------------------
%% @spec (Reason, State) -> any
%% @doc  Callback executed on server shutdown. It is only invoked if
%%       `process_flag(trap_exit, true)' is set by the server process.
%%       The return value is ignored.
%% @end
%% @private
%%-------------------------------------------------------------------------
terminate(_Reason, _State) ->
  ok.

%%-------------------------------------------------------------------------
%% @spec (OldVsn, State, Extra) -> {ok, NewState}
%% @doc  Convert process state when code is changed.
%% @end
%% @private
%%-------------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.





%%%%%%%%%%%%%%%%%%% Make license request logic
make_request_internal(#client{license = OldLicense, timeout = OldTimeout} = State) ->
  {License, Timeout} = case read_license() of
    {OldLicense, _} -> {OldLicense,OldTimeout};
    undefined -> {undefined,OldTimeout};
    {Env, LicensePath} ->
      error_logger:info_msg("Reading license key from ~s", [LicensePath]),
      {Env,proplists:get_value(timeout,Env,OldTimeout)}
  end,
  request_licensed(License, State),
  State#client{license = License, timeout = Timeout}.


read_license() ->
  case file:path_consult(["priv", "/etc/erlyvideo"], "license.txt") of
    {ok, Env, LicensePath} ->
      {Env,LicensePath};
    {error, enoent} ->
      undefined;
    {error, Reason} ->
      error_logger:error_msg("Invalid license key: ~p", [Reason]),
      undefined
  end.

request_licensed(undefined, _State) ->
  ok;
  
request_licensed(Env, State) ->
  case proplists:get_value(license, Env) of
    undefined -> ok;
    License ->
      LicenseUrl = proplists:get_value(url, Env, "http://license.erlyvideo.org/license"),
      request_code_from_server(LicenseUrl, License, State)
  end.
  
request_code_from_server(LicenseUrl, License, State) ->
  Command = "save",
  URL = lists:flatten(io_lib:format("~s?key=~s&command=~s", [LicenseUrl, License, Command])),
  case ibrowse:send_req(URL,[],get,[],[{response_format,binary}]) of
    {ok, "200", _ResponseHeaders, Bin} ->
      read_license_response(Bin, State#client{key = License});
    _Else ->
      ?D({license_error, _Else}),
      _Else
  end.    
  
read_license_response(Bin, State) ->
  case erlang:binary_to_term(Bin) of
    {reply, Reply} ->
      case proplists:get_value(version, Reply) of
        1 ->
          Commands = proplists:get_value(commands, Reply),
          Startup = execute_commands_v1(Commands, [], State),
          handle_loaded_modules_v1(lists:reverse(Startup));
        Version ->
          {error,{unknown_license_version, Version}}
      end;
    {error, Reason} ->
      error_logger:error_msg("Couldn't load license key ~p: ~p~n", [State#client.key, Reason]),
      {error, Reason}
  end.
  
execute_commands_v1([], Startup, _State) -> 
  Startup;

execute_commands_v1([{purge,Module}|Commands], Startup, State) ->
  case erlang:function_exported(Module, ems_client_unload, 0) of
    true -> (catch Module:ems_client_unload());
    false -> ok
  end,
  
  case code:is_loaded(Module) of
    true -> error_logger:info_msg("Licence purge ~p", [Module]), code:purge(Module);
    false -> ok
  end,
  execute_commands_v1(Commands, Startup, State);

execute_commands_v1([{save,_Info}|Commands], Startup, #client{storage_opened = false} = State) ->
  execute_commands_v1(Commands, Startup, State);
  

execute_commands_v1([{save,Info}|Commands], Startup, #client{storage_opened = true} = State) ->
  File = proplists:get_value(file, Info),
  Path = proplists:get_value(path, Info),
  case writeable_cache_dir() of
    undefined -> ok;
    CacheDir -> 
      FullPath = ems:pathjoin(CacheDir, Path),
      code:add_patha(filename:dirname(FullPath)),
      case file:read_file(FullPath) of
        {ok, File} -> ok;
        _ ->
          filelib:ensure_dir(FullPath),
          file:write_file(FullPath, File),
          error_logger:info_msg("License file ~p", [Path])
      end
  end,
  execute_commands_v1(Commands, Startup, State);

execute_commands_v1([{save_app, {application,Name,Desc} = AppDescr}|Commands], Startup, #client{storage_opened = CanSave} = State) ->
  Version = proplists:get_value(vsn, Desc),
  case application:load(AppDescr) of
    ok when CanSave == true ->
      save_application(Name,Desc),
      error_logger:info_msg("License save application ~p(~s)", [Name, Version]);
    ok when CanSave == false ->
      error_logger:info_msg("License only load application ~p(~s)", [Name, Version]);
    _ -> ok
  end,
  execute_commands_v1(Commands, Startup, State);
  
execute_commands_v1([{load_app, {application,Name,_Desc} = AppDescr}|Commands], Startup, State) ->
  case application:load(AppDescr) of
    ok -> error_logger:info_msg("License load application ~p", [Name]);
    _ -> ok
  end,
  execute_commands_v1(Commands, Startup, State);
  
  
execute_commands_v1([{load,ModInfo}|Commands], Startup, State) ->
  Code = proplists:get_value(code, ModInfo),
  {ok, {Module, [Version]}} = beam_lib:version(Code),
  case is_new_version(ModInfo) of
    false -> 
      execute_commands_v1(Commands, Startup, State);
    true -> 
      error_logger:info_msg("Licence load ~p(~p)", [Module, Version]),
      code:soft_purge(Module),
      code:load_binary(Module, "license/"++atom_to_list(Module)++".erl", Code),
      execute_commands_v1(Commands, [Module|Startup], State)
  end;
  
execute_commands_v1([_Command|Commands], Startup, State) ->
  error_logger:error_msg("Unknown license server command"),
  execute_commands_v1(Commands, Startup, State).


is_new_version(ModInfo) ->
  Code = proplists:get_value(code, ModInfo),
  {ok, {Module, NewVersion}} = beam_lib:version(Code),
  OldVersion = case code:is_loaded(Module) of
    false -> undefined;
    _ -> proplists:get_value(vsn, Module:module_info(attributes))
  end,
  OldVersion =/= NewVersion.

  
handle_loaded_modules_v1([]) ->
  ok;
  
handle_loaded_modules_v1([Module|Startup]) ->
  case erlang:function_exported(Module, ems_client_load, 0) of
    true -> Module:ems_client_load();
    false -> ok
  end,
  handle_loaded_modules_v1(Startup).

  
save_application(AppName, Desc) ->
  Version = proplists:get_value(vsn, Desc),
  case need_to_update_application(AppName, Version) of
    true -> save_or_update_application(AppName, Desc);
    false -> ok
  end.


need_to_update_application(AppName, Version) ->
  case saved_application(AppName) of
    undefined -> true;
    Desc ->
      case proplists:get_value(vsn, Desc) of
        Version -> false;
        _ -> true
      end
  end.
    
    
save_or_update_application(AppName, Desc) ->
  error_logger:info_msg("Saving license application ~p~n", [AppName]),
  SavedApps = saved_applications(),
  Modules = lists:foldl(fun
    (_Name, undefined) -> undefined;
    (Name, Modules_) ->
      case code:get_object_code(Name) of
        {Name,Bin,_Path} -> [{{mod,Name},Bin}|Modules_];
        _ -> undefined
      end
  end, [], proplists:get_value(modules, Desc)),
  case Modules of
    undefined -> ok;
    _ ->
      NewApps = lists:usort([AppName|SavedApps]),
      dets:insert(license_storage, [{saved_apps,NewApps},{{app,AppName},Desc}|Modules])
  end,
  ok.


writeable_cache_dir() ->
  case ems:get_var(license_cache_dir, undefined) of
    undefined -> undefined;
    Path -> 
      filelib:ensure_dir(Path),
      case file:read_file_info(Path) of
        {ok, #file_info{access = write}} -> Path;
        {ok, #file_info{access = read_write}} -> Path;
        _ -> undefined
      end
  end.


open_license_storage() ->
  case writeable_cache_dir() of
    undefined -> {error, no_cache_dir};
    StorageDir ->
      case dets:open_file(?LICENSE_TABLE, [{file,ems:pathjoin(StorageDir,"license_storage.db")}]) of
        {ok, ?LICENSE_TABLE} -> {ok, ?LICENSE_TABLE};
        {error, Reason} -> {error, Reason} 
      end
  end.
  
  
saved_applications() ->
  [{saved_apps,SavedApps}] = dets:lookup(?LICENSE_TABLE, saved_apps),
  SavedApps.
  
saved_application(AppName) ->
  case dets:lookup(?LICENSE_TABLE, {app,AppName}) of
    [] -> undefined;
    [{{app,AppName},Desc}] -> Desc
  end.

saved_module(Module) ->
  case dets:lookup(?LICENSE_TABLE, {mod,Module}) of
    [] -> undefined;
    [{{mod,Module},Code}] -> Code
  end.

restore_license_code() ->
  SavedApps = saved_applications(),
  restore_saved_applications(SavedApps),
  SavedApps.


restore_saved_applications([]) -> 
  ok;
  
restore_saved_applications([App|SavedApps]) -> 
  case saved_application(App) of
    undefined -> 
      restore_saved_applications(SavedApps);
    Desc ->
      Modules = proplists:get_value(modules, Desc),
      load_saved_modules(Modules),
      application:load(Desc),
      application:start(App),
      restore_saved_applications(SavedApps)
  end.
  
  
load_saved_modules([]) ->
  ok;
  
load_saved_modules([Module|Modules]) ->
  case saved_module(Module) of
    undefined -> load_saved_modules(Modules);
    Code ->
      {ok, {Module, [Version]}} = beam_lib:version(Code),
      error_logger:info_msg("Licence restore ~p(~p)", [Module, Version]),
      code:soft_purge(Module),
      code:load_binary(Module, "license/"++atom_to_list(Module)++".erl", Code),
      load_saved_modules(Modules)
  end.
      