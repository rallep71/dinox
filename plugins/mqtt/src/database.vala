/*
 * MQTT Plugin Database — Separate SQLite database for MQTT runtime data.
 *
 * Stored as `mqtt.db` in the DinoX data directory (alongside dino.db, omemo.db).
 * Uses the Qlite ORM for schema management and versioning.
 *
 * Tables:
 *   mqtt_messages        — Received MQTT messages (persistent history)
 *   mqtt_freetext        — Freetext publish/response log (Node-RED integration)
 *   mqtt_connection_log  — Connect/disconnect/error events
 *   mqtt_topic_stats     — Per-topic statistics (message count, intervals)
 *   mqtt_alert_rules     — Alert rules (replaces JSON in settings)
 *   mqtt_bridge_rules    — Bridge rules (replaces JSON in settings)
 *   mqtt_publish_presets — Predefined publish actions
 *   mqtt_publish_history — Outgoing publish log
 *   mqtt_retained_cache  — Local cache of retained messages
 *
 * Configuration (host, port, TLS, credentials, topics) remains in the
 * main DinoX database (settings / account_settings tables).
 *
 * Copyright (C) 2026 Ralf Peter <dinox@handwerker.jetzt>
 */

using Qlite;
using Gee;

namespace Dino.Plugins.Mqtt {

public class MqttDatabase : Qlite.Database {

    private const int VERSION = 1;

    /* ══════════════════════════════════════════════════════════════════
     *  Table 1: mqtt_messages — Received MQTT messages
     * ══════════════════════════════════════════════════════════════════
     *
     * Every message arriving on a subscribed topic is stored here.
     * Enables persistent history, search, sparkline charts, and
     * post-restart replay.
     *
     * The `connection_id` is "standalone" for the standalone broker
     * connection, or the account bare JID for per-account connections.
     */
    public class MessagesTable : Table {
        public Column<int> id = new Column.Integer("id") { primary_key = true, auto_increment = true };
        public Column<string> connection_id = new Column.NonNullText("connection_id");
        public Column<string> topic = new Column.NonNullText("topic");
        public Column<string?> payload = new Column.Text("payload");
        public Column<int> payload_bytes = new Column.Integer("payload_bytes") { default = "0" };
        public Column<int> qos = new Column.Integer("qos") { default = "0" };
        public Column<bool> retained = new Column.BoolInt("retained") { default = "0" };
        public Column<string> priority = new Column.NonNullText("priority") { default = "'normal'" };
        public Column<long> timestamp = new Column.Long("timestamp") { not_null = true };

        internal MessagesTable(MqttDatabase db) {
            base(db, "mqtt_messages");
            init({id, connection_id, topic, payload, payload_bytes, qos, retained, priority, timestamp});
            index("mqtt_messages_ts_idx", {timestamp});
            index("mqtt_messages_topic_idx", {connection_id, topic});
        }
    }

    /* ══════════════════════════════════════════════════════════════════
     *  Table 2: mqtt_freetext — Freetext publish/response log
     * ══════════════════════════════════════════════════════════════════
     *
     * Logs free-form text published to a topic (e.g. for Node-RED) and
     * the responses received on the response topic.  This provides a
     * chat-like history for the freetext feature.
     */
    public class FreetextTable : Table {
        public Column<int> id = new Column.Integer("id") { primary_key = true, auto_increment = true };
        public Column<string> connection_id = new Column.NonNullText("connection_id");
        public Column<string> direction = new Column.NonNullText("direction");  /* 'outgoing' | 'incoming' */
        public Column<string> topic = new Column.NonNullText("topic");
        public Column<string?> payload = new Column.Text("payload");
        public Column<int> qos = new Column.Integer("qos") { default = "1" };
        public Column<bool> retain = new Column.BoolInt("retain") { default = "0" };
        public Column<long> timestamp = new Column.Long("timestamp") { not_null = true };

        internal FreetextTable(MqttDatabase db) {
            base(db, "mqtt_freetext");
            init({id, connection_id, direction, topic, payload, qos, retain, timestamp});
            index("mqtt_freetext_ts_idx", {timestamp});
            index("mqtt_freetext_conn_idx", {connection_id, direction});
        }
    }

