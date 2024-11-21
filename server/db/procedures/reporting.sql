-- User activity reporting
CREATE OR REPLACE FUNCTION generate_user_activity_report(
    p_start_date TIMESTAMP,
    p_end_date TIMESTAMP
)
RETURNS TABLE (
    username VARCHAR(50),
    login_count BIGINT,
    last_activity TIMESTAMP,
    session_duration INTERVAL,
    failed_attempts BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.username,
        COUNT(DISTINCT s.session_id) as login_count,
        MAX(s.created_at) as last_activity,
        SUM(s.expires_at - s.created_at) as session_duration,
        COUNT(se.event_id) as failed_attempts
    FROM users u
    LEFT JOIN user_sessions s ON u.user_id = s.user_id
    LEFT JOIN security_events se ON u.user_id = se.user_id 
        AND se.event_type = 'LOGIN_FAILURE'
    WHERE s.created_at BETWEEN p_start_date AND p_end_date
    GROUP BY u.username
    ORDER BY login_count DESC;
END;
$$;

-- Performance metrics reporting
CREATE OR REPLACE FUNCTION generate_performance_report(
    p_metric_type VARCHAR(50),
    p_period_start TIMESTAMP,
    p_period_end TIMESTAMP,
    p_granularity VARCHAR(20) DEFAULT 'hour'
)
RETURNS TABLE (
    time_bucket TIMESTAMP,
    metric_value DECIMAL,
    deviation_from_baseline DECIMAL,
    alert_count BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH baseline AS (
        SELECT baseline_value
        FROM performance_baselines
        WHERE metric_type = p_metric_type
        ORDER BY created_at DESC
        LIMIT 1
    )
    SELECT 
        date_trunc(p_granularity, smh.collection_time) as time_bucket,
        avg(smh.metric_value)::DECIMAL as metric_value,
        (avg(smh.metric_value) - (SELECT baseline_value FROM baseline))::DECIMAL as deviation,
        COUNT(DISTINCT pa.alert_id) as alert_count
    FROM system_metrics_history smh
    LEFT JOIN performance_alerts pa ON pa.metric_type = smh.metric_type
        AND pa.created_at BETWEEN p_period_start AND p_period_end
    WHERE smh.metric_type = p_metric_type
        AND smh.collection_time BETWEEN p_period_start AND p_period_end
    GROUP BY date_trunc(p_granularity, smh.collection_time)
    ORDER BY time_bucket;
END;
$$;

-- Audit summary report
CREATE OR REPLACE FUNCTION generate_audit_summary(
    p_start_date TIMESTAMP,
    p_end_date TIMESTAMP
)
RETURNS TABLE (
    entity_type VARCHAR(50),
    action_type VARCHAR(50),
    change_count BIGINT,
    unique_users BIGINT,
    most_common_changes JSONB
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        al.entity_type,
        al.action_type,
        COUNT(*) as change_count,
        COUNT(DISTINCT al.performed_by) as unique_users,
        jsonb_agg(
            DISTINCT jsonb_build_object(
                'field', (jsonb_each_text(al.new_values)).key,
                'count', COUNT(*) OVER (PARTITION BY (jsonb_each_text(al.new_values)).key)
            )
            ORDER BY COUNT(*) OVER (PARTITION BY (jsonb_each_text(al.new_values)).key) DESC
        ) FILTER (WHERE al.new_values IS NOT NULL) as most_common_changes
    FROM audit_log al
    WHERE al.action_date BETWEEN p_start_date AND p_end_date
    GROUP BY al.entity_type, al.action_type
    ORDER BY change_count DESC;
END;
$$; 