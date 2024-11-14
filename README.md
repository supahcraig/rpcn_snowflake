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

---

## Redpanda Setup


### Create Redpanda Cluster
You will need a Redpanda cluster (a single node cluster via Docker is fine, but BYOC or Serverless work work just as well)

Follow the Redpanda self-hosted Quickstart guide to spin up a 1 (or 3) broker cluster using Docker Compose.
https://docs.redpanda.com/current/get-started/quick-start/



### Configure cluster & environment variables

Once you have your Redpanda cluster up and running, you'll want to add the broker addresses to your `.env` file.

```bash
echo "REDPANDA_BROKER_ADDRESSES=[ broker.1:9092, broker.2:9092, broker.3:9092 ]" >> .env
```

Assuming you have your rpk profile set up, use `rpk` to create the topic with 10 partitions and 1 hour retention.

```bash
rpk topic create vehicle_telemetry -p 10 -c retention.ms=3600000
```

---

## Redpanda Connect:  HTTP Server ➡️ Redpanda 

We will use Redpanda Connect's `http_server` input as a way to capture the data we will generate and publish it to a topic in our Redpanda cluster.   

In a new terminal window, fire up the RPCN pipeline.  This will stay running, and will show log entries roll by as data is being processed by the pipeline.

The endpoint is configurable in the `http_ingest.yaml` config file, but ours will run at `http://localhost:8888/telemetry`

```bash
rpk connect run -e .env http_ingest.yanml
```

### How does it work?

_TODO:  add schema registry handling?_

#### Input: http_server

When the `http_ingest` pipeline fires up, the input creates an http server that listens on `localhost`, port `8888`, on the `/telemetry` path.  Because Redpanda Connect runs transctionally, it won't return a response to the caller until the message is successfully processed by the output stage (`kafka_franz` in our case).  This means that subsequent messages will not be processed by the input until the current message has made it completely through.   This is probably not what we want.

#### The buffer

_TODO:  is the buffer even necessary here?  Or is batching at the output sufficient?_


The buffer allows us to receive & acknowledge messages without waiting for the output to complete first.   In other words, the caller will receive the 200 response almost immediately, acknowledging that the pipeline has received the message, thereby allowing for the input section to handle the next message.  These messages are stored in an in-memory buffer allocated at 50MB, after which the pipeline will apply backpressure on the input, preventing it from accepting new messages.  The buffer itself is configured to hold up to 1000 messages, 32MB worth of messages, and hold them for up to 3 seconds, _whichever comes first_.

This is not without risk, however.  Any messages stored in the in-memory buffer are volatile, meaning that if the pipeline process were to shut down, messages in the buffer would be lost.  

#### Output: kafka_franz

Once the buffer releases a batch of messages, the `kafka_franz` output will take the messages and publish them to the topic defined in the .env file, on the Repdanda cluster at the `seed_broker` address.


---

## Redpanda Connect:  Redpanda ➡️ Snowflake

TODO:  will need to investigate batching here
TODO:  parameterize the Snowflake stuff

In a different terminal window, fire up this RPCN pipeline. 

```bash
rpk connect run -e .env telemetry_to_snowflake.yanml
```

### How does it work?

#### Input:  kafka_franz
When the `telemetry_to_snowflake` pipeline fires up, it begins by using the `kafka_franz` input to consume messages from a Redpanda cluster on one or more topics, using the `snowpipe_streaming` consumer group.

#### Output: snowflake_streaming

The `snowflake_streaming` output is used to stream data into a snowflake table.   In the times of yore, you could stream data into Snowflake using Snowpipe, but it required setting up Snowflake stages that would hold the data for a time before making it available for querying.  Recently, Snowflake has provided a mechanism to stream data "directly" to a table to be immediately available for querying.   This processor uses that functionality.  We do still enable some batching here, by specifying to wait for either 1000 messages or 5 seconds, _whichever comes first,_ although it is not strictly-speaking necessary.  The Snowflake specifics are all provided via .env file.

Handling dates is always tricky when pushing data to a database, and this is no exception.   The processor requires date/time/timestamp data to be in either unixtime or RFC3339 format.  Within Redpanda Connect, bloblang provides several methods for parsing such data, including `ts_parse`, `ts_strptime`, and `ts_strftime`.  Our input data has 2 date-type fields, one of which is already unixtime so no special handling is needed.   However, the `expiration_date` field is formatted as `YYYY-MM-DD` so we need to turn that into an acceptable format.  The `mapping` section shows this transformation in action.