    /* ══════════════════════════════════════════════════════════════════
     *  Table 3: mqtt_connection_log — Connect/disconnect/error events
     * ══════════════════════════════════════════════════════════════════
     *
     * Tracks all connection lifecycle events for debugging and
     * uptime statistics.  Events: connected, disconnected, error,
     * reconnect, auth_failed.
     */
    public class ConnectionLogTable : Table {
        public Column<int> id = new Column.Integer("id") { primary_key = true, auto_increment = true };
        public Column<string> connection_id = new Column.NonNullText("connection_id");
        public Column<string> event = new Column.NonNullText("event");
        public Column<string?> broker_host = new Column.Text("broker_host");
        public Column<int> broker_port = new Column.Integer("broker_port") { default = "1883" };
        public Column<string?> error_message = new Column.Text("error_message");
        public Column<long> timestamp = new Column.Long("timestamp") { not_null = true };

        internal ConnectionLogTable(MqttDatabase db) {
            base(db, "mqtt_connection_log");
            init({id, connection_id, event, broker_host, broker_port, error_message, timestamp});
            index("mqtt_connlog_ts_idx", {timestamp});
            index("mqtt_connlog_conn_idx", {connection_id});
        }
    }

    /* ══════════════════════════════════════════════════════════════════
     *  Table 4: mqtt_topic_stats — Per-topic statistics
     * ══════════════════════════════════════════════════════════════════
     *
     * Aggregated statistics per (connection, topic) pair.
     * Updated incrementally on each incoming message.  Enables
     * "topic dashboard" and inactivity detection.
     */
    public class TopicStatsTable : Table {
        public Column<int> id = new Column.Integer("id") { primary_key = true, auto_increment = true };
        public Column<string> connection_id = new Column.NonNullText("connection_id");
        public Column<string> topic = new Column.NonNullText("topic");
        public Column<long> first_seen = new Column.Long("first_seen") { not_null = true };
        public Column<long> last_seen = new Column.Long("last_seen") { not_null = true };
        public Column<long> message_count = new Column.Long("message_count") { default = "0" };
        public Column<long> avg_interval_ms = new Column.Long("avg_interval_ms") { default = "0" };
        public Column<string?> min_payload = new Column.Text("min_payload");
        public Column<string?> max_payload = new Column.Text("max_payload");
        public Column<string?> last_payload = new Column.Text("last_payload");

        internal TopicStatsTable(MqttDatabase db) {
            base(db, "mqtt_topic_stats");
            init({id, connection_id, topic, first_seen, last_seen, message_count,
                  avg_interval_ms, min_payload, max_payload, last_payload});
            unique({connection_id, topic}, "REPLACE");
            index("mqtt_topic_stats_conn_idx", {connection_id});
        }
    }

    /* ══════════════════════════════════════════════════════════════════
     *  Table 5: mqtt_alert_rules — Alert / threshold rules
     * ══════════════════════════════════════════════════════════════════
     *
     * Replaces the JSON array previously stored in the settings table.
     * Each row is one alert rule with its own UUID, topic pattern,
     * comparison operator, threshold, and priority mapping.
     */
    public class AlertRulesTable : Table {
        public Column<string> id = new Column.NonNullText("id") { primary_key = true };  /* UUID */
        public Column<string?> connection_id = new Column.Text("connection_id");  /* NULL = all connections */
        public Column<string> topic = new Column.NonNullText("topic");
        public Column<string?> field = new Column.Text("field");  /* JSON field or NULL */
        public Column<string> operator = new Column.NonNullText("operator");  /* '>', '<', '>=', etc. */
        public Column<string> threshold = new Column.NonNullText("threshold");
        public Column<string> priority = new Column.NonNullText("priority") { default = "'alert'" };
        public Column<bool> enabled = new Column.BoolInt("enabled") { default = "1" };
        public Column<long> cooldown_secs = new Column.Long("cooldown_secs") { default = "60" };
        public Column<long> last_triggered = new Column.Long("last_triggered") { default = "0" };
        public Column<long> created_at = new Column.Long("created_at") { default = "0" };

