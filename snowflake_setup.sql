create warehouse rpcn;
create role rpcn;
grant usage on warehouse rpcn to role rpcn;
grant operate on warehouse rpcn to role rpcn;
create database rpcn;
create schema rpcn;
grant ownership on database rpcn to role rpcn;
grant ownership on schema rpcn.rpcn to role rpcn;

create user rpcn password='$n0w4L@k3' login_name='rpcn' must_change_password=FALSE
  , disabled=false
  , default_warehouse='rpcn'
  , default_namespace='rpcn.rpcn'
  , default_role='rpcn';

grant role rpcn to user rpcn;
-- grant role rpcn to user <your username>;  is this necessary?

-- create table for streaming
USE ROLE rpcn;
CREATE OR REPLACE TABLE vehicle_telemetry
 (MSGID varchar(255),
  VEHICLE_ID varchar(255),
  LATITUDE float,
  LONGITUDE float,
  SPEED number,
  AIRBAG number,
  low_tire_pressure_alert number,
  tail_light_alert number,
  event_datetime datetime);
