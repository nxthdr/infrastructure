CREATE TABLE nxthdr.bgp_broker
(
	timestamp DateTime64,
	router_addr IPv6,
	router_port UInt32,
	peer_addr IPv6,
	peer_bgp_id IPv4,
	peer_asn UInt32,
	prefix_addr IPv6,
	prefix_len UInt8,
	is_post_policy bool,
	is_adj_rib_out bool,
	announced bool,
	origin String,
	path Array(UInt32),
	communities Array(Tuple(UInt32, UInt16)),
	synthetic bool,
)
ENGINE = Kafka()
SETTINGS
    kafka_broker_list = '[2a06:de00:50:cafe:10::103]:9092',
    kafka_topic_list = 'bgp-updates',
    kafka_group_name = 'clickhouse-bgp-group',
    kafka_format = 'CSV';

CREATE TABLE nxthdr.bgp_updates
(
	timestamp DateTime64,
	router_addr IPv6,
	router_port UInt32,
	peer_addr IPv6,
	peer_bgp_id IPv4,
	peer_asn UInt32,
	prefix_addr IPv6,
	prefix_len UInt8,
	is_post_policy bool,
	is_adj_rib_out bool,
	announced bool,
	origin String,
	path Array(UInt32),
	communities Array(Tuple(UInt32, UInt16)),
	synthetic bool,
)
ENGINE = MergeTree()
ORDER BY (timestamp, router_addr, peer_addr, prefix_addr, prefix_len)
TTL toDateTime(timestamp) + INTERVAL 7 DAY DELETE;

CREATE MATERIALIZED VIEW nxthdr.bgp_broker_mv TO nxthdr.bgp_updates
AS SELECT * FROM nxthdr.bgp_broker;