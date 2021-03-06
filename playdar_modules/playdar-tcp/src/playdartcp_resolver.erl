-module(playdartcp_resolver).
-behaviour(gen_server).
-behaviour(playdar_reader).
-behaviour(playdar_resolver).
-include("playdar.hrl").

%% playdar_reader exports:
-export([reader_protocols/0]).

-export([start_link/0, resolve/2, weight/1, targettime/1, name/1, localonly/1]).

-export([playdartcp_reader/3, reader_start_link/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, 
		 terminate/2, code_change/3]).

-record(state, {seenqids}).

start_link()            -> gen_server:start_link({local,?MODULE},?MODULE,[],[]).

resolve(_Pid, Qry)      -> gen_server:cast(playdartcp_router, {resolve, Qry}).
weight(_Pid)            -> 60.
targettime(_Pid)        -> 1000.
name(_Pid)              -> "playdartcp".
localonly(_Pid) 		-> false.

reader_start_link(A, Pid, Ref) -> spawn_link( ?MODULE, playdartcp_reader, [A, Pid, Ref]). 

%% ====================================================================
%% Server functions
%% ====================================================================
reader_protocols() ->
    [ {"playdartcp", {?MODULE, reader_start_link}} ].

init([]) ->
    {ok,_} = playdartcp_router:start_link(?CONFVAL({playdartcp,port},60211)),
    % Connect to any peers listed in the config file
	% the connect call will timeout+crash if connection fails
    lists:foreach(fun({Ip,Port})->
						  spawn(fun()->playdartcp_router:connect(Ip,Port)end)
				  end, ?CONFVAL({playdartcp,peers},[])),
    % Register us as a playdar resolver
    playdar_resolver:add_resolver(?MODULE, self()),
    % Register our web request handler (for our localhost web gui)
    playdar_http_registry:register_handler("playdartcp", fun playdartcp_web:http_req/2, "playdartcp Connection Status Page", "/playdartcp"),
	% register our ctl cmd:
	playdar_ctl:register_command("peers", "List current playdartcp connections",
							 fun peers/1),
    {ok, #state{ seenqids=ets:new(seenqids,[]) }}.

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

handle_cast(_Msg, State) -> {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% --------------------------------------------------------------------
%%% Internal functions
%% --------------------------------------------------------------------

playdartcp_reader({struct, A}, Pid, Ref) ->
	"playdartcp://"++Rest = binary_to_list(proplists:get_value(<<"url">>, A)),
	[Sid, Name] = string:tokens(Rest, "\t"),
	?LOG(info, "Requesting playdartcp stream for '~p' from '~p'", [Sid, Name]),
	%TODO name2pid
	case lists:keysearch(Name, 1, playdartcp_router:peers()) of
		{value, {Name, P, _Sharing}} ->
			playdartcp_conn:request_sid(P, list_to_binary(Sid), Pid, Ref);
		false ->
			Pid ! {Ref, error, wtf}
	end.
	
	
%% playdar_ctl stuff

peers([]) ->
	Peers = playdartcp_router:peers(),
	lists:foreach(fun({Name, Pid, {WeShare, TheyShare}})->
						  io:format("~20.s  ~p  ~p / ~p~n",
									[Name, Pid, WeShare, TheyShare])
				  end, Peers),
	?OK.

