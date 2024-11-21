-- Session Management Procedures
CREATE OR REPLACE PROCEDURE create_session(
    p_user_id INT,
    p_session_id VARCHAR,
    p_user_agent TEXT DEFAULT NULL,
    p_ip_address INET DEFAULT NULL,
    p_expires_at TIMESTAMP
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO user_sessions (
        session_id,
        user_id,
        created_at,
        expires_at,
        is_valid,
        ip_address,
        user_agent
    ) VALUES (
        p_session_id,
        p_user_id,
        CURRENT_TIMESTAMP,
        p_expires_at,
        TRUE,
        p_ip_address,
        p_user_agent
    );

    -- Update user's last login
    UPDATE users
    SET last_login = CURRENT_TIMESTAMP
    WHERE user_id = p_user_id;
END;
$$;

-- Validate and refresh session
CREATE OR REPLACE FUNCTION validate_session(
    p_session_id VARCHAR
) RETURNS TABLE (
    is_valid BOOLEAN,
    user_id INT,
    username VARCHAR(50),
    role VARCHAR(20)
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.is_valid,
        u.user_id,
        u.username,
        u.role
    FROM user_sessions s
    JOIN users u ON s.user_id = u.user_id
    WHERE s.session_id = p_session_id
    AND s.expires_at > CURRENT_TIMESTAMP
    AND s.is_valid = TRUE
    AND COALESCE(u.is_active, TRUE) = TRUE;
END;
$$;

-- Invalidate session
CREATE OR REPLACE PROCEDURE invalidate_session(
    p_session_id VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE user_sessions
    SET is_valid = FALSE
    WHERE session_id = p_session_id;
END;
$$; 