        internal AlertRulesTable(MqttDatabase db) {
            base(db, "mqtt_alert_rules");
            init({id, connection_id, topic, field, operator, threshold, priority,
                  enabled, cooldown_secs, last_triggered, created_at});
            index("mqtt_alert_rules_topic_idx", {topic});
        }
    }

    /* ══════════════════════════════════════════════════════════════════
     *  Table 6: mqtt_bridge_rules — MQTT → XMPP bridge rules
     * ══════════════════════════════════════════════════════════════════
     *
     * Replaces the JSON array previously stored in the settings table.
     * Each row maps an MQTT topic pattern to an XMPP JID for
     * automatic message forwarding.
     */
    public class BridgeRulesTable : Table {
        public Column<string> id = new Column.NonNullText("id") { primary_key = true };  /* UUID */
        public Column<string?> connection_id = new Column.Text("connection_id");
        public Column<string> topic = new Column.NonNullText("topic");
        public Column<string> target_jid = new Column.NonNullText("target_jid");
        public Column<string> format = new Column.NonNullText("format") { default = "'full'" };
        public Column<bool> enabled = new Column.BoolInt("enabled") { default = "1" };
        public Column<long> created_at = new Column.Long("created_at") { default = "0" };

        internal BridgeRulesTable(MqttDatabase db) {
            base(db, "mqtt_bridge_rules");
            init({id, connection_id, topic, target_jid, format, enabled, created_at});
            index("mqtt_bridge_rules_topic_idx", {topic});
        }
    }

    /* ══════════════════════════════════════════════════════════════════
     *  Table 7: mqtt_publish_presets — Predefined publish actions
     * ══════════════════════════════════════════════════════════════════
     *
     * Quick-publish templates: the user defines a name, topic, payload
     * template, QoS, and retain flag.  Can be triggered from the bot
     * chat via /mqtt preset <name> or from a future UI button.
     *
     * Payload can contain placeholders like {timestamp}, {value}.
     */
    public class PublishPresetsTable : Table {
        public Column<string> id = new Column.NonNullText("id") { primary_key = true };  /* UUID */
        public Column<string?> connection_id = new Column.Text("connection_id");
        public Column<string> preset_name = new Column.NonNullText("name");
        public Column<string> topic = new Column.NonNullText("topic");
        public Column<string?> payload = new Column.Text("payload");
        public Column<int> qos = new Column.Integer("qos") { default = "0" };
        public Column<bool> retain = new Column.BoolInt("retain") { default = "0" };
        public Column<long> created_at = new Column.Long("created_at") { default = "0" };
        public Column<long> last_used = new Column.Long("last_used") { default = "0" };
        public Column<long> use_count = new Column.Long("use_count") { default = "0" };

        internal PublishPresetsTable(MqttDatabase db) {
            base(db, "mqtt_publish_presets");
            init({id, connection_id, preset_name, topic, payload, qos, retain,
                  created_at, last_used, use_count});
            index("mqtt_publish_presets_name_idx", {connection_id, preset_name});
        }
    }

    /* ══════════════════════════════════════════════════════════════════
     *  Table 8: mqtt_publish_history — Outgoing publish log
     * ══════════════════════════════════════════════════════════════════
     *
     * Records every MQTT publish sent from DinoX.  Useful for debugging,
     * audit trail, and the /mqtt history --sent command.
     *
     * source: 'manual' (cmd), 'preset', 'freetext', 'bridge_response'
     */
    public class PublishHistoryTable : Table {
        public Column<int> id = new Column.Integer("id") { primary_key = true, auto_increment = true };
        public Column<string> connection_id = new Column.NonNullText("connection_id");
        public Column<string> topic = new Column.NonNullText("topic");
        public Column<string?> payload = new Column.Text("payload");
        public Column<int> qos = new Column.Integer("qos") { default = "0" };
        public Column<bool> retain = new Column.BoolInt("retain") { default = "0" };
        public Column<string> source = new Column.NonNullText("source") { default = "'manual'" };
        public Column<long> timestamp = new Column.Long("timestamp") { not_null = true };

