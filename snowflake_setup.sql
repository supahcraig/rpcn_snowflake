create warehouse rpcn;
create role rpcn;
grant usage on warehouse rpcn to role rpcn;
grant operate on warehouse rpcn to role rpcn;
create database rpcn;
create schema rpcn;
grant ownership on database rpcn to role rpcn;
grant ownership on schema rpcn.rpcn to role rpcn;

create user rpcn password='temp' login_name='rpcn' must_change_password=FALSE
  , disabled=false
  , default_warehouse='rpcn'
  , default_namespace='rpcn.rpcn'
  , default_role='rpcn';

grant role rpcn to user rpcn;
grant role rpcn to user <your username>;

-- create table for streaming
USE ROLE rpcn;
CREATE OR REPLACE TABLE vehicle_telemetry
(TXID varchar(255),
 RFID varchar(255),
 RESORT varchar(255),
 PURCHASE_TIME datetime,
 EXPIRATION_DATE date,
 DAYS number,
 NAME varchar(255),
 ADDRESS variant,
 PHONE varchar(255),
 EMAIL varchar(255),
 EMERGENCY_CONTACT variant);