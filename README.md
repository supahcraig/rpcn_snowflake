# Streaming to Snowflake using Redpanda Connect & `snowflake_streaming` output
Streaming sample data via http endpoint through Redpanda and into Snowflake using Redpanda Connect



## Requirements

You'll need a Snowflake account (the basic trial account will work perfectly) as well as redpanda-connect 4.39.0 or greater.  Lastly you'll optionally need to be able to deploy a Docker container to deploy Redpanda if you don't have access to Redpanda cloud or similar.

Also optionally you can use the python data generator, or you can use the Redpanda Connect data generator.  If you go down the python route, you will need Python 3.11 or greater, Faker, requests, and several other modules defined in `requirments.txt`, which you will need to pip install into the virtual environment of your choice.


## Database setup

### Keypair authentication setup

You'll need to create a keypair to allow Redpanda Connect to authenticate with Snowflake.  This block will create those keys and produce an `ALTER USER` statement which will attach your public key your Snowflake user.

Run this block in a terminal window on your local machine.

```bash
openssl genrsa 4096 | openssl pkcs8 -topk8 -inform PEM -out snowflake_private_key.p8 -nocrypt
openssl rsa -in snowflake_private_key.p8 -pubout -out snowflake_public_key.pub
PUBK=`cat ./snowflake_public_key.pub | grep -v KEY- | tr -d '\012'`
echo "ALTER USER rpcn SET RSA_PUBLIC_KEY='$PUBK';"
```

Run the generated `ALTER USER` statement in Snowflake to attach the public key to your `rpcn` user in Snowflake.


## Set up your .env

From your local working directory, you'll find a file called `.env`, but we need to add one additional item for your Snowflake account.  It can be found within Snowflake, perhaps most easily by running this query:

```sql
select current_organization_name() || '-' || current_account_name();
```

Then inject it into your `.env` file:

```bash
echo "SNOWFLAKE_ACCOUNT=<your Snowflake account" >> .env
```


---

## Redpanda Setup


### Create Redpanda Cluster
You will need a Redpanda cluster (a single node cluster via Docker is fine, but BYOC or Serverless work work just as well)

Follow the Redpanda self-hosted Quickstart guide to spin up a 1 (or 3) broker cluster using Docker Compose.  The `docker-compose.yaml` in this repo is taken directly from that location.
https://docs.redpanda.com/current/get-started/quick-start/

(Later steps assume a 3-node Docker deployment, if your deployment is different you may have to make changes around broker addresses and TLS/SASL users as necessary)

```bash
docker-compose up
```


### Configure cluster & environment variables

It is not required, but the following commands assume you have set up an rpk profile pointed to your Redpanda cluster.

Once you have your Redpanda cluster up and running, you'll want to add the seed broker addresses to your `.env` file.  The `.env` is already configured for the Redpanda Quickstart Docker-hosted 3-node cluster.   If you have your own, you'll need the edit `.env` accordingly.  Your seed broker addresses can be found via `rpk cluster info`.

```bash
rpk cluster info
```

Next, use `rpk` to create the topic with 10 partitions and 1 hour retention policy.

