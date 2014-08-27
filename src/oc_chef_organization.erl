%% -*- erlang-indent-level: 4;indent-tabs-mode: nil; fill-column: 92 -*-
%% ex: ts=4 sw=4 et
%% @author Tyler Cloke <tyler@getchef.com>
%% Copyright 2014 Opscode, Inc. All Rights Reserved.

-module(oc_chef_organization).

-include("oc_chef_types.hrl").
-include_lib("mixer/include/mixer.hrl").
-include_lib("chef_objects/include/chef_types.hrl").

-behaviour(chef_object).

-export([
         authz_id/1,
         is_indexed/0,
         ejson_for_indexing/2,
         update_from_ejson/2,
         set_created/2,
         set_updated/2,
         create_query/0,
         update_query/0,
         delete_query/0,
         find_query/0,
         list_query/0,
         bulk_get_query/0,
         fields_for_update/1,
         fields_for_fetch/1,
         record_fields/0,
         list/2,
         new_record/3,
         name/1,
         id/1,
         org_id/1,
         type_name/1,
         assemble_organization_ejson/1,
         parse_binary_json/1
        ]).

-mixin([
        {chef_object, [{default_fetch/2, fetch},
                       {default_update/2, update}]}
       ]).

%% We don't have a class for 'organizations' on the client yet, but eventually we may want
%% to send a json_class Chef::ApiOrganization or the like.
%% Then we would amend DEFAULT_FIELD_VALUES and VALIDATION_CONSTRAINTS to include:
%% {<<"json_class">>, <<"Chef::Organization">>},
%% {<<"chef_type">>, <<"organization">>},
-define(DEFAULT_FIELD_VALUES, [ ]).

-define(VALIDATION_CONSTRAINTS,
        {[ {<<"name">>, {string_match, regex_for(org_name)}},
           {<<"full_name">>,  {string_match, regex_for(org_full_name) }}
         ]}).

-define(VALID_KEYS, [<<"name">>, <<"full_name">>]).



authz_id(#oc_chef_organization{authz_id = AuthzId}) ->
    AuthzId.

is_indexed() ->
    false.

ejson_for_indexing(#oc_chef_organization{}, _EjsonTerm) ->
   erlang:error(not_indexed).

update_from_ejson(#oc_chef_organization{} = Organization, OrganizationData) ->
    Name = ej:get({<<"name">>}, OrganizationData),
    FullName = ej:get({<<"fullname">>}, OrganizationData),
    Organization#oc_chef_organization{name = Name, full_name = FullName}.

set_created(#oc_chef_organization{} = Organization, ActorId) ->
    Now = chef_object_base:sql_date(now),
    Organization#oc_chef_organization{created_at = Now, updated_at = Now, last_updated_by = ActorId}.

set_updated(#oc_chef_organization{} = Organization, ActorId) ->
    Now = chef_object_base:sql_date(now),
    Organization#oc_chef_organization{updated_at = Now, last_updated_by = ActorId}.

create_query() ->
    insert_organization.

update_query() ->
    update_organization_by_id.

delete_query() ->
    delete_organization_by_id.

find_query() ->
    find_organization_by_id.

list_query() ->
    list_organizations.

%% Not implemented because we have no serialized json body
bulk_get_query() ->
    erlang:error(not_implemented).

fields_for_update(#oc_chef_organization{last_updated_by = LastUpdatedBy,
                                        updated_at = UpdatedAt,
                                        name = Name,
                                        full_name = FullName,
                                        id = Id}) ->
    [LastUpdatedBy, UpdatedAt, Name, FullName, Id].

fields_for_fetch(#oc_chef_organization{id = Id}) ->
    [Id].

record_fields() ->
    record_info(fields, oc_chef_organization).

list(#oc_chef_organization{}, CallbackFun) ->
    CallbackFun({list_query(), [], [name]}).

parse_binary_json(Bin) ->
    Org0 = chef_json:decode_body(Bin),
    Org = chef_object_base:set_default_values(Org0, ?DEFAULT_FIELD_VALUES),
    {ok, ValidOrg} = validate_org(Org), %% TODO need action specific version?
    ValidOrg.

validate_org(Org) ->
    case ej:valid(?VALIDATION_CONSTRAINTS, Org) of
        ok -> {ok, Org};
        Bad -> throw(Bad)
    end.

%%
%% Open question: We don't expose json_class and chef_type fields currently, and the client doesn't have objects for them.
%% Is it worth sending at least chef_type fields?
%%
assemble_organization_ejson(#oc_chef_organization{name = Name,
                                                  full_name = FullName}) ->
    Org = {[{<<"name">>, Name},
            {<<"full_name">>, FullName} ]},
    chef_object_base:set_default_values(Org, ?DEFAULT_FIELD_VALUES).

new_record(null, AuthzId, OrganizationData) ->
    % TODO: write id generator for org-less objects (see chef_object_base:make_org_prefix_id
    % and oc_chef_group:new_record for examples)
    Id = null,

    Name = ej:get({<<"name">>}, OrganizationData),
    FullName = ej:get({<<"full_name">>}, OrganizationData),
    AssignedAt = ej:get({<<"assigned_at">>}, OrganizationData),
    #oc_chef_organization{
       id = Id,
       authz_id = AuthzId,
       name = Name,
       full_name = FullName,
       assigned_at = AssignedAt
      }.

name(#oc_chef_organization{name = Name}) ->
    Name.

id(#oc_chef_organization{id = Id}) ->
    Id.

org_id(#oc_chef_organization{}) ->
    erlang:error(not_implemented).

type_name(#oc_chef_organization{}) ->
    organization.

%%
%% TODO: This was copy-pasta'd from chef_regex, reunite someday (see also oc_chef_container)
%%
%% The name regex should limit to some short length. Nginx default is 8k. (large_client_header_buffers)
%% but we probably for sanity's sake want something less. 255 seems reasonable, but we probably should dig deeper.
%% For reference, I've succesfully created orgs of 900+ character lengths in hosted, but failed with 1000.
%% Probably have to be able to handle api.opscode.us/<ORGNAME>/environments/default in 1k?)
-define(ORG_NAME_REGEX, "[[:lower:][:digit:]][[:lower:][:digit:]_-]{0,254}").
-define(FULL_NAME_REGEX, "\\S.{0,1022}"). %% Must start with nonspace.
-define(ANCHOR_REGEX(Regex), "^" ++ Regex ++ "$").

generate_regex(Pattern) ->
  {ok, Regex} = re:compile(Pattern),
  Regex.

generate_regex_msg_tuple(Pattern, Message) ->
  Regex = generate_regex(Pattern),
  {Regex, Message}.

regex_for(org_name) ->
    generate_regex_msg_tuple(?ANCHOR_REGEX(?ORG_NAME_REGEX),
                             <<"Malformed org name.  Must only contain A-Z, a-z, 0-9, _, or -">>);
regex_for(org_full_name) ->
    generate_regex_msg_tuple(?ANCHOR_REGEX(?FULL_NAME_REGEX),
                             <<"Malformed org full name.  Must only contain A-Z, a-z, 0-9, _, or -">>).