        internal PublishHistoryTable(MqttDatabase db) {
            base(db, "mqtt_publish_history");
            init({id, connection_id, topic, payload, qos, retain, source, timestamp});
            index("mqtt_publish_history_ts_idx", {timestamp});
            index("mqtt_publish_history_conn_idx", {connection_id});
        }
    }

    /* ══════════════════════════════════════════════════════════════════
     *  Table 9: mqtt_retained_cache — Local cache of retained messages
     * ══════════════════════════════════════════════════════════════════
     *
     * When a retained message is received, the latest value per
     * (connection, topic) pair is cached here.  This allows the UI to
     * show "last known value" immediately on start, before a broker
     * reconnect delivers the retained message again.
     */
    public class RetainedCacheTable : Table {
        public Column<int> id = new Column.Integer("id") { primary_key = true, auto_increment = true };
        public Column<string> connection_id = new Column.NonNullText("connection_id");
        public Column<string> topic = new Column.NonNullText("topic");
        public Column<string?> payload = new Column.Text("payload");
        public Column<long> timestamp = new Column.Long("timestamp") { not_null = true };

        internal RetainedCacheTable(MqttDatabase db) {
            base(db, "mqtt_retained_cache");
            init({id, connection_id, topic, payload, timestamp});
            unique({connection_id, topic}, "REPLACE");
        }
    }

    /* ══════════════════════════════════════════════════════════════════
     *  Database instance — public table accessors
     * ══════════════════════════════════════════════════════════════════ */

    public MessagesTable messages { get; private set; }
    public FreetextTable freetext { get; private set; }
    public ConnectionLogTable connection_log { get; private set; }
    public TopicStatsTable topic_stats { get; private set; }
    public AlertRulesTable alert_rules { get; private set; }
    public BridgeRulesTable bridge_rules { get; private set; }
    public PublishPresetsTable publish_presets { get; private set; }
    public PublishHistoryTable publish_history { get; private set; }
    public RetainedCacheTable retained_cache { get; private set; }

    /**
     * Open (or create) the MQTT database at the given path.
     *
     * DinoX encrypts ALL databases. The key is either:
     *   - app.db_key (the user's master password), or
     *   - KeyManager.get_or_create_db_key() (auto-generated, OMEMO style).
     *
     * We use app.db_key (same as bot_registry.db) so that rekey_database()
     * works correctly when the user changes their master password.
     */
    public MqttDatabase(string file_name, string? key = null) throws Error {
        base(file_name, VERSION);

        messages = new MessagesTable(this);
        freetext = new FreetextTable(this);
        connection_log = new ConnectionLogTable(this);
        topic_stats = new TopicStatsTable(this);
        alert_rules = new AlertRulesTable(this);
        bridge_rules = new BridgeRulesTable(this);
        publish_presets = new PublishPresetsTable(this);
        publish_history = new PublishHistoryTable(this);
        retained_cache = new RetainedCacheTable(this);

        init({messages, freetext, connection_log, topic_stats, alert_rules,
              bridge_rules, publish_presets, publish_history, retained_cache}, key);

        try {
            exec("PRAGMA journal_mode = WAL");
            exec("PRAGMA synchronous = NORMAL");
        } catch (Error e) {
            warning("MqttDatabase: Failed to set PRAGMAs: %s", e.message);
        }
    }

    public override void migrate(long old_version) {
        /* Version 1 is the initial schema — no migration needed yet.
         * Future migrations go here:
         *
         * if (old_version < 2) {
         *     // Add new columns or tables for v2
         * }
         */
    }

    /* ── Convenience methods ─────────────────────────────────────── */

