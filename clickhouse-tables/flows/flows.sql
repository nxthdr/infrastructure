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


CREATE TABLE flows.records
(
    date Date,
    time_inserted_ns DateTime64(9),
    time_received_ns DateTime64(9),
    time_flow_start_ns DateTime64(9),
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

CREATE FUNCTION convertToIPv6 AS (addr) ->
(
    -- if the first 12 bytes are zero, then it's an IPv4 address, otherwise it's an IPv6 address
    -- convert to IPv4-mapped IPv6 address or return the original IPv6 address
    if(reinterpretAsUInt128(substring(reverse(addr), 1, 12)) = 0, IPv4ToIPv6(reinterpretAsUInt32(substring(reverse(addr), 13, 4))), addr)
);

CREATE MATERIALIZED VIEW flows.from_kafka_mv TO flows.records
AS SELECT
    toDate(time_received_ns) AS date,
    now() AS time_inserted_ns,
    toDateTime64(time_received_ns/1000000000, 9) AS time_received_ns,
    toDateTime64(time_flow_start_ns/1000000000, 9) AS time_flow_start_ns,
    sequence_num,
    sampling_rate,
    convertToIPv6(sampler_address) AS sampler_address,
    convertToIPv6(src_addr) AS src_addr,
    convertToIPv6(dst_addr) AS dst_addr,
    src_as,
    dst_as,
    etype,
    proto,
    src_port,
    dst_port,
    bytes,
    packets
FROM flows.from_kafka;
