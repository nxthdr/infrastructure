CREATE TABLE flows.from_kafka
(
    timeReceivedNs UInt64,
    agentAddr FixedString(16),
    agentPort UInt16,
    agentSubId UInt32,
    datagramSequenceNumber UInt32,
    uptime UInt32,
    sampleSequenceNumber UInt32,
    sourceId UInt32,
    samplingRate UInt32,
    samplePool UInt32,
    drops UInt32,
    inputInterface UInt32,
    outputInterface UInt32,
    length UInt32,
    protocol UInt32,
    srcIp FixedString(16),
    dstIp FixedString(16),
    srcPort UInt32,
    dstPort UInt32,
    tcpFlags UInt32,
    tos UInt32
)
ENGINE = Kafka()
SETTINGS
    kafka_broker_list = '[2a06:de00:50:cafe:10::103]:9092',
    kafka_topic_list = 'pesto-sflow',
    kafka_group_name = 'clickhouse-pesto-group',
    kafka_format = 'CapnProto',
    kafka_schema = 'sflow:SFlowFlowRecord',
    kafka_num_consumers = 1,
    kafka_max_block_size = 1048576;


CREATE TABLE flows.records
(
    date Date,
    time_inserted_ns DateTime64(9),
    time_received_ns DateTime64(9),
    sequence_num UInt32,
    sampling_rate UInt64,
    sampler_address IPv6,
    sampler_port UInt16,
    src_addr IPv6,
    dst_addr IPv6,
    src_port UInt32,
    dst_port UInt32,
    protocol UInt32,
    etype UInt32,
    packet_length UInt32,
    bytes UInt64,
    packets UInt64
)
ENGINE = MergeTree()
PARTITION BY date
ORDER BY (time_received_ns, src_addr, dst_addr)
TTL date + INTERVAL 7 DAY DELETE;

CREATE FUNCTION IF NOT EXISTS convertToIPv6 AS (addr) ->
(
    -- if the first 12 bytes are zero, then it's an IPv4 address, otherwise it's an IPv6 address
    -- convert to IPv4-mapped IPv6 address or return the original IPv6 address
    if(reinterpretAsUInt128(substring(reverse(addr), 1, 12)) = 0, IPv4ToIPv6(reinterpretAsUInt32(substring(reverse(addr), 13, 4))), addr)
);

CREATE MATERIALIZED VIEW flows.from_kafka_mv TO flows.records
AS SELECT
    toDate(timeReceivedNs / 1000000000) AS date,
    now() AS time_inserted_ns,
    toDateTime64(timeReceivedNs / 1000000000, 9) AS time_received_ns,
    datagramSequenceNumber AS sequence_num,
    toUInt64(samplingRate) AS sampling_rate,
    toIPv6(agentAddr) AS sampler_address,
    agentPort AS sampler_port,

    -- Extract IPs (already IPv6 format)
    toIPv6(srcIp) AS src_addr,
    toIPv6(dstIp) AS dst_addr,

    -- Extract ports and protocol
    srcPort AS src_port,
    dstPort AS dst_port,
    protocol AS protocol,
    0 AS etype,

    -- Raw packet data
    length AS packet_length,
    toUInt64(length) AS bytes,
    1 AS packets
FROM flows.from_kafka
WHERE samplingRate > 0;
