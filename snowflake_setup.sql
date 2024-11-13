create warehouse rpcn;
create role rpcn;
grant usage on warehouse ingest to role rpcn;
grant operate on warehouse ingest to role rpcn;
create database rpcn;
create schema rpcn;
grant ownership on database rpcn to role rpcn;
grant ownership on schema rpcn.rpcn to role rpcn;

create user ingest password='temp' login_name ='rpcn' must_change_password=FALSE
  , disabled=false
  , default_warehouse='rpcn'
  , default_namespace='rpcn.rpcn'
  , default_role='rpcn';

grant role rpcn to user rpcn;
grant role rpcn to user <your username>;