    /**
     * Record a received MQTT message in the messages table and
     * update topic_stats atomically.
     */
    public void record_message(string conn_id, string topic_name,
                               string? payload_str, int qos_val,
                               bool is_retained, string priority_str) {
        long now = (long) new DateTime.now_utc().to_unix();
        int payload_len = payload_str != null ? payload_str.length : 0;

        /* Insert into messages */
        messages.insert()
            .value(messages.connection_id, conn_id)
            .value(messages.topic, topic_name)
            .value(messages.payload, payload_str)
            .value(messages.payload_bytes, payload_len)
            .value(messages.qos, qos_val)
            .value(messages.retained, is_retained)
            .value(messages.priority, priority_str)
            .value(messages.timestamp, now)
            .perform();

        /* Update topic_stats (UPSERT) */
        var existing = topic_stats.select()
            .with(topic_stats.connection_id, "=", conn_id)
            .with(topic_stats.topic, "=", topic_name)
            .single().row();

        if (existing.is_present()) {
            Row row = (!) existing.inner;
            long old_last_seen = topic_stats.last_seen[row];
            long old_count = topic_stats.message_count[row];
            long old_avg = topic_stats.avg_interval_ms[row];
            long interval_ms = (now - old_last_seen) * 1000;

            /* Running average: new_avg = (old_avg * old_count + interval) / (old_count + 1) */
            long new_avg = old_count > 0
                ? (old_avg * old_count + interval_ms) / (old_count + 1)
                : interval_ms;

            /* Update min/max for numeric payloads */
            string? new_min = topic_stats.min_payload[row];
            string? new_max = topic_stats.max_payload[row];
            if (payload_str != null) {
                double val;
                if (double.try_parse(payload_str.strip(), out val)) {
                    if (new_min == null) {
                        new_min = payload_str.strip();
                        new_max = payload_str.strip();
                    } else {
                        double d_min;
                        double d_max;
                        if (double.try_parse(new_min, out d_min) && val < d_min) {
                            new_min = payload_str.strip();
                        }
                        if (double.try_parse(new_max, out d_max) && val > d_max) {
                            new_max = payload_str.strip();
                        }
                    }
                }
            }

            topic_stats.update()
                .with(topic_stats.connection_id, "=", conn_id)
                .with(topic_stats.topic, "=", topic_name)
                .set(topic_stats.last_seen, now)
                .set(topic_stats.message_count, old_count + 1)
                .set(topic_stats.avg_interval_ms, new_avg)
                .set(topic_stats.min_payload, new_min)
                .set(topic_stats.max_payload, new_max)
                .set(topic_stats.last_payload, payload_str)
                .perform();
        } else {
            topic_stats.insert()
                .value(topic_stats.connection_id, conn_id)
                .value(topic_stats.topic, topic_name)
                .value(topic_stats.first_seen, now)
                .value(topic_stats.last_seen, now)
                .value(topic_stats.message_count, (long) 1)
                .value(topic_stats.avg_interval_ms, (long) 0)
                .value(topic_stats.min_payload, payload_str)
                .value(topic_stats.max_payload, payload_str)
                .value(topic_stats.last_payload, payload_str)
                .perform();
        }

        /* Update retained cache if applicable */
        if (is_retained) {
            retained_cache.upsert()
                .value(retained_cache.connection_id, conn_id, true)
                .value(retained_cache.topic, topic_name, true)
                .value(retained_cache.payload, payload_str)
                .value(retained_cache.timestamp, now)
                .perform();
        }
    }

    /**
     * Record a freetext exchange (outgoing publish or incoming response).
     */
    public void record_freetext(string conn_id, string direction_str,
                                string topic_name, string? payload_str,
                                int qos_val, bool retain_flag) {
        long now = (long) new DateTime.now_utc().to_unix();
        freetext.insert()
            .value(freetext.connection_id, conn_id)
            .value(freetext.direction, direction_str)
            .value(freetext.topic, topic_name)
            .value(freetext.payload, payload_str)
            .value(freetext.qos, qos_val)
            .value(freetext.retain, retain_flag)
            .value(freetext.timestamp, now)
            .perform();
    }

    /**
     * Record a connection lifecycle event.
     */
    public void record_connection_event(string conn_id, string event_name,
                                        string? host, int port,
                                        string? error_msg = null) {
        long now = (long) new DateTime.now_utc().to_unix();
        connection_log.insert()
            .value(connection_log.connection_id, conn_id)
            .value(connection_log.event, event_name)
            .value(connection_log.broker_host, host)
            .value(connection_log.broker_port, port)
            .value(connection_log.error_message, error_msg)
            .value(connection_log.timestamp, now)
            .perform();
    }

