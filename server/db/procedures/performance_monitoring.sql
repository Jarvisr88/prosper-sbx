-- Performance monitoring procedures
CREATE OR REPLACE PROCEDURE log_performance_metric(
    p_metric_name VARCHAR(100),
    p_metric_value DECIMAL,
    p_metric_type VARCHAR(50),
    p_dimensions JSONB DEFAULT '{}'::jsonb
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO system_metrics_history (
        metric_name,
        metric_value,
        metric_type,
        collection_time,
        granularity,
        dimensions
    ) VALUES (
        p_metric_name,
        p_metric_value,
        p_metric_type,
        CURRENT_TIMESTAMP,
        'minute',
        p_dimensions
    );
END;
$$;

-- Query performance tracking
CREATE OR REPLACE FUNCTION track_query_performance()
RETURNS TRIGGER AS $$
BEGIN
    -- Log query execution time
    INSERT INTO query_patterns (
        query_hash,
        execution_time,
        rows_affected,
        query_plan,
        optimization_status,
        created_at
    ) VALUES (
        md5(current_query()),
        extract(epoch from clock_timestamp() - statement_timestamp()),
        (SELECT count(*) FROM OLD),
        current_setting('plan_cache.query_plan'),
        'ANALYZED',
        CURRENT_TIMESTAMP
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create performance baseline
CREATE OR REPLACE PROCEDURE create_performance_baseline(
    p_metric_type VARCHAR(50),
    p_calculation_window INTERVAL,
    p_threshold_value DECIMAL
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO performance_baselines (
        metric_type,
        calculation_window,
        threshold_value,
        baseline_value,
        created_at,
        last_updated
    )
    SELECT 
        p_metric_type,
        p_calculation_window,
        p_threshold_value,
        avg(metric_value),
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    FROM system_metrics_history
    WHERE metric_type = p_metric_type
    AND collection_time >= (CURRENT_TIMESTAMP - p_calculation_window);
END;
$$;

-- Alert on performance deviation
CREATE OR REPLACE FUNCTION check_performance_deviation()
RETURNS TRIGGER AS $$
BEGIN
    -- Check if metric exceeds baseline threshold
    IF EXISTS (
        SELECT 1 
        FROM performance_baselines b
        WHERE b.metric_type = NEW.metric_type
        AND ABS(NEW.metric_value - b.baseline_value) > b.threshold_value
    ) THEN
        INSERT INTO performance_alerts (
            metric_type,
            alert_value,
            baseline_value,
            deviation_percentage,
            alert_type,
            created_at,
            status
        )
        SELECT 
            NEW.metric_type,
            NEW.metric_value,
            b.baseline_value,
            ((NEW.metric_value - b.baseline_value) / b.baseline_value * 100),
            'THRESHOLD_BREACH',
            CURRENT_TIMESTAMP,
            'OPEN'
        FROM performance_baselines b
        WHERE b.metric_type = NEW.metric_type;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for performance monitoring
CREATE TRIGGER monitor_performance_metrics
AFTER INSERT ON system_metrics_history
FOR EACH ROW
EXECUTE FUNCTION check_performance_deviation(); 