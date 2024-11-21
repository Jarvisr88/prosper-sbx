-- User Management Procedures
CREATE OR REPLACE PROCEDURE create_user(
    p_username VARCHAR(50),
    p_email VARCHAR(255),
    p_password_hash TEXT,
    p_salt TEXT,
    p_role VARCHAR(20) DEFAULT 'user'
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO users (
        username,
        email,
        password_hash,
        salt,
        role,
        created_at,
        updated_at
    ) VALUES (
        p_username,
        p_email,
        p_password_hash,
        p_salt,
        p_role,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    );
END;
$$;

-- User Authentication Function
CREATE OR REPLACE FUNCTION authenticate_user(
    p_email VARCHAR(255),
    p_password_hash TEXT
) RETURNS TABLE (
    user_id INT,
    username VARCHAR(50),
    role VARCHAR(20),
    is_active BOOLEAN
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.user_id,
        u.username,
        u.role,
        COALESCE(u.is_active, false)
    FROM users u
    WHERE u.email = p_email
    AND u.password_hash = p_password_hash
    AND COALESCE(u.is_active, true) = true;
END;
$$; 