    /**
     * Record an outgoing publish.
     */
    public void record_publish(string conn_id, string topic_name,
                               string? payload_str, int qos_val,
                               bool retain_flag, string source_type) {
        long now = (long) new DateTime.now_utc().to_unix();
        publish_history.insert()
            .value(publish_history.connection_id, conn_id)
            .value(publish_history.topic, topic_name)
            .value(publish_history.payload, payload_str)
            .value(publish_history.qos, qos_val)
            .value(publish_history.retain, retain_flag)
            .value(publish_history.source, source_type)
            .value(publish_history.timestamp, now)
            .perform();
    }

    /**
     * Get recent messages for a topic (newest first).
     */
    public Gee.List<Row> get_topic_history(string conn_id, string topic_name,
                                            int limit = 50) {
        var result = new Gee.ArrayList<Row>();
        var iter = messages.select()
            .with(messages.connection_id, "=", conn_id)
            .with(messages.topic, "=", topic_name)
            .order_by(messages.timestamp, "DESC")
            .limit(limit)
            .iterator();
        while (iter.next()) {
            result.add(iter.get());
        }
        return result;
    }

    /**
     * Get all topic stats for a connection.
     */
    public Gee.List<Row> get_all_topic_stats(string conn_id) {
        var result = new Gee.ArrayList<Row>();
        var iter = topic_stats.select()
            .with(topic_stats.connection_id, "=", conn_id)
            .order_by(topic_stats.last_seen, "DESC")
            .iterator();
        while (iter.next()) {
            result.add(iter.get());
        }
        return result;
    }

    /**
     * Get connection log entries (newest first).
     */
    public Gee.List<Row> query_connection_log(string conn_id, int limit = 100) {
        var result = new Gee.ArrayList<Row>();
        var iter = connection_log.select()
            .with(connection_log.connection_id, "=", conn_id)
            .order_by(connection_log.timestamp, "DESC")
            .limit(limit)
            .iterator();
        while (iter.next()) {
            result.add(iter.get());
        }
        return result;
    }

    /**
     * Get recent messages for a topic across ALL connections (newest first).
     */
    public Gee.List<Row> get_topic_history_all(string topic_name, int limit = 50) {
        var result = new Gee.ArrayList<Row>();
        var iter = messages.select()
            .with(messages.topic, "=", topic_name)
            .order_by(messages.timestamp, "DESC")
            .limit(limit)
            .iterator();
        while (iter.next()) {
            result.add(iter.get());
        }
        return result;
    }

    /**
     * Get distinct topics that have messages, with their message counts.
     * Returns rows from topic_stats sorted by last_seen DESC.
     */
    public Gee.List<Row> get_all_topic_stats_all() {
        var result = new Gee.ArrayList<Row>();
        var iter = topic_stats.select()
            .order_by(topic_stats.last_seen, "DESC")
            .iterator();
        while (iter.next()) {
            result.add(iter.get());
        }
        return result;
    }

    /**
     * Purge old messages older than the given Unix timestamp.
     */
    public void purge_messages_before(long before_timestamp) {
        messages.delete()
            .with(messages.timestamp, "<", before_timestamp)
            .perform();
    }

    /**
     * Purge old connection log entries.
     */
    public void purge_connection_log_before(long before_timestamp) {
        connection_log.delete()
            .with(connection_log.timestamp, "<", before_timestamp)
            .perform();
    }

    /**
     * Purge old publish history entries.
     */
    public void purge_publish_history_before(long before_timestamp) {
        publish_history.delete()
            .with(publish_history.timestamp, "<", before_timestamp)
            .perform();
    }

    /**
     * Purge old freetext entries.
     */
    public void purge_freetext_before(long before_timestamp) {
        freetext.delete()
            .with(freetext.timestamp, "<", before_timestamp)
            .perform();
    }

    /* ── Automatic data retention ──────────────────────────────── */

    /* Default retention periods (in seconds) */
    public const long RETENTION_MESSAGES_SECS      = 30 * 86400;  /* 30 Tage */
    public const long RETENTION_FREETEXT_SECS      = 30 * 86400;  /* 30 Tage */
    public const long RETENTION_CONNLOG_SECS       = 90 * 86400;  /* 90 Tage */
    public const long RETENTION_PUBLISH_HIST_SECS  = 30 * 86400;  /* 30 Tage */

