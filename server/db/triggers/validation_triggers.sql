-- User data validation trigger function
CREATE OR REPLACE FUNCTION validate_user_data()
RETURNS TRIGGER AS $$
BEGIN
    -- Validate email format
    IF NEW.email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN
        RAISE EXCEPTION 'Invalid email format';
    END IF;

    -- Validate username length and characters
    IF LENGTH(NEW.username) < 3 OR LENGTH(NEW.username) > 50 OR
       NEW.username !~ '^[A-Za-z0-9._-]+$' THEN
        RAISE EXCEPTION 'Username must be 3-50 characters and contain only letters, numbers, dots, underscores, and hyphens';
    END IF;

    -- Validate role
    IF NEW.role NOT IN ('admin', 'manager', 'user', 'developer', 'analyst') THEN
        RAISE EXCEPTION 'Invalid role specified';
    END IF;

    -- Set updated_at timestamp
    NEW.updated_at = CURRENT_TIMESTAMP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for user validation
CREATE TRIGGER user_validation_trigger
BEFORE INSERT OR UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION validate_user_data();

-- Session validation trigger function
CREATE OR REPLACE FUNCTION validate_session_data()
RETURNS TRIGGER AS $$
BEGIN
    -- Validate session expiry
    IF NEW.expires_at <= CURRENT_TIMESTAMP THEN
        RAISE EXCEPTION 'Session expiry must be in the future';
    END IF;

    -- Validate user existence
    IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = NEW.user_id) THEN
        RAISE EXCEPTION 'Referenced user does not exist';
    END IF;

    -- Validate IP address format if provided
    IF NEW.ip_address IS NOT NULL AND 
       NEW.ip_address !~ '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$' THEN
        RAISE EXCEPTION 'Invalid IP address format';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for session validation
CREATE TRIGGER session_validation_trigger
BEFORE INSERT OR UPDATE ON user_sessions
FOR EACH ROW EXECUTE FUNCTION validate_session_data(); 