CREATE TABLE flows.from_kafka
(
    time_received_ns UInt64,
    time_flow_start_ns UInt64,
    sequence_num UInt32,
    sampling_rate UInt64,
    sampler_address FixedString(16),
    src_addr FixedString(16),
    dst_addr FixedString(16),
    src_as UInt32,
    dst_as UInt32,
    etype UInt32,
    proto UInt32,
    src_port UInt32,
    dst_port UInt32,
    bytes UInt64,
    packets UInt64
)
ENGINE = Kafka()
SETTINGS
    kafka_broker_list = '[2a06:de00:50:cafe:10::103]:9092',
    kafka_topic_list = 'goflow-flows',
    kafka_group_name = 'clickhouse-goflow-group',
    kafka_format = 'Protobuf',
    kafka_schema = 'flows.proto:FlowMessage';


CREATE TABLE flows.flows
(
    date Date,
    time_inserted_ns DateTime64,
    time_received_ns DateTime64,
    time_flow_start_ns DateTime64,
    sequence_num UInt32,
    sampling_rate UInt64,
    sampler_address FixedString(16),
    src_addr FixedString(16),
    dst_addr FixedString(16),
    src_as UInt32,
    dst_as UInt32,
    etype UInt32,
    proto UInt32,
    src_port UInt32,
    dst_port UInt32,
    bytes UInt64,
    packets UInt64
)
ENGINE = MergeTree()
PARTITION BY date
ORDER BY time_received_ns
TTL date + INTERVAL 7 DAY DELETE;

CREATE MATERIALIZED VIEW flows.from_kafka_mv TO flows.flows
AS SELECT * FROM flows.from_kafka;
