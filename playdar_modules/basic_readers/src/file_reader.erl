-module(file_reader).
-behaviour(playdar_reader).
-include("playdar.hrl").
-include_lib("kernel/include/file.hrl").

-export([start_link/5, start_link/3, reader_protocols/0]).

start_link(A, Pid, Ref) ->
    spawn_link(fun()->run(A,Pid,Ref)end).

reader_protocols() ->
    [ {"file", {?MODULE, start_link}} ].

start_link(A, Start, Len, Pid, Ref) ->
    spawn_link(fun()->run(A,Start,Len,Pid,Ref)end).


% starts sending file data to Pid
run({struct, A}, Pid, Ref) ->
    "file://"++Path = binary_to_list(proplists:get_value(<<"url">>, A)),
    ?LOG(info, "Requesting ~p", [Path]),
    case file:open(Path, [read, binary]) of
        {ok, Io} ->
            Mimetype=proplists:get_value(<<"mimetype">>, A, <<"binary/unknown">>),
            {ok, FileInfo} = file:read_file_info(Path),
            Headers = [ {"content-type", binary_to_list(Mimetype)},
                        {"content-length", FileInfo#file_info.size}
                      ],
            Pid ! {Ref, headers, Headers},
            start_streaming(Io, Pid, Ref),
            file:close(Io),
            ok;
        _ ->
            % error opening file
            ?LOG(warning, "Error opening file ~s", [Path]),
            Pid ! {Ref, error, could_not_open_file},
            error
    end.
    
start_streaming(Io, Pid, Ref) ->
    case file:read(Io, 8192) of
        {ok, Data} ->
            Pid ! {Ref, data, Data},
            start_streaming(Io, Pid, Ref);
            
        {error, Reason} ->
            Pid ! {Ref, error, Reason};
        
        eof ->
            Pid ! {Ref, eof}
            
    end.

% starts sending file data to Pid
run({struct, A}, Begin, Len, Pid, Ref) ->
    "file://"++Path = binary_to_list(proplists:get_value(<<"url">>, A)),
    ?LOG(info, "Requesting ~p", [Path]),
    case file:open(Path, [read, binary]) of
        {ok, Io} ->
            Mimetype=proplists:get_value(<<"mimetype">>, A, <<"binary/unknown">>),
            {ok, FileInfo} = file:read_file_info(Path),
            Headers = [ {"content-type", binary_to_list(Mimetype)},
                        {"content-length", FileInfo#file_info.size}
                      ],
            Pid ! {Ref, headers, Headers},
            file:position(Io, Begin),
            start_streaming_limited(Io, Len, Pid, Ref),
            file:close(Io),
            ok;
        _ ->
            % error opening file
            ?LOG(warning, "Error opening file ~s", [Path]),
            Pid ! {Ref, error, could_not_open_file},
            error
    end.
    
start_streaming_limited(_Io, 0, Pid, Ref) ->
    Pid ! {Ref, eof};
start_streaming_limited(Io, Len, Pid, Ref) ->
    ReadBytes = if
        8192 < Len ->
            8192;
        true ->
            Len
    end,
    case file:read(Io, ReadBytes) of
        {ok, Data} ->
            Pid ! {Ref, data, Data},
            start_streaming_limited(Io, Len - size(Data), Pid, Ref);
            
        {error, Reason} ->
            Pid ! {Ref, error, Reason};
        
        eof ->
            Pid ! {Ref, eof}
            
    end.

