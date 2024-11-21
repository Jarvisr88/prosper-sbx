-- Create audit log trigger function
CREATE OR REPLACE FUNCTION log_user_changes()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (
        entity_type,
        entity_id,
        action_type,
        action_date,
        old_values,
        new_values,
        performed_by
    ) VALUES (
        'user',
        CASE 
            WHEN TG_OP = 'DELETE' THEN OLD.user_id
            ELSE NEW.user_id
        END,
        TG_OP,
        CURRENT_TIMESTAMP,
        CASE 
            WHEN TG_OP = 'UPDATE' OR TG_OP = 'DELETE' 
            THEN to_jsonb(OLD)
            ELSE NULL
        END,
        CASE 
            WHEN TG_OP = 'UPDATE' OR TG_OP = 'INSERT' 
            THEN to_jsonb(NEW)
            ELSE NULL
        END,
        current_setting('app.current_user_id', true)::integer
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for user table
CREATE TRIGGER user_audit_trigger
AFTER INSERT OR UPDATE OR DELETE ON users
FOR EACH ROW EXECUTE FUNCTION log_user_changes();

-- Create session audit trigger
CREATE OR REPLACE FUNCTION log_session_changes()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (
        entity_type,
        entity_id,
        action_type,
        action_date,
        old_values,
        new_values,
        performed_by
    ) VALUES (
        'session',
        NEW.session_id,
        TG_OP,
        CURRENT_TIMESTAMP,
        CASE 
            WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD)
            ELSE NULL
        END,
        to_jsonb(NEW),
        NEW.user_id
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for session table
CREATE TRIGGER session_audit_trigger
AFTER INSERT OR UPDATE ON user_sessions
FOR EACH ROW EXECUTE FUNCTION log_session_changes(); 