-- Security audit procedures
CREATE OR REPLACE PROCEDURE log_security_event(
    p_event_type VARCHAR(50),
    p_severity VARCHAR(20),
    p_user_id INT,
    p_ip_address INET,
    p_details JSONB
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO security_events (
        event_type,
        severity,
        user_id,
        ip_address,
        event_details,
        created_at
    ) VALUES (
        p_event_type,
        p_severity,
        p_user_id,
        p_ip_address,
        p_details,
        CURRENT_TIMESTAMP
    );

    -- Create notification for high severity events
    IF p_severity IN ('HIGH', 'CRITICAL') THEN
        INSERT INTO security_notifications (
            event_id,
            notification_type,
            recipient_role,
            message,
            created_at,
            status
        )
        VALUES (
            currval('security_events_event_id_seq'),
            'SECURITY_ALERT',
            'admin',
            format('High severity security event: %s', p_event_type),
            CURRENT_TIMESTAMP,
            'PENDING'
        );
    END IF;
END;
$$;

-- Security monitoring function
CREATE OR REPLACE FUNCTION monitor_security_metrics()
RETURNS TRIGGER AS $$
DECLARE
    v_threshold INT;
    v_count INT;
BEGIN
    -- Check for suspicious activities
    IF NEW.event_type = 'LOGIN_FAILURE' THEN
        -- Count failed login attempts in last hour
        SELECT COUNT(*)
        INTO v_count
        FROM security_events
        WHERE event_type = 'LOGIN_FAILURE'
        AND user_id = NEW.user_id
        AND created_at >= (CURRENT_TIMESTAMP - INTERVAL '1 hour');

        IF v_count >= 5 THEN
            -- Log account lockout event
            INSERT INTO security_events (
                event_type,
                severity,
                user_id,
                ip_address,
                event_details,
                created_at
            ) VALUES (
                'ACCOUNT_LOCKED',
                'HIGH',
                NEW.user_id,
                NEW.ip_address,
                jsonb_build_object(
                    'reason', 'Too many failed login attempts',
                    'failed_attempts', v_count
                ),
                CURRENT_TIMESTAMP
            );

            -- Update user status
            UPDATE users
            SET is_active = FALSE
            WHERE user_id = NEW.user_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create security monitoring trigger
CREATE TRIGGER security_monitoring_trigger
AFTER INSERT ON security_events
FOR EACH ROW
EXECUTE FUNCTION monitor_security_metrics();

-- Security audit report function
CREATE OR REPLACE FUNCTION generate_security_audit_report(
    p_start_date TIMESTAMP,
    p_end_date TIMESTAMP
)
RETURNS TABLE (
    event_type VARCHAR(50),
    severity_level VARCHAR(20),
    event_count BIGINT,
    unique_users BIGINT,
    unique_ips BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        se.event_type,
        se.severity,
        COUNT(*) as event_count,
        COUNT(DISTINCT se.user_id) as unique_users,
        COUNT(DISTINCT se.ip_address) as unique_ips
    FROM security_events se
    WHERE se.created_at BETWEEN p_start_date AND p_end_date
    GROUP BY se.event_type, se.severity
    ORDER BY COUNT(*) DESC;
END;
$$; 