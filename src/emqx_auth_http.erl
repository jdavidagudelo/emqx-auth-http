%% Copyright (c) 2013-2019 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(emqx_auth_http).

-include("emqx_auth_http.hrl").

-include_lib("emqx/include/emqx.hrl").
-include_lib("emqx/include/logger.hrl").

-import(emqx_auth_http_cli,
        [ request/3
        , feedvar/2
        , feedvar/3
        ]).

%% Callbacks
-export([ check/2
        , description/0
        ]).

-define(UNDEFINED(S), (S =:= undefined orelse S =:= <<>>)).

check(Credentials = #{username := Username, password := Password}, _Config)
  when ?UNDEFINED(Username) ->
    {ok, Credentials#{auth_result => bad_username_or_password}};

check(Credentials = #{password := Password},
      #{auth_req := #http_request{method = Method, url = Url, params = Params},
        super_req := SuperReq}) ->
    Params1 = feedvar(feedvar(Params, Credentials), "%P", Password),
    case request(Method, Url, Params1) of
        {ok, 200, "ignore"} -> ok;
        {ok, 200, Body}  -> {stop, Credentials#{is_superuser => is_superuser(SuperReq, Credentials),
                                                 auth_result => success,
                                                 mountpoint  => mountpoint(Body, Credentials)}};
        {ok, Code, _Body} -> {stop, Credentials#{auth_result => Code}};
        {error, Error}    -> ?LOG(error, "[Auth http] check_auth Url: ~p Error: ~p", [Url, Error]),
                             {stop, Credentials#{auth_result => Error}}
    end.

description() -> "Authentication by HTTP API".

%%--------------------------------------------------------------------
%% Is Superuser
%%--------------------------------------------------------------------

-spec(is_superuser(undefined | #http_request{}, emqx_types:credetials()) -> boolean()).
is_superuser(undefined, _Credetials) ->
    false;
is_superuser(#http_request{method = Method, url = Url, params = Params}, Credetials) ->
    case request(Method, Url, feedvar(Params, Credetials)) of
        {ok, 200, _Body}   -> true;
        {ok, _Code, _Body} -> false;
        {error, Error}     -> logger:error("HTTP ~s Error: ~p", [Url, Error]),
                              false
    end.

mountpoint(Body, Credetials) when is_list(Body) ->
    mountpoint(list_to_binary(Body), Credetials);

mountpoint(Body, #{mountpoint := Mountpoint}) ->
    case emqx_json:safe_decode(Body, [return_maps]) of
        {error, _} -> Mountpoint;
        {ok, Json} when is_map(Json) ->
            maps:get(<<"mountpoint">>, Json, Mountpoint);
        {ok, _NotMap} ->
            Mountpoint
    end.

