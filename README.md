# rpcn_snowflake
Streaming sample data via http endpoint through Redpanda and into Snowflake using Redpanda Connect


TODO:

redpanda docker compose

fake data gen to http

rpcn http server input to RP


rpcn RP to Snowflake


## Requirements

You'll need a Snoflake account (the basic trial account will work perfectly).  You'll also need Python 3.11 or greater, as well as redpanda-connect 4.39.0 or greater.  Lastly you'll optionally need to be able to deploy a Docker container to deploy Redpanda if you don't have access to Redpanda cloud or similar.


## Database setup


### Keypair authentication setup

You'll need to create a keypair to allow Redpanda Connect to authenticate with Snowflake.  This block will create those keys and produce an `ALTER USER` statement which will attach your public key your Snowflake user.

```bash
openssl genrsa 4096 | openssl pkcs8 -topk8 -inform PEM -out snowflake_private_key.p8 -nocrypt
openssl rsa -in snowflake_private_key.p8 -pubout -out snowflake_public_key.pub
PUBK=`cat ./snowflake_public_key.pub | grep -v KEY- | tr -d '\012'`
echo "ALTER USER rpcn SET RSA_PUBLIC_KEY='$PUBK';"
```

Run the genrerated `ALTER USER` statment in Snowflake to attach the public key to your `rpcn` user.


## Set up your .env


From your local working directory, create a file called `.env`

```
SNOWFLAKE_ACCOUNT=<Snowflake Account Here>
SNOWFLAKE_USER=rpcn
PRIVATE_KEY_FILE=/path/to/your/private/key/file.p8
```

Your Snowflake Account can be found within Snowflake, perhaps most easily by running this query:

```sql
select current_organization_name() || '-' || current_account_name();
```

## Redpanda Setup

You will need a Redpanda cluster (a single node cluster via Docker is fine, but BYOC or Serverless work work just as well)


Once you have your Redpanda cluster up and running, you'll want to add the broker addresses to your `.env` file.

```bash
echo "REDPANDA_BROKER_ADDRESSES=[ broker.1:9092, broker.2:9092, broker.3:9092 ]" >> .env
echo "REDPANDA_TOPIC=vehicle_telemetry" >> .env
```

## Redpanda Connect:  HTTP Server ==> Redpanda 

We will use Redpanda Connect's `http_server` input as a way to capture the data we will generate and publish it to a topic in our Redpanda cluster.   

In a new terminal window, fire up the RPCN pipeline.  This will stay running, and will show log entries roll by as data is being processed by the pipeline.

The endpoint is configurable in the `http_ingest.yaml` config file, but ours will run at `http://localhost:8888/telemetry`

```bash
rpk connect run -e .env http_ingest.yanml
```

TODO:  the buffer may not be necessary here, but could probably replace with batching at the kafka producer


## Redpanda Connect:  Redpanda ==> Snowflake

TODO:  will need to investigate batching here

In a different terminal window, fire up this RPCN pipeline. 

```bash
rpk connect run -e .env snowpipe_streaming.yanml
```