    /**
     * Purge all expired data across all tables in one call.
     *
     * This is the single entry point for automatic data retention.
     * Called periodically by Plugin (every 6 hours) and once at startup.
     *
     * topic_stats and retained_cache are NOT purged — they contain
     * only aggregated or single-row-per-topic data and stay small.
     * alert_rules, bridge_rules, publish_presets are user-managed
     * and never auto-purged.
     *
     * Returns total number of rows deleted (for logging).
     */
    public int purge_expired() {
        long now = (long) new DateTime.now_utc().to_unix();
        int total = 0;

        /* Count before delete for logging */
        int msg_before = count_rows(messages);
        purge_messages_before(now - RETENTION_MESSAGES_SECS);
        int msg_deleted = msg_before - count_rows(messages);
        total += msg_deleted;

        int ft_before = count_rows(freetext);
        purge_freetext_before(now - RETENTION_FREETEXT_SECS);
        int ft_deleted = ft_before - count_rows(freetext);
        total += ft_deleted;

        int cl_before = count_rows(connection_log);
        purge_connection_log_before(now - RETENTION_CONNLOG_SECS);
        int cl_deleted = cl_before - count_rows(connection_log);
        total += cl_deleted;

        int ph_before = count_rows(publish_history);
        purge_publish_history_before(now - RETENTION_PUBLISH_HIST_SECS);
        int ph_deleted = ph_before - count_rows(publish_history);
        total += ph_deleted;

        if (total > 0) {
            message("MqttDatabase: purge_expired() deleted %d rows " +
                    "(messages=%d, freetext=%d, connlog=%d, publish=%d)",
                    total, msg_deleted, ft_deleted, cl_deleted, ph_deleted);

            /* VACUUM after significant deletes to reclaim disk space */
            if (total > 1000) {
                try {
                    exec("VACUUM");
                    message("MqttDatabase: VACUUM completed after purging %d rows", total);
                } catch (Error e) {
                    warning("MqttDatabase: VACUUM failed: %s", e.message);
                }
            }
        }

        return total;
    }

    /**
     * Count rows in a table using SQL COUNT(*) for O(1) performance.
     * (Previously iterated every row which was O(n).)
     */
    private int count_rows(Table table) {
        var ri = query_sql("SELECT COUNT(*) AS cnt FROM " + table.name);
        if (ri.next()) {
            return (int) ri.get().get_integer("cnt");
        }
        return 0;
    }

    /**
     * Get approximate database size info for diagnostics.
     * Returns a human-readable string with row counts per table.
     */
    public string get_stats_summary() {
        var sb = new StringBuilder();
        sb.append(_("mqtt.db Statistics\n"));
        sb.append("──────────────────\n");
        sb.append(_("Messages:       %d rows (max %d days)\n").printf(
            count_rows(messages), (int)(RETENTION_MESSAGES_SECS / 86400)));
        sb.append(_("Freetext:       %d rows (max %d days)\n").printf(
            count_rows(freetext), (int)(RETENTION_FREETEXT_SECS / 86400)));
        sb.append(_("Connection Log: %d rows (max %d days)\n").printf(
            count_rows(connection_log), (int)(RETENTION_CONNLOG_SECS / 86400)));
        sb.append(_("Topic Stats:    %d rows (permanent)\n").printf(
            count_rows(topic_stats)));
        sb.append(_("Alert Rules:    %d rows (user-managed)\n").printf(
            count_rows(alert_rules)));
        sb.append(_("Bridge Rules:   %d rows (user-managed)\n").printf(
            count_rows(bridge_rules)));
        sb.append(_("Publish Presets:%d rows (user-managed)\n").printf(
            count_rows(publish_presets)));
        sb.append(_("Publish History:%d rows (max %d days)\n").printf(
            count_rows(publish_history), (int)(RETENTION_PUBLISH_HIST_SECS / 86400)));
        sb.append(_("Retained Cache: %d rows (permanent)\n").printf(
            count_rows(retained_cache)));
        return sb.str;
    }
}

}