```bash
rpk topic create vehicle_telemetry -p 10 -c retention.ms=3600000
rpk topic create vehicle_alert -p 10 -c retention.ms=3600000
rpk topic create vehicle_high_risk_behavior -p 10 -c retention.ms=3600000
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

When the `http_ingest` pipeline fires up, the input creates an http server that listens on `localhost`, port `8888`, on the `/telemetry` path.  Because Redpanda Connect runs transctionally, it won't return a response to the caller until the message is successfully processed by the output stage (`redpanda` in our case).  This means that subsequent messages will not be processed by the input until the current message has made it completely through.   This is probably not what we want.  We'll address that in the buffer section.


#### The pipeline

There is a pipeline processor after the output which we will use to inspect and conditionally modify the message payload.  Specifically, if the speed is > 85, then we inject an element into a new array called `high_risk_behavior`.  Similarly checking for (admittedly arbitrary) conditions on the tail light, airbag, and tire pressor sensors, we can add those alerts to the `vehicle_alerts` array.  Since each event could have multiple conditions met and we would expect to add more over time, an array is the right choice here.  Later on, we will use these new items to route to different topics in Redpanda.


#### The buffer

The buffer allows us to receive & acknowledge messages without waiting for the output to complete first.   In other words, the caller will receive the 200 response almost immediately, acknowledging that the pipeline has received the message, thereby allowing for the input section to handle the next message.  These messages are stored in an in-memory buffer allocated at 50MB, after which the pipeline will apply backpressure on the input, preventing it from accepting new messages.  The buffer itself is configured to hold up to 1000 messages, 32MB worth of messages, and hold them for up to 3 seconds, _whichever comes first_.

This is not without risk, however.  Any messages stored in the in-memory buffer are volatile, meaning that if the pipeline process were to shut down, messages in the buffer would be lost.  

_NOTE:  the buffer is only necessary here because we want a high throughput for demo purposes.  Batching at the output instead of a buffer would be a best practice if there are lots of producers and you wanted to maximize throughput at the expense of latency._


#### Output: redpanda

Once the buffer releases a batch of messages, the `redpanda` output will take the messages and publish them to the Repdanda cluster at the `seed_broker` address.  Which topic we publish to is defined by the cases in the switch statement.   If there are items in the alerts element, then the message will be routed to `vehicle_alerts`.  If there are items in the high risk element, the message will get published to `vehicle_high_risk_behavior`.  Lastly, regardless of any alert conditions, the message will be published to the `vehicle_telemetry` topic.  Note that these are not exclusive OR condidionts, all can be true simultaneously so a single message could be published to 1, 2, or 3 topics in this example.

It is left as an exercise to the reader to further manipulate the payload within each case.

---

## Redpanda Connect:  Redpanda ➡️ Snowflake


In a different terminal window, fire up this RPCN pipeline. 

```bash
rpk connect run -e .env telemetry_to_snowflake.yanml
```

### How does it work?

#### Input:  kafka_franz

When the `telemetry_to_snowflake` pipeline fires up, it begins by using the `kafka_franz` input to consume messages from a Redpanda cluster on one or more topics, using the `snowpipe_streaming` consumer group.

#### Output: snowflake_streaming

The `snowflake_streaming` output is used to stream data into a snowflake table.   In the times of yore, you could stream data into Snowflake using Snowpipe, but it required setting up Snowflake Stages and Pipes that would define loading instructions and hold the data for a time (think:  minutes) before making it available for querying.  Recently, Snowflake has provided a mechanism to stream data "directly" to a table to be immediately available for querying.   This processor uses that functionality.  We do still enable some batching here, by specifying to wait for either 1000 messages or 5 seconds, _whichever comes first,_ although it is not strictly-speaking necessary.  The Snowflake specifics are all provided via .env file.

Handling dates is always tricky when pushing data to a database, and this is no exception.   The processor requires date/time/timestamp data to be in either unixtime or RFC3339 format.  Within Redpanda Connect, bloblang provides several methods for parsing such data, including `ts_parse`, `ts_strptime`, and `ts_strftime`.  Our input data has 2 date-type fields, one of which is already unixtime so no special handling is needed.   However, the `expiration_date` field is formatted as `YYYY-MM-DD` so we need to turn that into an acceptable format.  The `mapping` section shows this transformation in action.


## Generate some data

In yet another window, fire up the data generator.   

```bash
rpk connect run -e .env rpcn_generate.yaml
```

You should see randomized json output streaming to stdout.  If you don't have the http ingest pipeline running already, you will see errors as it is trying to hit an endpoint that doesn't exist (yet).  Once http ingest is running the errors should go away.  This will generate data for as long as the pipeline is alive.

If you want to generate a set number of messages, you can specify it as a command line parameter:

```bash
rpk connect run  --set "input.generate.count=5" rpcn_generate.yaml
```


### OPTIONAL:  use the python data generator instead 
It uses `Faker` and `optional-faker` to generate some randomized payloads and uses `requests` to send them to the http endpoint created by the `http_ingest` Redpanda Connect pipeline.  You can specify the number of messages to generate by supplying it on the command line.

```bash
python data_generator.py 10000
```

You should immediately see results in 2 different forms:

* In the Redpanda console (`http://localhost:8080`) you will see messages in the `vehicle_telemetry` topic
* In Snowflake, querying the `vehicle_telemetry` table will show those same messages, more or less in real time.

---

# Lab Exercises

This is me just thinking out loud...

* Demonstrate schema evolution  (this is stubbed out already)
  * add a field to the data generator payload
  * update the schema evolution setting in the rpcn yaml / restart pipeline
  * observe new field in Snowflake
* Apply windowing to look for a certain number of events in a window and handle them

_NOTE:  Probably don't need to make this a lab on how to use bloblang, but depending on the demo purposes it might be worthwhile_