-- One-off migration from the stateful Risotto (`risotto-updates` topic,
-- `update.capnp:Update` schema) to the stateless Risotto (`risotto` topic,
-- `message.capnp:Message` schema). Run it before bmp.sql.
--
-- The previous `bmp.updates` table is kept as `bmp.updates_legacy`: its 7-day TTL
-- empties it, after which it can be dropped.

DROP VIEW IF EXISTS bmp.from_kafka_mv;
DROP TABLE IF EXISTS bmp.from_kafka;
RENAME TABLE bmp.updates TO bmp.updates_legacy;
