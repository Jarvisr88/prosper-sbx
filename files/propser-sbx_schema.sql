--
-- PostgreSQL database dump
--

-- Dumped from database version 17.1
-- Dumped by pg_dump version 17.0

-- Started on 2024-11-23 23:38:51

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 5165 (class 1262 OID 32768)
-- Name: propser-sbx; Type: DATABASE; Schema: -; Owner: prosper-dev_owner
--

CREATE DATABASE "propser-sbx" WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE_PROVIDER = builtin LOCALE = 'C.UTF-8' BUILTIN_LOCALE = 'C.UTF-8';


ALTER DATABASE "propser-sbx" OWNER TO "prosper-dev_owner";

\connect -reuse-previous=on "dbname='propser-sbx'"

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 5 (class 2615 OID 188416)
-- Name: public; Type: SCHEMA; Schema: -; Owner: prosper-dev_owner
--

-- *not* creating schema, since initdb creates it


ALTER SCHEMA public OWNER TO "prosper-dev_owner";

--
-- TOC entry 5167 (class 0 OID 0)
-- Dependencies: 5
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: prosper-dev_owner
--

COMMENT ON SCHEMA public IS '';


--
-- TOC entry 1251 (class 1247 OID 196609)
-- Name: prosper_category; Type: TYPE; Schema: public; Owner: prosper-dev_owner
--

CREATE TYPE public.prosper_category AS ENUM (
    'PORTFOLIO',
    'RELATIONSHIP',
    'OPERATIONS',
    'SUCCESS',
    'PRODUCTIVITY',
    'ENABLEMENT',
    'RESPONSIBILITY'
);


ALTER TYPE public.prosper_category OWNER TO "prosper-dev_owner";

--
-- TOC entry 563 (class 1255 OID 196623)
-- Name: aggregate_metrics(timestamp without time zone, timestamp without time zone, text[]); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.aggregate_metrics(p_start_time timestamp without time zone, p_end_time timestamp without time zone, p_granularities text[] DEFAULT ARRAY['HOUR'::text, 'DAY'::text]) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_granularity text;
BEGIN
    FOREACH v_granularity IN ARRAY p_granularities
    LOOP
        INSERT INTO metric_aggregations (
            metric_name,
            granularity,
            time_bucket,
            min_value,
            max_value,
            avg_value,
            sum_value,
            count_value,
            percentiles,
            dimensions
        )
        SELECT 
            metric_name,
            v_granularity,
            date_trunc(lower(v_granularity), collection_time) as time_bucket,
            MIN(metric_value),
            MAX(metric_value),
            AVG(metric_value),
            SUM(metric_value),
            COUNT(*),
            jsonb_build_object(
                'p50', percentile_cont(0.5) WITHIN GROUP (ORDER BY metric_value),
                'p90', percentile_cont(0.9) WITHIN GROUP (ORDER BY metric_value),
                'p95', percentile_cont(0.95) WITHIN GROUP (ORDER BY metric_value),
                'p99', percentile_cont(0.99) WITHIN GROUP (ORDER BY metric_value)
            ),
            dimensions
        FROM system_metrics_history
        WHERE collection_time BETWEEN p_start_time AND p_end_time
        GROUP BY 
            metric_name,
            date_trunc(lower(v_granularity), collection_time),
            dimensions
        ON CONFLICT (metric_name, granularity, time_bucket, dimensions)
        DO UPDATE SET
            min_value = EXCLUDED.min_value,
            max_value = EXCLUDED.max_value,
            avg_value = EXCLUDED.avg_value,
            sum_value = EXCLUDED.sum_value,
            count_value = EXCLUDED.count_value,
            percentiles = EXCLUDED.percentiles;
    END LOOP;
END;
$$;


ALTER FUNCTION public.aggregate_metrics(p_start_time timestamp without time zone, p_end_time timestamp without time zone, p_granularities text[]) OWNER TO "prosper-dev_owner";

--
-- TOC entry 613 (class 1255 OID 196624)
-- Name: analyze_career_progression(integer, integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.analyze_career_progression(p_employee_id integer, p_timeframe_months integer DEFAULT 12) RETURNS TABLE(current_level character varying, progression_rate numeric, skill_growth jsonb, next_level_readiness numeric, recommended_actions jsonb)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH SkillProgress AS (
        SELECT 
            si.skill_name,
            si.proficiency_level,
            si.last_assessed,
            LAG(si.proficiency_level) OVER (
                PARTITION BY si.skill_name 
                ORDER BY si.last_assessed
            ) as previous_level
        FROM Skills_Inventory si
        WHERE si.employee_id = p_employee_id
        AND si.last_assessed >= CURRENT_DATE - (p_timeframe_months || ' months')::INTERVAL
    ),
    CareerPath AS (
        SELECT 
            cdp.role_current,
            cdp.role_target,
            sr.required_skills,
            sr.minimum_proficiency
        FROM Career_Development_Plans cdp
        JOIN Skill_Requirements sr ON cdp.role_target = sr.role_name
        WHERE cdp.employee_id = p_employee_id
        AND cdp.progress_status = 'Active'
    )
    SELECT 
        cp.role_current,
        ROUND(AVG(
            CASE WHEN sp.previous_level IS NOT NULL 
            THEN (sp.proficiency_level - sp.previous_level) / 
                 EXTRACT(EPOCH FROM (sp.last_assessed - LAG(sp.last_assessed) OVER (
                     PARTITION BY sp.skill_name ORDER BY sp.last_assessed
                 )))::DECIMAL * 2592000  -- Convert to monthly rate
            ELSE 0 
            END
        ), 2),
        jsonb_build_object(
            'improved_skills', (
                SELECT jsonb_agg(skill_name) 
                FROM SkillProgress 
                WHERE proficiency_level > COALESCE(previous_level, 0)
            ),
            'growth_rate', ROUND(AVG(
                CASE WHEN previous_level IS NOT NULL 
                THEN (proficiency_level - previous_level) 
                ELSE 0 END
            ), 2)
        ),
        ROUND(
            (SELECT COUNT(*) FROM Skills_Inventory si
             WHERE si.employee_id = p_employee_id
             AND si.proficiency_level >= cp.minimum_proficiency)::DECIMAL /
            NULLIF(jsonb_array_length(cp.required_skills), 0) * 100,
        2),
        jsonb_build_object(
            'missing_skills', (
                SELECT jsonb_agg(skill) 
                FROM jsonb_array_elements(cp.required_skills) skill
                WHERE NOT EXISTS (
                    SELECT 1 FROM Skills_Inventory si
                    WHERE si.employee_id = p_employee_id
                    AND si.skill_name = skill->>'name'
                    AND si.proficiency_level >= (skill->>'required_level')::DECIMAL
                )
            ),
            'recommended_training', (
                SELECT jsonb_agg(DISTINCT t.training_name)
                FROM Training_Records t
                WHERE t.category IN (
                    SELECT DISTINCT category 
                    FROM Skills_Inventory si
                    WHERE si.employee_id = p_employee_id
                    AND si.proficiency_level < cp.minimum_proficiency
                )
                AND t.effectiveness_rating >= 4
            )
        )
    FROM CareerPath cp
    LEFT JOIN SkillProgress sp ON true
    GROUP BY cp.role_current, cp.role_target, cp.required_skills, cp.minimum_proficiency;
END;
$$;


ALTER FUNCTION public.analyze_career_progression(p_employee_id integer, p_timeframe_months integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 588 (class 1255 OID 196625)
-- Name: analyze_configuration_settings(); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.analyze_configuration_settings() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_settings record;
    v_current_value text;
    v_recommended_value text;
BEGIN
    -- Check shared_buffers
    v_current_value := current_setting('shared_buffers');
    v_recommended_value := (pg_size_bytes(current_setting('shared_buffers'))::numeric / 
                          pg_size_bytes(current_setting('max_connections'))::numeric)::text;
    
    IF pg_size_bytes(v_current_value) < pg_size_bytes('1GB') THEN
        INSERT INTO optimization_recommendations (
            category,
            priority,
            title,
            description,
            current_value,
            recommended_value,
            estimated_impact,
            implementation_sql
        ) VALUES (
            'CONFIGURATION',
            'HIGH',
            'Increase shared_buffers',
            'Current shared_buffers setting is below recommended minimum for production',
            v_current_value,
            '25% of total RAM',
            jsonb_build_object(
                'performance_improvement', '10-30%',
                'risk_level', 'LOW',
                'restart_required', true
            ),
            format('ALTER SYSTEM SET shared_buffers = ''%s'';', v_recommended_value)
        );
    END IF;

    -- Check work_mem
    v_current_value := current_setting('work_mem');
    IF pg_size_bytes(v_current_value) < pg_size_bytes('4MB') THEN
        INSERT INTO optimization_recommendations (
            category,
            priority,
            title,
            description,
            current_value,
            recommended_value,
            estimated_impact,
            implementation_sql
        ) VALUES (
            'CONFIGURATION',
            'MEDIUM',
            'Adjust work_mem',
            'work_mem might be too low for complex queries',
            v_current_value,
            '4MB-64MB depending on workload',
            jsonb_build_object(
                'performance_improvement', '5-15%',
                'risk_level', 'LOW',
                'restart_required', false
            ),
            'ALTER SYSTEM SET work_mem = ''16MB'';'
        );
    END IF;

    -- Additional configuration checks can be added here
END;
$$;


ALTER FUNCTION public.analyze_configuration_settings() OWNER TO "prosper-dev_owner";

--
-- TOC entry 599 (class 1255 OID 196626)
-- Name: analyze_department_portfolio(integer, integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.analyze_department_portfolio(p_department_id integer, p_months integer DEFAULT 3) RETURNS TABLE(portfolio_type text, avg_department_score numeric, high_performers integer, needs_improvement integer, score_distribution jsonb, trend_analysis jsonb)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH department_metrics AS (
        SELECT 
            portfolio_type,
            employee_id,
            average_score,
            evaluation_date,
            ROW_NUMBER() OVER (
                PARTITION BY employee_id, portfolio_type 
                ORDER BY evaluation_date DESC
            ) as rn
        FROM public.portfolio_analysis_view
        WHERE department_id = p_department_id
        AND evaluation_date >= CURRENT_DATE - (p_months || ' months')::INTERVAL
    )
    SELECT 
        dm.portfolio_type,
        ROUND(AVG(dm.average_score), 2) as avg_department_score,
        COUNT(CASE WHEN dm.average_score >= 8 THEN 1 END) as high_performers,
        COUNT(CASE WHEN dm.average_score < 6 THEN 1 END) as needs_improvement,
        jsonb_build_object(
            'ranges', jsonb_build_object(
                '9-10', COUNT(CASE WHEN dm.average_score >= 9 THEN 1 END),
                '8-8.99', COUNT(CASE WHEN dm.average_score >= 8 AND dm.average_score < 9 THEN 1 END),
                '7-7.99', COUNT(CASE WHEN dm.average_score >= 7 AND dm.average_score < 8 THEN 1 END),
                '6-6.99', COUNT(CASE WHEN dm.average_score >= 6 AND dm.average_score < 7 THEN 1 END),
                'below_6', COUNT(CASE WHEN dm.average_score < 6 THEN 1 END)
            ),
            'statistics', jsonb_build_object(
                'median', PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dm.average_score),
                'stddev', ROUND(STDDEV(dm.average_score), 2),
                'min', MIN(dm.average_score),
                'max', MAX(dm.average_score)
            )
        ) as score_distribution,
        jsonb_build_object(
            'month_over_month', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'month', date_trunc('month', evaluation_date),
                        'avg_score', ROUND(AVG(average_score), 2),
                        'employees_evaluated', COUNT(DISTINCT employee_id)
                    )
                )
                FROM department_metrics dm2
                WHERE dm2.portfolio_type = dm.portfolio_type
                GROUP BY date_trunc('month', evaluation_date)
                ORDER BY date_trunc('month', evaluation_date)
            )
        ) as trend_analysis
    FROM department_metrics dm
    WHERE dm.rn = 1
    GROUP BY dm.portfolio_type;
END;
$$;


ALTER FUNCTION public.analyze_department_portfolio(p_department_id integer, p_months integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 615 (class 1255 OID 196627)
-- Name: analyze_index_usage(); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.analyze_index_usage() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_index record;
BEGIN
    -- Find unused indexes
    FOR v_index IN 
        SELECT 
            schemaname,
            tablename,
            indexname,
            idx_scan,
            pg_size_pretty(pg_relation_size(format('%I.%I', schemaname, indexname)::regclass)) as index_size
        FROM pg_stat_user_indexes
        WHERE idx_scan = 0
        AND NOT EXISTS (
            SELECT 1
            FROM pg_index i
            WHERE i.indexrelid = format('%I.%I', schemaname, indexname)::regclass
            AND i.indisprimary
        )
    LOOP
        INSERT INTO optimization_recommendations (
            category,
            priority,
            title,
            description,
            current_value,
            recommended_value,
            estimated_impact,
            implementation_sql
        ) VALUES (
            'INDEX',
            'MEDIUM',
            format('Remove unused index %I', v_index.indexname),
            format('Index %I on table %I.%I has never been used and occupies %s of space',
                   v_index.indexname, v_index.schemaname, v_index.tablename, v_index.index_size),
            'EXISTS',
            'DROP',
            jsonb_build_object(
                'space_saved', v_index.index_size,
                'risk_level', 'MEDIUM',
                'write_performance_improvement', '1-5%'
            ),
            format('DROP INDEX %I.%I;', v_index.schemaname, v_index.indexname)
        );
    END LOOP;

    -- Find missing indexes
    -- This is a simplified example; real-world implementation would be more complex
    INSERT INTO optimization_recommendations (
        category,
        priority,
        title,
        description,
        current_value,
        recommended_value,
        estimated_impact,
        implementation_sql
    )
    SELECT 
        'INDEX',
        'HIGH',
        format('Add index on %I.%I', schemaname, tablename),
        format('Table %I.%I has high sequential scan count (%s) relative to size',
               schemaname, tablename, seq_scan::text),
        'NO INDEX',
        'CREATE INDEX',
        jsonb_build_object(
            'estimated_improvement', '20-40%',
            'risk_level', 'LOW'
        ),
        format('CREATE INDEX idx_%s_%s ON %I.%I USING btree (%s);',
               tablename, 
               regexp_replace(attname, '[^a-zA-Z0-9]', '_', 'g'),
               schemaname,
               tablename,
               attname)
    FROM pg_stat_user_tables t
    JOIN pg_attribute a ON a.attrelid = format('%I.%I', schemaname, tablename)::regclass
    WHERE seq_scan > 1000
    AND NOT EXISTS (
        SELECT 1
        FROM pg_index i
        WHERE i.indrelid = format('%I.%I', schemaname, tablename)::regclass
        AND a.attnum = ANY(i.indkey)
    )
    AND a.attnum > 0
    AND NOT a.attisdropped;
END;
$$;


ALTER FUNCTION public.analyze_index_usage() OWNER TO "prosper-dev_owner";

--
-- TOC entry 585 (class 1255 OID 196628)
-- Name: analyze_performance_trend(integer, integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.analyze_performance_trend(p_employee_id integer, p_months integer DEFAULT 6) RETURNS TABLE(category character varying, trend_direction character varying, trend_value numeric, confidence_score numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH PerformanceData AS (
        SELECT 
            category,
            average_score,
            evaluation_date,
            ROW_NUMBER() OVER (PARTITION BY category ORDER BY evaluation_date) as rn,
            COUNT(*) OVER (PARTITION BY category) as sample_size
        FROM Performance_Scores
        WHERE employee_id = p_employee_id
        AND evaluation_date >= CURRENT_DATE - (p_months || ' months')::INTERVAL
    )
    SELECT 
        pd.category,
        CASE 
            WHEN COALESCE(
                regr_slope(pd.average_score::float8, 
                          EXTRACT(EPOCH FROM pd.evaluation_date)::float8
                ), 0) > 0 THEN 'Improving'
            WHEN COALESCE(
                regr_slope(pd.average_score::float8, 
                          EXTRACT(EPOCH FROM pd.evaluation_date)::float8
                ), 0) < 0 THEN 'Declining'
            ELSE 'Stable'
        END as trend_direction,
        COALESCE(
            regr_slope(pd.average_score::float8, 
                      EXTRACT(EPOCH FROM pd.evaluation_date)::float8
            ), 0) as trend_value,
        CASE 
            WHEN sample_size >= 5 THEN 0.9
            WHEN sample_size >= 3 THEN 0.7
            ELSE 0.5
        END as confidence_score
    FROM PerformanceData pd
    GROUP BY pd.category, pd.sample_size;
END;
$$;


ALTER FUNCTION public.analyze_performance_trend(p_employee_id integer, p_months integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 594 (class 1255 OID 196629)
-- Name: analyze_portfolio_trends(integer, integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.analyze_portfolio_trends(p_employee_id integer, p_months integer DEFAULT 6) RETURNS TABLE(portfolio_type text, current_score numeric, initial_to_current_delta numeric, self_to_manager_delta numeric, trend_direction text, volatility numeric, percentile numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH portfolio_stats AS (
        SELECT 
            portfolio_type,
            evaluation_date,
            average_score,
            initial_self_score,
            self_score,
            manager_score,
            AVG(average_score) OVER (
                PARTITION BY portfolio_type
            ) as avg_portfolio_score,
            STDDEV(average_score) OVER (
                PARTITION BY portfolio_type
            ) as score_stddev,
            PERCENT_RANK() OVER (
                PARTITION BY portfolio_type
                ORDER BY average_score
            ) as score_percentile,
            ROW_NUMBER() OVER (
                PARTITION BY portfolio_type
                ORDER BY evaluation_date DESC
            ) as rn
        FROM public.portfolio_analysis_view
        WHERE employee_id = p_employee_id
        AND evaluation_date >= CURRENT_DATE - (p_months || ' months')::INTERVAL
    )
    SELECT 
        ps.portfolio_type,
        ps.average_score as current_score,
        ROUND(ps.self_score - ps.initial_self_score, 2) as initial_to_current_delta,
        ROUND(ps.self_score - ps.manager_score, 2) as self_to_manager_delta,
        CASE 
            WHEN ps.average_score > ps.avg_portfolio_score + ps.score_stddev THEN 'Strong Positive'
            WHEN ps.average_score > ps.avg_portfolio_score THEN 'Positive'
            WHEN ps.average_score < ps.avg_portfolio_score - ps.score_stddev THEN 'Strong Negative'
            WHEN ps.average_score < ps.avg_portfolio_score THEN 'Negative'
            ELSE 'Neutral'
        END as trend_direction,
        ROUND(ps.score_stddev, 2) as volatility,
        ROUND(ps.score_percentile * 100, 2) as percentile
    FROM portfolio_stats ps
    WHERE ps.rn = 1;
END;
$$;


ALTER FUNCTION public.analyze_portfolio_trends(p_employee_id integer, p_months integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 565 (class 1255 OID 196630)
-- Name: analyze_query_patterns(); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.analyze_query_patterns() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_pattern record;
BEGIN
    -- Analyze slow queries from pg_stat_statements
    FOR v_pattern IN 
        SELECT 
            queryid,
            query,
            calls,
            total_time / calls as avg_time,
            rows / calls as avg_rows,
            shared_blks_hit,
            shared_blks_read,
            temp_blks_written
        FROM pg_stat_statements
        WHERE total_time / calls > 100  -- ms
        AND calls > 100
    LOOP
        -- Record query pattern
        INSERT INTO query_patterns (
            pattern_hash,
            query_pattern,
            execution_count,
            total_time,
            mean_time,
            rows_processed,
            shared_blks_hit,
            shared_blks_read,
            temp_blks_written,
            metadata
        ) VALUES (
            v_pattern.queryid::text,
            v_pattern.query,
            v_pattern.calls,
            v_pattern.total_time,
            v_pattern.avg_time,
            v_pattern.avg_rows,
            v_pattern.shared_blks_hit,
            v_pattern.shared_blks_read,
            v_pattern.temp_blks_written,
            jsonb_build_object(
                'first_seen', CURRENT_TIMESTAMP,
                'analysis_version', '1.0'
            )
        )
        ON CONFLICT (pattern_hash) 
        DO UPDATE SET
            execution_count = query_patterns.execution_count + v_pattern.calls,
            total_time = query_patterns.total_time + v_pattern.total_time,
            mean_time = (query_patterns.mean_time * query_patterns.execution_count + 
                        v_pattern.avg_time * v_pattern.calls) / 
                       (query_patterns.execution_count + v_pattern.calls),
            last_seen = CURRENT_TIMESTAMP;

        -- Generate optimization recommendations
        INSERT INTO optimization_recommendations (
            category,
            priority,
            title,
            description,
            current_value,
            recommended_value,
            estimated_impact,
            metadata
        ) VALUES (
            'QUERY',
            CASE 
                WHEN v_pattern.avg_time > 1000 THEN 'HIGH'
                WHEN v_pattern.avg_time > 500 THEN 'MEDIUM'
                ELSE 'LOW'
            END,
            'Optimize slow query pattern',
            format('Query averaging %.2f ms with %s calls', v_pattern.avg_time, v_pattern.calls),
            format('%.2f ms avg', v_pattern.avg_time),
            '< 100 ms avg',
            jsonb_build_object(
                'current_load', v_pattern.calls * v_pattern.avg_time / 1000.0,
                'potential_savings', (v_pattern.avg_time - 100) * v_pattern.calls / 1000.0
            ),
            jsonb_build_object(
                'query_id', v_pattern.queryid,
                'query_pattern', v_pattern.query,
                'performance_metrics', jsonb_build_object(
                    'calls', v_pattern.calls,
                    'avg_rows', v_pattern.avg_rows,
                    'shared_blks_hit', v_pattern.shared_blks_hit,
                    'shared_blks_read', v_pattern.shared_blks_read,
                    'temp_blks_written', v_pattern.temp_blks_written
                )
            )
        );
    END LOOP;
END;
$$;


ALTER FUNCTION public.analyze_query_patterns() OWNER TO "prosper-dev_owner";

--
-- TOC entry 607 (class 1255 OID 196631)
-- Name: analyze_query_performance(integer, interval); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.analyze_query_performance(p_min_calls integer DEFAULT 100, p_min_total_time interval DEFAULT '00:00:01'::interval) RETURNS TABLE(query_id bigint, query_text text, execution_count bigint, total_time interval, avg_time interval, rows_per_call numeric, optimization_suggestions jsonb)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH query_stats AS (
        SELECT 
            queryid,
            query,
            calls,
            total_exec_time,
            mean_exec_time,
            rows,
            shared_blks_hit,
            shared_blks_read,
            shared_blks_dirtied,
            shared_blks_written,
            local_blks_hit,
            local_blks_read,
            temp_blks_read,
            temp_blks_written
        FROM pg_stat_statements
        WHERE calls >= p_min_calls
        AND total_exec_time >= EXTRACT(EPOCH FROM p_min_total_time) * 1000
    )
    SELECT 
        qs.queryid,
        qs.query,
        qs.calls,
        (qs.total_exec_time * interval '1 millisecond'),
        (qs.mean_exec_time * interval '1 millisecond'),
        (qs.rows::numeric / NULLIF(qs.calls, 0))::numeric(10,2),
        jsonb_build_object(
            'performance_metrics', jsonb_build_object(
                'cache_hit_ratio', CASE 
                    WHEN (qs.shared_blks_hit + qs.shared_blks_read) = 0 THEN 0
                    ELSE (qs.shared_blks_hit::numeric / 
                          NULLIF(qs.shared_blks_hit + qs.shared_blks_read, 0))::numeric(5,2)
                END,
                'write_ratio', CASE 
                    WHEN (qs.shared_blks_read + qs.shared_blks_written) = 0 THEN 0
                    ELSE (qs.shared_blks_written::numeric / 
                          NULLIF(qs.shared_blks_read + qs.shared_blks_written, 0))::numeric(5,2)
                END
            ),
            'suggestions', jsonb_build_array(
                CASE 
                    WHEN qs.shared_blks_read > qs.shared_blks_hit THEN 
                        'Consider adding indexes or increasing cache size'
                    ELSE NULL
                END,
                CASE 
                    WHEN qs.temp_blks_written > 0 THEN 
                        'Query using temp tables - consider optimizing memory parameters'
                    ELSE NULL
                END,
                CASE 
                    WHEN qs.mean_exec_time > 1000 THEN 
                        'High average execution time - consider query optimization'
                    ELSE NULL
                END
            ) - jsonb_build_array(NULL)
        )
    FROM query_stats qs
    ORDER BY qs.total_exec_time DESC;
END;
$$;


ALTER FUNCTION public.analyze_query_performance(p_min_calls integer, p_min_total_time interval) OWNER TO "prosper-dev_owner";

--
-- TOC entry 614 (class 1255 OID 196632)
-- Name: analyze_resource_allocation(integer, date, date); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.analyze_resource_allocation(p_team_id integer, p_start_date date, p_end_date date) RETURNS TABLE(employee_id integer, employee_name character varying, total_allocation numeric, available_capacity numeric, project_count integer, skill_utilization jsonb)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH ResourceData AS (
        SELECT 
            ra.employee_id,
            emh.employee_name,
            SUM(ra.allocation_percentage) as allocated,
            COUNT(DISTINCT ra.project_id) as projects,
            jsonb_agg(DISTINCT ra.skills_utilized) as skills
        FROM Resource_Allocation ra
        JOIN Employee_Manager_Hierarchy emh ON ra.employee_id = emh.employee_id
        WHERE ra.start_date <= p_end_date 
        AND ra.end_date >= p_start_date
        AND emh.team_id = p_team_id
        GROUP BY ra.employee_id, emh.employee_name
    )
    SELECT 
        rd.employee_id,
        rd.employee_name,
        COALESCE(rd.allocated, 0) as total_allocation,
        100 - COALESCE(rd.allocated, 0) as available_capacity,
        rd.projects,
        rd.skills
    FROM ResourceData rd;
END;
$$;


ALTER FUNCTION public.analyze_resource_allocation(p_team_id integer, p_start_date date, p_end_date date) OWNER TO "prosper-dev_owner";

--
-- TOC entry 536 (class 1255 OID 196633)
-- Name: analyze_system_performance(text[], jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.analyze_system_performance(p_categories text[] DEFAULT NULL::text[], p_options jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(recommendations_count integer, analysis_details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_start_time timestamp;
    v_rec_count integer := 0;
    v_results jsonb := '[]'::jsonb;
BEGIN
    v_start_time := clock_timestamp();

    -- Analyze configuration settings
    IF p_categories IS NULL OR 'CONFIGURATION' = ANY(p_categories) THEN
        PERFORM analyze_configuration_settings();
        GET DIAGNOSTICS v_rec_count = ROW_COUNT;
        v_results := v_results || jsonb_build_object('category', 'CONFIGURATION', 'count', v_rec_count);
    END IF;

    -- Analyze index usage
    IF p_categories IS NULL OR 'INDEX' = ANY(p_categories) THEN
        PERFORM analyze_index_usage();
        GET DIAGNOSTICS v_rec_count = ROW_COUNT;
        v_results := v_results || jsonb_build_object('category', 'INDEX', 'count', v_rec_count);
    END IF;

    -- Analyze vacuum needs
    IF p_categories IS NULL OR 'VACUUM' = ANY(p_categories) THEN
        PERFORM analyze_vacuum_needs();
        GET DIAGNOSTICS v_rec_count = ROW_COUNT;
        v_results := v_results || jsonb_build_object('category', 'VACUUM', 'count', v_rec_count);
    END IF;

    -- Analyze query patterns
    IF p_categories IS NULL OR 'QUERY' = ANY(p_categories) THEN
        PERFORM analyze_query_patterns();
        GET DIAGNOSTICS v_rec_count = ROW_COUNT;
        v_results := v_results || jsonb_build_object('category', 'QUERY', 'count', v_rec_count);
    END IF;

    RETURN QUERY
    SELECT 
        (SELECT sum((value->>'count')::int) FROM jsonb_array_elements(v_results)),
        jsonb_build_object(
            'start_time', v_start_time,
            'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000,
            'categories', v_results
        );
END;
$$;


ALTER FUNCTION public.analyze_system_performance(p_categories text[], p_options jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 575 (class 1255 OID 196634)
-- Name: analyze_team_dynamics(integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.analyze_team_dynamics(p_department_id integer) RETURNS TABLE(metric_name text, metric_value numeric, interpretation text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH TeamMetrics AS (
        -- Team Cohesion Score
        SELECT 
            'Team Cohesion' as metric_name,
            ROUND(1 - (STDDEV(avg_score) / NULLIF(AVG(avg_score), 0)), 2) as metric_value
        FROM (
            SELECT 
                employee_id,
                AVG((COALESCE(self_score, 0) + COALESCE(manager_score, 0) + 
                     COALESCE(challenge_score, 0)) / 3) as avg_score
            FROM Performance_Scores ps
            JOIN Employee_Performance ep ON ps.employee_id = ep.employee_id
            WHERE ep.department_id = p_department_id
            GROUP BY employee_id
        ) scores

        UNION ALL

        -- Collaboration Index
        SELECT 
            'Collaboration Index',
            ROUND(AVG(
                CASE 
                    WHEN category = 'RELATIONSHIP' THEN 
                        (COALESCE(self_score, 0) + COALESCE(manager_score, 0)) / 2
                    ELSE NULL
                END
            ), 2)
        FROM Performance_Scores ps
        JOIN Employee_Performance ep ON ps.employee_id = ep.employee_id
        WHERE ep.department_id = p_department_id

        UNION ALL

        -- Performance Alignment
        SELECT 
            'Performance Alignment',
            ROUND(1 - (ABS(AVG(self_score) - AVG(manager_score)) / 100), 2)
        FROM Performance_Scores ps
        JOIN Employee_Performance ep ON ps.employee_id = ep.employee_id
        WHERE ep.department_id = p_department_id
    )
    SELECT 
        tm.metric_name,
        tm.metric_value,
        CASE 
            WHEN tm.metric_name = 'Team Cohesion' THEN
                CASE 
                    WHEN tm.metric_value >= 0.8 THEN 'Strong team cohesion'
                    WHEN tm.metric_value >= 0.6 THEN 'Moderate team cohesion'
                    ELSE 'Needs team building focus'
                END
            WHEN tm.metric_name = 'Collaboration Index' THEN
                CASE 
                    WHEN tm.metric_value >= 85 THEN 'Excellent collaboration'
                    WHEN tm.metric_value >= 70 THEN 'Good collaboration'
                    ELSE 'Collaboration needs improvement'
                END
            WHEN tm.metric_name = 'Performance Alignment' THEN
                CASE 
                    WHEN tm.metric_value >= 0.9 THEN 'Strong alignment'
                    WHEN tm.metric_value >= 0.7 THEN 'Moderate alignment'
                    ELSE 'Significant perception gap'
                END
        END as interpretation
    FROM TeamMetrics tm;
END;
$$;


ALTER FUNCTION public.analyze_team_dynamics(p_department_id integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 600 (class 1255 OID 196635)
-- Name: analyze_team_performance(integer, integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.analyze_team_performance(p_manager_id integer, p_months integer DEFAULT 3) RETURNS TABLE(category public.prosper_category, team_size integer, avg_team_score numeric, high_performers integer, needs_improvement integer, score_distribution jsonb, trend_analysis jsonb)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH team_scores AS (
        SELECT 
            CASE 
                WHEN pds.score_id IS NOT NULL THEN 'PORTFOLIO'::prosper_category
                WHEN ppe.score_id IS NOT NULL THEN 'RELATIONSHIP'::prosper_category
                WHEN pcs.score_id IS NOT NULL THEN 'OPERATIONS'::prosper_category
            END as category,
            emh.employee_id,
            COALESCE(pds.average_score, ppe.average_score, pcs.average_score) as score,
            COALESCE(pds.evaluation_date, ppe.evaluation_date, pcs.evaluation_date) as eval_date
        FROM employee_manager_hierarchy emh
        LEFT JOIN portfolio_design_success pds 
            ON emh.employee_id = pds.employee_id 
            AND pds.evaluation_date >= CURRENT_DATE - (p_months || ' months')::INTERVAL
        LEFT JOIN portfolio_premium_engagement ppe 
            ON emh.employee_id = ppe.employee_id 
            AND ppe.evaluation_date >= CURRENT_DATE - (p_months || ' months')::INTERVAL
        LEFT JOIN portfolio_cloud_services pcs 
            ON emh.employee_id = pcs.employee_id 
            AND pcs.evaluation_date >= CURRENT_DATE - (p_months || ' months')::INTERVAL
        WHERE emh.manager_id = p_manager_id
        AND COALESCE(pds.score_id, ppe.score_id, pcs.score_id) IS NOT NULL
    ),
    team_metrics AS (
        SELECT 
            category,
            COUNT(DISTINCT employee_id) as team_members,
            ROUND(AVG(score), 2) as avg_score,
            COUNT(CASE WHEN score >= 8 THEN 1 END) as high_perf_count,
            COUNT(CASE WHEN score < 6 THEN 1 END) as improvement_count
        FROM team_scores
        GROUP BY category
    )
    SELECT 
        tm.category,
        tm.team_members,
        tm.avg_score,
        tm.high_perf_count,
        tm.improvement_count,
        jsonb_build_object(
            'ranges', jsonb_build_object(
                '9-10', COUNT(CASE WHEN ts.score >= 9 THEN 1 END),
                '8-8.99', COUNT(CASE WHEN ts.score >= 8 AND ts.score < 9 THEN 1 END),
                '7-7.99', COUNT(CASE WHEN ts.score >= 7 AND ts.score < 8 THEN 1 END),
                '6-6.99', COUNT(CASE WHEN ts.score >= 6 AND ts.score < 7 THEN 1 END),
                'below_6', COUNT(CASE WHEN ts.score < 6 THEN 1 END)
            )
        ) as score_distribution,
        jsonb_build_object(
            'monthly_avg', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'month', date_trunc('month', ts2.eval_date),
                        'avg_score', ROUND(AVG(ts2.score), 2)
                    )
                )
                FROM team_scores ts2
                WHERE ts2.category = tm.category
                GROUP BY date_trunc('month', ts2.eval_date)
                ORDER BY date_trunc('month', ts2.eval_date)
            )
        ) as trend_analysis
    FROM team_metrics tm
    JOIN team_scores ts ON tm.category = ts.category
    GROUP BY 
        tm.category, 
        tm.team_members, 
        tm.avg_score, 
        tm.high_perf_count, 
        tm.improvement_count;
END;
$$;


ALTER FUNCTION public.analyze_team_performance(p_manager_id integer, p_months integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 618 (class 1255 OID 196636)
-- Name: analyze_team_portfolio_gaps(integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.analyze_team_portfolio_gaps(p_manager_id integer) RETURNS TABLE(portfolio_type text, team_size integer, coverage_percentage numeric, avg_team_score numeric, score_gaps jsonb, recommended_actions jsonb)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH team_metrics AS (
        SELECT 
            pa.portfolio_type,
            pa.employee_id,
            pa.average_score,
            pa.evaluation_date,
            ROW_NUMBER() OVER (
                PARTITION BY pa.employee_id, pa.portfolio_type 
                ORDER BY pa.evaluation_date DESC
            ) as rn
        FROM public.portfolio_analysis_view pa
        JOIN public.employee_manager_hierarchy emh ON pa.employee_id = emh.employee_id
        WHERE emh.manager_id = p_manager_id
    ),
    team_size_calc AS (
        SELECT COUNT(DISTINCT employee_id) as total_employees
        FROM public.employee_manager_hierarchy
        WHERE manager_id = p_manager_id
    )
    SELECT 
        tm.portfolio_type,
        ts.total_employees as team_size,
        ROUND(COUNT(DISTINCT tm.employee_id)::DECIMAL / ts.total_employees * 100, 2) as coverage_percentage,
        ROUND(AVG(tm.average_score), 2) as avg_team_score,
        jsonb_build_object(
            'skill_gaps', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'employee_id', tm2.employee_id,
                        'current_score', tm2.average_score,
                        'gap_to_target', GREATEST(8 - tm2.average_score, 0)
                    )
                )
                FROM team_metrics tm2
                WHERE tm2.rn = 1 
                AND tm2.portfolio_type = tm.portfolio_type
                AND tm2.average_score < 8
            ),
            'coverage_gaps', (
                SELECT jsonb_agg(e.employee_id)
                FROM public.employee_manager_hierarchy e
                WHERE e.manager_id = p_manager_id
                AND NOT EXISTS (
                    SELECT 1 FROM team_metrics tm3
                    WHERE tm3.employee_id = e.employee_id
                    AND tm3.portfolio_type = tm.portfolio_type
                )
            )
        ) as score_gaps,
        jsonb_build_object(
            'priority_actions', CASE 
                WHEN AVG(tm.average_score) < 6 THEN jsonb_build_array(
                    'Immediate team training required',
                    'Schedule weekly coaching sessions',
                    'Implement peer mentoring program'
                )
                WHEN AVG(tm.average_score) < 7 THEN jsonb_build_array(
                    'Identify common improvement areas',
                    'Monthly skill development workshops',
                    'Cross-training opportunities'
                )
                ELSE jsonb_build_array(
                    'Maintain current performance',
                    'Document best practices',
                    'Develop mentoring capabilities'
                )
            END,
            'development_focus', CASE 
                WHEN COUNT(DISTINCT tm.employee_id)::DECIMAL / ts.total_employees < 0.7 
                THEN 'Coverage Expansion'
                WHEN AVG(tm.average_score) < 7 
                THEN 'Skill Enhancement'
                ELSE 'Excellence Maintenance'
            END
        ) as recommended_actions
    FROM team_metrics tm
    CROSS JOIN team_size_calc ts
    WHERE tm.rn = 1
    GROUP BY tm.portfolio_type, ts.total_employees;
END;
$$;


ALTER FUNCTION public.analyze_team_portfolio_gaps(p_manager_id integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 572 (class 1255 OID 196637)
-- Name: assess_performance_risks(numeric, integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.assess_performance_risks(p_threshold_score numeric DEFAULT 6.0, p_trend_months integer DEFAULT 3) RETURNS TABLE(department_name text, risk_level text, at_risk_employees integer, risk_factors jsonb, recommended_actions jsonb)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH score_changes AS (
        SELECT 
            ps.employee_id,
            d.department_name::text as dept_name,  -- Cast to text
            ps.average_score,
            ps.average_score - LAG(ps.average_score) 
                OVER (PARTITION BY ps.employee_id ORDER BY ps.evaluation_date) as score_change
        FROM performance_scores ps
        JOIN employee_manager_hierarchy emh ON ps.employee_id = emh.employee_id
        JOIN department d ON emh.department_id = d.department_id
        WHERE ps.evaluation_date >= CURRENT_DATE - (p_trend_months || ' months')::INTERVAL
        AND emh.active = true
    ),
    risk_metrics AS (
        SELECT 
            sc.dept_name,
            COUNT(DISTINCT CASE WHEN sc.average_score < p_threshold_score THEN sc.employee_id END) as at_risk_count,
            COUNT(DISTINCT CASE WHEN sc.score_change < 0 THEN sc.employee_id END) as declining_count,
            ROUND(AVG(sc.average_score)::numeric, 2) as avg_dept_score,
            ROUND(AVG(COALESCE(sc.score_change, 0))::numeric, 2) as avg_score_change,
            jsonb_build_object(
                'below_threshold_percentage', 
                ROUND((COUNT(CASE WHEN sc.average_score < p_threshold_score THEN 1 END)::numeric / 
                       NULLIF(COUNT(*), 0) * 100)::numeric, 2),
                'trend_direction',
                CASE 
                    WHEN AVG(COALESCE(sc.score_change, 0)) > 0 THEN 'Improving'
                    WHEN AVG(COALESCE(sc.score_change, 0)) < 0 THEN 'Declining'
                    ELSE 'Stable'
                END
            ) as additional_metrics
        FROM score_changes sc
        GROUP BY sc.dept_name
    )
    SELECT 
        rm.dept_name::text,  -- Cast to text
        CASE 
            WHEN rm.at_risk_count > 5 OR rm.avg_dept_score < p_threshold_score THEN 'High Risk'
            WHEN rm.at_risk_count > 2 OR rm.avg_score_change < -0.5 THEN 'Medium Risk'
            ELSE 'Low Risk'
        END::text,  -- Cast to text
        rm.at_risk_count,
        jsonb_build_object(
            'avg_score', rm.avg_dept_score,
            'score_trend', rm.avg_score_change,
            'declining_performers', rm.declining_count,
            'metrics', rm.additional_metrics
        ),
        CASE 
            WHEN rm.at_risk_count > 5 OR rm.avg_dept_score < p_threshold_score THEN 
                jsonb_build_array(
                    'Immediate performance intervention required',
                    'Schedule weekly progress reviews',
                    'Implement intensive coaching program',
                    'Review resource allocation',
                    'Conduct skill gap analysis',
                    'Consider structural improvements'
                )
            WHEN rm.at_risk_count > 2 OR rm.avg_score_change < -0.5 THEN 
                jsonb_build_array(
                    'Increase monitoring frequency',
                    'Identify specific improvement areas',
                    'Schedule monthly check-ins',
                    'Review training needs',
                    'Set up mentoring pairs'
                )
            ELSE 
                jsonb_build_array(
                    'Maintain current monitoring',
                    'Continue regular reviews',
                    'Document best practices',
                    'Consider peer learning opportunities'
                )
        END
    FROM risk_metrics rm
    ORDER BY 
        CASE 
            WHEN rm.at_risk_count > 5 OR rm.avg_dept_score < p_threshold_score THEN 1
            WHEN rm.at_risk_count > 2 OR rm.avg_score_change < -0.5 THEN 2
            ELSE 3
        END,
        rm.at_risk_count DESC;
END;
$$;


ALTER FUNCTION public.assess_performance_risks(p_threshold_score numeric, p_trend_months integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 611 (class 1255 OID 196638)
-- Name: audit_configuration_changes(); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.audit_configuration_changes() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        INSERT INTO configuration_history (
            config_id,
            previous_value,
            new_value,
            changed_by,
            change_metadata
        ) VALUES (
            NEW.config_id,
            OLD.config_value,
            NEW.config_value,
            NEW.modified_by,
            jsonb_build_object(
                'operation', TG_OP,
                'timestamp', CURRENT_TIMESTAMP,
                'database_user', current_user,
                'application_user', NEW.modified_by,
                'client_addr', inet_client_addr()
            )
        );
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.audit_configuration_changes() OWNER TO "prosper-dev_owner";

--
-- TOC entry 551 (class 1255 OID 229377)
-- Name: authenticate_user(character varying, text); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.authenticate_user(p_email character varying, p_password_hash text) RETURNS TABLE(user_id integer, username character varying, role character varying, is_active boolean)
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
  AND COALESCE(u.is_active, false) = true;

  UPDATE users
  SET last_login = CURRENT_TIMESTAMP
  WHERE email = p_email;
END;
$$;


ALTER FUNCTION public.authenticate_user(p_email character varying, p_password_hash text) OWNER TO "prosper-dev_owner";

--
-- TOC entry 532 (class 1255 OID 196639)
-- Name: award_recognition_points(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.award_recognition_points(p_employee_id integer, p_points integer, p_recognition_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_current_balance INTEGER;
BEGIN
    -- Get current balance
    SELECT COALESCE(MAX(balance_after), 0)
    INTO v_current_balance
    FROM public.recognition_points_ledger
    WHERE employee_id = p_employee_id;
    
    -- Insert new transaction
    INSERT INTO public.recognition_points_ledger (
        employee_id,
        points_change,
        transaction_type,
        reference_id,
        reference_type,
        balance_after
    ) VALUES (
        p_employee_id,
        p_points,
        'AWARD',
        p_recognition_id,
        'RECOGNITION',
        v_current_balance + p_points
    );
    
    -- Update recognition record
    UPDATE public.employee_recognition
    SET points_awarded = p_points
    WHERE recognition_id = p_recognition_id;
END;
$$;


ALTER FUNCTION public.award_recognition_points(p_employee_id integer, p_points integer, p_recognition_id integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 625 (class 1255 OID 196640)
-- Name: build_report_query(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.build_report_query(p_query_definition jsonb, p_parameters jsonb) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_query text;
    v_param record;
    v_value text;
BEGIN
    v_query := p_query_definition->>'base_query';

    -- Replace parameters
    FOR v_param IN SELECT * FROM jsonb_each(p_parameters)
    LOOP
        -- Safely quote and type cast parameter values
        v_value := CASE jsonb_typeof(v_param.value)
            WHEN 'string' THEN quote_literal(v_param.value#>>'{}')
            WHEN 'number' THEN v_param.value#>>'{}'
            WHEN 'boolean' THEN v_param.value#>>'{}'
            WHEN 'null' THEN 'NULL'
            ELSE quote_literal(v_param.value#>>'{}')
        END;

        v_query := replace(v_query, 
                          format('{{%s}}', v_param.key), 
                          v_value);
    END LOOP;

    -- Add filters if defined
    IF p_query_definition ? 'filters' THEN
        v_query := v_query || ' WHERE ' || 
                  build_filter_clause(
                      p_query_definition->'filters', 
                      p_parameters->'filters'
                  );
    END IF;

    -- Add group by if defined
    IF p_query_definition ? 'group_by' THEN
        v_query := v_query || ' GROUP BY ' || 
                  (p_query_definition->>'group_by');
    END IF;

    -- Add having if defined
    IF p_query_definition ? 'having' THEN
        v_query := v_query || ' HAVING ' || 
                  (p_query_definition->>'having');
    END IF;

    -- Add order by if defined
    IF p_query_definition ? 'order_by' THEN
        v_query := v_query || ' ORDER BY ' || 
                  (p_query_definition->>'order_by');
    END IF;

    -- Add limit if defined
    IF p_query_definition ? 'limit' THEN
        v_query := v_query || ' LIMIT ' || 
                  (p_query_definition->>'limit');
    END IF;

    RETURN v_query;
END;
$$;


ALTER FUNCTION public.build_report_query(p_query_definition jsonb, p_parameters jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 597 (class 1255 OID 196641)
-- Name: calculate_base_score(integer, character varying); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.calculate_base_score(p_employee_id integer, p_category character varying) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN COALESCE(
        (SELECT (self_score + manager_score + COALESCE(challenge_score, 0)) / 
                CASE WHEN challenge_score IS NULL THEN 2 ELSE 3 END
         FROM Performance_Scores
         WHERE employee_id = p_employee_id 
         AND category = p_category
         ORDER BY evaluation_date DESC
         LIMIT 1),
        0
    );
END;
$$;


ALTER FUNCTION public.calculate_base_score(p_employee_id integer, p_category character varying) OWNER TO "prosper-dev_owner";

--
-- TOC entry 604 (class 1255 OID 196642)
-- Name: calculate_employee_average(numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.calculate_employee_average(p_self_score numeric, p_manager_score numeric, p_challenge_score numeric) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN ROUND((p_Self_Score + p_Manager_Score + p_Challenge_Score) / 3, 2);
END;
$$;


ALTER FUNCTION public.calculate_employee_average(p_self_score numeric, p_manager_score numeric, p_challenge_score numeric) OWNER TO "prosper-dev_owner";

--
-- TOC entry 627 (class 1255 OID 196643)
-- Name: calculate_next_cron_run(text, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.calculate_next_cron_run(p_cron_expression text, p_from_time timestamp without time zone DEFAULT CURRENT_TIMESTAMP) RETURNS timestamp without time zone
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_minute text;
    v_hour text;
    v_day text;
    v_month text;
    v_dow text;
    v_next timestamp;
    v_parts text[];
BEGIN
    -- Parse cron expression
    v_parts := string_to_array(p_cron_expression, ' ');
    
    IF array_length(v_parts, 1) != 5 THEN
        RAISE EXCEPTION 'Invalid cron expression: %', p_cron_expression;
    END IF;

    v_minute := v_parts[1];
    v_hour := v_parts[2];
    v_day := v_parts[3];
    v_month := v_parts[4];
    v_dow := v_parts[5];

    -- Start from next minute
    v_next := date_trunc('minute', p_from_time) + interval '1 minute';

    -- Implement cron calculation logic here
    -- This is a simplified version that only handles basic patterns
    WHILE true LOOP
        IF (
            (v_minute = '*' OR to_char(v_next, 'MI') = v_minute) AND
            (v_hour = '*' OR to_char(v_next, 'HH24') = v_hour) AND
            (v_day = '*' OR to_char(v_next, 'DD') = v_day) AND
            (v_month = '*' OR to_char(v_next, 'MM') = v_month) AND
            (v_dow = '*' OR to_char(v_next, 'ID') = v_dow)
        ) THEN
            RETURN v_next;
        END IF;

        v_next := v_next + interval '1 minute';
        
        -- Prevent infinite loop
        IF v_next > p_from_time + interval '1 year' THEN
            RAISE EXCEPTION 'Could not calculate next run time for cron expression: %', p_cron_expression;
        END IF;
    END LOOP;
END;
$$;


ALTER FUNCTION public.calculate_next_cron_run(p_cron_expression text, p_from_time timestamp without time zone) OWNER TO "prosper-dev_owner";

--
-- TOC entry 586 (class 1255 OID 196644)
-- Name: calculate_performance_improvement(integer, integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.calculate_performance_improvement(p_employee_id integer, p_periods integer DEFAULT 1) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    current_score DECIMAL(5,2);
    previous_score DECIMAL(5,2);
BEGIN
    -- Get current score
    SELECT Average_Score INTO current_score
    FROM Employee_Performance
    WHERE Employee_ID = p_Employee_ID
    ORDER BY Evaluation_Date DESC
    LIMIT 1;

    -- Get previous score
    SELECT Average_Score INTO previous_score
    FROM Employee_Performance
    WHERE Employee_ID = p_Employee_ID
    ORDER BY Evaluation_Date DESC
    OFFSET p_Periods
    LIMIT 1;

    RETURN ROUND(COALESCE(current_score - previous_score, 0), 2);
END;
$$;


ALTER FUNCTION public.calculate_performance_improvement(p_employee_id integer, p_periods integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 633 (class 1255 OID 196645)
-- Name: calculate_portfolio_score(integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.calculate_portfolio_score(p_employee_id integer) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_total_score DECIMAL(5,2) := 0;
    v_count INTEGER := 0;
BEGIN
    -- Design Success
    SELECT COALESCE(average_score, 0) 
    INTO v_total_score
    FROM Portfolio_Design_Success
    WHERE employee_id = p_employee_id
    ORDER BY evaluation_date DESC
    LIMIT 1;
    
    v_count := 1;

    -- Add other portfolio scores
    v_total_score := v_total_score + COALESCE(
        (SELECT average_score 
         FROM Portfolio_Premium_Engagement
         WHERE employee_id = p_employee_id
         ORDER BY evaluation_date DESC
         LIMIT 1), 0);
    v_count := v_count + 1;

    -- Return average
    RETURN CASE WHEN v_count > 0 THEN v_total_score / v_count ELSE 0 END;
END;
$$;


ALTER FUNCTION public.calculate_portfolio_score(p_employee_id integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 616 (class 1255 OID 196646)
-- Name: calculate_prosper_scores(integer, date); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.calculate_prosper_scores(p_employee_id integer, p_evaluation_date date DEFAULT CURRENT_DATE) RETURNS TABLE(category public.prosper_category, total_score numeric, weighted_score numeric, performance_level character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH category_weights AS (
        SELECT unnest(enum_range(NULL::prosper_category)) as category,
               CASE 
                   WHEN unnest(enum_range(NULL::prosper_category)) = 'PORTFOLIO' THEN 0.4
                   WHEN unnest(enum_range(NULL::prosper_category)) = 'RELATIONSHIP' THEN 0.3
                   WHEN unnest(enum_range(NULL::prosper_category)) = 'OPERATIONS' THEN 0.3
                   ELSE 0.2
               END as weight
    ),
    scores AS (
        SELECT * FROM (
            SELECT 
                'PORTFOLIO'::prosper_category as category,
                average_score as score
            FROM portfolio_design_success
            WHERE employee_id = p_employee_id
            AND evaluation_date <= p_evaluation_date
            ORDER BY evaluation_date DESC
            LIMIT 1
        ) a
        
        UNION ALL
        
        SELECT * FROM (
            SELECT 
                'RELATIONSHIP'::prosper_category,
                average_score
            FROM portfolio_premium_engagement
            WHERE employee_id = p_employee_id
            AND evaluation_date <= p_evaluation_date
            ORDER BY evaluation_date DESC
            LIMIT 1
        ) b
        
        UNION ALL
        
        SELECT * FROM (
            SELECT 
                'OPERATIONS'::prosper_category,
                average_score
            FROM portfolio_cloud_services
            WHERE employee_id = p_employee_id
            AND evaluation_date <= p_evaluation_date
            ORDER BY evaluation_date DESC
            LIMIT 1
        ) c
    )
    SELECT 
        s.category,
        ROUND(s.score, 2) as total_score,
        ROUND(s.score * cw.weight, 2) as weighted_score,
        CASE 
            WHEN s.score >= 8.5 THEN 'Outstanding'
            WHEN s.score >= 7.5 THEN 'Exceeds Expectations'
            WHEN s.score >= 6.5 THEN 'Meets Expectations'
            WHEN s.score >= 5.0 THEN 'Needs Improvement'
            ELSE 'Critical Attention Required'
        END as performance_level
    FROM scores s
    JOIN category_weights cw ON s.category = cw.category
    ORDER BY cw.weight DESC;
END;
$$;


ALTER FUNCTION public.calculate_prosper_scores(p_employee_id integer, p_evaluation_date date) OWNER TO "prosper-dev_owner";

--
-- TOC entry 569 (class 1255 OID 196647)
-- Name: check_performance_alerts(); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.check_performance_alerts() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_baseline record;
    v_current_value numeric;
BEGIN
    -- Check each metric against its baseline
    FOR v_baseline IN 
        SELECT * FROM performance_baselines 
        WHERE time_period = 'HOUR'
    LOOP
        -- Get the most recent value
        SELECT metric_value INTO v_current_value
        FROM performance_metrics
        WHERE metric_name = v_baseline.metric_name
        ORDER BY collection_time DESC
        LIMIT 1;

        -- Check for threshold violations
        IF v_current_value > v_baseline.percentile_99 THEN
            INSERT INTO performance_alerts (
                metric_name,
                alert_type,
                threshold_value,
                current_value,
                metadata
            ) VALUES (
                v_baseline.metric_name,
                'THRESHOLD',
                v_baseline.percentile_99,
                v_current_value,
                jsonb_build_object(
                    'baseline_period', 'HOUR',
                    'baseline_avg', v_baseline.avg_value,
                    'deviation_percent', 
                    ((v_current_value - v_baseline.avg_value) / v_baseline.avg_value * 100)::numeric(10,2)
                )
            )
            ON CONFLICT (metric_name) WHERE status = 'ACTIVE'
            DO UPDATE SET 
                current_value = EXCLUDED.current_value,
                metadata = performance_alerts.metadata || 
                          jsonb_build_object('updated_at', CURRENT_TIMESTAMP);
        END IF;
    END LOOP;
END;
$$;


ALTER FUNCTION public.check_performance_alerts() OWNER TO "prosper-dev_owner";

--
-- TOC entry 557 (class 1255 OID 196648)
-- Name: check_resource_availability(integer, date, date); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.check_resource_availability(p_employee_id integer, p_start_date date, p_end_date date) RETURNS TABLE(available_percentage numeric, concurrent_projects integer, can_be_assigned boolean, reason text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH current_allocations AS (
        SELECT 
            COALESCE(SUM(allocation_percentage), 0) as total_allocation,
            COUNT(DISTINCT project_id) as project_count
        FROM public.resource_allocation
        WHERE employee_id = p_employee_id
        AND start_date <= p_end_date
        AND end_date >= p_start_date
        AND allocation_status = 'active'
    )
    SELECT 
        100 - COALESCE(ca.total_allocation, 0) as available_percentage,
        COALESCE(ca.project_count, 0) as concurrent_projects,
        CASE 
            WHEN COALESCE(ca.total_allocation, 0) >= 100 THEN false
            ELSE true
        END as can_be_assigned,
        CASE 
            WHEN COALESCE(ca.total_allocation, 0) >= 100 
            THEN 'Resource is fully allocated'
            ELSE 'Resource has availability'
        END as reason
    FROM current_allocations ca;
END;
$$;


ALTER FUNCTION public.check_resource_availability(p_employee_id integer, p_start_date date, p_end_date date) OWNER TO "prosper-dev_owner";

--
-- TOC entry 537 (class 1255 OID 196649)
-- Name: cleanup_historical_data(integer); Type: PROCEDURE; Schema: public; Owner: prosper-dev_owner
--

CREATE PROCEDURE public.cleanup_historical_data(IN p_months_to_keep integer DEFAULT 24)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_cutoff_date DATE;
BEGIN
    v_cutoff_date := CURRENT_DATE - (p_months_to_keep || ' months')::INTERVAL;
    
    -- Archive old performance scores
    INSERT INTO Performance_Scores_Archive
    SELECT *
    FROM Performance_Scores
    WHERE evaluation_date < v_cutoff_date;
    
    -- Delete archived records
    DELETE FROM Performance_Scores
    WHERE evaluation_date < v_cutoff_date;
    
    -- Log the cleanup
    INSERT INTO Audit_Log (
        entity_type,
        action_type,
        action_date,
        performed_by,
        new_values
    ) VALUES (
        'Data_Cleanup',
        'ARCHIVE',
        CURRENT_TIMESTAMP,
        CURRENT_USER::INTEGER,
        jsonb_build_object(
            'cutoff_date', v_cutoff_date,
            'tables_cleaned', jsonb_build_array('Performance_Scores'),
            'cleanup_time', CURRENT_TIMESTAMP
        )
    );
END;
$$;


ALTER PROCEDURE public.cleanup_historical_data(IN p_months_to_keep integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 592 (class 1255 OID 196650)
-- Name: cleanup_old_backups(bigint); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.cleanup_old_backups(p_config_id bigint) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_config record;
    v_backup record;
BEGIN
    -- Get backup configuration
    SELECT * INTO v_config
    FROM backup_configurations
    WHERE config_id = p_config_id;

    -- Find and remove old backups
    FOR v_backup IN (
        SELECT *
        FROM backup_history
        WHERE config_id = p_config_id
        AND status = 'COMPLETED'
        AND backup_start < (CURRENT_TIMESTAMP - v_config.retention_period)
        ORDER BY backup_start DESC
    ) LOOP
        -- Delete backup files
        DELETE FROM backup_files
        WHERE backup_id = v_backup.backup_id;

        -- Remove physical files
        -- Note: This would need to be implemented based on your storage system
        -- PERFORM remove_backup_files(v_backup.file_location);

        -- Update backup history
        UPDATE backup_history
        SET status = 'DELETED'
        WHERE backup_id = v_backup.backup_id;
    END LOOP;
END;
$$;


ALTER FUNCTION public.cleanup_old_backups(p_config_id bigint) OWNER TO "prosper-dev_owner";

--
-- TOC entry 619 (class 1255 OID 196651)
-- Name: cleanup_old_backups(integer, integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.cleanup_old_backups(p_retention_days integer DEFAULT 30, p_min_backups integer DEFAULT 5) RETURNS TABLE(cleaned_count integer, details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_cleaned_count integer := 0;
    v_retained_backups jsonb;
BEGIN
    -- Get list of backups to retain
    WITH ranked_backups AS (
        SELECT 
            backup_id,
            backup_type,
            start_time,
            backup_location,
            ROW_NUMBER() OVER (PARTITION BY backup_type ORDER BY start_time DESC) as backup_rank
        FROM backup_catalog
        WHERE status = 'COMPLETED'
    )
    SELECT jsonb_agg(
        jsonb_build_object(
            'backup_id', backup_id,
            'type', backup_type,
            'date', start_time,
            'rank', backup_rank
        )
    )
    INTO v_retained_backups
    FROM ranked_backups
    WHERE backup_rank <= p_min_backups
    OR start_time > CURRENT_TIMESTAMP - (p_retention_days || ' days')::interval;

    -- Delete old backups
    WITH deleted_backups AS (
        DELETE FROM backup_catalog
        WHERE backup_id NOT IN (
            SELECT (jsonb_array_elements(v_retained_backups)->>'backup_id')::bigint
        )
        AND status = 'COMPLETED'
        RETURNING backup_id, backup_location
    )
    SELECT COUNT(*) INTO v_cleaned_count
    FROM deleted_backups;

    RETURN QUERY
    SELECT 
        v_cleaned_count,
        jsonb_build_object(
            'retained_backups', v_retained_backups,
            'retention_days', p_retention_days,
            'min_backups', p_min_backups,
            'execution_time', CURRENT_TIMESTAMP
        );
END;
$$;


ALTER FUNCTION public.cleanup_old_backups(p_retention_days integer, p_min_backups integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 535 (class 1255 OID 196652)
-- Name: cleanup_security_data(integer, integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.cleanup_security_data(p_retention_days integer DEFAULT 90, p_batch_size integer DEFAULT 1000) RETURNS TABLE(cleaned_events integer, archived_events integer, execution_details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_start_time timestamp := clock_timestamp();
    v_cutoff_date timestamp := CURRENT_TIMESTAMP - (p_retention_days || ' days')::interval;
    v_cleaned_count integer := 0;
    v_archived_count integer := 0;
BEGIN
    -- Archive important events before deletion
    WITH important_events AS (
        SELECT *
        FROM security_events
        WHERE event_time < v_cutoff_date
        AND (severity IN ('HIGH', 'CRITICAL') 
             OR event_details ? 'requires_retention')
        LIMIT p_batch_size
    )
    INSERT INTO security_events_archive (
        event_type,
        event_time,
        ip_address,
        user_id,
        event_details,
        severity,
        archived_at
    )
    SELECT 
        event_type,
        event_time,
        ip_address,
        user_id,
        event_details,
        severity,
        CURRENT_TIMESTAMP
    FROM important_events
    RETURNING 1 INTO v_archived_count;

    -- Delete old events
    WITH deleted_events AS (
        DELETE FROM security_events
        WHERE event_time < v_cutoff_date
        AND event_id IN (
            SELECT event_id 
            FROM security_events 
            WHERE event_time < v_cutoff_date
            LIMIT p_batch_size
        )
        RETURNING 1
    )
    SELECT COUNT(*) INTO v_cleaned_count FROM deleted_events;

    -- Return results
    RETURN QUERY
    SELECT 
        v_cleaned_count,
        v_archived_count,
        jsonb_build_object(
            'start_time', v_start_time,
            'end_time', clock_timestamp(),
            'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000,
            'retention_days', p_retention_days,
            'batch_size', p_batch_size,
            'cutoff_date', v_cutoff_date
        );

    -- Log cleanup operation
    INSERT INTO maintenance_log (
        operation_type,
        start_time,
        end_time,
        details
    ) VALUES (
        'SECURITY_DATA_CLEANUP',
        v_start_time,
        clock_timestamp(),
        jsonb_build_object(
            'cleaned_events', v_cleaned_count,
            'archived_events', v_archived_count,
            'retention_days', p_retention_days,
            'batch_size', p_batch_size
        )
    );
END;
$$;


ALTER FUNCTION public.cleanup_security_data(p_retention_days integer, p_batch_size integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 609 (class 1255 OID 196653)
-- Name: collect_performance_metrics(text[], jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.collect_performance_metrics(p_metric_types text[] DEFAULT NULL::text[], p_options jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(metrics_collected integer, collection_details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_start_time timestamp;
    v_metrics_count integer := 0;
    v_host_info jsonb;
    v_metric_results jsonb := '[]'::jsonb;
BEGIN
    v_start_time := clock_timestamp();
    
    -- Collect host information
    v_host_info := jsonb_build_object(
        'database', current_database(),
        'host', current_setting('server_version'),
        'pid', pg_backend_pid()
    );

    -- Collect CPU metrics
    IF p_metric_types IS NULL OR 'CPU' = ANY(p_metric_types) THEN
        INSERT INTO performance_metrics (
            metric_name,
            metric_value,
            metric_type,
            collection_interval,
            host_info,
            metadata
        )
        SELECT 
            metric_name,
            metric_value,
            'CPU',
            '1 minute'::interval,
            v_host_info,
            jsonb_build_object('source', 'pg_stat_activity')
        FROM (
            SELECT 
                'cpu_active_sessions' as metric_name,
                count(*) as metric_value
            FROM pg_stat_activity
            WHERE state = 'active'
            
            UNION ALL
            
            SELECT 
                'cpu_idle_sessions',
                count(*)
            FROM pg_stat_activity
            WHERE state = 'idle'
        ) cpu_metrics;
        
        GET DIAGNOSTICS v_metrics_count = ROW_COUNT;
        v_metric_results := v_metric_results || jsonb_build_object('type', 'CPU', 'count', v_metrics_count);
    END IF;

    -- Collect Memory metrics
    IF p_metric_types IS NULL OR 'MEMORY' = ANY(p_metric_types) THEN
        INSERT INTO performance_metrics (
            metric_name,
            metric_value,
            metric_type,
            collection_interval,
            host_info,
            metadata
        )
        SELECT 
            metric_name,
            metric_value,
            'MEMORY',
            '1 minute'::interval,
            v_host_info,
            jsonb_build_object('source', source)
        FROM (
            SELECT 
                'shared_buffers_usage' as metric_name,
                pg_size_bytes(current_setting('shared_buffers'))::numeric as metric_value,
                'configuration' as source
            
            UNION ALL
            
            SELECT 
                'work_mem_total',
                sum(work_mem::numeric)::numeric,
                'pg_stat_activity'
            FROM (
                SELECT current_setting('work_mem')::numeric as work_mem
                FROM pg_stat_activity
                WHERE state = 'active'
            ) work_mem_calc
        ) memory_metrics;
        
        GET DIAGNOSTICS v_metrics_count = ROW_COUNT;
        v_metric_results := v_metric_results || jsonb_build_object('type', 'MEMORY', 'count', v_metrics_count);
    END IF;

    -- Collect IO metrics
    IF p_metric_types IS NULL OR 'IO' = ANY(p_metric_types) THEN
        INSERT INTO performance_metrics (
            metric_name,
            metric_value,
            metric_type,
            collection_interval,
            host_info,
            metadata
        )
        SELECT 
            metric_name,
            metric_value,
            'IO',
            '1 minute'::interval,
            v_host_info,
            jsonb_build_object('source', 'pg_stat_database')
        FROM (
            SELECT 
                'blks_read' as metric_name,
                sum(blks_read)::numeric as metric_value
            FROM pg_stat_database
            
            UNION ALL
            
            SELECT 
                'blks_hit',
                sum(blks_hit)::numeric
            FROM pg_stat_database
            
            UNION ALL
            
            SELECT 
                'cache_hit_ratio',
                sum(blks_hit)::numeric / nullif(sum(blks_hit + blks_read), 0) * 100
            FROM pg_stat_database
        ) io_metrics;
        
        GET DIAGNOSTICS v_metrics_count = ROW_COUNT;
        v_metric_results := v_metric_results || jsonb_build_object('type', 'IO', 'count', v_metrics_count);
    END IF;

    -- Update performance baselines
    PERFORM update_performance_baselines();

    -- Check for performance alerts
    PERFORM check_performance_alerts();

    RETURN QUERY
    SELECT 
        (SELECT sum((value->>'count')::int) FROM jsonb_array_elements(v_metric_results)),
        jsonb_build_object(
            'start_time', v_start_time,
            'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000,
            'metrics', v_metric_results
        );
END;
$$;


ALTER FUNCTION public.collect_performance_metrics(p_metric_types text[], p_options jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 562 (class 1255 OID 196654)
-- Name: collect_system_statistics(text[], jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.collect_system_statistics(p_metric_types text[] DEFAULT NULL::text[], p_options jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(metrics_collected integer, collection_details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_start_time timestamp;
    v_metrics_count integer := 0;
    v_collected_metrics jsonb := '[]'::jsonb;
BEGIN
    v_start_time := clock_timestamp();

    -- Collect performance metrics
    IF p_metric_types IS NULL OR 'PERFORMANCE' = ANY(p_metric_types) THEN
        WITH performance_metrics AS (
            INSERT INTO system_metrics_history (
                metric_name,
                metric_value,
                metric_type,
                granularity,
                dimensions
            )
            SELECT 
                metric_name,
                metric_value,
                'PERFORMANCE',
                'MINUTE',
                dimensions
            FROM (
                -- Query execution metrics
                SELECT 
                    'avg_query_duration' as metric_name,
                    COALESCE(AVG(EXTRACT(EPOCH FROM total_exec_time) * 1000), 0) as metric_value,
                    jsonb_build_object(
                        'database', current_database(),
                        'user_type', usename
                    ) as dimensions
                FROM pg_stat_statements pss
                JOIN pg_user u ON u.usesysid = pss.userid
                WHERE calls > 0
                GROUP BY usename

                UNION ALL

                -- Connection metrics
                SELECT 
                    'active_connections',
                    COUNT(*)::numeric,
                    jsonb_build_object(
                        'database', current_database(),
                        'state', state
                    )
                FROM pg_stat_activity
                GROUP BY state

                UNION ALL

                -- Cache hit ratio
                SELECT 
                    'cache_hit_ratio',
                    CASE WHEN blks_hit + blks_read = 0 THEN 100
                         ELSE (blks_hit::numeric / (blks_hit + blks_read) * 100)
                    END,
                    jsonb_build_object(
                        'database', datname
                    )
                FROM pg_stat_database
                WHERE datname = current_database()

                UNION ALL

                -- Transaction metrics
                SELECT 
                    'transaction_rate',
                    (xact_commit + xact_rollback)::numeric / 
                        GREATEST(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - stats_reset)), 1),
                    jsonb_build_object(
                        'database', datname,
                        'commit_ratio', (xact_commit::numeric / 
                            GREATEST(xact_commit + xact_rollback, 1))::numeric(5,2)
                    )
                FROM pg_stat_database
                WHERE datname = current_database()
            ) perf_metrics
            RETURNING 1
        )
        SELECT COUNT(*) INTO v_metrics_count FROM performance_metrics;
        
        v_collected_metrics := v_collected_metrics || jsonb_build_object(
            'type', 'PERFORMANCE',
            'count', v_metrics_count
        );
    END IF;

    -- Collect resource metrics
    IF p_metric_types IS NULL OR 'RESOURCE' = ANY(p_metric_types) THEN
        WITH resource_metrics AS (
            INSERT INTO system_metrics_history (
                metric_name,
                metric_value,
                metric_type,
                granularity,
                dimensions
            )
            SELECT 
                metric_name,
                metric_value,
                'RESOURCE',
                'MINUTE',
                dimensions
            FROM (
                -- Table sizes
                SELECT 
                    'table_size',
                    pg_table_size(format('%I.%I', schemaname, tablename))::numeric,
                    jsonb_build_object(
                        'schema', schemaname,
                        'table', tablename
                    )
                FROM pg_tables
                WHERE schemaname NOT IN ('pg_catalog', 'information_schema')

                UNION ALL

                -- Index sizes
                SELECT 
                    'index_size',
                    pg_relation_size(format('%I.%I', schemaname, indexname))::numeric,
                    jsonb_build_object(
                        'schema', schemaname,
                        'table', tablename,
                        'index', indexname
                    )
                FROM pg_indexes
                WHERE schemaname NOT IN ('pg_catalog', 'information_schema')

                UNION ALL

                -- Database size
                SELECT 
                    'database_size',
                    pg_database_size(current_database())::numeric,
                    jsonb_build_object(
                        'database', current_database()
                    )
            ) resource_metrics
            RETURNING 1
        )
        SELECT COUNT(*) INTO v_metrics_count FROM resource_metrics;
        
        v_collected_metrics := v_collected_metrics || jsonb_build_object(
            'type', 'RESOURCE',
            'count', v_metrics_count
        );
    END IF;

    -- Aggregate metrics
    PERFORM aggregate_metrics(
        CURRENT_TIMESTAMP - interval '1 hour',
        CURRENT_TIMESTAMP,
        ARRAY['HOUR', 'DAY']
    );

    RETURN QUERY
    SELECT 
        (SELECT SUM(value::int) FROM jsonb_each_text(
            jsonb_agg(value->>'count')::jsonb
        ) WHERE value IS NOT NULL),
        jsonb_build_object(
            'start_time', v_start_time,
            'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000,
            'metrics', v_collected_metrics,
            'options', p_options
        );
END;
$$;


ALTER FUNCTION public.collect_system_statistics(p_metric_types text[], p_options jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 571 (class 1255 OID 196656)
-- Name: create_audit_log(); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.create_audit_log() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO Audit_Log (
        entity_type,
        entity_id,
        action_type,
        action_date,
        performed_by,
        old_values,
        new_values
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.employee_id, OLD.employee_id),
        TG_OP,
        CURRENT_TIMESTAMP,
        CURRENT_USER::INTEGER,
        CASE WHEN TG_OP = 'DELETE' THEN row_to_json(OLD)::jsonb
             WHEN TG_OP = 'UPDATE' THEN row_to_json(OLD)::jsonb
             ELSE NULL
        END,
        CASE WHEN TG_OP = 'INSERT' THEN row_to_json(NEW)::jsonb
             WHEN TG_OP = 'UPDATE' THEN row_to_json(NEW)::jsonb
             ELSE NULL
        END
    );
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.create_audit_log() OWNER TO "prosper-dev_owner";

--
-- TOC entry 602 (class 1255 OID 196657)
-- Name: create_deployment_plan(text, text, jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.create_deployment_plan(p_version text, p_deployment_type text, p_steps jsonb, p_options jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(deployment_id bigint, deployment_plan jsonb, validation_results jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_deployment_id bigint;
    v_validation_results jsonb := '[]'::jsonb;
    v_step jsonb;
    v_step_number integer := 1;
    v_rollback_steps jsonb := '[]'::jsonb;
BEGIN
    -- Validate deployment steps
    FOR v_step IN SELECT * FROM jsonb_array_elements(p_steps)
    LOOP
        -- Validate step syntax
        IF v_step->>'sql_command' IS NOT NULL THEN
            BEGIN
                PERFORM validate_sql_syntax(v_step->>'sql_command');
                v_validation_results := v_validation_results || jsonb_build_object(
                    'step', v_step_number,
                    'status', 'VALID',
                    'details', 'SQL syntax validated'
                );
            EXCEPTION WHEN OTHERS THEN
                v_validation_results := v_validation_results || jsonb_build_object(
                    'step', v_step_number,
                    'status', 'INVALID',
                    'error', SQLERRM
                );
            END;
        END IF;

        -- Generate rollback step
        v_rollback_steps := v_rollback_steps || generate_rollback_step(v_step);
        
        v_step_number := v_step_number + 1;
    END LOOP;

    -- Create deployment record
    INSERT INTO deployments (
        version,
        deployment_type,
        status,
        deployed_by,
        deployment_plan,
        rollback_plan
    ) VALUES (
        p_version,
        p_deployment_type,
        'PENDING',
        current_user,
        p_steps,
        v_rollback_steps
    ) RETURNING deployment_id INTO v_deployment_id;

    -- Create deployment steps
    v_step_number := 1;
    FOR v_step IN SELECT * FROM jsonb_array_elements(p_steps)
    LOOP
        INSERT INTO deployment_steps (
            deployment_id,
            step_number,
            step_type,
            sql_command
        ) VALUES (
            v_deployment_id,
            v_step_number,
            v_step->>'type',
            v_step->>'sql_command'
        );
        
        v_step_number := v_step_number + 1;
    END LOOP;

    RETURN QUERY
    SELECT 
        v_deployment_id,
        jsonb_build_object(
            'version', p_version,
            'type', p_deployment_type,
            'steps', p_steps,
            'rollback_plan', v_rollback_steps,
            'options', p_options
        ),
        v_validation_results;
END;
$$;


ALTER FUNCTION public.create_deployment_plan(p_version text, p_deployment_type text, p_steps jsonb, p_options jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 542 (class 1255 OID 196658)
-- Name: create_session(integer, text, inet, text, interval); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.create_session(p_user_id integer, p_session_id text, p_ip_address inet, p_user_agent text, p_duration interval DEFAULT '24:00:00'::interval) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO user_sessions (
        session_id,
        user_id,
        expires_at,
        ip_address,
        user_agent
    )
    VALUES (
        p_session_id,
        p_user_id,
        CURRENT_TIMESTAMP + p_duration,
        p_ip_address,
        p_user_agent
    );
    
    -- Update last login timestamp
    UPDATE users 
    SET last_login = CURRENT_TIMESTAMP
    WHERE user_id = p_user_id;
    
    RETURN TRUE;
END;
$$;


ALTER FUNCTION public.create_session(p_user_id integer, p_session_id text, p_ip_address inet, p_user_agent text, p_duration interval) OWNER TO "prosper-dev_owner";

--
-- TOC entry 593 (class 1255 OID 196659)
-- Name: create_user(character varying, character varying, text, character varying); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.create_user(p_username character varying, p_email character varying, p_password text, p_role character varying DEFAULT 'user'::character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_user_id INTEGER;
    v_salt TEXT;
    v_password_hash TEXT;
BEGIN
    -- Generate salt and hash password
    v_salt := gen_salt('bf');
    v_password_hash := crypt(p_password, v_salt);
    
    INSERT INTO users (username, email, password_hash, salt, role)
    VALUES (p_username, p_email, v_password_hash, v_salt, p_role)
    RETURNING user_id INTO v_user_id;
    
    RETURN v_user_id;
END;
$$;


ALTER FUNCTION public.create_user(p_username character varying, p_email character varying, p_password text, p_role character varying) OWNER TO "prosper-dev_owner";

--
-- TOC entry 628 (class 1255 OID 229376)
-- Name: create_user(character varying, character varying, text, text, character varying); Type: PROCEDURE; Schema: public; Owner: prosper-dev_owner
--

CREATE PROCEDURE public.create_user(IN p_username character varying, IN p_email character varying, IN p_password_hash text, IN p_salt text, IN p_role character varying DEFAULT 'user'::character varying)
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
  

  INSERT INTO audit_log (
    entity_type,
    action_type,
    action_date,
    new_values
  ) VALUES (
    'user',
    'create',
    CURRENT_TIMESTAMP,
    jsonb_build_object(
      'username', p_username,
      'email', p_email,
      'role', p_role
    )
  );
END;
$$;


ALTER PROCEDURE public.create_user(IN p_username character varying, IN p_email character varying, IN p_password_hash text, IN p_salt text, IN p_role character varying) OWNER TO "prosper-dev_owner";

--
-- TOC entry 584 (class 1255 OID 196660)
-- Name: execute_backup(bigint, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.execute_backup(p_config_id bigint, p_options jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(success boolean, backup_id bigint, details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_config record;
    v_backup_id bigint;
    v_start_time timestamp;
    v_backup_path text;
    v_file_count integer := 0;
    v_total_size bigint := 0;
    v_checksum text;
BEGIN
    -- Get backup configuration
    SELECT * INTO v_config
    FROM backup_configurations
    WHERE config_id = p_config_id AND is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Backup configuration % not found or inactive', p_config_id;
    END IF;

    v_start_time := clock_timestamp();

    -- Create backup history record
    INSERT INTO backup_history (
        config_id,
        backup_type,
        metadata
    ) VALUES (
        p_config_id,
        v_config.backup_type,
        jsonb_build_object(
            'options', p_options,
            'database', current_database(),
            'user', current_user
        )
    ) RETURNING backup_id INTO v_backup_id;

    -- Execute pre-backup script if exists
    IF v_config.pre_backup_script IS NOT NULL THEN
        EXECUTE v_config.pre_backup_script;
    END IF;

    BEGIN
        -- Generate backup path
        v_backup_path := format('%s/%s_%s',
            v_config.storage_location,
            current_database(),
            to_char(v_start_time, 'YYYY_MM_DD_HH24_MI_SS')
        );

        -- Execute backup based on type
        CASE v_config.backup_type
            WHEN 'FULL' THEN
                -- Perform full backup
                PERFORM perform_full_backup(
                    v_backup_path,
                    v_config.compression_type,
                    v_config.encryption_config
                );

            WHEN 'INCREMENTAL' THEN
                -- Perform incremental backup
                PERFORM perform_incremental_backup(
                    v_backup_path,
                    v_config.compression_type,
                    v_config.encryption_config,
                    get_last_successful_backup(p_config_id)
                );

            WHEN 'LOGICAL' THEN
                -- Perform logical backup
                PERFORM perform_logical_backup(
                    v_backup_path,
                    v_config.compression_type,
                    v_config.encryption_config,
                    p_options
                );

            WHEN 'SCHEMA_ONLY' THEN
                -- Perform schema-only backup
                PERFORM perform_schema_backup(
                    v_backup_path,
                    v_config.compression_type,
                    v_config.encryption_config
                );
        END CASE;

        -- Calculate backup checksum
        SELECT 
            count(*),
            sum(file_size),
            string_agg(checksum, ',' ORDER BY file_path)
        INTO 
            v_file_count,
            v_total_size,
            v_checksum
        FROM backup_files
        WHERE backup_id = v_backup_id;

        -- Execute post-backup script if exists
        IF v_config.post_backup_script IS NOT NULL THEN
            EXECUTE v_config.post_backup_script;
        END IF;

        -- Update backup history
        UPDATE backup_history
        SET 
            status = 'COMPLETED',
            backup_end = clock_timestamp(),
            file_location = v_backup_path,
            file_size = v_total_size,
            checksum = v_checksum,
            metadata = metadata || jsonb_build_object(
                'file_count', v_file_count,
                'compression_type', v_config.compression_type,
                'execution_time', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time))
            )
        WHERE backup_id = v_backup_id;

        -- Clean up old backups based on retention policy
        PERFORM cleanup_old_backups(p_config_id);

        RETURN QUERY
        SELECT 
            true,
            v_backup_id,
            jsonb_build_object(
                'backup_type', v_config.backup_type,
                'file_count', v_file_count,
                'total_size', v_total_size,
                'execution_time', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time))
            );

    EXCEPTION WHEN OTHERS THEN
        -- Update backup history with error
        UPDATE backup_history
        SET 
            status = 'FAILED',
            backup_end = clock_timestamp(),
            error_details = jsonb_build_object(
                'error', SQLERRM,
                'context', SQLSTATE
            )
        WHERE backup_id = v_backup_id;

        RETURN QUERY
        SELECT 
            false,
            v_backup_id,
            jsonb_build_object(
                'error', SQLERRM,
                'execution_time', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time))
            );
    END;
END;
$$;


ALTER FUNCTION public.execute_backup(p_config_id bigint, p_options jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 570 (class 1255 OID 196661)
-- Name: execute_cleanup_policy(bigint, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.execute_cleanup_policy(p_policy_id bigint, p_options jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(success boolean, rows_affected bigint, execution_details jsonb)
    LANGUAGE plpgsql
    AS $_$
DECLARE
    v_policy record;
    v_start_time timestamp;
    v_batch_size integer;
    v_total_rows bigint := 0;
    v_space_before bigint;
    v_space_after bigint;
    v_cutoff_date timestamp;
    v_history_id bigint;
    v_table_size jsonb;
    v_rows_deleted integer;
BEGIN
    -- Get policy details
    SELECT * INTO v_policy
    FROM cleanup_policies
    WHERE policy_id = p_policy_id AND is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cleanup policy % not found or inactive', p_policy_id;
    END IF;

    v_start_time := clock_timestamp();
    v_batch_size := COALESCE((p_options->>'batch_size')::integer, v_policy.batch_size);
    v_cutoff_date := CURRENT_TIMESTAMP - v_policy.retention_period;

    -- Get initial table size
    SELECT pg_table_size(v_policy.table_name) INTO v_space_before;

    -- Create history record
    INSERT INTO cleanup_history (
        policy_id,
        started_at
    ) VALUES (
        p_policy_id,
        v_start_time
    ) RETURNING history_id INTO v_history_id;

    -- Execute cleanup based on method
    CASE v_policy.cleanup_method
        WHEN 'DELETE' THEN
            LOOP
                EXECUTE format(
                    'WITH deleted AS (
                        DELETE FROM %I 
                        WHERE ctid IN (
                            SELECT ctid 
                            FROM %I 
                            WHERE created_at < $1 
                            LIMIT $2
                        )
                        RETURNING 1
                    )
                    SELECT COUNT(*) FROM deleted',
                    v_policy.table_name,
                    v_policy.table_name
                ) INTO v_rows_deleted USING v_cutoff_date, v_batch_size;

                v_total_rows := v_total_rows + v_rows_deleted;
                
                EXIT WHEN v_rows_deleted < v_batch_size;
                COMMIT;
            END LOOP;

        WHEN 'ARCHIVE' THEN
            -- Archive data before deletion
            v_table_size := archive_table_data(
                v_policy.table_name,
                format('created_at < %L', v_cutoff_date),
                v_policy.configuration
            );
            
            -- Delete archived data
            EXECUTE format(
                'WITH deleted AS (
                    DELETE FROM %I
                    WHERE created_at < $1
                    RETURNING 1
                )
                SELECT COUNT(*) FROM deleted',
                v_policy.table_name
            ) INTO v_total_rows USING v_cutoff_date;

        WHEN 'PARTITION' THEN
            -- Drop old partitions
            v_total_rows := drop_old_partitions(
                v_policy.table_name,
                v_cutoff_date,
                v_policy.configuration
            );

        WHEN 'CUSTOM' THEN
            -- Execute custom cleanup function
            IF v_policy.configuration->>'function_name' IS NOT NULL THEN
                EXECUTE format(
                    'SELECT %s($1, $2, $3)',
                    v_policy.configuration->>'function_name'
                ) USING v_policy.table_name, v_cutoff_date, v_policy.configuration
                INTO v_total_rows;
            END IF;
    END CASE;

    -- Get final table size
    SELECT pg_table_size(v_policy.table_name) INTO v_space_after;

    -- Update cleanup history
    UPDATE cleanup_history
    SET 
        completed_at = clock_timestamp(),
        rows_processed = v_total_rows,
        space_recovered = v_space_before - v_space_after,
        execution_details = jsonb_build_object(
            'cleanup_method', v_policy.cleanup_method,
            'cutoff_date', v_cutoff_date,
            'batch_size', v_batch_size,
            'initial_size_bytes', v_space_before,
            'final_size_bytes', v_space_after,
            'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000,
            'configuration', v_policy.configuration
        )
    WHERE history_id = v_history_id;

    -- Update policy last run time
    UPDATE cleanup_policies
    SET last_run = v_start_time
    WHERE policy_id = p_policy_id;

    RETURN QUERY
    SELECT 
        true,
        v_total_rows,
        jsonb_build_object(
            'policy_name', v_policy.policy_name,
            'table_name', v_policy.table_name,
            'cleanup_method', v_policy.cleanup_method,
            'rows_processed', v_total_rows,
            'space_recovered_bytes', v_space_before - v_space_after,
            'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000
        );
END;
$_$;


ALTER FUNCTION public.execute_cleanup_policy(p_policy_id bigint, p_options jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 581 (class 1255 OID 196662)
-- Name: execute_deployment(bigint, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.execute_deployment(p_deployment_id bigint, p_options jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(success boolean, execution_details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_deployment record;
    v_step record;
    v_start_time timestamp;
    v_results jsonb := '[]'::jsonb;
    v_success boolean := true;
BEGIN
    -- Get deployment details
    SELECT * INTO v_deployment
    FROM deployments
    WHERE deployment_id = p_deployment_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Deployment ID % not found', p_deployment_id;
    END IF;

    -- Update deployment status
    UPDATE deployments
    SET status = 'IN_PROGRESS'
    WHERE deployment_id = p_deployment_id;

    -- Execute each step
    FOR v_step IN (
        SELECT *
        FROM deployment_steps
        WHERE deployment_id = p_deployment_id
        ORDER BY step_number
    ) LOOP
        v_start_time := clock_timestamp();
        
        BEGIN
            -- Update step status
            UPDATE deployment_steps
            SET 
                status = 'IN_PROGRESS',
                started_at = v_start_time
            WHERE step_id = v_step.step_id;

            -- Execute step
            CASE v_step.step_type
                WHEN 'SQL' THEN
                    EXECUTE v_step.sql_command;
                WHEN 'FUNCTION' THEN
                    EXECUTE format('SELECT %s()', v_step.sql_command);
                WHEN 'VALIDATION' THEN
                    PERFORM validate_deployment_step(v_step.sql_command);
            END CASE;

            -- Update step status
            UPDATE deployment_steps
            SET 
                status = 'COMPLETED',
                completed_at = clock_timestamp(),
                execution_result = jsonb_build_object(
                    'success', true,
                    'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000
                )
            WHERE step_id = v_step.step_id;

            v_results := v_results || jsonb_build_object(
                'step', v_step.step_number,
                'status', 'COMPLETED',
                'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000
            );

        EXCEPTION WHEN OTHERS THEN
            v_success := false;
            
            -- Update step status
            UPDATE deployment_steps
            SET 
                status = 'FAILED',
                completed_at = clock_timestamp(),
                execution_result = jsonb_build_object(
                    'success', false,
                    'error', SQLERRM,
                    'context', SQLSTATE,
                    'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000
                )
            WHERE step_id = v_step.step_id;

            v_results := v_results || jsonb_build_object(
                'step', v_step.step_number,
                'status', 'FAILED',
                'error', SQLERRM,
                'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000
            );

            -- Handle failure based on options
            IF NOT (p_options->>'continue_on_error')::boolean THEN
                EXIT;
            END IF;
        END;
    END LOOP;

    -- Update deployment status
    UPDATE deployments
    SET 
        status = CASE WHEN v_success THEN 'COMPLETED' ELSE 'FAILED' END,
        completed_at = clock_timestamp()
    WHERE deployment_id = p_deployment_id;

    -- Update schema version if successful
    IF v_success THEN
        INSERT INTO schema_versions (
            version_number,
            is_current,
            deployment_id,
            schema_snapshot,
            metadata
        ) VALUES (
            v_deployment.version,
            true,
            p_deployment_id,
            get_schema_snapshot(),
            jsonb_build_object(
                'deployment_type', v_deployment.deployment_type,
                'deployed_by', v_deployment.deployed_by,
                'deployment_time', clock_timestamp()
            )
        );

        -- Set previous version as not current
        UPDATE schema_versions
        SET is_current = false
        WHERE version_id != currval('schema_versions_version_id_seq');
    END IF;

    RETURN QUERY
    SELECT 
        v_success,
        jsonb_build_object(
            'deployment_id', p_deployment_id,
            'version', v_deployment.version,
            'status', CASE WHEN v_success THEN 'COMPLETED' ELSE 'FAILED' END,
            'steps', v_results,
            'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_deployment.started_at)) * 1000
        );
END;
$$;


ALTER FUNCTION public.execute_deployment(p_deployment_id bigint, p_options jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 561 (class 1255 OID 196663)
-- Name: execute_health_checks(bigint, bigint, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.execute_health_checks(p_task_id bigint, p_history_id bigint, p_options jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_check record;
    v_result record;
    v_check_results jsonb := '[]'::jsonb;
    v_start_time timestamp;
    v_query text;
    v_threshold jsonb;
    v_status text;
BEGIN
    v_start_time := clock_timestamp();

    -- Execute each active health check
    FOR v_check IN 
        SELECT *
        FROM health_checks
        WHERE is_active = true
    LOOP
        BEGIN
            -- Execute check query
            EXECUTE v_check.check_query INTO v_result;

            -- Evaluate against thresholds
            v_threshold := v_check.threshold_config;
            v_status := evaluate_health_check(
                v_result,
                v_threshold
            );

            -- Record check results
            v_check_results := v_check_results || jsonb_build_object(
                'check_name', v_check.check_name,
                'check_type', v_check.check_type,
                'status', v_status,
                'details', to_jsonb(v_result)
            );

            -- Update health check status
            UPDATE health_checks
            SET 
                last_check = clock_timestamp(),
                last_status = v_status
            WHERE check_id = v_check.check_id;

            -- Send notification if configured and status is concerning
            IF v_status IN ('WARNING', 'CRITICAL') 
               AND v_check.notification_config IS NOT NULL 
            THEN
                PERFORM send_health_notification(
                    v_check.check_name,
                    v_status,
                    v_result,
                    v_check.notification_config
                );
            END IF;

        EXCEPTION WHEN OTHERS THEN
            -- Log error but continue with other checks
            v_check_results := v_check_results || jsonb_build_object(
                'check_name', v_check.check_name,
                'status', 'ERROR',
                'error', SQLERRM
            );
        END;
    END LOOP;

    -- Update maintenance history
    UPDATE maintenance_history
    SET 
        status = 'COMPLETED',
        end_time = clock_timestamp(),
        execution_details = jsonb_build_object(
            'checks_executed', jsonb_array_length(v_check_results),
            'results', v_check_results,
            'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000
        )
    WHERE history_id = p_history_id;
END;
$$;


ALTER FUNCTION public.execute_health_checks(p_task_id bigint, p_history_id bigint, p_options jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 624 (class 1255 OID 196664)
-- Name: execute_maintenance(text[], jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.execute_maintenance(p_task_types text[] DEFAULT NULL::text[], p_options jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(tasks_executed integer, execution_details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_start_time timestamp;
    v_task record;
    v_history_id bigint;
    v_task_count integer := 0;
    v_results jsonb := '[]'::jsonb;
BEGIN
    v_start_time := clock_timestamp();

    -- Get due maintenance tasks
    FOR v_task IN 
        SELECT *
        FROM maintenance_tasks
        WHERE is_active = true
        AND (p_task_types IS NULL OR task_type = ANY(p_task_types))
        AND (
            next_run IS NULL 
            OR next_run <= CURRENT_TIMESTAMP
            OR (schedule_type = 'CONDITION' AND check_maintenance_condition(schedule_config))
        )
        ORDER BY next_run NULLS FIRST
    LOOP
        BEGIN
            -- Create history record
            INSERT INTO maintenance_history (
                task_id,
                status
            ) VALUES (
                v_task.task_id,
                'RUNNING'
            ) RETURNING history_id INTO v_history_id;

            -- Execute task based on type
            CASE v_task.task_type
                WHEN 'VACUUM' THEN
                    PERFORM execute_vacuum_maintenance(v_task.task_id, v_history_id, p_options);
                
                WHEN 'ANALYZE' THEN
                    PERFORM execute_analyze_maintenance(v_task.task_id, v_history_id, p_options);
                
                WHEN 'REINDEX' THEN
                    PERFORM execute_reindex_maintenance(v_task.task_id, v_history_id, p_options);
                
                WHEN 'HEALTH_CHECK' THEN
                    PERFORM execute_health_checks(v_task.task_id, v_history_id, p_options);
                
                WHEN 'CUSTOM' THEN
                    PERFORM execute_custom_maintenance(v_task.task_id, v_history_id, p_options);
            END CASE;

            -- Update task next run time
            UPDATE maintenance_tasks
            SET 
                last_run = v_start_time,
                next_run = calculate_next_run(schedule_type, schedule_config, v_start_time),
                updated_at = clock_timestamp()
            WHERE task_id = v_task.task_id;

            v_task_count := v_task_count + 1;
            v_results := v_results || jsonb_build_object(
                'task_id', v_task.task_id,
                'task_name', v_task.task_name,
                'status', 'COMPLETED'
            );

        EXCEPTION WHEN OTHERS THEN
            -- Update history with error
            UPDATE maintenance_history
            SET 
                status = 'FAILED',
                end_time = clock_timestamp(),
                error_details = jsonb_build_object(
                    'error', SQLERRM,
                    'context', SQLSTATE
                )
            WHERE history_id = v_history_id;

            v_results := v_results || jsonb_build_object(
                'task_id', v_task.task_id,
                'task_name', v_task.task_name,
                'status', 'FAILED',
                'error', SQLERRM
            );
        END;
    END LOOP;

    RETURN QUERY
    SELECT 
        v_task_count,
        jsonb_build_object(
            'start_time', v_start_time,
            'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000,
            'tasks', v_results
        );
END;
$$;


ALTER FUNCTION public.execute_maintenance(p_task_types text[], p_options jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 629 (class 1255 OID 196665)
-- Name: execute_maintenance_tasks(text[], boolean); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.execute_maintenance_tasks(p_task_types text[] DEFAULT NULL::text[], p_force_run boolean DEFAULT false) RETURNS TABLE(task_name text, execution_status text, execution_details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_task record;
    v_start_time timestamp;
    v_history_id bigint;
    v_status text;
    v_details jsonb;
BEGIN
    FOR v_task IN (
        SELECT *
        FROM maintenance_schedule ms
        WHERE is_active = true
        AND (p_force_run OR (next_run IS NULL OR next_run <= CURRENT_TIMESTAMP))
        AND (p_task_types IS NULL OR task_type = ANY(p_task_types))
        ORDER BY 
            CASE 
                WHEN task_type = 'VACUUM' THEN 1
                WHEN task_type = 'ANALYZE' THEN 2
                WHEN task_type = 'REINDEX' THEN 3
                WHEN task_type = 'OPTIMIZE' THEN 4
                ELSE 5
            END
    ) LOOP
        v_start_time := clock_timestamp();
        v_status := 'SUCCESS';
        
        -- Create history record
        INSERT INTO maintenance_history (schedule_id, status)
        VALUES (v_task.schedule_id, 'IN_PROGRESS')
        RETURNING history_id INTO v_history_id;
        
        BEGIN
            CASE v_task.task_type
                WHEN 'VACUUM' THEN
                    v_details := perform_vacuum_maintenance(
                        (v_task.configuration->>'table_filter')::text,
                        (v_task.configuration->>'vacuum_type')::text
                    );
                    
                WHEN 'ANALYZE' THEN
                    v_details := perform_analyze_maintenance(
                        (v_task.configuration->>'table_filter')::text,
                        (v_task.configuration->>'analysis_level')::text
                    );
                    
                WHEN 'REINDEX' THEN
                    v_details := perform_reindex_maintenance(
                        (v_task.configuration->>'index_filter')::text,
                        (v_task.configuration->>'concurrent')::boolean
                    );
                    
                WHEN 'OPTIMIZE' THEN
                    v_details := perform_query_optimization(
                        (v_task.configuration->>'min_calls')::integer,
                        (v_task.configuration->>'min_time')::interval
                    );
                    
                WHEN 'CLEANUP' THEN
                    v_details := perform_cleanup_maintenance(
                        (v_task.configuration->>'retention_days')::integer,
                        (v_task.configuration->>'batch_size')::integer
                    );
            END CASE;

            -- Update schedule
            UPDATE maintenance_schedule
            SET 
                last_run = v_start_time,
                next_run = v_start_time + frequency
            WHERE schedule_id = v_task.schedule_id;

        EXCEPTION WHEN OTHERS THEN
            v_status := 'ERROR';
            v_details := jsonb_build_object(
                'error_message', SQLERRM,
                'error_detail', SQLSTATE,
                'error_context', pg_exception_context()
            );
        END;

        -- Update history record
        UPDATE maintenance_history
        SET 
            end_time = clock_timestamp(),
            status = v_status,
            affected_objects = v_details,
            performance_impact = jsonb_build_object(
                'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000,
                'cpu_impact', pg_stat_get_cpu_usage()
            ),
            error_details = CASE WHEN v_status = 'ERROR' THEN v_details->>'error_message' ELSE NULL END
        WHERE history_id = v_history_id;

        task_name := v_task.task_name;
        execution_status := v_status;
        execution_details := v_details;
        
        RETURN NEXT;
    END LOOP;
END;
$$;


ALTER FUNCTION public.execute_maintenance_tasks(p_task_types text[], p_force_run boolean) OWNER TO "prosper-dev_owner";

--
-- TOC entry 603 (class 1255 OID 196666)
-- Name: execute_sql_step(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.execute_sql_step(p_step_data jsonb, p_context jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_query text;
    v_result jsonb;
BEGIN
    -- Replace context variables in query
    v_query := replace_context_variables(
        p_step_data->>'sql',
        p_context
    );

    -- Execute query
    EXECUTE format('SELECT row_to_json(t)::jsonb FROM (%s) t', v_query)
    INTO v_result;

    RETURN v_result;
END;
$$;


ALTER FUNCTION public.execute_sql_step(p_step_data jsonb, p_context jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 621 (class 1255 OID 196667)
-- Name: execute_test_suite(text, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.execute_test_suite(p_suite_name text, p_options jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(suite_name text, tests_total integer, tests_passed integer, execution_details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_suite record;
    v_test record;
    v_start_time timestamp;
    v_result jsonb;
    v_passed_count integer := 0;
    v_failed_count integer := 0;
    v_error_count integer := 0;
    v_execution_id bigint;
    v_test_results jsonb := '[]'::jsonb;
BEGIN
    -- Get suite details
    SELECT * INTO v_suite
    FROM test_suites
    WHERE suite_name = p_suite_name AND is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Test suite % not found', p_suite_name;
    END IF;

    -- Execute each test case
    FOR v_test IN (
        SELECT *
        FROM test_cases
        WHERE suite_id = v_suite.suite_id
        AND is_active = true
        ORDER BY test_id
    ) LOOP
        v_start_time := clock_timestamp();
        
        -- Create execution record
        INSERT INTO test_executions (
            test_id,
            status
        ) VALUES (
            v_test.test_id,
            'RUNNING'
        ) RETURNING execution_id INTO v_execution_id;

        BEGIN
            -- Execute test with timeout
            PERFORM set_config('statement_timeout', 
                             (EXTRACT(EPOCH FROM v_test.timeout) * 1000)::text, 
                             false);

            EXECUTE v_test.test_query INTO v_result;

            -- Validate result
            IF jsonb_typeof(v_result) = jsonb_typeof(v_test.expected_result) AND
               v_result @> v_test.expected_result AND 
               v_test.expected_result @> v_result THEN
                v_passed_count := v_passed_count + 1;
                
                UPDATE test_executions
                SET 
                    status = 'PASSED',
                    execution_end = clock_timestamp(),
                    actual_result = v_result,
                    execution_details = jsonb_build_object(
                        'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000,
                        'comparison', 'EXACT_MATCH'
                    )
                WHERE execution_id = v_execution_id;
            ELSE
                v_failed_count := v_failed_count + 1;
                
                UPDATE test_executions
                SET 
                    status = 'FAILED',
                    execution_end = clock_timestamp(),
                    actual_result = v_result,
                    execution_details = jsonb_build_object(
                        'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000,
                        'comparison', 'MISMATCH',
                        'diff', jsonb_diff_val(v_test.expected_result, v_result)
                    )
                WHERE execution_id = v_execution_id;
            END IF;

        EXCEPTION WHEN OTHERS THEN
            v_error_count := v_error_count + 1;
            
            UPDATE test_executions
            SET 
                status = 'ERROR',
                execution_end = clock_timestamp(),
                execution_details = jsonb_build_object(
                    'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000,
                    'error_message', SQLERRM,
                    'error_detail', SQLSTATE,
                    'error_context', pg_exception_context()
                )
            WHERE execution_id = v_execution_id;
        END;

        -- Collect test results
        SELECT jsonb_build_object(
            'test_name', v_test.test_name,
            'status', status,
            'duration_ms', EXTRACT(EPOCH FROM (execution_end - execution_start)) * 1000,
            'details', execution_details
        ) INTO v_result
        FROM test_executions
        WHERE execution_id = v_execution_id;

        v_test_results := v_test_results || v_result;
    END LOOP;

    RETURN QUERY
    SELECT 
        v_suite.suite_name,
        v_passed_count + v_failed_count + v_error_count,
        v_passed_count,
        jsonb_build_object(
            'execution_time', clock_timestamp(),
            'suite_type', v_suite.suite_type,
            'summary', jsonb_build_object(
                'total', v_passed_count + v_failed_count + v_error_count,
                'passed', v_passed_count,
                'failed', v_failed_count,
                'errors', v_error_count
            ),
            'test_results', v_test_results,
            'options', p_options
        );
END;
$$;


ALTER FUNCTION public.execute_test_suite(p_suite_name text, p_options jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 626 (class 1255 OID 196668)
-- Name: execute_vacuum_maintenance(bigint, bigint, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.execute_vacuum_maintenance(p_task_id bigint, p_history_id bigint, p_options jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_table record;
    v_affected_objects jsonb := '[]'::jsonb;
    v_start_time timestamp;
BEGIN
    v_start_time := clock_timestamp();

    -- Find tables needing vacuum
    FOR v_table IN 
        SELECT 
            schemaname,
            tablename,
            n_dead_tup,
            n_live_tup,
            last_vacuum,
            last_autovacuum
        FROM pg_stat_user_tables
        WHERE n_dead_tup > 1000
        OR last_vacuum IS NULL
        OR last_vacuum < CURRENT_TIMESTAMP - interval '1 day'
    LOOP
        BEGIN
            -- Execute vacuum
            EXECUTE format(
                'VACUUM ANALYZE %I.%I',
                v_table.schemaname,
                v_table.tablename
            );

            v_affected_objects := v_affected_objects || jsonb_build_object(
                'schema', v_table.schemaname,
                'table', v_table.tablename,
                'dead_tuples', v_table.n_dead_tup,
                'live_tuples', v_table.n_live_tup
            );

        EXCEPTION WHEN OTHERS THEN
            -- Log error but continue with other tables
            RAISE WARNING 'Error vacuuming %.%: %', 
                v_table.schemaname, v_table.tablename, SQLERRM;
        END;
    END LOOP;

    -- Update maintenance history
    UPDATE maintenance_history
    SET 
        status = 'COMPLETED',
        end_time = clock_timestamp(),
        affected_objects = v_affected_objects,
        execution_details = jsonb_build_object(
            'tables_processed', jsonb_array_length(v_affected_objects),
            'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000
        )
    WHERE history_id = p_history_id;
END;
$$;


ALTER FUNCTION public.execute_vacuum_maintenance(p_task_id bigint, p_history_id bigint, p_options jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 554 (class 1255 OID 196669)
-- Name: execute_workflow(bigint, text, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.execute_workflow(p_workflow_id bigint, p_trigger_source text, p_parameters jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(success boolean, execution_id bigint, execution_details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_workflow record;
    v_execution_id bigint;
    v_step record;
    v_step_result jsonb;
    v_context jsonb := '{}';
    v_start_time timestamp;
BEGIN
    -- Get workflow definition
    SELECT * INTO v_workflow
    FROM automation_workflows
    WHERE workflow_id = p_workflow_id AND is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Workflow ID % not found or inactive', p_workflow_id;
    END IF;

    v_start_time := clock_timestamp();

    -- Create execution record
    INSERT INTO workflow_executions (
        workflow_id,
        trigger_source,
        execution_data
    ) VALUES (
        p_workflow_id,
        p_trigger_source,
        jsonb_build_object(
            'parameters', p_parameters,
            'start_time', v_start_time
        )
    ) RETURNING execution_id INTO v_execution_id;

    -- Initialize context with parameters
    v_context := v_context || jsonb_build_object('parameters', p_parameters);

    -- Execute each step
    FOR v_step IN 
        SELECT *
        FROM jsonb_array_elements(v_workflow.steps) WITH ORDINALITY AS steps(step_data, step_number)
    LOOP
        BEGIN
            -- Log step start
            INSERT INTO workflow_step_logs (
                execution_id,
                step_number,
                step_name,
                status
            ) VALUES (
                v_execution_id,
                v_step.step_number,
                v_step.step_data->>'name',
                'RUNNING'
            );

            -- Execute step based on type
            v_step_result := execute_workflow_step(
                v_step.step_data,
                v_context
            );

            -- Update step log
            UPDATE workflow_step_logs
            SET 
                status = 'COMPLETED',
                completed_at = clock_timestamp(),
                output_data = v_step_result
            WHERE execution_id = v_execution_id
            AND step_number = v_step.step_number;

            -- Update context with step output
            v_context := v_context || jsonb_build_object(
                format('step_%s_output', v_step.step_number),
                v_step_result
            );

        EXCEPTION WHEN OTHERS THEN
            -- Log step error
            UPDATE workflow_step_logs
            SET 
                status = 'FAILED',
                completed_at = clock_timestamp(),
                error_details = jsonb_build_object(
                    'error', SQLERRM,
                    'context', SQLSTATE,
                    'stack_trace', pg_exception_context()
                )
            WHERE execution_id = v_execution_id
            AND step_number = v_step.step_number;

            -- Update execution status
            UPDATE workflow_executions
            SET 
                status = 'FAILED',
                completed_at = clock_timestamp(),
                error_details = jsonb_build_object(
                    'step_number', v_step.step_number,
                    'error', SQLERRM,
                    'context', SQLSTATE
                )
            WHERE execution_id = v_execution_id;

            RETURN QUERY
            SELECT 
                false,
                v_execution_id,
                jsonb_build_object(
                    'error', SQLERRM,
                    'failed_step', v_step.step_number,
                    'execution_time', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time))
                );
            RETURN;
        END;
    END LOOP;

    -- Update workflow last run time
    UPDATE automation_workflows
    SET 
        last_run = v_start_time,
        updated_at = clock_timestamp()
    WHERE workflow_id = p_workflow_id;

    -- Update execution status
    UPDATE workflow_executions
    SET 
        status = 'COMPLETED',
        completed_at = clock_timestamp(),
        execution_data = execution_data || jsonb_build_object(
            'context', v_context,
            'execution_time', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time))
        )
    WHERE execution_id = v_execution_id;

    RETURN QUERY
    SELECT 
        true,
        v_execution_id,
        jsonb_build_object(
            'workflow_name', v_workflow.workflow_name,
            'execution_time', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)),
            'steps_completed', jsonb_array_length(v_workflow.steps),
            'context', v_context
        );
END;
$$;


ALTER FUNCTION public.execute_workflow(p_workflow_id bigint, p_trigger_source text, p_parameters jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 623 (class 1255 OID 196670)
-- Name: execute_workflow_step(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.execute_workflow_step(p_step_data jsonb, p_context jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_step_type text;
    v_result jsonb;
BEGIN
    v_step_type := p_step_data->>'type';

    CASE v_step_type
        WHEN 'SQL' THEN
            v_result := execute_sql_step(p_step_data, p_context);
        WHEN 'FUNCTION' THEN
            v_result := execute_function_step(p_step_data, p_context);
        WHEN 'HTTP' THEN
            v_result := execute_http_step(p_step_data, p_context);
        WHEN 'CONDITION' THEN
            v_result := execute_condition_step(p_step_data, p_context);
        WHEN 'TRANSFORM' THEN
            v_result := execute_transform_step(p_step_data, p_context);
        ELSE
            RAISE EXCEPTION 'Unsupported step type: %', v_step_type;
    END CASE;

    RETURN v_result;
END;
$$;


ALTER FUNCTION public.execute_workflow_step(p_step_data jsonb, p_context jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 606 (class 1255 OID 196671)
-- Name: export_prosper_report(text, integer, integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.export_prosper_report(p_format text DEFAULT 'JSON'::text, p_department_id integer DEFAULT NULL::integer, p_date_range_months integer DEFAULT 3) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_export_data jsonb;
    v_csv_output TEXT := '';
BEGIN
    -- Gather comprehensive performance data
    WITH PerformanceData AS (
        SELECT 
            ep.employee_id,
            ep.employee_name,
            d.department_name,
            m.manager_name,
            ps.category,
            ps.self_score,
            ps.manager_score,
            ps.challenge_score,
            ps.evaluation_date,
            ROUND((COALESCE(ps.self_score, 0) + COALESCE(ps.manager_score, 0) + 
                   COALESCE(ps.challenge_score, 0)) / 3, 2) as avg_score
        FROM Employee_Performance ep
        JOIN Department d ON ep.department_id = d.department_id
        JOIN Manager m ON d.manager_id = m.manager_id
        JOIN Performance_Scores ps ON ep.employee_id = ps.employee_id
        WHERE (p_department_id IS NULL OR ep.department_id = p_department_id)
        AND ps.evaluation_date >= CURRENT_DATE - (p_date_range_months || ' months')::interval
    )
    SELECT jsonb_build_object(
        'export_date', CURRENT_TIMESTAMP,
        'parameters', jsonb_build_object(
            'department_id', p_department_id,
            'date_range_months', p_date_range_months
        ),
        'data', jsonb_agg(
            jsonb_build_object(
                'employee', employee_name,
                'department', department_name,
                'manager', manager_name,
                'category', category,
                'scores', jsonb_build_object(
                    'self', self_score,
                    'manager', manager_score,
                    'challenge', challenge_score,
                    'average', avg_score
                ),
                'evaluation_date', evaluation_date
            )
        )
    ) INTO v_export_data
    FROM PerformanceData;

    -- Format output based on requested format
    CASE p_format
        WHEN 'JSON' THEN
            RETURN v_export_data::TEXT;
        WHEN 'CSV' THEN
            -- Convert JSON to CSV format
            SELECT string_agg(
                format('%s,%s,%s,%s,%s,%s,%s,%s,%s',
                    employee_name,
                    department_name,
                    manager_name,
                    category,
                    self_score,
                    manager_score,
                    challenge_score,
                    avg_score,
                    evaluation_date
                ),
                E'\n'
            ) INTO v_csv_output
            FROM PerformanceData;
            RETURN 'Employee,Department,Manager,Category,Self Score,Manager Score,Challenge Score,Average Score,Evaluation Date' 
                   || E'\n' || v_csv_output;
        ELSE
            RAISE EXCEPTION 'Unsupported export format: %', p_format;
    END CASE;
END;
$$;


ALTER FUNCTION public.export_prosper_report(p_format text, p_department_id integer, p_date_range_months integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 631 (class 1255 OID 196672)
-- Name: generate_api_key(text, jsonb, integer, interval); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.generate_api_key(p_client_name text, p_permissions jsonb DEFAULT NULL::jsonb, p_rate_limit integer DEFAULT NULL::integer, p_expires_in interval DEFAULT NULL::interval) RETURNS TABLE(success boolean, api_key text, details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_api_key text;
    v_key_id bigint;
BEGIN
    -- Generate unique API key
    v_api_key := encode(gen_random_bytes(32), 'hex');

    -- Insert new API key
    INSERT INTO api_keys (
        api_key,
        client_name,
        permissions,
        rate_limit,
        expires_at
    ) VALUES (
        v_api_key,
        p_client_name,
        COALESCE(p_permissions, '{}'::jsonb),
        p_rate_limit,
        CASE 
            WHEN p_expires_in IS NOT NULL 
            THEN CURRENT_TIMESTAMP + p_expires_in
            ELSE NULL 
        END
    ) RETURNING key_id INTO v_key_id;

    RETURN QUERY SELECT 
        true, 
        v_api_key,
        jsonb_build_object(
            'key_id', v_key_id,
            'client_name', p_client_name,
            'expires_at', CASE 
                WHEN p_expires_in IS NOT NULL 
                THEN CURRENT_TIMESTAMP + p_expires_in
                ELSE NULL 
            END,
            'permissions', COALESCE(p_permissions, '{}'::jsonb)
        );
END;
$$;


ALTER FUNCTION public.generate_api_key(p_client_name text, p_permissions jsonb, p_rate_limit integer, p_expires_in interval) OWNER TO "prosper-dev_owner";

--
-- TOC entry 546 (class 1255 OID 196673)
-- Name: generate_performance_report(timestamp without time zone, timestamp without time zone, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.generate_performance_report(p_start_date timestamp without time zone, p_end_date timestamp without time zone, p_config jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_report_data jsonb;
BEGIN
    SELECT jsonb_build_object(
        'overview', (
            SELECT jsonb_build_object(
                'total_queries', COUNT(*),
                'avg_query_time', AVG(EXTRACT(EPOCH FROM total_exec_time)),
                'max_query_time', MAX(EXTRACT(EPOCH FROM total_exec_time)),
                'total_rows', SUM(rows)
            )
            FROM pg_stat_statements
            WHERE query_start >= p_start_date
            AND query_start < p_end_date
        ),
        'metrics', (
            SELECT jsonb_agg(metric_data)
            FROM (
                SELECT 
                    metric_name,
                    jsonb_build_object(
                        'min', MIN(metric_value),
                        'max', MAX(metric_value),
                        'avg', AVG(metric_value),
                        'samples', COUNT(*)
                    ) as metric_data
                FROM monitoring_metrics
                WHERE collection_timestamp BETWEEN p_start_date AND p_end_date
                GROUP BY metric_name
            ) metrics
        ),
        'top_queries', (
            SELECT jsonb_agg(query_data)
            FROM (
                SELECT jsonb_build_object(
                    'query', query,
                    'calls', calls,
                    'total_time', total_exec_time,
                    'avg_time', mean_exec_time,
                    'rows', rows
                ) as query_data
                FROM pg_stat_statements
                WHERE query_start >= p_start_date
                AND query_start < p_end_date
                ORDER BY total_exec_time DESC
                LIMIT COALESCE((p_config->>'top_queries_limit')::integer, 10)
            ) top_queries
        )
    ) INTO v_report_data;

    RETURN v_report_data;
END;
$$;


ALTER FUNCTION public.generate_performance_report(p_start_date timestamp without time zone, p_end_date timestamp without time zone, p_config jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 574 (class 1255 OID 196674)
-- Name: generate_security_report(timestamp without time zone, timestamp without time zone, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.generate_security_report(p_start_date timestamp without time zone, p_end_date timestamp without time zone, p_config jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_report_data jsonb;
BEGIN
    SELECT jsonb_build_object(
        'security_events', (
            SELECT jsonb_build_object(
                'total_events', COUNT(*),
                'by_severity', jsonb_object_agg(
                    severity, event_count
                ),
                'top_event_types', jsonb_object_agg(
                    event_type, event_count
                )
            )
            FROM (
                SELECT 
                    severity,
                    COUNT(*) as event_count
                FROM security_events
                WHERE event_time BETWEEN p_start_date AND p_end_date
                GROUP BY severity
            ) severity_counts,
            LATERAL (
                SELECT 
                    event_type,
                    COUNT(*) as event_count
                FROM security_events
                WHERE event_time BETWEEN p_start_date AND p_end_date
                GROUP BY event_type
                ORDER BY COUNT(*) DESC
                LIMIT COALESCE((p_config->>'top_events_limit')::integer, 10)
            ) event_types
        ),
        'alerts', (
            SELECT jsonb_build_object(
                'total_alerts', COUNT(*),
                'unresolved_alerts', COUNT(*) FILTER (WHERE resolved_at IS NULL),
                'avg_resolution_time', AVG(EXTRACT(EPOCH FROM (resolved_at - triggered_at))) FILTER (WHERE resolved_at IS NOT NULL)
            )
            FROM alert_history
            WHERE triggered_at BETWEEN p_start_date AND p_end_date
        )
    ) INTO v_report_data;

    RETURN v_report_data;
END;
$$;


ALTER FUNCTION public.generate_security_report(p_start_date timestamp without time zone, p_end_date timestamp without time zone, p_config jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 548 (class 1255 OID 196675)
-- Name: generate_system_report(bigint, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.generate_system_report(p_report_id bigint, p_parameters jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(success boolean, report_data jsonb, visualization_data jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_report record;
    v_start_time timestamp;
    v_execution_id bigint;
    v_query text;
    v_result jsonb;
    v_visualization jsonb;
BEGIN
    -- Get report definition
    SELECT * INTO v_report
    FROM report_definitions
    WHERE report_id = p_report_id AND is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Report ID % not found or inactive', p_report_id;
    END IF;

    v_start_time := clock_timestamp();

    -- Create execution record
    INSERT INTO report_executions (
        report_id,
        execution_metadata
    ) VALUES (
        p_report_id,
        jsonb_build_object(
            'parameters', p_parameters,
            'user', current_user,
            'database', current_database()
        )
    ) RETURNING execution_id INTO v_execution_id;

    BEGIN
        -- Build and execute query
        v_query := build_report_query(v_report.query_definition, p_parameters);
        EXECUTE v_query INTO v_result;

        -- Generate visualization if configured
        IF v_report.visualization_config IS NOT NULL THEN
            v_visualization := generate_visualization(
                v_result,
                v_report.visualization_config
            );
        END IF;

        -- Update execution record
        UPDATE report_executions
        SET 
            status = 'COMPLETED',
            execution_end = clock_timestamp(),
            result_data = v_result,
            visualization_data = v_visualization
        WHERE execution_id = v_execution_id;

        RETURN QUERY
        SELECT 
            true,
            v_result,
            v_visualization;

    EXCEPTION WHEN OTHERS THEN
        -- Update execution record with error
        UPDATE report_executions
        SET 
            status = 'FAILED',
            execution_end = clock_timestamp(),
            execution_metadata = execution_metadata || jsonb_build_object(
                'error', SQLERRM,
                'context', SQLSTATE
            )
        WHERE execution_id = v_execution_id;

        RETURN QUERY
        SELECT 
            false,
            jsonb_build_object('error', SQLERRM),
            NULL::jsonb;
    END;
END;
$$;


ALTER FUNCTION public.generate_system_report(p_report_id bigint, p_parameters jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 560 (class 1255 OID 196676)
-- Name: generate_system_report(bigint, timestamp without time zone, timestamp without time zone, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.generate_system_report(p_template_id bigint, p_start_date timestamp without time zone DEFAULT (CURRENT_TIMESTAMP - '24:00:00'::interval), p_end_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP, p_options jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(report_id bigint, report_data jsonb, generation_details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_template record;
    v_report_id bigint;
    v_report_data jsonb;
    v_start_time timestamp := clock_timestamp();
BEGIN
    -- Get template
    SELECT * INTO v_template
    FROM report_templates
    WHERE template_id = p_template_id AND is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Template ID % not found or inactive', p_template_id;
    END IF;

    -- Create report record
    INSERT INTO report_history (
        template_id,
        report_metadata
    ) VALUES (
        p_template_id,
        jsonb_build_object(
            'start_date', p_start_date,
            'end_date', p_end_date,
            'options', p_options,
            'template_name', v_template.template_name,
            'template_type', v_template.template_type
        )
    ) RETURNING report_id INTO v_report_id;

    -- Generate report based on template type
    CASE v_template.template_type
        WHEN 'PERFORMANCE' THEN
            v_report_data := generate_performance_report(
                p_start_date,
                p_end_date,
                v_template.template_config
            );
            
        WHEN 'SECURITY' THEN
            v_report_data := generate_security_report(
                p_start_date,
                p_end_date,
                v_template.template_config
            );
            
        WHEN 'MAINTENANCE' THEN
            v_report_data := generate_maintenance_report(
                p_start_date,
                p_end_date,
                v_template.template_config
            );
            
        WHEN 'CUSTOM' THEN
            v_report_data := generate_custom_report(
                p_start_date,
                p_end_date,
                v_template.template_config,
                p_options
            );
    END CASE;

    -- Update report record
    UPDATE report_history
    SET 
        status = 'COMPLETED',
        generation_end = clock_timestamp(),
        report_data = v_report_data
    WHERE report_id = v_report_id;

    -- Return results
    RETURN QUERY
    SELECT 
        v_report_id,
        v_report_data,
        jsonb_build_object(
            'generation_time_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000,
            'template_type', v_template.template_type,
            'date_range', jsonb_build_object(
                'start_date', p_start_date,
                'end_date', p_end_date
            )
        );
END;
$$;


ALTER FUNCTION public.generate_system_report(p_template_id bigint, p_start_date timestamp without time zone, p_end_date timestamp without time zone, p_options jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 620 (class 1255 OID 196677)
-- Name: generate_time_series_visualization(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.generate_time_series_visualization(p_data jsonb, p_config jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_result jsonb;
    v_series jsonb;
    v_record jsonb;
BEGIN
    v_result := jsonb_build_object(
        'labels', ARRAY[]::text[],
        'datasets', '[]'::jsonb
    );

    -- Extract time series data
    SELECT 
        jsonb_agg(
            jsonb_build_object(
                'label', key,
                'data', (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'x', (value->>'timestamp'),
                            'y', (value->>'value')::numeric
                        )
                        ORDER BY (value->>'timestamp')
                    )
                    FROM jsonb_array_elements(value->'values')
                )
            )
        )
    INTO v_series
    FROM jsonb_each(p_data);

    RETURN jsonb_build_object(
        'series', v_series,
        'options', jsonb_build_object(
            'title', p_config->>'title',
            'x_axis_label', p_config->>'x_axis_label',
            'y_axis_label', p_config->>'y_axis_label'
        )
    );
END;
$$;


ALTER FUNCTION public.generate_time_series_visualization(p_data jsonb, p_config jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 555 (class 1255 OID 196678)
-- Name: generate_visualization(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.generate_visualization(p_data jsonb, p_config jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_visualization_type text;
    v_result jsonb;
BEGIN
    v_visualization_type := p_config->>'type';

    CASE v_visualization_type
        WHEN 'TIME_SERIES' THEN
            v_result := generate_time_series_visualization(p_data, p_config);
        WHEN 'BAR_CHART' THEN
            v_result := generate_bar_chart_visualization(p_data, p_config);
        WHEN 'PIE_CHART' THEN
            v_result := generate_pie_chart_visualization(p_data, p_config);
        WHEN 'TABLE' THEN
            v_result := generate_table_visualization(p_data, p_config);
        WHEN 'METRICS' THEN
            v_result := generate_metrics_visualization(p_data, p_config);
        ELSE
            RAISE EXCEPTION 'Unsupported visualization type: %', v_visualization_type;
    END CASE;

    RETURN jsonb_build_object(
        'type', v_visualization_type,
        'data', v_result,
        'config', p_config
    );
END;
$$;


ALTER FUNCTION public.generate_visualization(p_data jsonb, p_config jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 549 (class 1255 OID 196679)
-- Name: get_challenge_completion_rate(integer, numeric); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.get_challenge_completion_rate(p_department_id integer DEFAULT NULL::integer, p_threshold numeric DEFAULT 80) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    total_count INT;
    passing_count INT;
BEGIN
    IF p_Department_ID IS NULL THEN
        -- Calculate for all departments
        SELECT 
            COUNT(*),
            COUNT(CASE WHEN Challenge_Score >= p_Threshold THEN 1 END)
        INTO total_count, passing_count
        FROM Employee_Performance;
    ELSE
        -- Calculate for specific department
        SELECT 
            COUNT(*),
            COUNT(CASE WHEN Challenge_Score >= p_Threshold THEN 1 END)
        INTO total_count, passing_count
        FROM Employee_Performance
        WHERE Department_ID = p_Department_ID;
    END IF;

    RETURN ROUND((passing_count::DECIMAL / NULLIF(total_count, 0)) * 100, 2);
END;
$$;


ALTER FUNCTION public.get_challenge_completion_rate(p_department_id integer, p_threshold numeric) OWNER TO "prosper-dev_owner";

--
-- TOC entry 558 (class 1255 OID 196680)
-- Name: get_department_average(integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.get_department_average(p_department_id integer) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN (
        SELECT ROUND(AVG(Average_Score), 2)
        FROM Employee_Performance
        WHERE Department_ID = p_Department_ID
    );
END;
$$;


ALTER FUNCTION public.get_department_average(p_department_id integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 564 (class 1255 OID 196681)
-- Name: get_performance_trend(integer, integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.get_performance_trend(p_employee_id integer, p_periods integer DEFAULT 3) RETURNS TABLE(evaluation_date date, average_score numeric, score_change numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH RankedScores AS (
        SELECT 
            Evaluation_Date,
            Average_Score,
            LAG(Average_Score) OVER (ORDER BY Evaluation_Date) as Previous_Score
        FROM Employee_Performance
        WHERE Employee_ID = p_Employee_ID
        ORDER BY Evaluation_Date DESC
        LIMIT p_Periods
    )
    SELECT 
        rs.Evaluation_Date,
        rs.Average_Score,
        COALESCE(rs.Average_Score - rs.Previous_Score, 0) as Score_Change
    FROM RankedScores rs
    ORDER BY rs.Evaluation_Date DESC;
END;
$$;


ALTER FUNCTION public.get_performance_trend(p_employee_id integer, p_periods integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 530 (class 1255 OID 196682)
-- Name: get_security_status_summary(integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.get_security_status_summary(p_hours_back integer DEFAULT 24) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_result jsonb;
BEGIN
    SELECT jsonb_build_object(
        'time_range', jsonb_build_object(
            'start', CURRENT_TIMESTAMP - (p_hours_back || ' hours')::interval,
            'end', CURRENT_TIMESTAMP
        ),
        'event_summary', (
            SELECT jsonb_object_agg(
                event_type, event_count
            )
            FROM security_events_summary
        ),
        'active_alerts', (
            SELECT COUNT(*)
            FROM security_notifications
            WHERE notification_status = 'PENDING'
        ),
        'critical_events', (
            SELECT COUNT(*)
            FROM security_events
            WHERE severity = 'CRITICAL'
            AND event_time > CURRENT_TIMESTAMP - (p_hours_back || ' hours')::interval
        ),
        'latest_notifications', (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'type', notification_type,
                    'severity', severity,
                    'created_at', created_at,
                    'status', notification_status
                )
            )
            FROM (
                SELECT *
                FROM security_notifications
                ORDER BY created_at DESC
                LIMIT 5
            ) recent
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;


ALTER FUNCTION public.get_security_status_summary(p_hours_back integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 573 (class 1255 OID 196683)
-- Name: identify_portfolio_improvements(integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.identify_portfolio_improvements(p_employee_id integer) RETURNS TABLE(portfolio_type text, focus_area text, current_score numeric, target_score numeric, gap_size numeric, priority text, improvement_actions jsonb)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH latest_scores AS (
        SELECT 
            portfolio_type,
            self_score,
            manager_score,
            challenge_score,
            average_score,
            ROW_NUMBER() OVER (
                PARTITION BY portfolio_type 
                ORDER BY evaluation_date DESC
            ) as rn
        FROM public.portfolio_analysis_view
        WHERE employee_id = p_employee_id
    )
    SELECT 
        ls.portfolio_type,
        CASE 
            WHEN ls.self_score < ls.manager_score THEN 'Self Assessment'
            WHEN ls.challenge_score < ls.average_score THEN 'Challenge Score'
            ELSE 'Overall Performance'
        END as focus_area,
        ls.average_score as current_score,
        GREATEST(8.0, ls.average_score + 1) as target_score,
        GREATEST(8.0, ls.average_score + 1) - ls.average_score as gap_size,
        CASE 
            WHEN ls.average_score < 6 THEN 'High'
            WHEN ls.average_score < 7 THEN 'Medium'
            ELSE 'Low'
        END as priority,
        jsonb_build_object(
            'recommended_actions', CASE 
                WHEN ls.average_score < 6 THEN 
                    jsonb_build_array(
                        'Schedule immediate coaching session',
                        'Create detailed improvement plan',
                        'Weekly progress reviews'
                    )
                WHEN ls.average_score < 7 THEN 
                    jsonb_build_array(
                        'Identify specific improvement areas',
                        'Monthly progress reviews',
                        'Peer mentoring'
                    )
                ELSE 
                    jsonb_build_array(
                        'Maintain current performance',
                        'Share best practices',
                        'Mentor others'
                    )
            END,
            'timeline_months', CASE 
                WHEN ls.average_score < 6 THEN 3
                WHEN ls.average_score < 7 THEN 6
                ELSE 12
            END,
            'score_breakdown', jsonb_build_object(
                'self_score', ls.self_score,
                'manager_score', ls.manager_score,
                'challenge_score', ls.challenge_score,
                'average_score', ls.average_score
            )
        ) as improvement_actions
    FROM latest_scores ls
    WHERE ls.rn = 1
    ORDER BY ls.average_score;
END;
$$;


ALTER FUNCTION public.identify_portfolio_improvements(p_employee_id integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 550 (class 1255 OID 196684)
-- Name: identify_skill_gaps(integer, numeric); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.identify_skill_gaps(p_department_id integer DEFAULT NULL::integer, p_threshold numeric DEFAULT 7.0) RETURNS TABLE(category public.prosper_category, avg_score numeric, gap_size numeric, affected_employees integer, priority_level character varying, recommended_actions jsonb)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH department_scores AS (
        SELECT 
            CASE 
                WHEN pds.score_id IS NOT NULL THEN 'PORTFOLIO'::prosper_category
                WHEN ppe.score_id IS NOT NULL THEN 'RELATIONSHIP'::prosper_category
                WHEN pcs.score_id IS NOT NULL THEN 'OPERATIONS'::prosper_category
            END as category,
            emh.employee_id,
            COALESCE(pds.average_score, ppe.average_score, pcs.average_score) as score,
            COALESCE(pds.evaluation_date, ppe.evaluation_date, pcs.evaluation_date) as eval_date
        FROM employee_manager_hierarchy emh
        LEFT JOIN portfolio_design_success pds 
            ON emh.employee_id = pds.employee_id 
            AND pds.evaluation_date = (
                SELECT MAX(evaluation_date) 
                FROM portfolio_design_success 
                WHERE employee_id = emh.employee_id
            )
        LEFT JOIN portfolio_premium_engagement ppe 
            ON emh.employee_id = ppe.employee_id 
            AND ppe.evaluation_date = (
                SELECT MAX(evaluation_date) 
                FROM portfolio_premium_engagement 
                WHERE employee_id = emh.employee_id
            )
        LEFT JOIN portfolio_cloud_services pcs 
            ON emh.employee_id = pcs.employee_id 
            AND pcs.evaluation_date = (
                SELECT MAX(evaluation_date) 
                FROM portfolio_cloud_services 
                WHERE employee_id = emh.employee_id
            )
        WHERE (p_department_id IS NULL OR emh.department_id = p_department_id)
        AND COALESCE(pds.score_id, ppe.score_id, pcs.score_id) IS NOT NULL
    )
    SELECT 
        ds.category,
        ROUND(AVG(ds.score), 2) as avg_score,
        ROUND(p_threshold - AVG(ds.score), 2) as gap_size,
        COUNT(CASE WHEN ds.score < p_threshold THEN 1 END) as affected_employees,
        CASE 
            WHEN p_threshold - AVG(ds.score) >= 2 THEN 'Critical'
            WHEN p_threshold - AVG(ds.score) >= 1 THEN 'High'
            WHEN p_threshold - AVG(ds.score) > 0 THEN 'Medium'
            ELSE 'Low'
        END as priority_level,
        jsonb_build_object(
            'recommended_actions', 
            CASE 
                WHEN p_threshold - AVG(ds.score) >= 2 THEN jsonb_build_array(
                    'Immediate training intervention required',
                    'Schedule weekly coaching sessions',
                    'Develop detailed improvement plan'
                )
                WHEN p_threshold - AVG(ds.score) >= 1 THEN jsonb_build_array(
                    'Schedule monthly training sessions',
                    'Implement peer mentoring program',
                    'Regular progress reviews'
                )
                WHEN p_threshold - AVG(ds.score) > 0 THEN jsonb_build_array(
                    'Identify specific improvement areas',
                    'Optional skill enhancement workshops',
                    'Quarterly progress reviews'
                )
                ELSE jsonb_build_array(
                    'Maintain current performance',
                    'Share best practices',
                    'Consider mentoring others'
                )
            END,
            'timeline_months',
            CASE 
                WHEN p_threshold - AVG(ds.score) >= 2 THEN 3
                WHEN p_threshold - AVG(ds.score) >= 1 THEN 6
                ELSE 12
            END
        ) as recommended_actions
    FROM department_scores ds
    GROUP BY ds.category
    HAVING AVG(ds.score) < p_threshold
    ORDER BY p_threshold - AVG(ds.score) DESC;
END;
$$;


ALTER FUNCTION public.identify_skill_gaps(p_department_id integer, p_threshold numeric) OWNER TO "prosper-dev_owner";

--
-- TOC entry 595 (class 1255 OID 196685)
-- Name: initialize_default_configurations(text); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.initialize_default_configurations(p_modified_by text DEFAULT CURRENT_USER) RETURNS void
    LANGUAGE plpgsql
    AS $_$
BEGIN
    INSERT INTO system_configurations (
        config_name,
        config_value,
        config_type,
        description,
        validation_rules,
        modified_by
    ) VALUES 
    (
        'max_connections',
        '100',
        'DATABASE',
        'Maximum number of database connections',
        jsonb_build_object(
            'rules', jsonb_build_array(
                jsonb_build_object(
                    'type', 'range',
                    'min', 20,
                    'max', 1000,
                    'message', 'Value must be between 20 and 1000'
                )
            ),
            'fail_fast', true
        ),
        p_modified_by
    ),
    (
        'maintenance_window',
        '{"start": "00:00", "end": "04:00"}',
        'MAINTENANCE',
        'System maintenance window',
        jsonb_build_object(
            'rules', jsonb_build_array(
                jsonb_build_object(
                    'type', 'regex',
                    'pattern', '^{"start": "[0-2][0-9]:[0-5][0-9]", "end": "[0-2][0-9]:[0-5][0-9]"}$',
                    'message', 'Invalid time format'
                )
            )
        ),
        p_modified_by
    );
END;
$_$;


ALTER FUNCTION public.initialize_default_configurations(p_modified_by text) OWNER TO "prosper-dev_owner";

--
-- TOC entry 601 (class 1255 OID 196686)
-- Name: initialize_health_checks(); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.initialize_health_checks() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Performance checks
    INSERT INTO health_check_definitions (
        check_name,
        check_type,
        check_query,
        threshold_config,
        check_frequency
    ) VALUES 
    (
        'Cache Hit Ratio',
        'PERFORMANCE',
        'SELECT jsonb_build_object(
            ''value'', CASE WHEN blks_hit + blks_read = 0 THEN 100
                         ELSE (blks_hit::numeric / (blks_hit + blks_read) * 100)
                    END,
            ''metric'', ''percentage'',
            ''details'', jsonb_build_object(
                ''blocks_hit'', blks_hit,
                ''blocks_read'', blks_read
            )
        )
        FROM pg_stat_database
        WHERE datname = current_database()',
        '{"warning": 80, "critical": 50}',
        '5 minutes'
    ),
    (
        'Connection Utilization',
        'CAPACITY',
        'SELECT jsonb_build_object(
            ''value'', (COUNT(*)::numeric / current_setting(''max_connections'')::numeric * 100),
            ''metric'', ''percentage'',
            ''details'', jsonb_build_object(
                ''active_connections'', COUNT(*),
                ''max_connections'', current_setting(''max_connections'')
            )
        )
        FROM pg_stat_activity',
        '{"warning": 70, "critical": 90}',
        '1 minute'
    ),
    (
        'Transaction ID Wraparound',
        'INTEGRITY',
        'SELECT jsonb_build_object(
            ''value'', age(datfrozenxid),
            ''metric'', ''xid_age'',
            ''details'', jsonb_build_object(
                ''database'', datname,
                ''datfrozenxid'', datfrozenxid
            )
        )
        FROM pg_database
        WHERE datname = current_database()',
        '{"warning": 1000000000, "critical": 1500000000}',
        '1 hour'
    );
END;
$$;


ALTER FUNCTION public.initialize_health_checks() OWNER TO "prosper-dev_owner";

--
-- TOC entry 559 (class 1255 OID 196687)
-- Name: initialize_review_cycle(character varying, date, date, integer); Type: PROCEDURE; Schema: public; Owner: prosper-dev_owner
--

CREATE PROCEDURE public.initialize_review_cycle(IN p_cycle_name character varying, IN p_start_date date, IN p_end_date date, IN p_department_id integer DEFAULT NULL::integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_cycle_id INTEGER;
BEGIN
    -- Create review cycle
    INSERT INTO Review_Cycles (
        cycle_name, 
        start_date, 
        end_date, 
        status,
        participants,
        completion_status
    )
    VALUES (
        p_cycle_name,
        p_start_date,
        p_end_date,
        'Initiated',
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'employee_id', employee_id,
                    'status', 'Pending'
                )
            )
            FROM Employee_Manager_Hierarchy
            WHERE (p_department_id IS NULL OR department_id = p_department_id)
            AND active = true
        ),
        '{}'::jsonb
    )
    RETURNING cycle_id INTO v_cycle_id;

    -- Create evaluation submissions
    INSERT INTO Evaluation_Submissions (
        period_id,
        employee_id,
        category,
        status
    )
    SELECT 
        v_cycle_id,
        emh.employee_id,
        c.category,
        'Pending'
    FROM Employee_Manager_Hierarchy emh
    CROSS JOIN (
        SELECT DISTINCT category 
        FROM Performance_Scores
    ) c
    WHERE (p_department_id IS NULL OR emh.department_id = p_department_id)
    AND emh.active = true;

    -- Update system settings
    INSERT INTO System_Settings (
        setting_name,
        setting_value,
        category,
        description
    )
    VALUES (
        'active_review_cycle',
        jsonb_build_object(
            'cycle_id', v_cycle_id,
            'start_date', p_start_date,
            'end_date', p_end_date
        ),
        'REVIEW_CYCLE',
        'Currently active review cycle settings'
    )
    ON CONFLICT (setting_name) 
    DO UPDATE SET setting_value = EXCLUDED.setting_value;
END;
$$;


ALTER PROCEDURE public.initialize_review_cycle(IN p_cycle_name character varying, IN p_start_date date, IN p_end_date date, IN p_department_id integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 541 (class 1255 OID 196688)
-- Name: log_api_request(bigint, bigint, integer, jsonb, jsonb, interval); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.log_api_request(p_endpoint_id bigint, p_api_key_id bigint, p_status_code integer, p_request_details jsonb, p_response_details jsonb, p_response_time interval) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_request_id bigint;
BEGIN
    INSERT INTO api_requests (
        endpoint_id,
        api_key_id,
        status_code,
        request_details,
        response_details,
        response_time
    ) VALUES (
        p_endpoint_id,
        p_api_key_id,
        p_status_code,
        p_request_details,
        p_response_details,
        p_response_time
    ) RETURNING request_id INTO v_request_id;

    -- Update last_used_at timestamp for API key
    UPDATE api_keys
    SET last_used_at = CURRENT_TIMESTAMP
    WHERE key_id = p_api_key_id;

    RETURN v_request_id;
END;
$$;


ALTER FUNCTION public.log_api_request(p_endpoint_id bigint, p_api_key_id bigint, p_status_code integer, p_request_details jsonb, p_response_details jsonb, p_response_time interval) OWNER TO "prosper-dev_owner";

--
-- TOC entry 596 (class 1255 OID 196689)
-- Name: monitor_database_performance(interval); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.monitor_database_performance(p_collection_interval interval DEFAULT '00:05:00'::interval) RETURNS TABLE(metric_name text, current_value numeric, baseline_value numeric, deviation_percentage numeric, status text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_start_time timestamp := clock_timestamp();
BEGIN
    -- Collect current metrics
    INSERT INTO performance_metrics (
        metric_name,
        metric_value,
        metric_type,
        context_data
    )
    SELECT
        metric_name,
        metric_value,
        metric_type,
        context_data
    FROM (
        -- Query execution metrics
        SELECT 
            'avg_query_time' as metric_name,
            COALESCE(AVG(EXTRACT(EPOCH FROM total_exec_time)), 0) as metric_value,
            'QUERY'::text as metric_type,
            jsonb_build_object(
                'sample_size', COUNT(*),
                'max_time', MAX(EXTRACT(EPOCH FROM total_exec_time)),
                'min_time', MIN(EXTRACT(EPOCH FROM total_exec_time))
            ) as context_data
        FROM pg_stat_statements
        WHERE calls > 0
        AND last_call > v_start_time - p_collection_interval

        UNION ALL

        -- Table statistics
        SELECT 
            'table_bloat_ratio' as metric_name,
            AVG(n_dead_tup::numeric / NULLIF(n_live_tup, 0)) as metric_value,
            'SYSTEM'::text as metric_type,
            jsonb_build_object(
                'tables_analyzed', COUNT(*),
                'max_ratio', MAX(n_dead_tup::numeric / NULLIF(n_live_tup, 0)),
                'total_dead_tuples', SUM(n_dead_tup)
            ) as context_data
        FROM pg_stat_user_tables
        WHERE n_live_tup > 0

        UNION ALL

        -- Connection metrics
        SELECT 
            'active_connections' as metric_name,
            COUNT(*)::numeric as metric_value,
            'SYSTEM'::text as metric_type,
            jsonb_build_object(
                'idle_connections', SUM(CASE WHEN state = 'idle' THEN 1 ELSE 0 END),
                'active_connections', SUM(CASE WHEN state = 'active' THEN 1 ELSE 0 END),
                'waiting_connections', SUM(CASE WHEN wait_event IS NOT NULL THEN 1 ELSE 0 END)
            ) as context_data
        FROM pg_stat_activity
        WHERE datname = current_database()
    ) metrics;

    -- Update baselines
    INSERT INTO performance_baselines (
        metric_name,
        baseline_value,
        calculation_window,
        confidence_score,
        baseline_data
    )
    SELECT 
        pm.metric_name,
        AVG(pm.metric_value),
        p_collection_interval,
        LEAST(1.0, COUNT(*) / 100.0), -- Confidence score based on sample size
        jsonb_build_object(
            'sample_size', COUNT(*),
            'standard_deviation', stddev(pm.metric_value),
            'min_value', MIN(pm.metric_value),
            'max_value', MAX(pm.metric_value),
            'calculation_period', jsonb_build_object(
                'start_time', MIN(pm.collection_time),
                'end_time', MAX(pm.collection_time)
            )
        )
    FROM performance_metrics pm
    WHERE pm.collection_time > v_start_time - p_collection_interval
    GROUP BY pm.metric_name
    ON CONFLICT (metric_name) DO UPDATE
    SET 
        baseline_value = EXCLUDED.baseline_value,
        calculation_window = EXCLUDED.calculation_window,
        last_updated = CURRENT_TIMESTAMP,
        confidence_score = EXCLUDED.confidence_score,
        baseline_data = EXCLUDED.baseline_data;

    -- Return current status
    RETURN QUERY
    WITH current_metrics AS (
        SELECT 
            pm.metric_name,
            pm.metric_value as current_value,
            pb.baseline_value,
            CASE 
                WHEN pb.baseline_value = 0 THEN 0
                ELSE ((pm.metric_value - pb.baseline_value) / pb.baseline_value * 100)
            END as deviation
        FROM performance_metrics pm
        LEFT JOIN performance_baselines pb ON pm.metric_name = pb.metric_name
        WHERE pm.collection_time > v_start_time - interval '1 minute'
    )
    SELECT 
        cm.metric_name,
        cm.current_value,
        cm.baseline_value,
        cm.deviation,
        CASE 
            WHEN ABS(cm.deviation) > 50 THEN 'CRITICAL'
            WHEN ABS(cm.deviation) > 20 THEN 'WARNING'
            ELSE 'NORMAL'
        END as status
    FROM current_metrics cm
    ORDER BY ABS(cm.deviation) DESC;
END;
$$;


ALTER FUNCTION public.monitor_database_performance(p_collection_interval interval) OWNER TO "prosper-dev_owner";

--
-- TOC entry 605 (class 1255 OID 196690)
-- Name: monitor_security_events(integer, integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.monitor_security_events(p_lookback_hours integer DEFAULT 24, p_alert_threshold integer DEFAULT 5) RETURNS TABLE(event_type text, occurrence_count integer, latest_occurrence timestamp without time zone, severity text, details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_start_time timestamp := clock_timestamp();
    v_monitoring_period timestamp := v_start_time - (p_lookback_hours || ' hours')::interval;
BEGIN
    RETURN QUERY
    WITH security_metrics AS (
        SELECT 
            se.event_type,
            COUNT(*) as event_count,
            MAX(se.event_time) as latest_event,
            jsonb_agg(
                jsonb_build_object(
                    'time', se.event_time,
                    'ip_address', se.ip_address,
                    'user_id', se.user_id,
                    'details', se.event_details
                ) ORDER BY se.event_time DESC
            ) FILTER (WHERE se.event_time IN (
                SELECT event_time 
                FROM security_events se2 
                WHERE se2.event_type = se.event_type 
                ORDER BY event_time DESC 
                LIMIT 5
            )) as recent_events
        FROM security_events se
        WHERE se.event_time >= v_monitoring_period
        GROUP BY se.event_type
    )
    SELECT 
        sm.event_type,
        sm.event_count,
        sm.latest_event,
        CASE 
            WHEN sm.event_count >= p_alert_threshold * 2 THEN 'CRITICAL'
            WHEN sm.event_count >= p_alert_threshold THEN 'HIGH'
            ELSE 'NORMAL'
        END as severity,
        jsonb_build_object(
            'recent_events', sm.recent_events,
            'trend', (
                SELECT jsonb_build_object(
                    'previous_period_count', COUNT(*),
                    'change_percentage', 
                    CASE 
                        WHEN COUNT(*) = 0 THEN 100
                        ELSE ((sm.event_count::float - COUNT(*)::float) / COUNT(*)::float * 100)
                    END
                )
                FROM security_events se2
                WHERE se2.event_type = sm.event_type
                AND se2.event_time BETWEEN v_monitoring_period - (p_lookback_hours || ' hours')::interval 
                                     AND v_monitoring_period
            )
        ) as details
    FROM security_metrics sm
    ORDER BY 
        CASE 
            WHEN sm.event_count >= p_alert_threshold * 2 THEN 1
            WHEN sm.event_count >= p_alert_threshold THEN 2
            ELSE 3
        END,
        sm.event_count DESC;

    -- Log monitoring execution
    INSERT INTO security_monitoring_log (
        execution_time,
        lookback_hours,
        alert_threshold,
        execution_duration,
        findings
    )
    SELECT
        v_start_time,
        p_lookback_hours,
        p_alert_threshold,
        clock_timestamp() - v_start_time,
        jsonb_build_object(
            'critical_events', COUNT(*) FILTER (WHERE event_count >= p_alert_threshold * 2),
            'high_priority_events', COUNT(*) FILTER (WHERE event_count >= p_alert_threshold),
            'total_events', COUNT(*)
        )
    FROM security_metrics;
END;
$$;


ALTER FUNCTION public.monitor_security_events(p_lookback_hours integer, p_alert_threshold integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 543 (class 1255 OID 196691)
-- Name: perform_database_backup(text, text, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.perform_database_backup(p_backup_type text DEFAULT 'FULL'::text, p_backup_location text DEFAULT NULL::text, p_options jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(backup_id bigint, status text, details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_backup_id bigint;
    v_start_time timestamp;
    v_backup_path text;
    v_result jsonb;
    v_status text := 'COMPLETED';
BEGIN
    -- Generate backup path if not provided
    v_backup_path := COALESCE(p_backup_location, 
        format('/backup/%s/%s_%s', 
            p_backup_type, 
            current_database(), 
            to_char(CURRENT_TIMESTAMP, 'YYYY_MM_DD_HH24_MI_SS')
        )
    );

    -- Create backup record
    INSERT INTO backup_catalog (
        backup_type,
        backup_location,
        metadata
    ) VALUES (
        p_backup_type,
        v_backup_path,
        jsonb_build_object(
            'options', p_options,
            'database', current_database(),
            'user', current_user,
            'postgresql_version', version()
        )
    ) RETURNING backup_id INTO v_backup_id;

    BEGIN
        CASE p_backup_type
            WHEN 'FULL' THEN
                -- Perform full backup
                v_result := perform_full_backup(v_backup_path, p_options);
                
            WHEN 'INCREMENTAL' THEN
                -- Perform incremental backup
                v_result := perform_incremental_backup(v_backup_path, p_options);
                
            WHEN 'LOGICAL' THEN
                -- Perform logical backup
                v_result := perform_logical_backup(v_backup_path, p_options);
                
            WHEN 'SCHEMA_ONLY' THEN
                -- Perform schema-only backup
                v_result := perform_schema_backup(v_backup_path, p_options);
        END CASE;

    EXCEPTION WHEN OTHERS THEN
        v_status := 'FAILED';
        v_result := jsonb_build_object(
            'error_message', SQLERRM,
            'error_detail', SQLSTATE,
            'error_context', pg_exception_context()
        );
    END;

    -- Update backup record
    UPDATE backup_catalog
    SET 
        status = v_status,
        end_time = CURRENT_TIMESTAMP,
        size_bytes = CASE 
            WHEN v_status = 'COMPLETED' THEN (v_result->>'size_bytes')::bigint 
            ELSE NULL 
        END,
        metadata = metadata || jsonb_build_object(
            'execution_details', v_result,
            'duration_seconds', EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - start_time))
        )
    WHERE backup_id = v_backup_id;

    RETURN QUERY
    SELECT 
        v_backup_id,
        v_status,
        v_result;
END;
$$;


ALTER FUNCTION public.perform_database_backup(p_backup_type text, p_backup_location text, p_options jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 589 (class 1255 OID 196692)
-- Name: perform_vacuum_maintenance(text, text); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.perform_vacuum_maintenance(p_table_filter text DEFAULT NULL::text, p_vacuum_type text DEFAULT 'FULL'::text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_table record;
    v_results jsonb := '[]'::jsonb;
    v_start_time timestamp;
BEGIN
    FOR v_table IN (
        SELECT schemaname, tablename
        FROM pg_tables
        WHERE tableowner = current_user
        AND (p_table_filter IS NULL OR tablename LIKE p_table_filter)
    ) LOOP
        v_start_time := clock_timestamp();
        
        EXECUTE format(
            'VACUUM (%s) %I.%I',
            p_vacuum_type,
            v_table.schemaname,
            v_table.tablename
        );
        
        v_results := v_results || jsonb_build_object(
            'table', v_table.schemaname || '.' || v_table.tablename,
            'vacuum_type', p_vacuum_type,
            'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000
        );
    END LOOP;
    
    RETURN jsonb_build_object(
        'tables_processed', jsonb_array_length(v_results),
        'vacuum_details', v_results
    );
END;
$$;


ALTER FUNCTION public.perform_vacuum_maintenance(p_table_filter text, p_vacuum_type text) OWNER TO "prosper-dev_owner";

--
-- TOC entry 632 (class 1255 OID 196693)
-- Name: process_alert_notifications(integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.process_alert_notifications(p_max_batch_size integer DEFAULT 100) RETURNS TABLE(notifications_sent integer, notification_details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_alert record;
    v_channel record;
    v_notifications_sent integer := 0;
    v_notification_results jsonb := '[]'::jsonb;
BEGIN
    FOR v_alert IN (
        SELECT 
            ah.alert_id,
            ah.rule_id,
            ar.rule_name,
            ar.severity,
            ar.notification_channels,
            ah.metric_value,
            ah.alert_details
        FROM alert_history ah
        JOIN alert_rules ar ON ah.rule_id = ar.rule_id
        WHERE ah.triggered_at >= CURRENT_TIMESTAMP - interval '15 minutes'
        AND ah.resolved_at IS NULL
        LIMIT p_max_batch_size
    ) LOOP
        -- Process each notification channel
        FOR v_channel IN 
            SELECT value AS channel_config 
            FROM jsonb_array_elements(v_alert.notification_channels)
        LOOP
            BEGIN
                -- Implement notification logic here (email, Slack, etc.)
                -- This is a placeholder for actual notification implementation
                v_notification_results := v_notification_results || jsonb_build_object(
                    'alert_id', v_alert.alert_id,
                    'channel', v_channel.channel_config,
                    'status', 'sent',
                    'timestamp', CURRENT_TIMESTAMP
                );
                
                v_notifications_sent := v_notifications_sent + 1;
            EXCEPTION WHEN OTHERS THEN
                v_notification_results := v_notification_results || jsonb_build_object(
                    'alert_id', v_alert.alert_id,
                    'channel', v_channel.channel_config,
                    'status', 'failed',
                    'error', SQLERRM,
                    'timestamp', CURRENT_TIMESTAMP
                );
            END;
        END LOOP;
    END LOOP;

    RETURN QUERY
    SELECT 
        v_notifications_sent,
        jsonb_build_object(
            'notifications', v_notification_results,
            'execution_time', CURRENT_TIMESTAMP,
            'batch_size', p_max_batch_size
        );
END;
$$;


ALTER FUNCTION public.process_alert_notifications(p_max_batch_size integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 552 (class 1255 OID 196694)
-- Name: process_scheduled_jobs(integer, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.process_scheduled_jobs(p_batch_size integer DEFAULT 100, p_options jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(jobs_processed integer, execution_details jsonb)
    LANGUAGE plpgsql
    AS $_$
DECLARE
    v_job record;
    v_execution_id bigint;
    v_start_time timestamp;
    v_jobs_count integer := 0;
    v_results jsonb := '[]'::jsonb;
BEGIN
    v_start_time := clock_timestamp();

    -- Process due jobs
    FOR v_job IN (
        SELECT *
        FROM scheduled_jobs
        WHERE is_active = true
        AND (next_run IS NULL OR next_run <= CURRENT_TIMESTAMP)
        ORDER BY next_run NULLS FIRST
        LIMIT p_batch_size
        FOR UPDATE SKIP LOCKED
    ) LOOP
        BEGIN
            -- Create execution record
            INSERT INTO job_executions (
                job_id,
                scheduled_time,
                status
            ) VALUES (
                v_job.job_id,
                COALESCE(v_job.next_run, v_start_time),
                'RUNNING'
            ) RETURNING execution_id INTO v_execution_id;

            -- Execute job based on target type
            CASE v_job.target_type
                WHEN 'WORKFLOW' THEN
                    PERFORM execute_workflow(
                        v_job.target_id,
                        'SCHEDULER',
                        v_job.parameters
                    );

                WHEN 'REPORT' THEN
                    PERFORM generate_system_report(
                        v_job.target_id,
                        v_job.parameters
                    );

                WHEN 'FUNCTION' THEN
                    EXECUTE format(
                        'SELECT %s($1)',
                        v_job.target_id::regproc
                    ) USING v_job.parameters;

                WHEN 'SQL' THEN
                    EXECUTE replace_context_variables(
                        v_job.parameters->>'sql',
                        jsonb_build_object('job_id', v_job.job_id)
                    );
            END CASE;

            -- Calculate next run time
            UPDATE scheduled_jobs
            SET 
                last_run = v_start_time,
                next_run = CASE v_job.schedule_type
                    WHEN 'CRON' THEN
                        calculate_next_cron_run(v_job.cron_expression, v_start_time)
                    WHEN 'INTERVAL' THEN
                        v_start_time + v_job.interval_value
                    WHEN 'FIXED_TIME' THEN
                        NULL -- One-time job
                END,
                updated_at = clock_timestamp()
            WHERE job_id = v_job.job_id;

            -- Update execution status
            UPDATE job_executions
            SET 
                status = 'COMPLETED',
                completed_at = clock_timestamp(),
                result_data = jsonb_build_object(
                    'execution_time', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time))
                )
            WHERE execution_id = v_execution_id;

            v_jobs_count := v_jobs_count + 1;
            v_results := v_results || jsonb_build_object(
                'job_id', v_job.job_id,
                'job_name', v_job.job_name,
                'status', 'COMPLETED',
                'execution_time', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time))
            );

        EXCEPTION WHEN OTHERS THEN
            -- Update execution status
            UPDATE job_executions
            SET 
                status = 'FAILED',
                completed_at = clock_timestamp(),
                error_details = jsonb_build_object(
                    'error', SQLERRM,
                    'context', SQLSTATE
                )
            WHERE execution_id = v_execution_id;

            v_results := v_results || jsonb_build_object(
                'job_id', v_job.job_id,
                'job_name', v_job.job_name,
                'status', 'FAILED',
                'error', SQLERRM
            );
        END;
    END LOOP;

    RETURN QUERY
    SELECT 
        v_jobs_count,
        jsonb_build_object(
            'start_time', v_start_time,
            'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000,
            'batch_size', p_batch_size,
            'jobs', v_results
        );
END;
$_$;


ALTER FUNCTION public.process_scheduled_jobs(p_batch_size integer, p_options jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 538 (class 1255 OID 196695)
-- Name: process_security_notifications(integer); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.process_security_notifications(p_batch_size integer DEFAULT 100) RETURNS TABLE(processed_count integer, notification_details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_start_time timestamp := clock_timestamp();
    v_processed integer := 0;
    v_failed integer := 0;
    v_notification record;
BEGIN
    FOR v_notification IN (
        SELECT *
        FROM security_notifications
        WHERE notification_status = 'PENDING'
        ORDER BY severity DESC, created_at
        LIMIT p_batch_size
        FOR UPDATE SKIP LOCKED
    ) LOOP
        BEGIN
            -- Here you would add your actual notification logic
            -- (email, SMS, Slack, etc.)
            
            -- Update notification status
            UPDATE security_notifications
            SET 
                notification_status = 'SENT',
                processed_at = clock_timestamp()
            WHERE notification_id = v_notification.notification_id;
            
            v_processed := v_processed + 1;
        EXCEPTION WHEN OTHERS THEN
            UPDATE security_notifications
            SET 
                notification_status = 'FAILED',
                processed_at = clock_timestamp(),
                message_content = message_content || 
                    jsonb_build_object('error', SQLERRM)
            WHERE notification_id = v_notification.notification_id;
            
            v_failed := v_failed + 1;
        END;
    END LOOP;

    RETURN QUERY
    SELECT 
        v_processed + v_failed,
        jsonb_build_object(
            'start_time', v_start_time,
            'end_time', clock_timestamp(),
            'duration_ms', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000,
            'processed_successfully', v_processed,
            'failed_notifications', v_failed,
            'batch_size', p_batch_size
        );
END;
$$;


ALTER FUNCTION public.process_security_notifications(p_batch_size integer) OWNER TO "prosper-dev_owner";

--
-- TOC entry 544 (class 1255 OID 196696)
-- Name: process_workflow_escalations(); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.process_workflow_escalations() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    overdue_workflow RECORD;
BEGIN
    FOR overdue_workflow IN (
        SELECT 
            wi.instance_id,
            wi.workflow_id,
            wi.current_step,
            wi.escalation_level,
            wd.auto_escalation_hours
        FROM public.workflow_instances wi
        JOIN public.workflow_definitions wd ON wi.workflow_id = wd.workflow_id
        WHERE wi.status = 'active'
        AND wi.last_action_date < CURRENT_TIMESTAMP - (wd.auto_escalation_hours || ' hours')::INTERVAL
        AND wi.escalation_level < 3
    ) LOOP
        -- Increment escalation level
        UPDATE public.workflow_instances
        SET 
            escalation_level = escalation_level + 1,
            last_modified_at = CURRENT_TIMESTAMP
        WHERE instance_id = overdue_workflow.instance_id;
        
        -- Log escalation in history
        INSERT INTO public.workflow_step_history (
            instance_id,
            step_number,
            step_name,
            action_taken,
            comments
        ) VALUES (
            overdue_workflow.instance_id,
            overdue_workflow.current_step,
            'Escalation',
            'AUTO_ESCALATED',
            'Automatically escalated due to inactivity'
        );
    END LOOP;
END;
$$;


ALTER FUNCTION public.process_workflow_escalations() OWNER TO "prosper-dev_owner";

--
-- TOC entry 598 (class 1255 OID 196697)
-- Name: refresh_executive_summary(); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.refresh_executive_summary() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY executive_prosper_summary;
END;
$$;


ALTER FUNCTION public.refresh_executive_summary() OWNER TO "prosper-dev_owner";

--
-- TOC entry 608 (class 1255 OID 196698)
-- Name: refresh_performance_views(); Type: PROCEDURE; Schema: public; Owner: prosper-dev_owner
--

CREATE PROCEDURE public.refresh_performance_views()
    LANGUAGE plpgsql
    AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY Team_Performance_Summary;
    
    -- Log the refresh
    INSERT INTO Audit_Log (
        entity_type,
        action_type,
        action_date,
        performed_by,
        new_values
    ) VALUES (
        'Materialized_Views',
        'REFRESH',
        CURRENT_TIMESTAMP,
        CURRENT_USER::INTEGER,
        jsonb_build_object(
            'views_refreshed', jsonb_build_array('Team_Performance_Summary'),
            'refresh_time', CURRENT_TIMESTAMP
        )
    );
END;
$$;


ALTER PROCEDURE public.refresh_performance_views() OWNER TO "prosper-dev_owner";

--
-- TOC entry 612 (class 1255 OID 196699)
-- Name: register_api_endpoint(text, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.register_api_endpoint(p_endpoint_name text, p_endpoint_path text, p_method text, p_config jsonb DEFAULT '{}'::jsonb) RETURNS TABLE(success boolean, endpoint_id bigint, details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_endpoint_id bigint;
BEGIN
    -- Check for duplicate endpoint
    IF EXISTS (
        SELECT 1 FROM api_endpoints 
        WHERE endpoint_path = p_endpoint_path 
        AND method = p_method
        AND is_active = true
    ) THEN
        RETURN QUERY SELECT 
            false, 
            NULL::bigint,
            jsonb_build_object(
                'error', 'Endpoint already exists',
                'path', p_endpoint_path,
                'method', p_method
            );
        RETURN;
    END IF;

    -- Insert new endpoint
    INSERT INTO api_endpoints (
        endpoint_name,
        endpoint_path,
        method,
        rate_limit,
        auth_required,
        response_cache_ttl
    ) VALUES (
        p_endpoint_name,
        p_endpoint_path,
        p_method,
        (p_config->>'rate_limit')::integer,
        COALESCE((p_config->>'auth_required')::boolean, true),
        (p_config->>'cache_ttl')::interval
    ) RETURNING endpoint_id INTO v_endpoint_id;

    RETURN QUERY SELECT 
        true, 
        v_endpoint_id,
        jsonb_build_object(
            'endpoint_name', p_endpoint_name,
            'path', p_endpoint_path,
            'method', p_method,
            'config', p_config
        );
END;
$$;


ALTER FUNCTION public.register_api_endpoint(p_endpoint_name text, p_endpoint_path text, p_method text, p_config jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 531 (class 1255 OID 196700)
-- Name: render_template(text, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.render_template(p_template text, p_context jsonb) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_result text;
    v_key text;
    v_value text;
BEGIN
    v_result := p_template;
    
    -- Replace template variables
    FOR v_key, v_value IN 
        SELECT key, value::text 
        FROM jsonb_each_text(p_context)
    LOOP
        v_result := replace(v_result, '{{' || v_key || '}}', v_value);
    END LOOP;

    RETURN v_result;
END;
$$;


ALTER FUNCTION public.render_template(p_template text, p_context jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 576 (class 1255 OID 196701)
-- Name: schedule_maintenance_task(text, text, interval, jsonb, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.schedule_maintenance_task(p_task_name text, p_task_type text, p_frequency interval, p_configuration jsonb DEFAULT NULL::jsonb, p_start_time timestamp without time zone DEFAULT NULL::timestamp without time zone) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_schedule_id bigint;
BEGIN
    INSERT INTO maintenance_schedule (
        task_name,
        task_type,
        frequency,
        next_run,
        configuration
    ) VALUES (
        p_task_name,
        p_task_type,
        p_frequency,
        COALESCE(p_start_time, CURRENT_TIMESTAMP),
        p_configuration
    )
    RETURNING schedule_id INTO v_schedule_id;

    -- Schedule some common maintenance tasks
    IF p_task_name = 'DEFAULT_MAINTENANCE' THEN
        -- Schedule VACUUM
        PERFORM schedule_maintenance_task(
            'Daily VACUUM',
            'VACUUM',
            interval '1 day',
            jsonb_build_object(
                'vacuum_type', 'ANALYZE',
                'table_filter', NULL
            )
        );

        -- Schedule REINDEX
        PERFORM schedule_maintenance_task(
            'Weekly REINDEX',
            'REINDEX',
            interval '1 week',
            jsonb_build_object(
                'concurrent', true,
                'index_filter', NULL
            )
        );

        -- Schedule Query Optimization
        PERFORM schedule_maintenance_task(
            'Daily Query Optimization',
            'OPTIMIZE',
            interval '1 day',
            jsonb_build_object(
                'min_calls', 100,
                'min_time', interval '1 second'
            )
        );
    END IF;

    RETURN v_schedule_id;
END;
$$;


ALTER FUNCTION public.schedule_maintenance_task(p_task_name text, p_task_type text, p_frequency interval, p_configuration jsonb, p_start_time timestamp without time zone) OWNER TO "prosper-dev_owner";

--
-- TOC entry 568 (class 1255 OID 196702)
-- Name: security_event_monitor_trigger(); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.security_event_monitor_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_alert_threshold integer := 5; -- Configurable threshold
    v_time_window interval := interval '5 minutes';
    v_event_count integer;
    v_notification_data jsonb;
BEGIN
    -- Count recent events of the same type
    SELECT COUNT(*)
    INTO v_event_count
    FROM security_events
    WHERE event_type = NEW.event_type
    AND event_time > CURRENT_TIMESTAMP - v_time_window;

    -- Check if we need to create an alert
    IF v_event_count >= v_alert_threshold OR NEW.severity = 'CRITICAL' THEN
        v_notification_data := jsonb_build_object(
            'event_type', NEW.event_type,
            'event_count', v_event_count,
            'time_window_minutes', EXTRACT(EPOCH FROM v_time_window)/60,
            'latest_event', jsonb_build_object(
                'time', NEW.event_time,
                'ip_address', NEW.ip_address,
                'user_id', NEW.user_id,
                'details', NEW.event_details
            ),
            'threshold_reached', v_event_count >= v_alert_threshold,
            'is_critical', NEW.severity = 'CRITICAL'
        );

        -- Insert notification
        INSERT INTO security_notifications (
            notification_type,
            severity,
            recipient_list,
            message_content
        ) VALUES (
            'SECURITY_ALERT',
            CASE 
                WHEN NEW.severity = 'CRITICAL' THEN 'CRITICAL'
                WHEN v_event_count >= v_alert_threshold * 2 THEN 'HIGH'
                ELSE 'NORMAL'
            END,
            jsonb_build_array('security_team', 'system_admin'),
            v_notification_data
        );
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.security_event_monitor_trigger() OWNER TO "prosper-dev_owner";

--
-- TOC entry 590 (class 1255 OID 196703)
-- Name: send_notification(bigint, bigint, jsonb, text[]); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.send_notification(p_channel_id bigint, p_template_id bigint, p_context jsonb, p_recipients text[] DEFAULT NULL::text[]) RETURNS TABLE(success boolean, notification_id bigint, details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_channel record;
    v_template record;
    v_notification_id bigint;
    v_rendered_subject text;
    v_rendered_body text;
    v_recipient text;
    v_start_time timestamp;
BEGIN
    v_start_time := clock_timestamp();

    -- Get channel and template details
    SELECT * INTO v_channel
    FROM notification_channels
    WHERE channel_id = p_channel_id AND is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Notification channel % not found or inactive', p_channel_id;
    END IF;

    SELECT * INTO v_template
    FROM notification_templates
    WHERE template_id = p_template_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Notification template % not found', p_template_id;
    END IF;

    -- Render template
    v_rendered_subject := render_template(
        v_template.subject_template,
        p_context
    );

    v_rendered_body := render_template(
        v_template.body_template,
        p_context
    );

    -- Handle different channel types
    CASE v_channel.channel_type
        WHEN 'EMAIL' THEN
            FOREACH v_recipient IN ARRAY COALESCE(p_recipients, 
                                                ARRAY[v_channel.configuration->>'default_recipient'])
            LOOP
                -- Create notification record
                INSERT INTO notification_history (
                    channel_id,
                    template_id,
                    notification_type,
                    recipient,
                    subject,
                    body,
                    metadata
                ) VALUES (
                    p_channel_id,
                    p_template_id,
                    v_template.template_type,
                    v_recipient,
                    v_rendered_subject,
                    v_rendered_body,
                    jsonb_build_object(
                        'context', p_context,
                        'channel_config', v_channel.configuration
                    )
                ) RETURNING notification_id INTO v_notification_id;

                -- Send email
                BEGIN
                    PERFORM send_email(
                        v_recipient,
                        v_rendered_subject,
                        v_rendered_body,
                        v_template.format,
                        v_channel.configuration
                    );

                    -- Update notification status
                    UPDATE notification_history
                    SET 
                        status = 'SENT',
                        sent_at = clock_timestamp()
                    WHERE notification_id = v_notification_id;

                EXCEPTION WHEN OTHERS THEN
                    UPDATE notification_history
                    SET 
                        status = 'FAILED',
                        error_details = jsonb_build_object(
                            'error', SQLERRM,
                            'context', SQLSTATE
                        )
                    WHERE notification_id = v_notification_id;

                    RETURN QUERY
                    SELECT 
                        false,
                        v_notification_id,
                        jsonb_build_object(
                            'error', SQLERRM,
                            'recipient', v_recipient
                        );
                    RETURN;
                END;
            END LOOP;

        WHEN 'SLACK' THEN
            -- Create notification record
            INSERT INTO notification_history (
                channel_id,
                template_id,
                notification_type,
                body,
                metadata
            ) VALUES (
                p_channel_id,
                p_template_id,
                v_template.template_type,
                v_rendered_body,
                jsonb_build_object(
                    'context', p_context,
                    'channel_config', v_channel.configuration
                )
            ) RETURNING notification_id INTO v_notification_id;

            -- Send to Slack
            BEGIN
                PERFORM send_slack_message(
                    v_rendered_body,
                    v_channel.configuration
                );

                UPDATE notification_history
                SET 
                    status = 'SENT',
                    sent_at = clock_timestamp()
                WHERE notification_id = v_notification_id;

            EXCEPTION WHEN OTHERS THEN
                UPDATE notification_history
                SET 
                    status = 'FAILED',
                    error_details = jsonb_build_object(
                        'error', SQLERRM,
                        'context', SQLSTATE
                    )
                WHERE notification_id = v_notification_id;

                RETURN QUERY
                SELECT 
                    false,
                    v_notification_id,
                    jsonb_build_object('error', SQLERRM);
                RETURN;
            END;

        WHEN 'WEBHOOK' THEN
            -- Similar implementation for webhook notifications
            -- ... webhook specific code ...

        ELSE
            RAISE EXCEPTION 'Unsupported channel type: %', v_channel.channel_type;
    END CASE;

    RETURN QUERY
    SELECT 
        true,
        v_notification_id,
        jsonb_build_object(
            'channel_type', v_channel.channel_type,
            'template_type', v_template.template_type,
            'execution_time', EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time))
        );
END;
$$;


ALTER FUNCTION public.send_notification(p_channel_id bigint, p_template_id bigint, p_context jsonb, p_recipients text[]) OWNER TO "prosper-dev_owner";

--
-- TOC entry 582 (class 1255 OID 196704)
-- Name: track_allocation_changes(); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.track_allocation_changes() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.allocation_percentage != OLD.allocation_percentage 
        OR NEW.allocation_status != OLD.allocation_status THEN
            INSERT INTO public.resource_allocation_history (
                allocation_id,
                employee_id,
                old_allocation_percentage,
                new_allocation_percentage,
                old_status,
                new_status,
                changed_by
            ) VALUES (
                NEW.allocation_id,
                NEW.employee_id,
                OLD.allocation_percentage,
                NEW.allocation_percentage,
                OLD.allocation_status,
                NEW.allocation_status,
                NEW.last_modified_by
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.track_allocation_changes() OWNER TO "prosper-dev_owner";

--
-- TOC entry 547 (class 1255 OID 196705)
-- Name: track_score_history(); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.track_score_history() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        IF (NEW.average_score != OLD.average_score) THEN
            INSERT INTO Score_History (
                employee_id,
                category,
                score_type,
                old_value,
                new_value,
                change_date,
                changed_by
            ) VALUES (
                NEW.employee_id,
                NEW.category,
                'average_score',
                OLD.average_score,
                NEW.average_score,
                CURRENT_TIMESTAMP,
                CURRENT_USER::INTEGER
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.track_score_history() OWNER TO "prosper-dev_owner";

--
-- TOC entry 610 (class 1255 OID 196706)
-- Name: update_performance_baselines(); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.update_performance_baselines() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_period text;
    v_interval interval;
BEGIN
    FOR v_period, v_interval IN 
        VALUES 
            ('HOUR', '1 hour'::interval),
            ('DAY', '1 day'::interval),
            ('WEEK', '1 week'::interval),
            ('MONTH', '1 month'::interval)
    LOOP
        -- Update or insert baseline calculations
        INSERT INTO performance_baselines (
            metric_name,
            time_period,
            min_value,
            max_value,
            avg_value,
            percentile_90,
            percentile_95,
            percentile_99,
            sample_size,
            last_updated
        )
        SELECT 
            metric_name,
            v_period,
            min(metric_value),
            max(metric_value),
            avg(metric_value),
            percentile_cont(0.90) WITHIN GROUP (ORDER BY metric_value),
            percentile_cont(0.95) WITHIN GROUP (ORDER BY metric_value),
            percentile_cont(0.99) WITHIN GROUP (ORDER BY metric_value),
            count(*),
            clock_timestamp()
        FROM performance_metrics
        WHERE collection_time >= (CURRENT_TIMESTAMP - v_interval)
        GROUP BY metric_name
        ON CONFLICT (metric_name, time_period) DO UPDATE
        SET 
            min_value = EXCLUDED.min_value,
            max_value = EXCLUDED.max_value,
            avg_value = EXCLUDED.avg_value,
            percentile_90 = EXCLUDED.percentile_90,
            percentile_95 = EXCLUDED.percentile_95,
            percentile_99 = EXCLUDED.percentile_99,
            sample_size = EXCLUDED.sample_size,
            last_updated = EXCLUDED.last_updated;
    END LOOP;
END;
$$;


ALTER FUNCTION public.update_performance_baselines() OWNER TO "prosper-dev_owner";

--
-- TOC entry 567 (class 1255 OID 196707)
-- Name: update_system_configuration(text, text, text, text); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.update_system_configuration(p_config_name text, p_new_value text, p_modified_by text, p_change_reason text DEFAULT NULL::text) RETURNS TABLE(success boolean, message text, details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_config record;
    v_validation_result jsonb;
BEGIN
    -- Get existing configuration
    SELECT * INTO v_config
    FROM system_configurations
    WHERE config_name = p_config_name AND is_active = true;

    IF NOT FOUND THEN
        RETURN QUERY SELECT false, 'Configuration not found', NULL::jsonb;
        RETURN;
    END IF;

    -- Validate new value
    v_validation_result := validate_configuration_value(
        p_config_name,
        p_new_value,
        v_config.validation_rules
    );

    IF NOT (v_validation_result->>'is_valid')::boolean THEN
        RETURN QUERY SELECT 
            false, 
            'Validation failed', 
            v_validation_result;
        RETURN;
    END IF;

    -- Update configuration
    UPDATE system_configurations
    SET 
        config_value = p_new_value,
        last_modified = CURRENT_TIMESTAMP,
        modified_by = p_modified_by
    WHERE config_id = v_config.config_id;

    -- Return success
    RETURN QUERY SELECT 
        true, 
        'Configuration updated successfully',
        jsonb_build_object(
            'config_name', p_config_name,
            'previous_value', v_config.config_value,
            'new_value', p_new_value,
            'timestamp', CURRENT_TIMESTAMP,
            'validation_result', v_validation_result
        );
END;
$$;


ALTER FUNCTION public.update_system_configuration(p_config_name text, p_new_value text, p_modified_by text, p_change_reason text) OWNER TO "prosper-dev_owner";

--
-- TOC entry 578 (class 1255 OID 196708)
-- Name: update_team_size(); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.update_team_size() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE public.team_structure
    SET team_size = (
        SELECT COUNT(*)
        FROM public.employee_manager_hierarchy
        WHERE team_id = NEW.team_id AND active = true
    )
    WHERE team_id = NEW.team_id;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_team_size() OWNER TO "prosper-dev_owner";

--
-- TOC entry 545 (class 1255 OID 196709)
-- Name: validate_api_request(text, text, text); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.validate_api_request(p_api_key text, p_endpoint_path text, p_method text) RETURNS TABLE(is_valid boolean, key_id bigint, endpoint_id bigint, validation_details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_key_record record;
    v_endpoint_record record;
    v_rate_limit_exceeded boolean;
BEGIN
    -- Get API key record
    SELECT * INTO v_key_record
    FROM api_keys
    WHERE api_key = p_api_key AND is_active = true;

    -- Get endpoint record
    SELECT * INTO v_endpoint_record
    FROM api_endpoints
    WHERE endpoint_path = p_endpoint_path 
    AND method = p_method
    AND is_active = true;

    -- Check rate limit
    IF v_key_record.rate_limit IS NOT NULL THEN
        SELECT COUNT(*) > v_key_record.rate_limit INTO v_rate_limit_exceeded
        FROM api_requests
        WHERE api_key_id = v_key_record.key_id
        AND request_timestamp > CURRENT_TIMESTAMP - interval '1 hour';
    END IF;

    RETURN QUERY SELECT
        CASE
            WHEN v_key_record IS NULL THEN false
            WHEN v_endpoint_record IS NULL THEN false
            WHEN v_key_record.expires_at IS NOT NULL 
                 AND v_key_record.expires_at < CURRENT_TIMESTAMP THEN false
            WHEN v_rate_limit_exceeded THEN false
            ELSE true
        END,
        v_key_record.key_id,
        v_endpoint_record.endpoint_id,
        jsonb_build_object(
            'validation_time', CURRENT_TIMESTAMP,
            'errors', ARRAY[
                CASE WHEN v_key_record IS NULL THEN 'Invalid API key' END,
                CASE WHEN v_endpoint_record IS NULL THEN 'Invalid endpoint' END,
                CASE WHEN v_key_record.expires_at IS NOT NULL 
                          AND v_key_record.expires_at < CURRENT_TIMESTAMP 
                     THEN 'Expired API key' 
                END,
                CASE WHEN v_rate_limit_exceeded THEN 'Rate limit exceeded' END
            ]::text[] - ARRAY[NULL]
        );
END;
$$;


ALTER FUNCTION public.validate_api_request(p_api_key text, p_endpoint_path text, p_method text) OWNER TO "prosper-dev_owner";

--
-- TOC entry 591 (class 1255 OID 196710)
-- Name: validate_configuration_value(text, text, jsonb); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.validate_configuration_value(p_config_name text, p_value text, p_validation_rules jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $_$
DECLARE
    v_rule record;
    v_is_valid boolean := true;
    v_messages jsonb := '[]'::jsonb;
BEGIN
    -- If no validation rules, consider valid
    IF p_validation_rules IS NULL THEN
        RETURN jsonb_build_object(
            'is_valid', true,
            'messages', v_messages
        );
    END IF;

    -- Process each validation rule
    FOR v_rule IN SELECT * FROM jsonb_array_elements(p_validation_rules->'rules')
    LOOP
        CASE v_rule.value->>'type'
            WHEN 'regex' THEN
                IF NOT p_value ~ (v_rule.value->>'pattern') THEN
                    v_is_valid := false;
                    v_messages := v_messages || jsonb_build_object(
                        'rule', 'regex',
                        'message', v_rule.value->>'message'
                    );
                END IF;

            WHEN 'range' THEN
                IF p_value::numeric < (v_rule.value->>'min')::numeric OR 
                   p_value::numeric > (v_rule.value->>'max')::numeric THEN
                    v_is_valid := false;
                    v_messages := v_messages || jsonb_build_object(
                        'rule', 'range',
                        'message', v_rule.value->>'message'
                    );
                END IF;

            WHEN 'enum' THEN
                IF NOT p_value = ANY (ARRAY(SELECT jsonb_array_elements_text(v_rule.value->'values'))) THEN
                    v_is_valid := false;
                    v_messages := v_messages || jsonb_build_object(
                        'rule', 'enum',
                        'message', v_rule.value->>'message'
                    );
                END IF;

            WHEN 'custom' THEN
                -- Execute custom validation function if specified
                IF v_rule.value->>'function' IS NOT NULL THEN
                    EXECUTE format(
                        'SELECT %s($1, $2)',
                        v_rule.value->>'function'
                    ) INTO v_is_valid USING p_value, v_rule.value->'params';

                    IF NOT v_is_valid THEN
                        v_messages := v_messages || jsonb_build_object(
                            'rule', 'custom',
                            'message', v_rule.value->>'message'
                        );
                    END IF;
                END IF;
        END CASE;

        EXIT WHEN NOT v_is_valid AND (p_validation_rules->>'fail_fast')::boolean;
    END LOOP;

    RETURN jsonb_build_object(
        'is_valid', v_is_valid,
        'messages', v_messages,
        'config_name', p_config_name,
        'value', p_value
    );
END;
$_$;


ALTER FUNCTION public.validate_configuration_value(p_config_name text, p_value text, p_validation_rules jsonb) OWNER TO "prosper-dev_owner";

--
-- TOC entry 566 (class 1255 OID 196711)
-- Name: validate_session(text); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.validate_session(p_session_id text) RETURNS TABLE(is_valid boolean, user_id integer, username character varying, role character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.is_valid AND s.expires_at > CURRENT_TIMESTAMP,
        u.user_id,
        u.username,
        u.role
    FROM user_sessions s
    JOIN users u ON s.user_id = u.user_id
    WHERE s.session_id = p_session_id
    AND s.is_valid = true
    AND u.is_active = true;
END;
$$;


ALTER FUNCTION public.validate_session(p_session_id text) OWNER TO "prosper-dev_owner";

--
-- TOC entry 579 (class 1255 OID 196712)
-- Name: verify_backup(bigint, text); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.verify_backup(p_backup_id bigint, p_verification_level text DEFAULT 'BASIC'::text) RETURNS TABLE(verification_status text, verification_details jsonb)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_backup record;
    v_result jsonb;
    v_status text := 'SUCCESS';
BEGIN
    -- Get backup record
    SELECT * INTO v_backup
    FROM backup_catalog
    WHERE backup_id = p_backup_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Backup ID % not found', p_backup_id;
    END IF;

    BEGIN
        CASE p_verification_level
            WHEN 'BASIC' THEN
                -- Basic file integrity check
                v_result := verify_backup_files(v_backup.backup_location);
                
            WHEN 'THOROUGH' THEN
                -- Detailed verification including restore test
                v_result := verify_backup_thorough(v_backup.backup_location);
                
            WHEN 'RESTORE_TEST' THEN
                -- Perform test restore
                v_result := test_backup_restore(v_backup.backup_location);
        END CASE;

    EXCEPTION WHEN OTHERS THEN
        v_status := 'FAILED';
        v_result := jsonb_build_object(
            'error_message', SQLERRM,
            'error_detail', SQLSTATE,
            'error_context', pg_exception_context()
        );
    END;

    -- Log verification result
    INSERT INTO backup_verification_log (
        backup_id,
        verification_status,
        verification_details
    ) VALUES (
        p_backup_id,
        v_status,
        v_result
    );

    RETURN QUERY
    SELECT v_status, v_result;
END;
$$;


ALTER FUNCTION public.verify_backup(p_backup_id bigint, p_verification_level text) OWNER TO "prosper-dev_owner";

--
-- TOC entry 583 (class 1255 OID 196713)
-- Name: verify_login(character varying, text, inet); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.verify_login(p_username character varying, p_password text, p_ip_address inet) RETURNS TABLE(success boolean, user_id integer, role character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_user RECORD;
BEGIN
    -- Get user record
    SELECT * INTO v_user 
    FROM users 
    WHERE username = p_username AND is_active = true;
    
    -- Log attempt
    INSERT INTO login_attempts (username, ip_address, success)
    VALUES (p_username, p_ip_address, 
            CASE WHEN v_user.user_id IS NOT NULL AND 
                      crypt(p_password, v_user.password_hash) = v_user.password_hash 
                 THEN true 
                 ELSE false 
            END);
    
    -- Return result
    RETURN QUERY
    SELECT 
        CASE WHEN v_user.user_id IS NOT NULL AND 
                  crypt(p_password, v_user.password_hash) = v_user.password_hash 
             THEN true 
             ELSE false 
        END,
        v_user.user_id,
        v_user.role;
END;
$$;


ALTER FUNCTION public.verify_login(p_username character varying, p_password text, p_ip_address inet) OWNER TO "prosper-dev_owner";

--
-- TOC entry 553 (class 1255 OID 196714)
-- Name: verify_tables_exist(text[]); Type: FUNCTION; Schema: public; Owner: prosper-dev_owner
--

CREATE FUNCTION public.verify_tables_exist(table_list text[]) RETURNS TABLE(checked_table text, table_exists boolean)
    LANGUAGE plpgsql
    AS $$
DECLARE
    curr_table text;
BEGIN
    FOREACH curr_table IN ARRAY table_list
    LOOP
        checked_table := curr_table;
        table_exists := (
            SELECT EXISTS (
                SELECT 1 
                FROM information_schema.tables 
                WHERE table_schema = 'public' 
                AND table_name = curr_table
            )
        );
        RETURN NEXT;
    END LOOP;
END;
$$;


ALTER FUNCTION public.verify_tables_exist(table_list text[]) OWNER TO "prosper-dev_owner";

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 529 (class 1259 OID 237568)
-- Name: User; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public."User" (
    id text NOT NULL,
    email text,
    name text,
    role text DEFAULT 'user'::text NOT NULL,
    "createdAt" timestamp(3) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    "updatedAt" timestamp(3) without time zone NOT NULL,
    "emailVerified" timestamp(3) without time zone,
    "employeeId" integer,
    image text,
    "isActive" boolean DEFAULT true NOT NULL,
    "lastLogin" timestamp(3) without time zone,
    "userId" integer
);


ALTER TABLE public."User" OWNER TO "prosper-dev_owner";

--
-- TOC entry 217 (class 1259 OID 196723)
-- Name: _prisma_migrations; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public._prisma_migrations (
    id character varying(36) NOT NULL,
    checksum character varying(64) NOT NULL,
    finished_at timestamp with time zone,
    migration_name character varying(255) NOT NULL,
    logs text,
    rolled_back_at timestamp with time zone,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    applied_steps_count integer DEFAULT 0 NOT NULL
);


ALTER TABLE public._prisma_migrations OWNER TO "prosper-dev_owner";

--
-- TOC entry 218 (class 1259 OID 196730)
-- Name: access_control; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.access_control (
    access_id integer NOT NULL,
    role_name character varying(100),
    permissions jsonb,
    description text,
    active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.access_control OWNER TO "prosper-dev_owner";

--
-- TOC entry 219 (class 1259 OID 196737)
-- Name: access_control_access_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.access_control_access_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.access_control_access_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5169 (class 0 OID 0)
-- Dependencies: 219
-- Name: access_control_access_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.access_control_access_id_seq OWNED BY public.access_control.access_id;


--
-- TOC entry 220 (class 1259 OID 196738)
-- Name: achievement_badges; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.achievement_badges (
    badge_id integer NOT NULL,
    employee_id integer,
    badge_name character varying(100),
    category character varying(50),
    awarded_date date,
    criteria_met jsonb,
    visibility character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.achievement_badges OWNER TO "prosper-dev_owner";

--
-- TOC entry 221 (class 1259 OID 196744)
-- Name: achievement_badges_badge_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.achievement_badges_badge_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.achievement_badges_badge_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5170 (class 0 OID 0)
-- Dependencies: 221
-- Name: achievement_badges_badge_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.achievement_badges_badge_id_seq OWNED BY public.achievement_badges.badge_id;


--
-- TOC entry 222 (class 1259 OID 196745)
-- Name: achievement_tracking; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.achievement_tracking (
    achievement_id integer NOT NULL,
    achievement_type character varying(50),
    description text,
    criteria jsonb,
    points integer,
    badge_image_url text
);


ALTER TABLE public.achievement_tracking OWNER TO "prosper-dev_owner";

--
-- TOC entry 223 (class 1259 OID 196750)
-- Name: achievement_tracking_achievement_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.achievement_tracking_achievement_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.achievement_tracking_achievement_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5171 (class 0 OID 0)
-- Dependencies: 223
-- Name: achievement_tracking_achievement_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.achievement_tracking_achievement_id_seq OWNED BY public.achievement_tracking.achievement_id;


--
-- TOC entry 224 (class 1259 OID 196751)
-- Name: action_items; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.action_items (
    item_id integer NOT NULL,
    employee_id integer,
    assigned_by integer,
    category character varying(50),
    description text,
    due_date date,
    priority character varying(20),
    status character varying(50),
    completion_date date,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.action_items OWNER TO "prosper-dev_owner";

--
-- TOC entry 225 (class 1259 OID 196757)
-- Name: action_items_item_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.action_items_item_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.action_items_item_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5172 (class 0 OID 0)
-- Dependencies: 225
-- Name: action_items_item_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.action_items_item_id_seq OWNED BY public.action_items.item_id;


--
-- TOC entry 226 (class 1259 OID 196758)
-- Name: alert_configuration; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.alert_configuration (
    alert_id integer NOT NULL,
    alert_type character varying(50),
    threshold_value numeric(5,2),
    frequency character varying(20),
    recipients jsonb,
    active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    last_triggered timestamp without time zone,
    CONSTRAINT valid_frequency CHECK (((frequency)::text = ANY (ARRAY[('Daily'::character varying)::text, ('Weekly'::character varying)::text, ('Monthly'::character varying)::text, ('Quarterly'::character varying)::text]))),
    CONSTRAINT valid_threshold CHECK (((threshold_value >= (0)::numeric) AND (threshold_value <= (100)::numeric)))
);


ALTER TABLE public.alert_configuration OWNER TO "prosper-dev_owner";

--
-- TOC entry 227 (class 1259 OID 196767)
-- Name: alert_configuration_alert_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.alert_configuration_alert_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.alert_configuration_alert_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5173 (class 0 OID 0)
-- Dependencies: 227
-- Name: alert_configuration_alert_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.alert_configuration_alert_id_seq OWNED BY public.alert_configuration.alert_id;


--
-- TOC entry 228 (class 1259 OID 196768)
-- Name: alert_notifications; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.alert_notifications (
    notification_id integer NOT NULL,
    alert_id integer,
    recipient_id integer,
    notification_type character varying(50),
    sent_at timestamp without time zone,
    acknowledged_at timestamp without time zone
);


ALTER TABLE public.alert_notifications OWNER TO "prosper-dev_owner";

--
-- TOC entry 229 (class 1259 OID 196771)
-- Name: alert_notifications_notification_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.alert_notifications_notification_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.alert_notifications_notification_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5174 (class 0 OID 0)
-- Dependencies: 229
-- Name: alert_notifications_notification_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.alert_notifications_notification_id_seq OWNED BY public.alert_notifications.notification_id;


--
-- TOC entry 230 (class 1259 OID 196772)
-- Name: analytics_dashboard; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.analytics_dashboard (
    dashboard_id integer NOT NULL,
    dashboard_name character varying(100),
    metrics jsonb[],
    refresh_frequency character varying(50),
    last_updated timestamp without time zone,
    access_roles text[],
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.analytics_dashboard OWNER TO "prosper-dev_owner";

--
-- TOC entry 231 (class 1259 OID 196778)
-- Name: analytics_dashboard_dashboard_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.analytics_dashboard_dashboard_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.analytics_dashboard_dashboard_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5175 (class 0 OID 0)
-- Dependencies: 231
-- Name: analytics_dashboard_dashboard_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.analytics_dashboard_dashboard_id_seq OWNED BY public.analytics_dashboard.dashboard_id;


--
-- TOC entry 232 (class 1259 OID 196779)
-- Name: api_endpoints; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.api_endpoints (
    endpoint_id bigint NOT NULL,
    endpoint_name text NOT NULL,
    endpoint_path text NOT NULL,
    method text NOT NULL,
    is_active boolean DEFAULT true,
    rate_limit integer,
    auth_required boolean DEFAULT true,
    response_cache_ttl interval,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT valid_method CHECK ((method = ANY (ARRAY['GET'::text, 'POST'::text, 'PUT'::text, 'DELETE'::text, 'PATCH'::text])))
);


ALTER TABLE public.api_endpoints OWNER TO "prosper-dev_owner";

--
-- TOC entry 233 (class 1259 OID 196789)
-- Name: api_endpoints_endpoint_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.api_endpoints_endpoint_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.api_endpoints_endpoint_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5176 (class 0 OID 0)
-- Dependencies: 233
-- Name: api_endpoints_endpoint_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.api_endpoints_endpoint_id_seq OWNED BY public.api_endpoints.endpoint_id;


--
-- TOC entry 234 (class 1259 OID 196790)
-- Name: api_keys; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.api_keys (
    key_id bigint NOT NULL,
    api_key text NOT NULL,
    client_name text NOT NULL,
    is_active boolean DEFAULT true,
    permissions jsonb,
    rate_limit integer,
    expires_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    last_used_at timestamp without time zone
);


ALTER TABLE public.api_keys OWNER TO "prosper-dev_owner";

--
-- TOC entry 235 (class 1259 OID 196797)
-- Name: api_keys_key_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.api_keys_key_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.api_keys_key_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5177 (class 0 OID 0)
-- Dependencies: 235
-- Name: api_keys_key_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.api_keys_key_id_seq OWNED BY public.api_keys.key_id;


--
-- TOC entry 236 (class 1259 OID 196798)
-- Name: api_requests; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.api_requests (
    request_id bigint NOT NULL,
    endpoint_id bigint,
    api_key_id bigint,
    request_timestamp timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    response_time interval,
    status_code integer,
    request_details jsonb,
    response_details jsonb
);


ALTER TABLE public.api_requests OWNER TO "prosper-dev_owner";

--
-- TOC entry 237 (class 1259 OID 196804)
-- Name: api_requests_request_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.api_requests_request_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.api_requests_request_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5178 (class 0 OID 0)
-- Dependencies: 237
-- Name: api_requests_request_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.api_requests_request_id_seq OWNED BY public.api_requests.request_id;


--
-- TOC entry 238 (class 1259 OID 196805)
-- Name: audit_log; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.audit_log (
    log_id integer NOT NULL,
    entity_type character varying(50),
    entity_id integer,
    action_type character varying(50),
    action_date timestamp without time zone,
    performed_by integer,
    old_values jsonb,
    new_values jsonb,
    ip_address character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.audit_log OWNER TO "prosper-dev_owner";

--
-- TOC entry 239 (class 1259 OID 196811)
-- Name: audit_log_log_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.audit_log_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.audit_log_log_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5179 (class 0 OID 0)
-- Dependencies: 239
-- Name: audit_log_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.audit_log_log_id_seq OWNED BY public.audit_log.log_id;


--
-- TOC entry 240 (class 1259 OID 196812)
-- Name: automation_workflows; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.automation_workflows (
    workflow_id bigint NOT NULL,
    workflow_name text NOT NULL,
    workflow_type text NOT NULL,
    description text,
    trigger_type text NOT NULL,
    trigger_config jsonb NOT NULL,
    steps jsonb NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    last_run timestamp without time zone,
    CONSTRAINT valid_trigger_type CHECK ((trigger_type = ANY (ARRAY['SCHEDULE'::text, 'EVENT'::text, 'CONDITION'::text, 'MANUAL'::text]))),
    CONSTRAINT valid_workflow_type CHECK ((workflow_type = ANY (ARRAY['MAINTENANCE'::text, 'MONITORING'::text, 'REPORTING'::text, 'CUSTOM'::text])))
);


ALTER TABLE public.automation_workflows OWNER TO "prosper-dev_owner";

--
-- TOC entry 241 (class 1259 OID 196822)
-- Name: automation_workflows_workflow_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.automation_workflows_workflow_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.automation_workflows_workflow_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5180 (class 0 OID 0)
-- Dependencies: 241
-- Name: automation_workflows_workflow_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.automation_workflows_workflow_id_seq OWNED BY public.automation_workflows.workflow_id;


--
-- TOC entry 242 (class 1259 OID 196823)
-- Name: backup_catalog; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.backup_catalog (
    backup_id bigint NOT NULL,
    backup_type text NOT NULL,
    start_time timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    end_time timestamp without time zone,
    status text DEFAULT 'IN_PROGRESS'::text NOT NULL,
    size_bytes bigint,
    backup_location text,
    metadata jsonb,
    CONSTRAINT valid_backup_status CHECK ((status = ANY (ARRAY['IN_PROGRESS'::text, 'COMPLETED'::text, 'FAILED'::text, 'VERIFIED'::text]))),
    CONSTRAINT valid_backup_type CHECK ((backup_type = ANY (ARRAY['FULL'::text, 'INCREMENTAL'::text, 'LOGICAL'::text, 'SCHEMA_ONLY'::text])))
);


ALTER TABLE public.backup_catalog OWNER TO "prosper-dev_owner";

--
-- TOC entry 243 (class 1259 OID 196832)
-- Name: backup_catalog_backup_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.backup_catalog_backup_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.backup_catalog_backup_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5181 (class 0 OID 0)
-- Dependencies: 243
-- Name: backup_catalog_backup_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.backup_catalog_backup_id_seq OWNED BY public.backup_catalog.backup_id;


--
-- TOC entry 244 (class 1259 OID 196833)
-- Name: backup_configurations; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.backup_configurations (
    config_id bigint NOT NULL,
    config_name text NOT NULL,
    backup_type text NOT NULL,
    schedule_expression text,
    retention_period interval,
    storage_location text NOT NULL,
    compression_type text DEFAULT 'GZIP'::text,
    encryption_config jsonb,
    pre_backup_script text,
    post_backup_script text,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT valid_backup_type CHECK ((backup_type = ANY (ARRAY['FULL'::text, 'INCREMENTAL'::text, 'LOGICAL'::text, 'SCHEMA_ONLY'::text]))),
    CONSTRAINT valid_compression CHECK ((compression_type = ANY (ARRAY['NONE'::text, 'GZIP'::text, 'ZSTD'::text, 'LZ4'::text])))
);


ALTER TABLE public.backup_configurations OWNER TO "prosper-dev_owner";

--
-- TOC entry 245 (class 1259 OID 196844)
-- Name: backup_configurations_config_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.backup_configurations_config_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.backup_configurations_config_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5182 (class 0 OID 0)
-- Dependencies: 245
-- Name: backup_configurations_config_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.backup_configurations_config_id_seq OWNED BY public.backup_configurations.config_id;


--
-- TOC entry 246 (class 1259 OID 196845)
-- Name: backup_files; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.backup_files (
    file_id bigint NOT NULL,
    backup_id bigint,
    file_path text NOT NULL,
    file_type text NOT NULL,
    file_size bigint NOT NULL,
    checksum text NOT NULL,
    compression_type text NOT NULL,
    is_encrypted boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    metadata jsonb
);


ALTER TABLE public.backup_files OWNER TO "prosper-dev_owner";

--
-- TOC entry 247 (class 1259 OID 196852)
-- Name: backup_files_file_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.backup_files_file_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.backup_files_file_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5183 (class 0 OID 0)
-- Dependencies: 247
-- Name: backup_files_file_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.backup_files_file_id_seq OWNED BY public.backup_files.file_id;


--
-- TOC entry 248 (class 1259 OID 196853)
-- Name: backup_history; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.backup_history (
    backup_id bigint NOT NULL,
    config_id bigint,
    backup_start timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    backup_end timestamp without time zone,
    backup_type text NOT NULL,
    status text DEFAULT 'RUNNING'::text NOT NULL,
    file_location text,
    file_size bigint,
    checksum text,
    error_details jsonb,
    metadata jsonb,
    CONSTRAINT valid_status CHECK ((status = ANY (ARRAY['RUNNING'::text, 'COMPLETED'::text, 'FAILED'::text, 'CORRUPTED'::text])))
);


ALTER TABLE public.backup_history OWNER TO "prosper-dev_owner";

--
-- TOC entry 249 (class 1259 OID 196861)
-- Name: backup_history_backup_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.backup_history_backup_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.backup_history_backup_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5184 (class 0 OID 0)
-- Dependencies: 249
-- Name: backup_history_backup_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.backup_history_backup_id_seq OWNED BY public.backup_history.backup_id;


--
-- TOC entry 250 (class 1259 OID 196862)
-- Name: backup_verification_log; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.backup_verification_log (
    verification_id bigint NOT NULL,
    backup_id bigint,
    verification_time timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    verification_status text NOT NULL,
    verification_details jsonb
);


ALTER TABLE public.backup_verification_log OWNER TO "prosper-dev_owner";

--
-- TOC entry 251 (class 1259 OID 196868)
-- Name: backup_verification_log_verification_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.backup_verification_log_verification_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.backup_verification_log_verification_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5185 (class 0 OID 0)
-- Dependencies: 251
-- Name: backup_verification_log_verification_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.backup_verification_log_verification_id_seq OWNED BY public.backup_verification_log.verification_id;


--
-- TOC entry 252 (class 1259 OID 196869)
-- Name: baseline_measurements; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.baseline_measurements (
    baseline_id integer NOT NULL,
    employee_id integer,
    measurement_date date,
    kpi_category character varying(50),
    initial_score numeric(5,2)
);


ALTER TABLE public.baseline_measurements OWNER TO "prosper-dev_owner";

--
-- TOC entry 253 (class 1259 OID 196872)
-- Name: baseline_measurements_baseline_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.baseline_measurements_baseline_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.baseline_measurements_baseline_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5186 (class 0 OID 0)
-- Dependencies: 253
-- Name: baseline_measurements_baseline_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.baseline_measurements_baseline_id_seq OWNED BY public.baseline_measurements.baseline_id;


--
-- TOC entry 254 (class 1259 OID 196873)
-- Name: capacity_planning; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.capacity_planning (
    planning_id integer NOT NULL,
    team_id integer,
    period_start date,
    period_end date,
    total_capacity integer,
    allocated_capacity integer,
    available_capacity integer,
    skills_distribution jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.capacity_planning OWNER TO "prosper-dev_owner";

--
-- TOC entry 255 (class 1259 OID 196879)
-- Name: capacity_planning_planning_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.capacity_planning_planning_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.capacity_planning_planning_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5187 (class 0 OID 0)
-- Dependencies: 255
-- Name: capacity_planning_planning_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.capacity_planning_planning_id_seq OWNED BY public.capacity_planning.planning_id;


--
-- TOC entry 256 (class 1259 OID 196880)
-- Name: department; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.department (
    department_id integer NOT NULL,
    department_name character varying(100) NOT NULL,
    parent_department_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    active boolean DEFAULT true
);


ALTER TABLE public.department OWNER TO "prosper-dev_owner";

--
-- TOC entry 257 (class 1259 OID 196885)
-- Name: employee_manager_hierarchy; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.employee_manager_hierarchy (
    employee_id integer NOT NULL,
    employee_name character varying(100) NOT NULL,
    manager_id integer,
    department_id integer,
    team_id integer,
    role character varying(100),
    last_updated timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    active boolean DEFAULT true
);


ALTER TABLE public.employee_manager_hierarchy OWNER TO "prosper-dev_owner";

--
-- TOC entry 258 (class 1259 OID 196890)
-- Name: project_assignments; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.project_assignments (
    assignment_id integer NOT NULL,
    employee_id integer,
    project_name character varying(100),
    role character varying(50),
    start_date date,
    end_date date,
    allocation_percentage numeric(5,2),
    impact_metrics jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    project_code character varying(50),
    billable boolean DEFAULT true,
    skills_utilized text[],
    assignment_type character varying(50),
    priority integer,
    weekly_hours numeric(5,2),
    assignment_status character varying(50) DEFAULT 'active'::character varying,
    last_modified_by integer,
    last_modified_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT project_assignments_priority_check CHECK (((priority >= 1) AND (priority <= 5))),
    CONSTRAINT valid_assignment_dates CHECK ((start_date <= end_date))
);


ALTER TABLE public.project_assignments OWNER TO "prosper-dev_owner";

--
-- TOC entry 259 (class 1259 OID 196901)
-- Name: resource_allocation; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.resource_allocation (
    allocation_id integer NOT NULL,
    employee_id integer,
    project_id integer,
    allocation_percentage numeric(5,2),
    start_date date,
    end_date date,
    role_type character varying(50),
    skills_utilized jsonb[],
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    allocation_type character varying(50),
    billing_type character varying(50),
    cost_center character varying(100),
    allocation_status character varying(50) DEFAULT 'active'::character varying,
    weekly_capacity integer DEFAULT 40,
    actual_hours numeric(5,2),
    variance_explanation text,
    last_modified_by integer,
    last_modified_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.resource_allocation OWNER TO "prosper-dev_owner";

--
-- TOC entry 260 (class 1259 OID 196910)
-- Name: capacity_planning_view; Type: VIEW; Schema: public; Owner: prosper-dev_owner
--

CREATE VIEW public.capacity_planning_view AS
 SELECT d.department_id,
    d.department_name,
    count(e.employee_id) AS total_resources,
    sum(
        CASE
            WHEN (COALESCE(ra.allocation_percentage, (0)::numeric) < (80)::numeric) THEN 1
            ELSE 0
        END) AS available_resources,
    round(avg(COALESCE(ra.allocation_percentage, (0)::numeric)), 2) AS avg_allocation_percentage,
    sum(pa.weekly_hours) AS total_allocated_hours,
    count(DISTINCT pa.project_code) AS active_projects
   FROM (((public.department d
     LEFT JOIN public.employee_manager_hierarchy e ON ((d.department_id = e.department_id)))
     LEFT JOIN public.resource_allocation ra ON ((e.employee_id = ra.employee_id)))
     LEFT JOIN public.project_assignments pa ON (((e.employee_id = pa.employee_id) AND ((pa.assignment_status)::text = 'active'::text))))
  WHERE (e.active = true)
  GROUP BY d.department_id, d.department_name;


ALTER VIEW public.capacity_planning_view OWNER TO "prosper-dev_owner";

--
-- TOC entry 261 (class 1259 OID 196915)
-- Name: career_development_plans; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.career_development_plans (
    plan_id integer NOT NULL,
    employee_id integer,
    role_current character varying(100),
    role_target character varying(100),
    timeline_months integer,
    development_areas jsonb[],
    progress_status character varying(50),
    review_dates date[],
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.career_development_plans OWNER TO "prosper-dev_owner";

--
-- TOC entry 262 (class 1259 OID 196921)
-- Name: career_development_plans_plan_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.career_development_plans_plan_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.career_development_plans_plan_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5188 (class 0 OID 0)
-- Dependencies: 262
-- Name: career_development_plans_plan_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.career_development_plans_plan_id_seq OWNED BY public.career_development_plans.plan_id;


--
-- TOC entry 263 (class 1259 OID 196922)
-- Name: career_progression; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.career_progression (
    progression_id integer NOT NULL,
    employee_id integer,
    level_start character varying(50),
    level_current character varying(50),
    progression_start_date date DEFAULT CURRENT_DATE,
    last_promotion_date date,
    skills_acquired jsonb[],
    achievements jsonb[],
    next_level_requirements jsonb,
    CONSTRAINT valid_dates CHECK (((progression_start_date <= CURRENT_DATE) AND ((last_promotion_date IS NULL) OR (last_promotion_date <= CURRENT_DATE)) AND ((last_promotion_date IS NULL) OR (last_promotion_date >= progression_start_date))))
);


ALTER TABLE public.career_progression OWNER TO "prosper-dev_owner";

--
-- TOC entry 264 (class 1259 OID 196929)
-- Name: career_progression_progression_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.career_progression_progression_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.career_progression_progression_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5189 (class 0 OID 0)
-- Dependencies: 264
-- Name: career_progression_progression_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.career_progression_progression_id_seq OWNED BY public.career_progression.progression_id;


--
-- TOC entry 265 (class 1259 OID 196930)
-- Name: certification_registry; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.certification_registry (
    cert_id integer NOT NULL,
    employee_id integer,
    certification_name character varying(100),
    category character varying(50),
    achievement_date date,
    expiry_date date,
    status character varying(20),
    score numeric(5,2),
    verification_url text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.certification_registry OWNER TO "prosper-dev_owner";

--
-- TOC entry 266 (class 1259 OID 196936)
-- Name: certification_registry_cert_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.certification_registry_cert_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.certification_registry_cert_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5190 (class 0 OID 0)
-- Dependencies: 266
-- Name: certification_registry_cert_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.certification_registry_cert_id_seq OWNED BY public.certification_registry.cert_id;


--
-- TOC entry 267 (class 1259 OID 196937)
-- Name: certification_status_summary; Type: VIEW; Schema: public; Owner: prosper-dev_owner
--

CREATE VIEW public.certification_status_summary AS
 SELECT e.employee_name,
    e.department_id,
    count(c.cert_id) AS total_certifications,
    count(
        CASE
            WHEN ((c.status)::text = 'active'::text) THEN 1
            ELSE NULL::integer
        END) AS active_certifications,
    count(
        CASE
            WHEN (c.expiry_date < (CURRENT_DATE + '90 days'::interval)) THEN 1
            ELSE NULL::integer
        END) AS expiring_soon,
    jsonb_object_agg(c.certification_name, jsonb_build_object('status', c.status, 'expiry_date', c.expiry_date, 'score', c.score)) AS certification_details
   FROM (public.employee_manager_hierarchy e
     LEFT JOIN public.certification_registry c ON ((e.employee_id = c.employee_id)))
  GROUP BY e.employee_name, e.department_id;


ALTER VIEW public.certification_status_summary OWNER TO "prosper-dev_owner";

--
-- TOC entry 268 (class 1259 OID 196942)
-- Name: communication_log; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.communication_log (
    log_id integer NOT NULL,
    template_id integer,
    recipient_id integer,
    sent_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    delivery_status character varying(50),
    open_status boolean DEFAULT false,
    response_tracking jsonb
);


ALTER TABLE public.communication_log OWNER TO "prosper-dev_owner";

--
-- TOC entry 269 (class 1259 OID 196949)
-- Name: communication_log_log_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.communication_log_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.communication_log_log_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5191 (class 0 OID 0)
-- Dependencies: 269
-- Name: communication_log_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.communication_log_log_id_seq OWNED BY public.communication_log.log_id;


--
-- TOC entry 270 (class 1259 OID 196950)
-- Name: communication_metrics; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.communication_metrics (
    metric_id integer NOT NULL,
    employee_id integer,
    communication_type character varying(50),
    frequency integer,
    effectiveness_score numeric(5,2),
    measurement_period character varying(50),
    feedback_received jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.communication_metrics OWNER TO "prosper-dev_owner";

--
-- TOC entry 271 (class 1259 OID 196956)
-- Name: communication_metrics_metric_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.communication_metrics_metric_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.communication_metrics_metric_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5192 (class 0 OID 0)
-- Dependencies: 271
-- Name: communication_metrics_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.communication_metrics_metric_id_seq OWNED BY public.communication_metrics.metric_id;


--
-- TOC entry 272 (class 1259 OID 196957)
-- Name: communication_templates; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.communication_templates (
    template_id integer NOT NULL,
    template_type character varying(100),
    subject_template text,
    body_template text,
    variables jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    last_modified timestamp without time zone
);


ALTER TABLE public.communication_templates OWNER TO "prosper-dev_owner";

--
-- TOC entry 273 (class 1259 OID 196963)
-- Name: communication_templates_template_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.communication_templates_template_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.communication_templates_template_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5193 (class 0 OID 0)
-- Dependencies: 273
-- Name: communication_templates_template_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.communication_templates_template_id_seq OWNED BY public.communication_templates.template_id;


--
-- TOC entry 274 (class 1259 OID 196964)
-- Name: competency_framework; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.competency_framework (
    framework_id integer NOT NULL,
    category character varying(50),
    level integer,
    required_skills jsonb,
    performance_indicators jsonb[],
    assessment_criteria jsonb,
    development_path jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.competency_framework OWNER TO "prosper-dev_owner";

--
-- TOC entry 275 (class 1259 OID 196970)
-- Name: competency_framework_framework_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.competency_framework_framework_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.competency_framework_framework_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5194 (class 0 OID 0)
-- Dependencies: 275
-- Name: competency_framework_framework_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.competency_framework_framework_id_seq OWNED BY public.competency_framework.framework_id;


--
-- TOC entry 276 (class 1259 OID 196971)
-- Name: configuration_history; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.configuration_history (
    history_id bigint NOT NULL,
    config_id bigint,
    previous_value text,
    new_value text,
    changed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    changed_by text NOT NULL,
    change_reason text,
    change_metadata jsonb
);


ALTER TABLE public.configuration_history OWNER TO "prosper-dev_owner";

--
-- TOC entry 277 (class 1259 OID 196977)
-- Name: configuration_history_history_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.configuration_history_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.configuration_history_history_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5195 (class 0 OID 0)
-- Dependencies: 277
-- Name: configuration_history_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.configuration_history_history_id_seq OWNED BY public.configuration_history.history_id;


--
-- TOC entry 278 (class 1259 OID 196978)
-- Name: custom_reports; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.custom_reports (
    report_id integer NOT NULL,
    report_name character varying(100),
    description text,
    query_parameters jsonb,
    schedule character varying(50),
    recipients text[],
    last_run timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.custom_reports OWNER TO "prosper-dev_owner";

--
-- TOC entry 279 (class 1259 OID 196984)
-- Name: custom_reports_report_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.custom_reports_report_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.custom_reports_report_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5196 (class 0 OID 0)
-- Dependencies: 279
-- Name: custom_reports_report_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.custom_reports_report_id_seq OWNED BY public.custom_reports.report_id;


--
-- TOC entry 280 (class 1259 OID 196985)
-- Name: customer_success_metrics; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.customer_success_metrics (
    metric_id integer NOT NULL,
    employee_id integer,
    escalation_resolution_rate numeric(5,2),
    business_expansion_impact numeric(10,2),
    service_quality_score numeric(5,2),
    measurement_period character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.customer_success_metrics OWNER TO "prosper-dev_owner";

--
-- TOC entry 281 (class 1259 OID 196989)
-- Name: customer_success_metrics_metric_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.customer_success_metrics_metric_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.customer_success_metrics_metric_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5197 (class 0 OID 0)
-- Dependencies: 281
-- Name: customer_success_metrics_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.customer_success_metrics_metric_id_seq OWNED BY public.customer_success_metrics.metric_id;


--
-- TOC entry 282 (class 1259 OID 196990)
-- Name: dashboard_color_scheme; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.dashboard_color_scheme (
    scheme_id integer NOT NULL,
    element_type character varying(50),
    color_code character varying(7),
    description text,
    is_active boolean DEFAULT true
);


ALTER TABLE public.dashboard_color_scheme OWNER TO "prosper-dev_owner";

--
-- TOC entry 283 (class 1259 OID 196996)
-- Name: dashboard_color_scheme_scheme_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.dashboard_color_scheme_scheme_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.dashboard_color_scheme_scheme_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5198 (class 0 OID 0)
-- Dependencies: 283
-- Name: dashboard_color_scheme_scheme_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.dashboard_color_scheme_scheme_id_seq OWNED BY public.dashboard_color_scheme.scheme_id;


--
-- TOC entry 284 (class 1259 OID 196997)
-- Name: dashboard_configuration; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.dashboard_configuration (
    config_id integer NOT NULL,
    dashboard_type character varying(50),
    layout_settings jsonb,
    visible_kpis jsonb,
    refresh_interval integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    last_modified timestamp without time zone
);


ALTER TABLE public.dashboard_configuration OWNER TO "prosper-dev_owner";

--
-- TOC entry 285 (class 1259 OID 197003)
-- Name: dashboard_configuration_config_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.dashboard_configuration_config_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.dashboard_configuration_config_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5199 (class 0 OID 0)
-- Dependencies: 285
-- Name: dashboard_configuration_config_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.dashboard_configuration_config_id_seq OWNED BY public.dashboard_configuration.config_id;


--
-- TOC entry 286 (class 1259 OID 197004)
-- Name: department_department_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.department_department_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.department_department_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5200 (class 0 OID 0)
-- Dependencies: 286
-- Name: department_department_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.department_department_id_seq OWNED BY public.department.department_id;


--
-- TOC entry 287 (class 1259 OID 197005)
-- Name: portfolio_cloud_services; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.portfolio_cloud_services (
    score_id integer NOT NULL,
    employee_id integer,
    initial_self_score numeric(5,2),
    concurrent_score numeric(5,2),
    delta_score numeric(5,2),
    self_score numeric(5,2),
    manager_score numeric(5,2),
    manager_comment text,
    challenge_score numeric(5,2),
    average_score numeric(5,2),
    evaluation_date date DEFAULT CURRENT_DATE,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    last_modified_by integer,
    last_modified_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    version integer DEFAULT 1,
    status character varying(50) DEFAULT 'active'::character varying,
    category public.prosper_category,
    CONSTRAINT check_portfolio_cloud_services_scores CHECK (((initial_self_score >= (0)::numeric) AND (initial_self_score <= (100)::numeric) AND ((concurrent_score >= (0)::numeric) AND (concurrent_score <= (100)::numeric)) AND ((self_score >= (0)::numeric) AND (self_score <= (100)::numeric)) AND ((manager_score >= (0)::numeric) AND (manager_score <= (100)::numeric)) AND ((challenge_score >= (0)::numeric) AND (challenge_score <= (100)::numeric))))
);


ALTER TABLE public.portfolio_cloud_services OWNER TO "prosper-dev_owner";

--
-- TOC entry 288 (class 1259 OID 197016)
-- Name: portfolio_design_success; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.portfolio_design_success (
    score_id integer NOT NULL,
    employee_id integer,
    initial_self_score numeric(5,2),
    concurrent_score numeric(5,2),
    delta_score numeric(5,2),
    self_score numeric(5,2),
    manager_score numeric(5,2),
    manager_comment text,
    challenge_score numeric(5,2),
    average_score numeric(5,2),
    evaluation_date date DEFAULT CURRENT_DATE,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    last_modified_by integer,
    last_modified_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    version integer DEFAULT 1,
    status character varying(50) DEFAULT 'active'::character varying,
    category public.prosper_category,
    CONSTRAINT check_portfolio_design_success_scores CHECK (((initial_self_score >= (0)::numeric) AND (initial_self_score <= (100)::numeric) AND ((concurrent_score >= (0)::numeric) AND (concurrent_score <= (100)::numeric)) AND ((self_score >= (0)::numeric) AND (self_score <= (100)::numeric)) AND ((manager_score >= (0)::numeric) AND (manager_score <= (100)::numeric)) AND ((challenge_score >= (0)::numeric) AND (challenge_score <= (100)::numeric))))
);


ALTER TABLE public.portfolio_design_success OWNER TO "prosper-dev_owner";

--
-- TOC entry 289 (class 1259 OID 197027)
-- Name: portfolio_premium_engagement; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.portfolio_premium_engagement (
    score_id integer NOT NULL,
    employee_id integer,
    initial_self_score numeric(5,2),
    concurrent_score numeric(5,2),
    delta_score numeric(5,2),
    self_score numeric(5,2),
    manager_score numeric(5,2),
    manager_comment text,
    challenge_score numeric(5,2),
    average_score numeric(5,2),
    evaluation_date date DEFAULT CURRENT_DATE,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    last_modified_by integer,
    last_modified_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    version integer DEFAULT 1,
    status character varying(50) DEFAULT 'active'::character varying,
    category public.prosper_category,
    CONSTRAINT check_portfolio_premium_engagement_scores CHECK (((initial_self_score >= (0)::numeric) AND (initial_self_score <= (100)::numeric) AND ((concurrent_score >= (0)::numeric) AND (concurrent_score <= (100)::numeric)) AND ((self_score >= (0)::numeric) AND (self_score <= (100)::numeric)) AND ((manager_score >= (0)::numeric) AND (manager_score <= (100)::numeric)) AND ((challenge_score >= (0)::numeric) AND (challenge_score <= (100)::numeric))))
);


ALTER TABLE public.portfolio_premium_engagement OWNER TO "prosper-dev_owner";

--
-- TOC entry 290 (class 1259 OID 197038)
-- Name: employee_performance_dashboard; Type: VIEW; Schema: public; Owner: prosper-dev_owner
--

CREATE VIEW public.employee_performance_dashboard AS
 WITH latest_scores AS (
         SELECT portfolio_design_success.employee_id,
            'PORTFOLIO'::public.prosper_category AS category,
            portfolio_design_success.average_score,
            portfolio_design_success.evaluation_date,
            row_number() OVER (PARTITION BY portfolio_design_success.employee_id ORDER BY portfolio_design_success.evaluation_date DESC) AS rn
           FROM public.portfolio_design_success
        UNION ALL
         SELECT portfolio_premium_engagement.employee_id,
            'RELATIONSHIP'::public.prosper_category AS prosper_category,
            portfolio_premium_engagement.average_score,
            portfolio_premium_engagement.evaluation_date,
            row_number() OVER (PARTITION BY portfolio_premium_engagement.employee_id ORDER BY portfolio_premium_engagement.evaluation_date DESC) AS rn
           FROM public.portfolio_premium_engagement
        UNION ALL
         SELECT portfolio_cloud_services.employee_id,
            'OPERATIONS'::public.prosper_category AS prosper_category,
            portfolio_cloud_services.average_score,
            portfolio_cloud_services.evaluation_date,
            row_number() OVER (PARTITION BY portfolio_cloud_services.employee_id ORDER BY portfolio_cloud_services.evaluation_date DESC) AS rn
           FROM public.portfolio_cloud_services
        )
 SELECT emh.employee_id,
    emh.employee_name,
    emh.manager_id,
    emh.department_id,
    d.department_name,
    ls.category,
    ls.average_score,
    ls.evaluation_date,
        CASE
            WHEN (ls.average_score >= 8.5) THEN 'Outstanding'::text
            WHEN (ls.average_score >= 7.5) THEN 'Exceeds Expectations'::text
            WHEN (ls.average_score >= 6.5) THEN 'Meets Expectations'::text
            WHEN (ls.average_score >= 5.0) THEN 'Needs Improvement'::text
            ELSE 'Critical Attention Required'::text
        END AS performance_level,
    lag(ls.average_score) OVER (PARTITION BY emh.employee_id, ls.category ORDER BY ls.evaluation_date) AS previous_score,
    (ls.average_score - lag(ls.average_score) OVER (PARTITION BY emh.employee_id, ls.category ORDER BY ls.evaluation_date)) AS score_change
   FROM ((latest_scores ls
     JOIN public.employee_manager_hierarchy emh ON ((ls.employee_id = emh.employee_id)))
     JOIN public.department d ON ((emh.department_id = d.department_id)))
  WHERE (ls.rn = 1);


ALTER VIEW public.employee_performance_dashboard OWNER TO "prosper-dev_owner";

--
-- TOC entry 291 (class 1259 OID 197043)
-- Name: department_performance_summary; Type: VIEW; Schema: public; Owner: prosper-dev_owner
--

CREATE VIEW public.department_performance_summary AS
 WITH dept_scores AS (
         SELECT emh.department_id,
            d.department_name,
            epd.category,
            count(DISTINCT emh.employee_id) AS total_employees,
            round(avg(epd.average_score), 2) AS avg_score,
            count(
                CASE
                    WHEN (epd.average_score >= (8)::numeric) THEN 1
                    ELSE NULL::integer
                END) AS high_performers,
            count(
                CASE
                    WHEN (epd.average_score < (6)::numeric) THEN 1
                    ELSE NULL::integer
                END) AS needs_improvement,
            min(epd.average_score) AS min_score,
            max(epd.average_score) AS max_score,
            percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY ((epd.average_score)::double precision)) AS median_score
           FROM ((public.employee_performance_dashboard epd
             JOIN public.employee_manager_hierarchy emh ON ((epd.employee_id = emh.employee_id)))
             JOIN public.department d ON ((emh.department_id = d.department_id)))
          GROUP BY emh.department_id, d.department_name, epd.category
        )
 SELECT department_id,
    department_name,
    category,
    total_employees,
    avg_score,
    high_performers,
    needs_improvement,
    round(((100.0 * (high_performers)::numeric) / (NULLIF(total_employees, 0))::numeric), 2) AS high_performer_percentage,
    round(((100.0 * (needs_improvement)::numeric) / (NULLIF(total_employees, 0))::numeric), 2) AS improvement_needed_percentage,
    min_score,
    max_score,
    median_score,
        CASE
            WHEN (avg_score >= (8)::numeric) THEN 'High Performing'::text
            WHEN (avg_score >= (7)::numeric) THEN 'Strong'::text
            WHEN (avg_score >= (6)::numeric) THEN 'Stable'::text
            ELSE 'Needs Attention'::text
        END AS department_status
   FROM dept_scores;


ALTER VIEW public.department_performance_summary OWNER TO "prosper-dev_owner";

--
-- TOC entry 292 (class 1259 OID 197048)
-- Name: deployment_steps; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.deployment_steps (
    step_id bigint NOT NULL,
    deployment_id bigint,
    step_number integer NOT NULL,
    step_type text NOT NULL,
    status text DEFAULT 'PENDING'::text NOT NULL,
    started_at timestamp without time zone,
    completed_at timestamp without time zone,
    sql_command text,
    execution_result jsonb,
    CONSTRAINT valid_step_type CHECK ((step_type = ANY (ARRAY['SQL'::text, 'FUNCTION'::text, 'VALIDATION'::text, 'CUSTOM'::text])))
);


ALTER TABLE public.deployment_steps OWNER TO "prosper-dev_owner";

--
-- TOC entry 293 (class 1259 OID 197055)
-- Name: deployment_steps_step_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.deployment_steps_step_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.deployment_steps_step_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5201 (class 0 OID 0)
-- Dependencies: 293
-- Name: deployment_steps_step_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.deployment_steps_step_id_seq OWNED BY public.deployment_steps.step_id;


--
-- TOC entry 294 (class 1259 OID 197056)
-- Name: deployments; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.deployments (
    deployment_id bigint NOT NULL,
    version text NOT NULL,
    deployment_type text NOT NULL,
    status text NOT NULL,
    started_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    completed_at timestamp without time zone,
    deployed_by text NOT NULL,
    deployment_plan jsonb NOT NULL,
    rollback_plan jsonb,
    CONSTRAINT valid_deployment_type CHECK ((deployment_type = ANY (ARRAY['FULL'::text, 'INCREMENTAL'::text, 'HOTFIX'::text, 'ROLLBACK'::text]))),
    CONSTRAINT valid_status CHECK ((status = ANY (ARRAY['PENDING'::text, 'IN_PROGRESS'::text, 'COMPLETED'::text, 'FAILED'::text, 'ROLLED_BACK'::text])))
);


ALTER TABLE public.deployments OWNER TO "prosper-dev_owner";

--
-- TOC entry 295 (class 1259 OID 197064)
-- Name: deployments_deployment_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.deployments_deployment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.deployments_deployment_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5202 (class 0 OID 0)
-- Dependencies: 295
-- Name: deployments_deployment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.deployments_deployment_id_seq OWNED BY public.deployments.deployment_id;


--
-- TOC entry 296 (class 1259 OID 197065)
-- Name: development_paths; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.development_paths (
    path_id integer NOT NULL,
    category public.prosper_category,
    level integer,
    required_skills jsonb,
    required_scores jsonb,
    certifications jsonb,
    next_level_requirements text,
    CONSTRAINT valid_level CHECK ((level >= 1))
);


ALTER TABLE public.development_paths OWNER TO "prosper-dev_owner";

--
-- TOC entry 297 (class 1259 OID 197071)
-- Name: development_paths_path_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.development_paths_path_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.development_paths_path_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5203 (class 0 OID 0)
-- Dependencies: 297
-- Name: development_paths_path_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.development_paths_path_id_seq OWNED BY public.development_paths.path_id;


--
-- TOC entry 298 (class 1259 OID 197072)
-- Name: employee_achievements; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.employee_achievements (
    id integer NOT NULL,
    employee_id integer,
    achievement_id integer,
    earned_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    points_earned integer,
    visibility_level character varying(20)
);


ALTER TABLE public.employee_achievements OWNER TO "prosper-dev_owner";

--
-- TOC entry 299 (class 1259 OID 197076)
-- Name: employee_achievements_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.employee_achievements_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.employee_achievements_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5204 (class 0 OID 0)
-- Dependencies: 299
-- Name: employee_achievements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.employee_achievements_id_seq OWNED BY public.employee_achievements.id;


--
-- TOC entry 300 (class 1259 OID 197077)
-- Name: employee_goals; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.employee_goals (
    goal_id integer NOT NULL,
    employee_id integer,
    period_id integer,
    category character varying(50),
    goal_description text,
    target_date date,
    priority character varying(20),
    status character varying(50),
    progress_percentage numeric(5,2),
    metrics jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.employee_goals OWNER TO "prosper-dev_owner";

--
-- TOC entry 301 (class 1259 OID 197083)
-- Name: employee_goals_goal_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.employee_goals_goal_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.employee_goals_goal_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5205 (class 0 OID 0)
-- Dependencies: 301
-- Name: employee_goals_goal_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.employee_goals_goal_id_seq OWNED BY public.employee_goals.goal_id;


--
-- TOC entry 302 (class 1259 OID 197084)
-- Name: employee_manager_hierarchy_employee_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.employee_manager_hierarchy_employee_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.employee_manager_hierarchy_employee_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5206 (class 0 OID 0)
-- Dependencies: 302
-- Name: employee_manager_hierarchy_employee_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.employee_manager_hierarchy_employee_id_seq OWNED BY public.employee_manager_hierarchy.employee_id;


--
-- TOC entry 303 (class 1259 OID 197085)
-- Name: employee_recognition; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.employee_recognition (
    recognition_id integer NOT NULL,
    employee_id integer,
    recognizer_id integer,
    recognition_type character varying(50),
    description text,
    award_date date,
    impact_level character varying(20),
    visibility character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.employee_recognition OWNER TO "prosper-dev_owner";

--
-- TOC entry 304 (class 1259 OID 197091)
-- Name: employee_recognition_recognition_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.employee_recognition_recognition_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.employee_recognition_recognition_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5207 (class 0 OID 0)
-- Dependencies: 304
-- Name: employee_recognition_recognition_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.employee_recognition_recognition_id_seq OWNED BY public.employee_recognition.recognition_id;


--
-- TOC entry 305 (class 1259 OID 197092)
-- Name: employee_risk_assessment; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.employee_risk_assessment (
    assessment_id integer NOT NULL,
    employee_id integer,
    assessment_date date,
    risk_level character varying(20),
    risk_factors jsonb,
    mitigation_plan text,
    follow_up_date date
);


ALTER TABLE public.employee_risk_assessment OWNER TO "prosper-dev_owner";

--
-- TOC entry 306 (class 1259 OID 197097)
-- Name: employee_risk_assessment_assessment_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.employee_risk_assessment_assessment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.employee_risk_assessment_assessment_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5208 (class 0 OID 0)
-- Dependencies: 306
-- Name: employee_risk_assessment_assessment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.employee_risk_assessment_assessment_id_seq OWNED BY public.employee_risk_assessment.assessment_id;


--
-- TOC entry 307 (class 1259 OID 197098)
-- Name: skills_inventory; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.skills_inventory (
    skill_id integer NOT NULL,
    employee_id integer,
    category character varying(50),
    skill_name character varying(100),
    proficiency_level numeric(5,2),
    last_assessed date,
    certification_proof text[],
    experience_months integer,
    last_used_date date,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.skills_inventory OWNER TO "prosper-dev_owner";

--
-- TOC entry 308 (class 1259 OID 197104)
-- Name: employee_skill_matrix; Type: VIEW; Schema: public; Owner: prosper-dev_owner
--

CREATE VIEW public.employee_skill_matrix AS
 SELECT e.employee_name,
    e.department_id,
    s.category,
    jsonb_object_agg(s.skill_name, jsonb_build_object('proficiency', s.proficiency_level, 'last_assessed', s.last_assessed, 'experience_months', s.experience_months)) AS skills
   FROM (public.employee_manager_hierarchy e
     LEFT JOIN public.skills_inventory s ON ((e.employee_id = s.employee_id)))
  GROUP BY e.employee_name, e.department_id, s.category;


ALTER VIEW public.employee_skill_matrix OWNER TO "prosper-dev_owner";

--
-- TOC entry 309 (class 1259 OID 197109)
-- Name: enablement_activities_catalog; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.enablement_activities_catalog (
    activity_id integer NOT NULL,
    activity_name character varying(200),
    category character varying(100),
    points_value integer,
    required_for_level character varying(50)[],
    validity_period integer,
    is_active boolean DEFAULT true
);


ALTER TABLE public.enablement_activities_catalog OWNER TO "prosper-dev_owner";

--
-- TOC entry 310 (class 1259 OID 197115)
-- Name: enablement_activities_catalog_activity_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.enablement_activities_catalog_activity_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.enablement_activities_catalog_activity_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5209 (class 0 OID 0)
-- Dependencies: 310
-- Name: enablement_activities_catalog_activity_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.enablement_activities_catalog_activity_id_seq OWNED BY public.enablement_activities_catalog.activity_id;


--
-- TOC entry 311 (class 1259 OID 197116)
-- Name: enablement_points_tracking; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.enablement_points_tracking (
    tracking_id integer NOT NULL,
    employee_id integer,
    activity_type character varying(100),
    points_earned integer,
    completion_date date,
    verification_status character varying(50),
    expiry_date date,
    CONSTRAINT valid_points CHECK ((points_earned >= 0))
);


ALTER TABLE public.enablement_points_tracking OWNER TO "prosper-dev_owner";

--
-- TOC entry 312 (class 1259 OID 197120)
-- Name: enablement_points_tracking_tracking_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.enablement_points_tracking_tracking_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.enablement_points_tracking_tracking_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5210 (class 0 OID 0)
-- Dependencies: 312
-- Name: enablement_points_tracking_tracking_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.enablement_points_tracking_tracking_id_seq OWNED BY public.enablement_points_tracking.tracking_id;


--
-- TOC entry 313 (class 1259 OID 197121)
-- Name: enablement_progress_metrics; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.enablement_progress_metrics (
    metric_id integer NOT NULL,
    period_start date,
    period_end date,
    total_participants integer,
    completed_activities integer,
    participation_rate numeric(5,2),
    activity_breakdown jsonb,
    CONSTRAINT valid_progress CHECK (((participation_rate >= (0)::numeric) AND (participation_rate <= (100)::numeric)))
);


ALTER TABLE public.enablement_progress_metrics OWNER TO "prosper-dev_owner";

--
-- TOC entry 314 (class 1259 OID 197127)
-- Name: enablement_progress_metrics_metric_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.enablement_progress_metrics_metric_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.enablement_progress_metrics_metric_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5211 (class 0 OID 0)
-- Dependencies: 314
-- Name: enablement_progress_metrics_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.enablement_progress_metrics_metric_id_seq OWNED BY public.enablement_progress_metrics.metric_id;


--
-- TOC entry 315 (class 1259 OID 197128)
-- Name: engagement_predictions; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.engagement_predictions (
    prediction_id integer NOT NULL,
    metric_type character varying(50),
    target_date date,
    predicted_value numeric(5,2),
    confidence_level numeric(5,2),
    factors_considered jsonb,
    model_version character varying(50)
);


ALTER TABLE public.engagement_predictions OWNER TO "prosper-dev_owner";

--
-- TOC entry 316 (class 1259 OID 197133)
-- Name: engagement_predictions_prediction_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.engagement_predictions_prediction_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.engagement_predictions_prediction_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5212 (class 0 OID 0)
-- Dependencies: 316
-- Name: engagement_predictions_prediction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.engagement_predictions_prediction_id_seq OWNED BY public.engagement_predictions.prediction_id;


--
-- TOC entry 317 (class 1259 OID 197134)
-- Name: engagement_risk_factors; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.engagement_risk_factors (
    factor_id integer NOT NULL,
    factor_name character varying(100),
    weight numeric(3,2),
    threshold_values jsonb,
    data_source character varying(50),
    calculation_method text
);


ALTER TABLE public.engagement_risk_factors OWNER TO "prosper-dev_owner";

--
-- TOC entry 318 (class 1259 OID 197139)
-- Name: engagement_risk_factors_factor_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.engagement_risk_factors_factor_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.engagement_risk_factors_factor_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5213 (class 0 OID 0)
-- Dependencies: 318
-- Name: engagement_risk_factors_factor_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.engagement_risk_factors_factor_id_seq OWNED BY public.engagement_risk_factors.factor_id;


--
-- TOC entry 319 (class 1259 OID 197140)
-- Name: evaluation_periods; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.evaluation_periods (
    period_id integer NOT NULL,
    period_name character varying(100),
    start_date date,
    end_date date,
    status character varying(50),
    category character varying(50),
    reminder_dates jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.evaluation_periods OWNER TO "prosper-dev_owner";

--
-- TOC entry 320 (class 1259 OID 197146)
-- Name: evaluation_periods_period_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.evaluation_periods_period_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.evaluation_periods_period_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5214 (class 0 OID 0)
-- Dependencies: 320
-- Name: evaluation_periods_period_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.evaluation_periods_period_id_seq OWNED BY public.evaluation_periods.period_id;


--
-- TOC entry 321 (class 1259 OID 197147)
-- Name: evaluation_submissions; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.evaluation_submissions (
    submission_id integer NOT NULL,
    period_id integer,
    employee_id integer,
    category character varying(50),
    submission_date timestamp without time zone,
    status character varying(50),
    last_modified timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.evaluation_submissions OWNER TO "prosper-dev_owner";

--
-- TOC entry 322 (class 1259 OID 197151)
-- Name: evaluation_submissions_submission_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.evaluation_submissions_submission_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.evaluation_submissions_submission_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5215 (class 0 OID 0)
-- Dependencies: 322
-- Name: evaluation_submissions_submission_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.evaluation_submissions_submission_id_seq OWNED BY public.evaluation_submissions.submission_id;


--
-- TOC entry 323 (class 1259 OID 197152)
-- Name: performance_scores; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.performance_scores (
    score_id integer NOT NULL,
    employee_id integer,
    category character varying(50),
    initial_self_score numeric(5,2),
    concurrent_score numeric(5,2),
    delta_score numeric(5,2),
    self_score numeric(5,2),
    manager_score numeric(5,2),
    manager_comment text,
    challenge_score numeric(5,2),
    average_score numeric(5,2),
    evaluation_date date DEFAULT CURRENT_DATE,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    service_id integer,
    comments text,
    last_modified_by integer,
    last_modified_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_score_ranges CHECK (((initial_self_score >= (0)::numeric) AND (initial_self_score <= (100)::numeric) AND ((concurrent_score >= (0)::numeric) AND (concurrent_score <= (100)::numeric)) AND ((self_score >= (0)::numeric) AND (self_score <= (100)::numeric)) AND ((manager_score >= (0)::numeric) AND (manager_score <= (100)::numeric)) AND ((challenge_score >= (0)::numeric) AND (challenge_score <= (100)::numeric)))),
    CONSTRAINT valid_challenge_score CHECK (((challenge_score >= (0)::numeric) AND (challenge_score <= (100)::numeric))),
    CONSTRAINT valid_concurrent_score CHECK (((concurrent_score >= (0)::numeric) AND (concurrent_score <= (100)::numeric))),
    CONSTRAINT valid_initial_self_score CHECK (((initial_self_score >= (0)::numeric) AND (initial_self_score <= (100)::numeric))),
    CONSTRAINT valid_manager_score CHECK (((manager_score >= (0)::numeric) AND (manager_score <= (100)::numeric))),
    CONSTRAINT valid_self_score CHECK (((self_score >= (0)::numeric) AND (self_score <= (100)::numeric)))
);


ALTER TABLE public.performance_scores OWNER TO "prosper-dev_owner";

--
-- TOC entry 324 (class 1259 OID 197166)
-- Name: executive_prosper_summary; Type: MATERIALIZED VIEW; Schema: public; Owner: prosper-dev_owner
--

CREATE MATERIALIZED VIEW public.executive_prosper_summary AS
 WITH portfolio_scores AS (
         SELECT d.department_name,
            emh.employee_id,
            ps.category,
            ps.average_score,
            ps.evaluation_date
           FROM ((public.department d
             JOIN public.employee_manager_hierarchy emh ON ((d.department_id = emh.department_id)))
             JOIN public.performance_scores ps ON ((emh.employee_id = ps.employee_id)))
          WHERE (emh.active = true)
        )
 SELECT department_name,
    count(DISTINCT employee_id) AS total_employees,
    round(avg(average_score), 2) AS overall_score,
    jsonb_build_object('portfolio', avg(
        CASE
            WHEN ((category)::text = 'PORTFOLIO'::text) THEN average_score
            ELSE NULL::numeric
        END), 'relationship', avg(
        CASE
            WHEN ((category)::text = 'RELATIONSHIP'::text) THEN average_score
            ELSE NULL::numeric
        END), 'operations', avg(
        CASE
            WHEN ((category)::text = 'OPERATIONS'::text) THEN average_score
            ELSE NULL::numeric
        END)) AS category_scores,
    round((((count(
        CASE
            WHEN (average_score >= (8)::numeric) THEN 1
            ELSE NULL::integer
        END))::numeric / (NULLIF(count(DISTINCT employee_id), 0))::numeric) * (100)::numeric), 2) AS high_performer_percentage,
    jsonb_build_object('critical_attention', count(
        CASE
            WHEN (average_score < (5)::numeric) THEN 1
            ELSE NULL::integer
        END), 'needs_improvement', count(
        CASE
            WHEN ((average_score >= (5)::numeric) AND (average_score < 6.5)) THEN 1
            ELSE NULL::integer
        END), 'meets_expectations', count(
        CASE
            WHEN ((average_score >= 6.5) AND (average_score < 7.5)) THEN 1
            ELSE NULL::integer
        END), 'exceeds_expectations', count(
        CASE
            WHEN ((average_score >= 7.5) AND (average_score < 8.5)) THEN 1
            ELSE NULL::integer
        END), 'outstanding', count(
        CASE
            WHEN (average_score >= 8.5) THEN 1
            ELSE NULL::integer
        END)) AS performance_distribution
   FROM portfolio_scores
  WHERE (evaluation_date >= (CURRENT_DATE - '3 mons'::interval))
  GROUP BY department_name
  WITH NO DATA;


ALTER MATERIALIZED VIEW public.executive_prosper_summary OWNER TO "prosper-dev_owner";

--
-- TOC entry 325 (class 1259 OID 197173)
-- Name: feedback_actions; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.feedback_actions (
    action_id integer NOT NULL,
    suggestion_id integer,
    action_type character varying(50),
    assigned_to integer,
    due_date date,
    completion_status character varying(20),
    impact_measurement jsonb
);


ALTER TABLE public.feedback_actions OWNER TO "prosper-dev_owner";

--
-- TOC entry 326 (class 1259 OID 197178)
-- Name: feedback_actions_action_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.feedback_actions_action_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.feedback_actions_action_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5216 (class 0 OID 0)
-- Dependencies: 326
-- Name: feedback_actions_action_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.feedback_actions_action_id_seq OWNED BY public.feedback_actions.action_id;


--
-- TOC entry 327 (class 1259 OID 197179)
-- Name: performance_feedback; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.performance_feedback (
    feedback_id integer NOT NULL,
    employee_id integer,
    provider_id integer,
    category character varying(50),
    feedback_type character varying(50),
    feedback_date date,
    content text,
    visibility character varying(50),
    impact_rating numeric(5,2),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.performance_feedback OWNER TO "prosper-dev_owner";

--
-- TOC entry 328 (class 1259 OID 197185)
-- Name: feedback_analysis_summary; Type: VIEW; Schema: public; Owner: prosper-dev_owner
--

CREATE VIEW public.feedback_analysis_summary AS
 WITH feedback_types AS (
         SELECT e_1.employee_name,
            e_1.department_id,
            f_1.feedback_type,
            count(*) AS type_count
           FROM (public.employee_manager_hierarchy e_1
             LEFT JOIN public.performance_feedback f_1 ON ((e_1.employee_id = f_1.employee_id)))
          WHERE (f_1.feedback_date >= (CURRENT_DATE - '1 year'::interval))
          GROUP BY e_1.employee_name, e_1.department_id, f_1.feedback_type
        )
 SELECT e.employee_name,
    e.department_id,
    count(f.feedback_id) AS total_feedback,
    round(avg(f.impact_rating), 2) AS avg_impact_rating,
    count(
        CASE
            WHEN ((f.feedback_type)::text = 'improvement'::text) THEN 1
            ELSE NULL::integer
        END) AS improvement_feedback_count,
    jsonb_object_agg(COALESCE(ft.feedback_type, 'undefined'::character varying), COALESCE(ft.type_count, (0)::bigint)) AS feedback_type_distribution
   FROM ((public.employee_manager_hierarchy e
     LEFT JOIN public.performance_feedback f ON ((e.employee_id = f.employee_id)))
     LEFT JOIN feedback_types ft ON ((((e.employee_name)::text = (ft.employee_name)::text) AND (e.department_id = ft.department_id))))
  WHERE (f.feedback_date >= (CURRENT_DATE - '1 year'::interval))
  GROUP BY e.employee_name, e.department_id;


ALTER VIEW public.feedback_analysis_summary OWNER TO "prosper-dev_owner";

--
-- TOC entry 329 (class 1259 OID 197190)
-- Name: form_submission_windows; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.form_submission_windows (
    window_id integer NOT NULL,
    form_type character varying(50),
    start_date timestamp without time zone,
    end_date timestamp without time zone,
    employee_id integer,
    status character varying(20),
    CONSTRAINT valid_window CHECK ((end_date > start_date))
);


ALTER TABLE public.form_submission_windows OWNER TO "prosper-dev_owner";

--
-- TOC entry 330 (class 1259 OID 197194)
-- Name: form_submission_windows_window_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.form_submission_windows_window_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.form_submission_windows_window_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5217 (class 0 OID 0)
-- Dependencies: 330
-- Name: form_submission_windows_window_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.form_submission_windows_window_id_seq OWNED BY public.form_submission_windows.window_id;


--
-- TOC entry 331 (class 1259 OID 197195)
-- Name: goal_achievement_metrics; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.goal_achievement_metrics (
    metric_id integer NOT NULL,
    employee_id integer,
    period_start date,
    period_end date,
    total_goals integer,
    goals_achieved integer,
    achievement_rate numeric(5,2),
    target_threshold numeric(5,2) DEFAULT 80.00,
    CONSTRAINT valid_achievement CHECK (((achievement_rate >= (0)::numeric) AND (achievement_rate <= (100)::numeric)))
);


ALTER TABLE public.goal_achievement_metrics OWNER TO "prosper-dev_owner";

--
-- TOC entry 332 (class 1259 OID 197200)
-- Name: goal_achievement_metrics_metric_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.goal_achievement_metrics_metric_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.goal_achievement_metrics_metric_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5218 (class 0 OID 0)
-- Dependencies: 332
-- Name: goal_achievement_metrics_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.goal_achievement_metrics_metric_id_seq OWNED BY public.goal_achievement_metrics.metric_id;


--
-- TOC entry 333 (class 1259 OID 197201)
-- Name: goal_dependencies; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.goal_dependencies (
    dependency_id integer NOT NULL,
    goal_id integer,
    dependent_goal_id integer,
    dependency_type character varying(50),
    impact_level character varying(20),
    status character varying(20)
);


ALTER TABLE public.goal_dependencies OWNER TO "prosper-dev_owner";

--
-- TOC entry 334 (class 1259 OID 197204)
-- Name: goal_dependencies_dependency_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.goal_dependencies_dependency_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.goal_dependencies_dependency_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5219 (class 0 OID 0)
-- Dependencies: 334
-- Name: goal_dependencies_dependency_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.goal_dependencies_dependency_id_seq OWNED BY public.goal_dependencies.dependency_id;


--
-- TOC entry 335 (class 1259 OID 197205)
-- Name: goal_milestones; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.goal_milestones (
    milestone_id integer NOT NULL,
    goal_id integer,
    milestone_name character varying(100),
    target_date date,
    completion_status character varying(20),
    blocking_issues jsonb,
    support_needed text
);


ALTER TABLE public.goal_milestones OWNER TO "prosper-dev_owner";

--
-- TOC entry 336 (class 1259 OID 197210)
-- Name: goal_milestones_milestone_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.goal_milestones_milestone_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.goal_milestones_milestone_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5220 (class 0 OID 0)
-- Dependencies: 336
-- Name: goal_milestones_milestone_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.goal_milestones_milestone_id_seq OWNED BY public.goal_milestones.milestone_id;


--
-- TOC entry 337 (class 1259 OID 197211)
-- Name: goal_reviews; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.goal_reviews (
    review_id integer NOT NULL,
    goal_id integer,
    review_date date,
    reviewer_id integer,
    status character varying(50),
    comments text,
    next_steps jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.goal_reviews OWNER TO "prosper-dev_owner";

--
-- TOC entry 338 (class 1259 OID 197217)
-- Name: goal_reviews_review_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.goal_reviews_review_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.goal_reviews_review_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5221 (class 0 OID 0)
-- Dependencies: 338
-- Name: goal_reviews_review_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.goal_reviews_review_id_seq OWNED BY public.goal_reviews.review_id;


--
-- TOC entry 339 (class 1259 OID 197218)
-- Name: health_checks; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.health_checks (
    check_id bigint NOT NULL,
    check_name text NOT NULL,
    check_type text NOT NULL,
    check_query text NOT NULL,
    threshold_config jsonb,
    is_active boolean DEFAULT true,
    last_check timestamp without time zone,
    last_status text,
    notification_config jsonb,
    CONSTRAINT valid_check_type CHECK ((check_type = ANY (ARRAY['PERFORMANCE'::text, 'STORAGE'::text, 'CONNECTIVITY'::text, 'REPLICATION'::text, 'CUSTOM'::text])))
);


ALTER TABLE public.health_checks OWNER TO "prosper-dev_owner";

--
-- TOC entry 340 (class 1259 OID 197225)
-- Name: health_checks_check_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.health_checks_check_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.health_checks_check_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5222 (class 0 OID 0)
-- Dependencies: 340
-- Name: health_checks_check_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.health_checks_check_id_seq OWNED BY public.health_checks.check_id;


--
-- TOC entry 341 (class 1259 OID 197226)
-- Name: implementation_milestones; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.implementation_milestones (
    milestone_id integer NOT NULL,
    milestone_name character varying(200),
    target_date date,
    actual_date date,
    status character varying(50),
    dependencies integer[],
    notes text,
    CONSTRAINT valid_dates CHECK ((actual_date >= target_date))
);


ALTER TABLE public.implementation_milestones OWNER TO "prosper-dev_owner";

--
-- TOC entry 342 (class 1259 OID 197232)
-- Name: implementation_milestones_milestone_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.implementation_milestones_milestone_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.implementation_milestones_milestone_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5223 (class 0 OID 0)
-- Dependencies: 342
-- Name: implementation_milestones_milestone_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.implementation_milestones_milestone_id_seq OWNED BY public.implementation_milestones.milestone_id;


--
-- TOC entry 343 (class 1259 OID 197233)
-- Name: improvement_initiatives; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.improvement_initiatives (
    initiative_id integer NOT NULL,
    employee_id integer,
    category character varying(50),
    description text,
    start_date date,
    target_completion_date date,
    status character varying(50),
    progress_metrics jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.improvement_initiatives OWNER TO "prosper-dev_owner";

--
-- TOC entry 344 (class 1259 OID 197239)
-- Name: improvement_initiatives_initiative_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.improvement_initiatives_initiative_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.improvement_initiatives_initiative_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5224 (class 0 OID 0)
-- Dependencies: 344
-- Name: improvement_initiatives_initiative_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.improvement_initiatives_initiative_id_seq OWNED BY public.improvement_initiatives.initiative_id;


--
-- TOC entry 345 (class 1259 OID 197240)
-- Name: improvement_suggestions; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.improvement_suggestions (
    suggestion_id integer NOT NULL,
    employee_id integer,
    category character varying(50),
    suggestion_text text,
    impact_area character varying(50),
    status character varying(20),
    votes integer DEFAULT 0,
    implementation_status character varying(20),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.improvement_suggestions OWNER TO "prosper-dev_owner";

--
-- TOC entry 346 (class 1259 OID 197247)
-- Name: improvement_suggestions_suggestion_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.improvement_suggestions_suggestion_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.improvement_suggestions_suggestion_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5225 (class 0 OID 0)
-- Dependencies: 346
-- Name: improvement_suggestions_suggestion_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.improvement_suggestions_suggestion_id_seq OWNED BY public.improvement_suggestions.suggestion_id;


--
-- TOC entry 347 (class 1259 OID 197248)
-- Name: job_executions; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.job_executions (
    execution_id bigint NOT NULL,
    job_id bigint,
    scheduled_time timestamp without time zone NOT NULL,
    started_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    completed_at timestamp without time zone,
    status text DEFAULT 'RUNNING'::text NOT NULL,
    result_data jsonb,
    error_details jsonb,
    CONSTRAINT valid_status CHECK ((status = ANY (ARRAY['RUNNING'::text, 'COMPLETED'::text, 'FAILED'::text, 'SKIPPED'::text])))
);


ALTER TABLE public.job_executions OWNER TO "prosper-dev_owner";

--
-- TOC entry 348 (class 1259 OID 197256)
-- Name: job_executions_execution_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.job_executions_execution_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.job_executions_execution_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5226 (class 0 OID 0)
-- Dependencies: 348
-- Name: job_executions_execution_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.job_executions_execution_id_seq OWNED BY public.job_executions.execution_id;


--
-- TOC entry 349 (class 1259 OID 197257)
-- Name: knowledge_transfer; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.knowledge_transfer (
    transfer_id integer NOT NULL,
    source_employee_id integer,
    target_employee_id integer,
    category character varying(50),
    knowledge_area character varying(100),
    start_date date,
    completion_date date,
    transfer_status character varying(50),
    effectiveness_metrics jsonb,
    verification_methods jsonb[],
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.knowledge_transfer OWNER TO "prosper-dev_owner";

--
-- TOC entry 350 (class 1259 OID 197263)
-- Name: knowledge_transfer_transfer_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.knowledge_transfer_transfer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.knowledge_transfer_transfer_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5227 (class 0 OID 0)
-- Dependencies: 350
-- Name: knowledge_transfer_transfer_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.knowledge_transfer_transfer_id_seq OWNED BY public.knowledge_transfer.transfer_id;


--
-- TOC entry 351 (class 1259 OID 197264)
-- Name: kpi_calculation_rules; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.kpi_calculation_rules (
    rule_id integer NOT NULL,
    kpi_category public.prosper_category,
    calculation_type character varying(50),
    weight_factor numeric(3,2),
    formula text,
    validation_rules jsonb,
    effective_date date,
    is_active boolean DEFAULT true
);


ALTER TABLE public.kpi_calculation_rules OWNER TO "prosper-dev_owner";

--
-- TOC entry 352 (class 1259 OID 197270)
-- Name: kpi_calculation_rules_rule_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.kpi_calculation_rules_rule_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.kpi_calculation_rules_rule_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5228 (class 0 OID 0)
-- Dependencies: 352
-- Name: kpi_calculation_rules_rule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.kpi_calculation_rules_rule_id_seq OWNED BY public.kpi_calculation_rules.rule_id;


--
-- TOC entry 353 (class 1259 OID 197271)
-- Name: kpi_relationship_metrics; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.kpi_relationship_metrics (
    metric_id integer NOT NULL,
    employee_id integer,
    relationship_type character varying(50),
    strength_score numeric(5,2),
    last_interaction date
);


ALTER TABLE public.kpi_relationship_metrics OWNER TO "prosper-dev_owner";

--
-- TOC entry 354 (class 1259 OID 197274)
-- Name: kpi_relationship_metrics_metric_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.kpi_relationship_metrics_metric_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.kpi_relationship_metrics_metric_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5229 (class 0 OID 0)
-- Dependencies: 354
-- Name: kpi_relationship_metrics_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.kpi_relationship_metrics_metric_id_seq OWNED BY public.kpi_relationship_metrics.metric_id;


--
-- TOC entry 355 (class 1259 OID 197275)
-- Name: kpi_weight_config; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.kpi_weight_config (
    config_id integer NOT NULL,
    role_type character varying(50),
    kpi_type character varying(50),
    weight numeric(3,2),
    effective_date date,
    end_date date,
    CONSTRAINT valid_weight CHECK (((weight >= (0)::numeric) AND (weight <= (1)::numeric)))
);


ALTER TABLE public.kpi_weight_config OWNER TO "prosper-dev_owner";

--
-- TOC entry 356 (class 1259 OID 197279)
-- Name: kpi_weight_config_config_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.kpi_weight_config_config_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.kpi_weight_config_config_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5230 (class 0 OID 0)
-- Dependencies: 356
-- Name: kpi_weight_config_config_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.kpi_weight_config_config_id_seq OWNED BY public.kpi_weight_config.config_id;


--
-- TOC entry 357 (class 1259 OID 197280)
-- Name: learning_paths; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.learning_paths (
    path_id integer NOT NULL,
    employee_id integer,
    category character varying(50),
    current_level character varying(50),
    target_level character varying(50),
    required_skills jsonb[],
    completed_modules jsonb[],
    start_date date,
    target_completion_date date,
    progress_percentage numeric(5,2),
    status character varying(20),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.learning_paths OWNER TO "prosper-dev_owner";

--
-- TOC entry 358 (class 1259 OID 197286)
-- Name: learning_paths_path_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.learning_paths_path_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.learning_paths_path_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5231 (class 0 OID 0)
-- Dependencies: 358
-- Name: learning_paths_path_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.learning_paths_path_id_seq OWNED BY public.learning_paths.path_id;


--
-- TOC entry 359 (class 1259 OID 197287)
-- Name: login_attempts; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.login_attempts (
    attempt_id integer NOT NULL,
    username character varying(50),
    ip_address inet,
    success boolean,
    attempt_time timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.login_attempts OWNER TO "prosper-dev_owner";

--
-- TOC entry 360 (class 1259 OID 197293)
-- Name: login_attempts_attempt_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.login_attempts_attempt_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.login_attempts_attempt_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5232 (class 0 OID 0)
-- Dependencies: 360
-- Name: login_attempts_attempt_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.login_attempts_attempt_id_seq OWNED BY public.login_attempts.attempt_id;


--
-- TOC entry 361 (class 1259 OID 197294)
-- Name: maintenance_history; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.maintenance_history (
    history_id bigint NOT NULL,
    schedule_id bigint,
    start_time timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    end_time timestamp without time zone,
    status text NOT NULL,
    affected_objects jsonb,
    performance_impact jsonb,
    error_details text
);


ALTER TABLE public.maintenance_history OWNER TO "prosper-dev_owner";

--
-- TOC entry 362 (class 1259 OID 197300)
-- Name: maintenance_history_history_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.maintenance_history_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.maintenance_history_history_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5233 (class 0 OID 0)
-- Dependencies: 362
-- Name: maintenance_history_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.maintenance_history_history_id_seq OWNED BY public.maintenance_history.history_id;


--
-- TOC entry 363 (class 1259 OID 197301)
-- Name: maintenance_schedule; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.maintenance_schedule (
    schedule_id bigint NOT NULL,
    task_name text NOT NULL,
    task_type text NOT NULL,
    frequency interval NOT NULL,
    last_run timestamp without time zone,
    next_run timestamp without time zone,
    is_active boolean DEFAULT true,
    configuration jsonb,
    CONSTRAINT valid_task_type CHECK ((task_type = ANY (ARRAY['VACUUM'::text, 'ANALYZE'::text, 'REINDEX'::text, 'CLEANUP'::text, 'OPTIMIZE'::text])))
);


ALTER TABLE public.maintenance_schedule OWNER TO "prosper-dev_owner";

--
-- TOC entry 364 (class 1259 OID 197308)
-- Name: maintenance_schedule_schedule_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.maintenance_schedule_schedule_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.maintenance_schedule_schedule_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5234 (class 0 OID 0)
-- Dependencies: 364
-- Name: maintenance_schedule_schedule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.maintenance_schedule_schedule_id_seq OWNED BY public.maintenance_schedule.schedule_id;


--
-- TOC entry 365 (class 1259 OID 197309)
-- Name: maintenance_tasks; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.maintenance_tasks (
    task_id bigint NOT NULL,
    task_name text NOT NULL,
    task_type text NOT NULL,
    schedule_type text NOT NULL,
    schedule_config jsonb NOT NULL,
    last_run timestamp without time zone,
    next_run timestamp without time zone,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT valid_schedule_type CHECK ((schedule_type = ANY (ARRAY['INTERVAL'::text, 'CRON'::text, 'CONDITION'::text, 'MANUAL'::text]))),
    CONSTRAINT valid_task_type CHECK ((task_type = ANY (ARRAY['VACUUM'::text, 'ANALYZE'::text, 'REINDEX'::text, 'HEALTH_CHECK'::text, 'CUSTOM'::text])))
);


ALTER TABLE public.maintenance_tasks OWNER TO "prosper-dev_owner";

--
-- TOC entry 366 (class 1259 OID 197319)
-- Name: maintenance_tasks_task_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.maintenance_tasks_task_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.maintenance_tasks_task_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5235 (class 0 OID 0)
-- Dependencies: 366
-- Name: maintenance_tasks_task_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.maintenance_tasks_task_id_seq OWNED BY public.maintenance_tasks.task_id;


--
-- TOC entry 367 (class 1259 OID 197320)
-- Name: manager; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.manager (
    manager_id integer NOT NULL,
    manager_name character varying(100),
    department_id integer,
    level character varying(50),
    start_date date DEFAULT CURRENT_DATE,
    direct_reports integer DEFAULT 0,
    status character varying(20) DEFAULT 'Active'::character varying
);


ALTER TABLE public.manager OWNER TO "prosper-dev_owner";

--
-- TOC entry 368 (class 1259 OID 197326)
-- Name: manager_effectiveness_dashboard; Type: VIEW; Schema: public; Owner: prosper-dev_owner
--

CREATE VIEW public.manager_effectiveness_dashboard AS
 WITH manager_metrics AS (
         SELECT emh.manager_id,
            m.employee_name AS manager_name,
            epd.category,
            count(DISTINCT emh.employee_id) AS team_size,
            round(avg(epd.average_score), 2) AS team_avg_score,
            round(avg(epd.score_change), 2) AS avg_score_change,
            count(DISTINCT
                CASE
                    WHEN (epd.average_score >= (8)::numeric) THEN emh.employee_id
                    ELSE NULL::integer
                END) AS high_performers,
            count(DISTINCT
                CASE
                    WHEN (epd.average_score < (6)::numeric) THEN emh.employee_id
                    ELSE NULL::integer
                END) AS struggling_employees
           FROM ((public.employee_performance_dashboard epd
             JOIN public.employee_manager_hierarchy emh ON ((epd.employee_id = emh.employee_id)))
             JOIN public.employee_manager_hierarchy m ON ((emh.manager_id = m.employee_id)))
          GROUP BY emh.manager_id, m.employee_name, epd.category
        )
 SELECT manager_id,
    manager_name,
    category,
    team_size,
    team_avg_score,
    avg_score_change,
    high_performers,
    struggling_employees,
    round(((100.0 * (high_performers)::numeric) / (NULLIF(team_size, 0))::numeric), 2) AS high_performer_ratio,
    round(((100.0 * (struggling_employees)::numeric) / (NULLIF(team_size, 0))::numeric), 2) AS struggling_ratio,
        CASE
            WHEN ((team_avg_score >= (8)::numeric) AND (avg_score_change >= (0)::numeric)) THEN 'Highly Effective'::text
            WHEN ((team_avg_score >= (7)::numeric) AND (avg_score_change >= (0)::numeric)) THEN 'Effective'::text
            WHEN ((team_avg_score >= (6)::numeric) AND (avg_score_change >= '-0.5'::numeric)) THEN 'Moderately Effective'::text
            ELSE 'Needs Development'::text
        END AS effectiveness_rating
   FROM manager_metrics
  ORDER BY team_avg_score DESC, avg_score_change DESC;


ALTER VIEW public.manager_effectiveness_dashboard OWNER TO "prosper-dev_owner";

--
-- TOC entry 369 (class 1259 OID 197331)
-- Name: manager_engagement_metrics; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.manager_engagement_metrics (
    metric_id integer NOT NULL,
    manager_id integer,
    period_start date,
    period_end date,
    reviews_due integer,
    reviews_completed integer,
    feedback_provided integer,
    engagement_score numeric(5,2),
    CONSTRAINT valid_engagement CHECK (((engagement_score >= (0)::numeric) AND (engagement_score <= (100)::numeric)))
);


ALTER TABLE public.manager_engagement_metrics OWNER TO "prosper-dev_owner";

--
-- TOC entry 370 (class 1259 OID 197335)
-- Name: manager_engagement_metrics_metric_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.manager_engagement_metrics_metric_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.manager_engagement_metrics_metric_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5236 (class 0 OID 0)
-- Dependencies: 370
-- Name: manager_engagement_metrics_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.manager_engagement_metrics_metric_id_seq OWNED BY public.manager_engagement_metrics.metric_id;


--
-- TOC entry 371 (class 1259 OID 197336)
-- Name: mentorship_interactions; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.mentorship_interactions (
    interaction_id integer NOT NULL,
    match_id integer,
    interaction_date timestamp without time zone,
    interaction_type character varying(50),
    topics_covered text[],
    action_items jsonb,
    effectiveness_rating integer
);


ALTER TABLE public.mentorship_interactions OWNER TO "prosper-dev_owner";

--
-- TOC entry 372 (class 1259 OID 197341)
-- Name: mentorship_interactions_interaction_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.mentorship_interactions_interaction_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.mentorship_interactions_interaction_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5237 (class 0 OID 0)
-- Dependencies: 372
-- Name: mentorship_interactions_interaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.mentorship_interactions_interaction_id_seq OWNED BY public.mentorship_interactions.interaction_id;


--
-- TOC entry 373 (class 1259 OID 197342)
-- Name: mentorship_matching; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.mentorship_matching (
    match_id integer NOT NULL,
    mentor_id integer,
    mentee_id integer,
    program_focus jsonb,
    start_date date,
    end_date date,
    success_metrics jsonb,
    status character varying(20)
);


ALTER TABLE public.mentorship_matching OWNER TO "prosper-dev_owner";

--
-- TOC entry 374 (class 1259 OID 197347)
-- Name: mentorship_matching_match_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.mentorship_matching_match_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.mentorship_matching_match_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5238 (class 0 OID 0)
-- Dependencies: 374
-- Name: mentorship_matching_match_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.mentorship_matching_match_id_seq OWNED BY public.mentorship_matching.match_id;


--
-- TOC entry 375 (class 1259 OID 197348)
-- Name: mentorship_programs; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.mentorship_programs (
    program_id integer NOT NULL,
    mentor_id integer,
    mentee_id integer,
    start_date date,
    end_date date,
    focus_areas jsonb[],
    status character varying(50),
    progress_notes jsonb[],
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.mentorship_programs OWNER TO "prosper-dev_owner";

--
-- TOC entry 376 (class 1259 OID 197354)
-- Name: mentorship_programs_program_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.mentorship_programs_program_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.mentorship_programs_program_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5239 (class 0 OID 0)
-- Dependencies: 376
-- Name: mentorship_programs_program_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.mentorship_programs_program_id_seq OWNED BY public.mentorship_programs.program_id;


--
-- TOC entry 377 (class 1259 OID 197355)
-- Name: metric_aggregations; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.metric_aggregations (
    aggregation_id bigint NOT NULL,
    metric_name text NOT NULL,
    granularity text NOT NULL,
    time_bucket timestamp without time zone NOT NULL,
    min_value numeric,
    max_value numeric,
    avg_value numeric,
    sum_value numeric,
    count_value bigint,
    percentiles jsonb,
    dimensions jsonb,
    CONSTRAINT valid_granularity CHECK ((granularity = ANY (ARRAY['HOUR'::text, 'DAY'::text, 'MONTH'::text, 'YEAR'::text])))
);


ALTER TABLE public.metric_aggregations OWNER TO "prosper-dev_owner";

--
-- TOC entry 378 (class 1259 OID 197361)
-- Name: metric_aggregations_aggregation_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.metric_aggregations_aggregation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.metric_aggregations_aggregation_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5240 (class 0 OID 0)
-- Dependencies: 378
-- Name: metric_aggregations_aggregation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.metric_aggregations_aggregation_id_seq OWNED BY public.metric_aggregations.aggregation_id;


--
-- TOC entry 379 (class 1259 OID 197362)
-- Name: metric_alerts; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.metric_alerts (
    alert_id integer NOT NULL,
    metric_type character varying(50),
    threshold_type character varying(20),
    threshold_value numeric(5,2),
    current_value numeric(5,2),
    alert_status character varying(20),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_threshold CHECK (((threshold_type)::text = ANY (ARRAY[('MIN'::character varying)::text, ('MAX'::character varying)::text, ('TARGET'::character varying)::text])))
);


ALTER TABLE public.metric_alerts OWNER TO "prosper-dev_owner";

--
-- TOC entry 380 (class 1259 OID 197367)
-- Name: metric_alerts_alert_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.metric_alerts_alert_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.metric_alerts_alert_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5241 (class 0 OID 0)
-- Dependencies: 380
-- Name: metric_alerts_alert_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.metric_alerts_alert_id_seq OWNED BY public.metric_alerts.alert_id;


--
-- TOC entry 381 (class 1259 OID 197368)
-- Name: metric_correlations; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.metric_correlations (
    correlation_id integer NOT NULL,
    primary_metric character varying(50),
    correlated_metric character varying(50),
    correlation_coefficient numeric(5,4),
    significance_level numeric(5,4),
    analysis_period_start date,
    analysis_period_end date,
    insights text
);


ALTER TABLE public.metric_correlations OWNER TO "prosper-dev_owner";

--
-- TOC entry 382 (class 1259 OID 197373)
-- Name: metric_correlations_correlation_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.metric_correlations_correlation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.metric_correlations_correlation_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5242 (class 0 OID 0)
-- Dependencies: 382
-- Name: metric_correlations_correlation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.metric_correlations_correlation_id_seq OWNED BY public.metric_correlations.correlation_id;


--
-- TOC entry 383 (class 1259 OID 197374)
-- Name: notification_channels; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.notification_channels (
    channel_id bigint NOT NULL,
    channel_name text NOT NULL,
    channel_type text NOT NULL,
    configuration jsonb NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT valid_channel_type CHECK ((channel_type = ANY (ARRAY['EMAIL'::text, 'SLACK'::text, 'WEBHOOK'::text, 'SMS'::text, 'CUSTOM'::text])))
);


ALTER TABLE public.notification_channels OWNER TO "prosper-dev_owner";

--
-- TOC entry 384 (class 1259 OID 197383)
-- Name: notification_channels_channel_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.notification_channels_channel_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.notification_channels_channel_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5243 (class 0 OID 0)
-- Dependencies: 384
-- Name: notification_channels_channel_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.notification_channels_channel_id_seq OWNED BY public.notification_channels.channel_id;


--
-- TOC entry 385 (class 1259 OID 197384)
-- Name: notification_history; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.notification_history (
    notification_id bigint NOT NULL,
    channel_id bigint,
    template_id integer,
    notification_type text NOT NULL,
    status text DEFAULT 'PENDING'::text NOT NULL,
    recipient text,
    subject text,
    body text,
    sent_at timestamp without time zone,
    error_details jsonb,
    metadata jsonb,
    CONSTRAINT valid_status CHECK ((status = ANY (ARRAY['PENDING'::text, 'SENT'::text, 'FAILED'::text, 'CANCELLED'::text])))
);


ALTER TABLE public.notification_history OWNER TO "prosper-dev_owner";

--
-- TOC entry 386 (class 1259 OID 197391)
-- Name: notification_history_notification_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.notification_history_notification_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.notification_history_notification_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5244 (class 0 OID 0)
-- Dependencies: 386
-- Name: notification_history_notification_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.notification_history_notification_id_seq OWNED BY public.notification_history.notification_id;


--
-- TOC entry 387 (class 1259 OID 197392)
-- Name: notification_log; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.notification_log (
    log_id integer NOT NULL,
    template_id bigint,
    recipient_id integer,
    notification_type character varying(50),
    status character varying(50),
    sent_at timestamp without time zone,
    delivery_status character varying(50),
    read_at timestamp without time zone,
    error_message text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.notification_log OWNER TO "prosper-dev_owner";

--
-- TOC entry 388 (class 1259 OID 197398)
-- Name: notification_log_log_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.notification_log_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.notification_log_log_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5245 (class 0 OID 0)
-- Dependencies: 388
-- Name: notification_log_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.notification_log_log_id_seq OWNED BY public.notification_log.log_id;


--
-- TOC entry 389 (class 1259 OID 197399)
-- Name: notification_templates; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.notification_templates (
    template_id integer NOT NULL,
    template_name character varying(100),
    category character varying(50),
    subject_template text,
    body_template text,
    variables jsonb,
    active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    template_type character varying(50),
    html_content text,
    required_placeholders text[],
    cc_roles text[],
    bcc_roles text[],
    version integer DEFAULT 1,
    last_modified_by integer,
    last_modified_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.notification_templates OWNER TO "prosper-dev_owner";

--
-- TOC entry 390 (class 1259 OID 197408)
-- Name: notification_templates_template_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.notification_templates_template_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.notification_templates_template_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5246 (class 0 OID 0)
-- Dependencies: 390
-- Name: notification_templates_template_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.notification_templates_template_id_seq OWNED BY public.notification_templates.template_id;


--
-- TOC entry 391 (class 1259 OID 197409)
-- Name: operational_efficiency_metrics; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.operational_efficiency_metrics (
    metric_id integer NOT NULL,
    employee_id integer,
    time_entry_compliance boolean,
    forecast_accuracy numeric(5,2),
    bsc_completion boolean,
    measurement_date date,
    notes text,
    CONSTRAINT valid_forecast CHECK (((forecast_accuracy >= (0)::numeric) AND (forecast_accuracy <= (100)::numeric)))
);


ALTER TABLE public.operational_efficiency_metrics OWNER TO "prosper-dev_owner";

--
-- TOC entry 392 (class 1259 OID 197415)
-- Name: operational_efficiency_metrics_metric_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.operational_efficiency_metrics_metric_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.operational_efficiency_metrics_metric_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5247 (class 0 OID 0)
-- Dependencies: 392
-- Name: operational_efficiency_metrics_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.operational_efficiency_metrics_metric_id_seq OWNED BY public.operational_efficiency_metrics.metric_id;


--
-- TOC entry 393 (class 1259 OID 197416)
-- Name: opt_in_metrics; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.opt_in_metrics (
    metric_id integer NOT NULL,
    year integer,
    quarter integer,
    total_invited integer,
    total_opted_in integer,
    opt_in_rate numeric(5,2),
    target_rate numeric(5,2),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.opt_in_metrics OWNER TO "prosper-dev_owner";

--
-- TOC entry 394 (class 1259 OID 197420)
-- Name: opt_in_metrics_metric_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.opt_in_metrics_metric_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.opt_in_metrics_metric_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5248 (class 0 OID 0)
-- Dependencies: 394
-- Name: opt_in_metrics_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.opt_in_metrics_metric_id_seq OWNED BY public.opt_in_metrics.metric_id;


--
-- TOC entry 395 (class 1259 OID 197421)
-- Name: opt_in_tracking; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.opt_in_tracking (
    tracking_id integer NOT NULL,
    employee_id integer,
    opt_in_date date,
    manager_approval_date date,
    status character varying(50),
    comments text,
    CONSTRAINT valid_approval CHECK ((manager_approval_date >= opt_in_date))
);


ALTER TABLE public.opt_in_tracking OWNER TO "prosper-dev_owner";

--
-- TOC entry 396 (class 1259 OID 197427)
-- Name: opt_in_tracking_tracking_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.opt_in_tracking_tracking_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.opt_in_tracking_tracking_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5249 (class 0 OID 0)
-- Dependencies: 396
-- Name: opt_in_tracking_tracking_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.opt_in_tracking_tracking_id_seq OWNED BY public.opt_in_tracking.tracking_id;


--
-- TOC entry 397 (class 1259 OID 197428)
-- Name: optimization_recommendations; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.optimization_recommendations (
    recommendation_id bigint NOT NULL,
    category text NOT NULL,
    priority text NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    current_value text,
    recommended_value text,
    estimated_impact jsonb,
    implementation_sql text,
    status text DEFAULT 'PENDING'::text NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    implemented_at timestamp without time zone,
    validation_results jsonb,
    metadata jsonb,
    CONSTRAINT valid_category CHECK ((category = ANY (ARRAY['CONFIGURATION'::text, 'INDEX'::text, 'VACUUM'::text, 'QUERY'::text, 'SCHEMA'::text, 'CUSTOM'::text]))),
    CONSTRAINT valid_priority CHECK ((priority = ANY (ARRAY['HIGH'::text, 'MEDIUM'::text, 'LOW'::text]))),
    CONSTRAINT valid_status CHECK ((status = ANY (ARRAY['PENDING'::text, 'IMPLEMENTED'::text, 'REJECTED'::text, 'FAILED'::text])))
);


ALTER TABLE public.optimization_recommendations OWNER TO "prosper-dev_owner";

--
-- TOC entry 398 (class 1259 OID 197438)
-- Name: optimization_recommendations_recommendation_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.optimization_recommendations_recommendation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.optimization_recommendations_recommendation_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5250 (class 0 OID 0)
-- Dependencies: 398
-- Name: optimization_recommendations_recommendation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.optimization_recommendations_recommendation_id_seq OWNED BY public.optimization_recommendations.recommendation_id;


--
-- TOC entry 399 (class 1259 OID 197439)
-- Name: participation_metrics; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.participation_metrics (
    metric_id integer NOT NULL,
    cycle_date date,
    total_eligible integer,
    total_submitted integer,
    participation_rate numeric(5,2),
    cycle_type character varying(50),
    CONSTRAINT valid_rate CHECK (((participation_rate >= (0)::numeric) AND (participation_rate <= (100)::numeric)))
);


ALTER TABLE public.participation_metrics OWNER TO "prosper-dev_owner";

--
-- TOC entry 400 (class 1259 OID 197443)
-- Name: participation_metrics_metric_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.participation_metrics_metric_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.participation_metrics_metric_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5251 (class 0 OID 0)
-- Dependencies: 400
-- Name: participation_metrics_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.participation_metrics_metric_id_seq OWNED BY public.participation_metrics.metric_id;


--
-- TOC entry 401 (class 1259 OID 197444)
-- Name: performance_alerts; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.performance_alerts (
    alert_id bigint NOT NULL,
    metric_name text NOT NULL,
    alert_type text NOT NULL,
    threshold_value numeric NOT NULL,
    current_value numeric NOT NULL,
    alert_time timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    resolution_time timestamp without time zone,
    status text DEFAULT 'ACTIVE'::text NOT NULL,
    notification_sent boolean DEFAULT false,
    metadata jsonb,
    CONSTRAINT valid_alert_type CHECK ((alert_type = ANY (ARRAY['THRESHOLD'::text, 'ANOMALY'::text, 'TREND'::text, 'CUSTOM'::text]))),
    CONSTRAINT valid_status CHECK ((status = ANY (ARRAY['ACTIVE'::text, 'RESOLVED'::text, 'ACKNOWLEDGED'::text])))
);


ALTER TABLE public.performance_alerts OWNER TO "prosper-dev_owner";

--
-- TOC entry 402 (class 1259 OID 197454)
-- Name: performance_alerts_alert_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.performance_alerts_alert_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.performance_alerts_alert_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5252 (class 0 OID 0)
-- Dependencies: 402
-- Name: performance_alerts_alert_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.performance_alerts_alert_id_seq OWNED BY public.performance_alerts.alert_id;


--
-- TOC entry 403 (class 1259 OID 197455)
-- Name: performance_baselines; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.performance_baselines (
    baseline_id bigint NOT NULL,
    metric_name text NOT NULL,
    baseline_value numeric NOT NULL,
    calculation_window interval NOT NULL,
    last_updated timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    confidence_score numeric,
    baseline_data jsonb
);


ALTER TABLE public.performance_baselines OWNER TO "prosper-dev_owner";

--
-- TOC entry 404 (class 1259 OID 197461)
-- Name: performance_baselines_baseline_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.performance_baselines_baseline_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.performance_baselines_baseline_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5253 (class 0 OID 0)
-- Dependencies: 404
-- Name: performance_baselines_baseline_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.performance_baselines_baseline_id_seq OWNED BY public.performance_baselines.baseline_id;


--
-- TOC entry 405 (class 1259 OID 197462)
-- Name: performance_delta_tracking; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.performance_delta_tracking (
    delta_id integer NOT NULL,
    employee_id integer,
    kpi_category public.prosper_category,
    previous_score numeric(5,2),
    new_score numeric(5,2),
    change_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    justification text,
    approved_by integer,
    CONSTRAINT valid_score_change CHECK ((previous_score <> new_score))
);


ALTER TABLE public.performance_delta_tracking OWNER TO "prosper-dev_owner";

--
-- TOC entry 406 (class 1259 OID 197469)
-- Name: performance_delta_tracking_delta_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.performance_delta_tracking_delta_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.performance_delta_tracking_delta_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5254 (class 0 OID 0)
-- Dependencies: 406
-- Name: performance_delta_tracking_delta_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.performance_delta_tracking_delta_id_seq OWNED BY public.performance_delta_tracking.delta_id;


--
-- TOC entry 407 (class 1259 OID 197470)
-- Name: performance_feedback_feedback_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.performance_feedback_feedback_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.performance_feedback_feedback_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5255 (class 0 OID 0)
-- Dependencies: 407
-- Name: performance_feedback_feedback_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.performance_feedback_feedback_id_seq OWNED BY public.performance_feedback.feedback_id;


--
-- TOC entry 408 (class 1259 OID 197471)
-- Name: performance_impact; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.performance_impact (
    impact_id integer NOT NULL,
    employee_id integer,
    category character varying(50),
    initiative_name character varying(100),
    impact_date date,
    metrics_before jsonb,
    metrics_after jsonb,
    roi_calculation numeric(10,2),
    impact_evidence text[],
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.performance_impact OWNER TO "prosper-dev_owner";

--
-- TOC entry 409 (class 1259 OID 197477)
-- Name: performance_impact_impact_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.performance_impact_impact_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.performance_impact_impact_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5256 (class 0 OID 0)
-- Dependencies: 409
-- Name: performance_impact_impact_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.performance_impact_impact_id_seq OWNED BY public.performance_impact.impact_id;


--
-- TOC entry 410 (class 1259 OID 197478)
-- Name: performance_improvement_metrics; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.performance_improvement_metrics (
    metric_id integer NOT NULL,
    employee_id integer,
    measurement_period character varying(50),
    baseline_score numeric(5,2),
    current_score numeric(5,2),
    improvement_percentage numeric(5,2),
    target_achieved boolean,
    CONSTRAINT valid_improvement CHECK ((improvement_percentage >= (0)::numeric))
);


ALTER TABLE public.performance_improvement_metrics OWNER TO "prosper-dev_owner";

--
-- TOC entry 411 (class 1259 OID 197482)
-- Name: performance_improvement_metrics_metric_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.performance_improvement_metrics_metric_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.performance_improvement_metrics_metric_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5257 (class 0 OID 0)
-- Dependencies: 411
-- Name: performance_improvement_metrics_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.performance_improvement_metrics_metric_id_seq OWNED BY public.performance_improvement_metrics.metric_id;


--
-- TOC entry 412 (class 1259 OID 197483)
-- Name: performance_improvements; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.performance_improvements (
    improvement_id integer NOT NULL,
    employee_id integer,
    area_of_improvement character varying(100),
    initial_score numeric(5,2),
    target_score numeric(5,2),
    current_score numeric(5,2),
    action_plan jsonb,
    review_frequency character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.performance_improvements OWNER TO "prosper-dev_owner";

--
-- TOC entry 413 (class 1259 OID 197489)
-- Name: performance_improvements_improvement_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.performance_improvements_improvement_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.performance_improvements_improvement_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5258 (class 0 OID 0)
-- Dependencies: 413
-- Name: performance_improvements_improvement_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.performance_improvements_improvement_id_seq OWNED BY public.performance_improvements.improvement_id;


--
-- TOC entry 414 (class 1259 OID 197490)
-- Name: performance_metrics; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.performance_metrics (
    metric_id integer NOT NULL,
    employee_id integer,
    category character varying(50),
    metric_name character varying(100),
    metric_value numeric(10,2),
    measurement_date date,
    comparison_period character varying(50),
    trend_direction character varying(20),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    calculation_formula text,
    weight numeric(3,2)
);


ALTER TABLE public.performance_metrics OWNER TO "prosper-dev_owner";

--
-- TOC entry 415 (class 1259 OID 197496)
-- Name: performance_metrics_metric_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.performance_metrics_metric_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.performance_metrics_metric_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5259 (class 0 OID 0)
-- Dependencies: 415
-- Name: performance_metrics_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.performance_metrics_metric_id_seq OWNED BY public.performance_metrics.metric_id;


--
-- TOC entry 416 (class 1259 OID 197497)
-- Name: performance_patterns; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.performance_patterns (
    pattern_id integer NOT NULL,
    pattern_name character varying(100),
    detection_rules jsonb,
    impact_level character varying(20),
    occurrence_frequency integer,
    action_recommendations text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.performance_patterns OWNER TO "prosper-dev_owner";

--
-- TOC entry 417 (class 1259 OID 197503)
-- Name: performance_patterns_pattern_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.performance_patterns_pattern_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.performance_patterns_pattern_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5260 (class 0 OID 0)
-- Dependencies: 417
-- Name: performance_patterns_pattern_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.performance_patterns_pattern_id_seq OWNED BY public.performance_patterns.pattern_id;


--
-- TOC entry 418 (class 1259 OID 197504)
-- Name: performance_scores_score_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.performance_scores_score_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.performance_scores_score_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5261 (class 0 OID 0)
-- Dependencies: 418
-- Name: performance_scores_score_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.performance_scores_score_id_seq OWNED BY public.performance_scores.score_id;


--
-- TOC entry 419 (class 1259 OID 197505)
-- Name: performance_trending_dashboard; Type: VIEW; Schema: public; Owner: prosper-dev_owner
--

CREATE VIEW public.performance_trending_dashboard AS
 WITH monthly_trends AS (
         SELECT d.department_name,
            (ps.category)::text AS category,
            date_trunc('month'::text, (ps.evaluation_date)::timestamp with time zone) AS month,
            round(avg(ps.average_score), 2) AS avg_score,
            count(DISTINCT ps.employee_id) AS employees_evaluated,
            lag(round(avg(ps.average_score), 2)) OVER (PARTITION BY d.department_name, ps.category ORDER BY (date_trunc('month'::text, (ps.evaluation_date)::timestamp with time zone))) AS prev_month_score
           FROM ((public.performance_scores ps
             JOIN public.employee_manager_hierarchy emh ON ((ps.employee_id = emh.employee_id)))
             JOIN public.department d ON ((emh.department_id = d.department_id)))
          WHERE ((ps.evaluation_date >= (CURRENT_DATE - '1 year'::interval)) AND (emh.active = true))
          GROUP BY d.department_name, ps.category, (date_trunc('month'::text, (ps.evaluation_date)::timestamp with time zone))
        )
 SELECT department_name,
    category,
    month,
    avg_score,
    employees_evaluated,
    round((avg_score - prev_month_score), 2) AS month_over_month_change,
    round(((100.0 * (avg_score - prev_month_score)) / NULLIF(prev_month_score, (0)::numeric)), 2) AS percentage_change,
        CASE
            WHEN ((avg_score - prev_month_score) >= 0.5) THEN 'Strong Improvement'::text
            WHEN ((avg_score - prev_month_score) > (0)::numeric) THEN 'Slight Improvement'::text
            WHEN ((avg_score - prev_month_score) = (0)::numeric) THEN 'Stable'::text
            WHEN ((avg_score - prev_month_score) >= '-0.5'::numeric) THEN 'Slight Decline'::text
            ELSE 'Significant Decline'::text
        END AS trend_indicator
   FROM monthly_trends
  WHERE (prev_month_score IS NOT NULL)
  ORDER BY department_name, category, month;


ALTER VIEW public.performance_trending_dashboard OWNER TO "prosper-dev_owner";

--
-- TOC entry 420 (class 1259 OID 197510)
-- Name: performance_trends; Type: VIEW; Schema: public; Owner: prosper-dev_owner
--

CREATE VIEW public.performance_trends AS
 WITH monthlyscores AS (
         SELECT date_trunc('month'::text, (ps.evaluation_date)::timestamp with time zone) AS month,
            ps.category,
            d.department_name,
            count(DISTINCT ps.employee_id) AS evaluated_employees,
            round(avg(ps.average_score), 2) AS avg_score,
            round(stddev(ps.average_score), 2) AS score_deviation
           FROM ((public.performance_scores ps
             JOIN public.employee_manager_hierarchy emh ON ((ps.employee_id = emh.employee_id)))
             JOIN public.department d ON ((emh.department_id = d.department_id)))
          WHERE (ps.evaluation_date >= (CURRENT_DATE - '1 year'::interval))
          GROUP BY (date_trunc('month'::text, (ps.evaluation_date)::timestamp with time zone)), ps.category, d.department_name
        )
 SELECT month,
    category,
    department_name,
    evaluated_employees,
    avg_score,
    score_deviation,
    (avg_score - lag(avg_score) OVER (PARTITION BY category, department_name ORDER BY month)) AS month_over_month_change,
    round(((100.0 * (avg_score - first_value(avg_score) OVER (PARTITION BY category, department_name ORDER BY month))) / NULLIF(first_value(avg_score) OVER (PARTITION BY category, department_name ORDER BY month), (0)::numeric)), 2) AS total_change_percentage
   FROM monthlyscores ms;


ALTER VIEW public.performance_trends OWNER TO "prosper-dev_owner";

--
-- TOC entry 421 (class 1259 OID 197515)
-- Name: portfolio_analysis_view; Type: VIEW; Schema: public; Owner: prosper-dev_owner
--

CREATE VIEW public.portfolio_analysis_view AS
 WITH combined_scores AS (
         SELECT portfolio_design_success.employee_id,
            'Design Success'::text AS portfolio_type,
            portfolio_design_success.evaluation_date,
            portfolio_design_success.initial_self_score,
            portfolio_design_success.self_score,
            portfolio_design_success.manager_score,
            portfolio_design_success.challenge_score,
            portfolio_design_success.average_score,
            portfolio_design_success.delta_score,
            jsonb_build_object('initial_self_score', portfolio_design_success.initial_self_score, 'self_score', portfolio_design_success.self_score, 'manager_score', portfolio_design_success.manager_score, 'challenge_score', portfolio_design_success.challenge_score, 'delta_score', portfolio_design_success.delta_score) AS detailed_scores
           FROM public.portfolio_design_success
        UNION ALL
         SELECT portfolio_premium_engagement.employee_id,
            'Premium Engagement'::text AS portfolio_type,
            portfolio_premium_engagement.evaluation_date,
            portfolio_premium_engagement.initial_self_score,
            portfolio_premium_engagement.self_score,
            portfolio_premium_engagement.manager_score,
            portfolio_premium_engagement.challenge_score,
            portfolio_premium_engagement.average_score,
            portfolio_premium_engagement.delta_score,
            jsonb_build_object('initial_self_score', portfolio_premium_engagement.initial_self_score, 'self_score', portfolio_premium_engagement.self_score, 'manager_score', portfolio_premium_engagement.manager_score, 'challenge_score', portfolio_premium_engagement.challenge_score, 'delta_score', portfolio_premium_engagement.delta_score) AS detailed_scores
           FROM public.portfolio_premium_engagement
        UNION ALL
         SELECT portfolio_cloud_services.employee_id,
            'Cloud Services'::text AS portfolio_type,
            portfolio_cloud_services.evaluation_date,
            portfolio_cloud_services.initial_self_score,
            portfolio_cloud_services.self_score,
            portfolio_cloud_services.manager_score,
            portfolio_cloud_services.challenge_score,
            portfolio_cloud_services.average_score,
            portfolio_cloud_services.delta_score,
            jsonb_build_object('initial_self_score', portfolio_cloud_services.initial_self_score, 'self_score', portfolio_cloud_services.self_score, 'manager_score', portfolio_cloud_services.manager_score, 'challenge_score', portfolio_cloud_services.challenge_score, 'delta_score', portfolio_cloud_services.delta_score) AS detailed_scores
           FROM public.portfolio_cloud_services
        )
 SELECT cs.employee_id,
    e.employee_name,
    e.department_id,
    cs.portfolio_type,
    cs.evaluation_date,
    cs.initial_self_score,
    cs.self_score,
    cs.manager_score,
    cs.challenge_score,
    cs.average_score,
    cs.delta_score,
    cs.detailed_scores,
    lag(cs.average_score) OVER (PARTITION BY cs.employee_id, cs.portfolio_type ORDER BY cs.evaluation_date) AS previous_score,
    (cs.average_score - lag(cs.average_score) OVER (PARTITION BY cs.employee_id, cs.portfolio_type ORDER BY cs.evaluation_date)) AS score_change
   FROM (combined_scores cs
     JOIN public.employee_manager_hierarchy e ON ((cs.employee_id = e.employee_id)));


ALTER VIEW public.portfolio_analysis_view OWNER TO "prosper-dev_owner";

--
-- TOC entry 422 (class 1259 OID 197520)
-- Name: portfolio_base; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.portfolio_base (
    score_id integer NOT NULL,
    employee_id integer,
    evaluation_date date DEFAULT CURRENT_DATE,
    initial_self_score numeric(5,2),
    concurrent_score numeric(5,2),
    delta_score numeric(5,2),
    self_score numeric(5,2),
    manager_score numeric(5,2),
    manager_comment text,
    challenge_score numeric(5,2),
    average_score numeric(5,2) GENERATED ALWAYS AS (NULLIF((((COALESCE(self_score, (0)::numeric) + COALESCE(manager_score, (0)::numeric)) + COALESCE(challenge_score, (0)::numeric)) / (NULLIF(((
CASE
    WHEN (self_score IS NOT NULL) THEN 1
    ELSE 0
END +
CASE
    WHEN (manager_score IS NOT NULL) THEN 1
    ELSE 0
END) +
CASE
    WHEN (challenge_score IS NOT NULL) THEN 1
    ELSE NULL::integer
END), 0))::numeric), (0)::numeric)) STORED,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    last_modified_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_scores CHECK (((initial_self_score >= (0)::numeric) AND (initial_self_score <= (100)::numeric) AND ((concurrent_score >= (0)::numeric) AND (concurrent_score <= (100)::numeric)) AND ((self_score >= (0)::numeric) AND (self_score <= (100)::numeric)) AND ((manager_score >= (0)::numeric) AND (manager_score <= (100)::numeric)) AND ((challenge_score >= (0)::numeric) AND (challenge_score <= (100)::numeric))))
);


ALTER TABLE public.portfolio_base OWNER TO "prosper-dev_owner";

--
-- TOC entry 423 (class 1259 OID 197530)
-- Name: portfolio_base_score_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.portfolio_base_score_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.portfolio_base_score_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5262 (class 0 OID 0)
-- Dependencies: 423
-- Name: portfolio_base_score_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.portfolio_base_score_id_seq OWNED BY public.portfolio_base.score_id;


--
-- TOC entry 424 (class 1259 OID 197531)
-- Name: portfolio_brownfield; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.portfolio_brownfield (
    score_id integer NOT NULL,
    employee_id integer,
    initial_self_score numeric(5,2),
    concurrent_score numeric(5,2),
    delta_score numeric(5,2),
    self_score numeric(5,2),
    manager_score numeric(5,2),
    manager_comment text,
    challenge_score numeric(5,2),
    average_score numeric(5,2),
    evaluation_date date DEFAULT CURRENT_DATE,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    last_modified_by integer,
    last_modified_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    version integer DEFAULT 1,
    status character varying(50) DEFAULT 'active'::character varying,
    CONSTRAINT check_portfolio_brownfield_scores CHECK (((initial_self_score >= (0)::numeric) AND (initial_self_score <= (100)::numeric) AND ((concurrent_score >= (0)::numeric) AND (concurrent_score <= (100)::numeric)) AND ((self_score >= (0)::numeric) AND (self_score <= (100)::numeric)) AND ((manager_score >= (0)::numeric) AND (manager_score <= (100)::numeric)) AND ((challenge_score >= (0)::numeric) AND (challenge_score <= (100)::numeric))))
);


ALTER TABLE public.portfolio_brownfield OWNER TO "prosper-dev_owner";

--
-- TOC entry 425 (class 1259 OID 197542)
-- Name: portfolio_brownfield_score_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.portfolio_brownfield_score_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.portfolio_brownfield_score_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5263 (class 0 OID 0)
-- Dependencies: 425
-- Name: portfolio_brownfield_score_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.portfolio_brownfield_score_id_seq OWNED BY public.portfolio_brownfield.score_id;


--
-- TOC entry 426 (class 1259 OID 197543)
-- Name: portfolio_cloud_services_score_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.portfolio_cloud_services_score_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.portfolio_cloud_services_score_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5264 (class 0 OID 0)
-- Dependencies: 426
-- Name: portfolio_cloud_services_score_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.portfolio_cloud_services_score_id_seq OWNED BY public.portfolio_cloud_services.score_id;


--
-- TOC entry 427 (class 1259 OID 197544)
-- Name: portfolio_design_success_score_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.portfolio_design_success_score_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.portfolio_design_success_score_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5265 (class 0 OID 0)
-- Dependencies: 427
-- Name: portfolio_design_success_score_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.portfolio_design_success_score_id_seq OWNED BY public.portfolio_design_success.score_id;


--
-- TOC entry 428 (class 1259 OID 197545)
-- Name: portfolio_preferred_success; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.portfolio_preferred_success (
    score_id integer NOT NULL,
    employee_id integer,
    initial_self_score numeric(5,2),
    concurrent_score numeric(5,2),
    delta_score numeric(5,2),
    self_score numeric(5,2),
    manager_score numeric(5,2),
    manager_comment text,
    challenge_score numeric(5,2),
    average_score numeric(5,2),
    evaluation_date date DEFAULT CURRENT_DATE,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    last_modified_by integer,
    last_modified_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    version integer DEFAULT 1,
    status character varying(50) DEFAULT 'active'::character varying,
    CONSTRAINT check_portfolio_preferred_success_scores CHECK (((initial_self_score >= (0)::numeric) AND (initial_self_score <= (100)::numeric) AND ((concurrent_score >= (0)::numeric) AND (concurrent_score <= (100)::numeric)) AND ((self_score >= (0)::numeric) AND (self_score <= (100)::numeric)) AND ((manager_score >= (0)::numeric) AND (manager_score <= (100)::numeric)) AND ((challenge_score >= (0)::numeric) AND (challenge_score <= (100)::numeric))))
);


ALTER TABLE public.portfolio_preferred_success OWNER TO "prosper-dev_owner";

--
-- TOC entry 429 (class 1259 OID 197556)
-- Name: portfolio_preferred_success_score_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.portfolio_preferred_success_score_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.portfolio_preferred_success_score_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5266 (class 0 OID 0)
-- Dependencies: 429
-- Name: portfolio_preferred_success_score_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.portfolio_preferred_success_score_id_seq OWNED BY public.portfolio_preferred_success.score_id;


--
-- TOC entry 430 (class 1259 OID 197557)
-- Name: portfolio_premium_engagement_score_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.portfolio_premium_engagement_score_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.portfolio_premium_engagement_score_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5267 (class 0 OID 0)
-- Dependencies: 430
-- Name: portfolio_premium_engagement_score_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.portfolio_premium_engagement_score_id_seq OWNED BY public.portfolio_premium_engagement.score_id;


--
-- TOC entry 431 (class 1259 OID 197558)
-- Name: portfolio_services; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.portfolio_services (
    service_id integer NOT NULL,
    service_name character varying(100) NOT NULL
);


ALTER TABLE public.portfolio_services OWNER TO "prosper-dev_owner";

--
-- TOC entry 432 (class 1259 OID 197561)
-- Name: portfolio_services_service_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.portfolio_services_service_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.portfolio_services_service_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5268 (class 0 OID 0)
-- Dependencies: 432
-- Name: portfolio_services_service_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.portfolio_services_service_id_seq OWNED BY public.portfolio_services.service_id;


--
-- TOC entry 433 (class 1259 OID 197562)
-- Name: portfolio_training; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.portfolio_training (
    score_id integer NOT NULL,
    employee_id integer,
    evaluation_date date DEFAULT CURRENT_DATE,
    initial_self_score numeric(5,2),
    concurrent_score numeric(5,2),
    delta_score numeric(5,2),
    self_score numeric(5,2),
    manager_score numeric(5,2),
    manager_comment text,
    challenge_score numeric(5,2),
    average_score numeric(5,2) GENERATED ALWAYS AS (NULLIF((((COALESCE(self_score, (0)::numeric) + COALESCE(manager_score, (0)::numeric)) + COALESCE(challenge_score, (0)::numeric)) / (NULLIF(((
CASE
    WHEN (self_score IS NOT NULL) THEN 1
    ELSE 0
END +
CASE
    WHEN (manager_score IS NOT NULL) THEN 1
    ELSE 0
END) +
CASE
    WHEN (challenge_score IS NOT NULL) THEN 1
    ELSE NULL::integer
END), 0))::numeric), (0)::numeric)) STORED,
    training_type character varying(50),
    completion_status character varying(20),
    effectiveness_score numeric(5,2)
);


ALTER TABLE public.portfolio_training OWNER TO "prosper-dev_owner";

--
-- TOC entry 434 (class 1259 OID 197569)
-- Name: portfolio_training_score_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.portfolio_training_score_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.portfolio_training_score_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5269 (class 0 OID 0)
-- Dependencies: 434
-- Name: portfolio_training_score_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.portfolio_training_score_id_seq OWNED BY public.portfolio_training.score_id;


--
-- TOC entry 435 (class 1259 OID 197570)
-- Name: program_retention_metrics; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.program_retention_metrics (
    metric_id integer NOT NULL,
    year integer,
    total_previous_year integer,
    total_retained integer,
    retention_rate numeric(5,2),
    target_rate numeric(5,2),
    analysis_date date,
    CONSTRAINT valid_retention CHECK (((retention_rate >= (0)::numeric) AND (retention_rate <= (100)::numeric)))
);


ALTER TABLE public.program_retention_metrics OWNER TO "prosper-dev_owner";

--
-- TOC entry 436 (class 1259 OID 197574)
-- Name: program_retention_metrics_metric_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.program_retention_metrics_metric_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.program_retention_metrics_metric_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5270 (class 0 OID 0)
-- Dependencies: 436
-- Name: program_retention_metrics_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.program_retention_metrics_metric_id_seq OWNED BY public.program_retention_metrics.metric_id;


--
-- TOC entry 437 (class 1259 OID 197575)
-- Name: project_assignments_assignment_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.project_assignments_assignment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.project_assignments_assignment_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5271 (class 0 OID 0)
-- Dependencies: 437
-- Name: project_assignments_assignment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.project_assignments_assignment_id_seq OWNED BY public.project_assignments.assignment_id;


--
-- TOC entry 438 (class 1259 OID 197576)
-- Name: prosper_score_metrics; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.prosper_score_metrics (
    metric_id integer NOT NULL,
    measurement_period character varying(50),
    total_employees integer,
    improved_employees integer,
    improvement_threshold numeric(5,2) DEFAULT 10.00,
    achievement_rate numeric(5,2),
    period_start date,
    period_end date,
    CONSTRAINT valid_metrics CHECK (((improvement_threshold > (0)::numeric) AND ((achievement_rate >= (0)::numeric) AND (achievement_rate <= (100)::numeric))))
);


ALTER TABLE public.prosper_score_metrics OWNER TO "prosper-dev_owner";

--
-- TOC entry 439 (class 1259 OID 197581)
-- Name: prosper_score_metrics_metric_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.prosper_score_metrics_metric_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.prosper_score_metrics_metric_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5272 (class 0 OID 0)
-- Dependencies: 439
-- Name: prosper_score_metrics_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.prosper_score_metrics_metric_id_seq OWNED BY public.prosper_score_metrics.metric_id;


--
-- TOC entry 440 (class 1259 OID 197582)
-- Name: query_patterns; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.query_patterns (
    pattern_id bigint NOT NULL,
    pattern_hash text NOT NULL,
    query_pattern text NOT NULL,
    first_seen timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    last_seen timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    execution_count bigint DEFAULT 1,
    total_time numeric DEFAULT 0,
    mean_time numeric DEFAULT 0,
    min_time numeric,
    max_time numeric,
    stddev_time numeric,
    rows_processed bigint DEFAULT 0,
    shared_blks_hit bigint DEFAULT 0,
    shared_blks_read bigint DEFAULT 0,
    temp_blks_written bigint DEFAULT 0,
    optimization_status text DEFAULT 'NONE'::text,
    metadata jsonb,
    CONSTRAINT valid_optimization_status CHECK ((optimization_status = ANY (ARRAY['NONE'::text, 'ANALYZED'::text, 'OPTIMIZED'::text, 'FAILED'::text])))
);


ALTER TABLE public.query_patterns OWNER TO "prosper-dev_owner";

--
-- TOC entry 441 (class 1259 OID 197598)
-- Name: query_patterns_pattern_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.query_patterns_pattern_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.query_patterns_pattern_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5273 (class 0 OID 0)
-- Dependencies: 441
-- Name: query_patterns_pattern_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.query_patterns_pattern_id_seq OWNED BY public.query_patterns.pattern_id;


--
-- TOC entry 442 (class 1259 OID 197599)
-- Name: rate_limit_tracking; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.rate_limit_tracking (
    tracking_id bigint NOT NULL,
    identifier text NOT NULL,
    action_type text NOT NULL,
    "timestamp" timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    request_details jsonb
);


ALTER TABLE public.rate_limit_tracking OWNER TO "prosper-dev_owner";

--
-- TOC entry 5274 (class 0 OID 0)
-- Dependencies: 442
-- Name: TABLE rate_limit_tracking; Type: COMMENT; Schema: public; Owner: prosper-dev_owner
--

COMMENT ON TABLE public.rate_limit_tracking IS 'Tracks rate limiting for various actions';


--
-- TOC entry 443 (class 1259 OID 197605)
-- Name: rate_limit_tracking_tracking_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.rate_limit_tracking_tracking_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rate_limit_tracking_tracking_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5275 (class 0 OID 0)
-- Dependencies: 443
-- Name: rate_limit_tracking_tracking_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.rate_limit_tracking_tracking_id_seq OWNED BY public.rate_limit_tracking.tracking_id;


--
-- TOC entry 444 (class 1259 OID 197606)
-- Name: relationship_assessment; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.relationship_assessment (
    assessment_id integer NOT NULL,
    employee_id integer,
    stakeholder_type character varying(50),
    relationship_strength numeric(5,2),
    interaction_frequency character varying(50),
    last_interaction_date date,
    next_action_date date,
    notes text
);


ALTER TABLE public.relationship_assessment OWNER TO "prosper-dev_owner";

--
-- TOC entry 445 (class 1259 OID 197611)
-- Name: relationship_assessment_assessment_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.relationship_assessment_assessment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.relationship_assessment_assessment_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5276 (class 0 OID 0)
-- Dependencies: 445
-- Name: relationship_assessment_assessment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.relationship_assessment_assessment_id_seq OWNED BY public.relationship_assessment.assessment_id;


--
-- TOC entry 446 (class 1259 OID 197612)
-- Name: relationship_improvement_metrics; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.relationship_improvement_metrics (
    metric_id integer NOT NULL,
    employee_id integer,
    measurement_period character varying(50),
    baseline_score numeric(5,2),
    current_score numeric(5,2),
    improvement_percentage numeric(5,2),
    stakeholder_category character varying(50),
    CONSTRAINT valid_scores CHECK (((baseline_score >= (0)::numeric) AND (baseline_score <= (5)::numeric) AND ((current_score >= (0)::numeric) AND (current_score <= (5)::numeric))))
);


ALTER TABLE public.relationship_improvement_metrics OWNER TO "prosper-dev_owner";

--
-- TOC entry 447 (class 1259 OID 197616)
-- Name: relationship_improvement_metrics_metric_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.relationship_improvement_metrics_metric_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.relationship_improvement_metrics_metric_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5277 (class 0 OID 0)
-- Dependencies: 447
-- Name: relationship_improvement_metrics_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.relationship_improvement_metrics_metric_id_seq OWNED BY public.relationship_improvement_metrics.metric_id;


--
-- TOC entry 448 (class 1259 OID 197617)
-- Name: report_definitions; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.report_definitions (
    report_id bigint NOT NULL,
    report_name text NOT NULL,
    report_type text NOT NULL,
    description text,
    query_definition jsonb NOT NULL,
    visualization_config jsonb,
    schedule_config jsonb,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT valid_report_type CHECK ((report_type = ANY (ARRAY['PERFORMANCE'::text, 'RESOURCE'::text, 'SECURITY'::text, 'BUSINESS'::text, 'CUSTOM'::text])))
);


ALTER TABLE public.report_definitions OWNER TO "prosper-dev_owner";

--
-- TOC entry 449 (class 1259 OID 197626)
-- Name: report_definitions_report_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.report_definitions_report_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.report_definitions_report_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5278 (class 0 OID 0)
-- Dependencies: 449
-- Name: report_definitions_report_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.report_definitions_report_id_seq OWNED BY public.report_definitions.report_id;


--
-- TOC entry 450 (class 1259 OID 197627)
-- Name: report_executions; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.report_executions (
    execution_id bigint NOT NULL,
    report_id bigint,
    execution_start timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    execution_end timestamp without time zone,
    status text DEFAULT 'RUNNING'::text NOT NULL,
    result_data jsonb,
    visualization_data jsonb,
    execution_metadata jsonb,
    CONSTRAINT valid_status CHECK ((status = ANY (ARRAY['RUNNING'::text, 'COMPLETED'::text, 'FAILED'::text, 'CANCELLED'::text])))
);


ALTER TABLE public.report_executions OWNER TO "prosper-dev_owner";

--
-- TOC entry 451 (class 1259 OID 197635)
-- Name: report_executions_execution_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.report_executions_execution_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.report_executions_execution_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5279 (class 0 OID 0)
-- Dependencies: 451
-- Name: report_executions_execution_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.report_executions_execution_id_seq OWNED BY public.report_executions.execution_id;


--
-- TOC entry 452 (class 1259 OID 197636)
-- Name: report_history; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.report_history (
    report_id bigint NOT NULL,
    template_id bigint,
    generation_start timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    generation_end timestamp without time zone,
    status text DEFAULT 'IN_PROGRESS'::text NOT NULL,
    report_data jsonb,
    report_metadata jsonb
);


ALTER TABLE public.report_history OWNER TO "prosper-dev_owner";

--
-- TOC entry 453 (class 1259 OID 197643)
-- Name: report_history_report_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.report_history_report_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.report_history_report_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5280 (class 0 OID 0)
-- Dependencies: 453
-- Name: report_history_report_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.report_history_report_id_seq OWNED BY public.report_history.report_id;


--
-- TOC entry 454 (class 1259 OID 197644)
-- Name: report_templates; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.report_templates (
    template_id bigint NOT NULL,
    template_name text NOT NULL,
    template_type text NOT NULL,
    template_config jsonb NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT valid_template_type CHECK ((template_type = ANY (ARRAY['PERFORMANCE'::text, 'SECURITY'::text, 'MAINTENANCE'::text, 'CUSTOM'::text])))
);


ALTER TABLE public.report_templates OWNER TO "prosper-dev_owner";

--
-- TOC entry 455 (class 1259 OID 197653)
-- Name: report_templates_template_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.report_templates_template_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.report_templates_template_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5281 (class 0 OID 0)
-- Dependencies: 455
-- Name: report_templates_template_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.report_templates_template_id_seq OWNED BY public.report_templates.template_id;


--
-- TOC entry 456 (class 1259 OID 197654)
-- Name: resource_allocation_allocation_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.resource_allocation_allocation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.resource_allocation_allocation_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5282 (class 0 OID 0)
-- Dependencies: 456
-- Name: resource_allocation_allocation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.resource_allocation_allocation_id_seq OWNED BY public.resource_allocation.allocation_id;


--
-- TOC entry 457 (class 1259 OID 197655)
-- Name: resource_allocation_history; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.resource_allocation_history (
    history_id integer NOT NULL,
    allocation_id integer,
    employee_id integer,
    change_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    old_allocation_percentage numeric(5,2),
    new_allocation_percentage numeric(5,2),
    old_status character varying(50),
    new_status character varying(50),
    changed_by integer,
    change_reason text
);


ALTER TABLE public.resource_allocation_history OWNER TO "prosper-dev_owner";

--
-- TOC entry 458 (class 1259 OID 197661)
-- Name: resource_allocation_history_history_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.resource_allocation_history_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.resource_allocation_history_history_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5283 (class 0 OID 0)
-- Dependencies: 458
-- Name: resource_allocation_history_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.resource_allocation_history_history_id_seq OWNED BY public.resource_allocation_history.history_id;


--
-- TOC entry 459 (class 1259 OID 197662)
-- Name: resource_utilization_view; Type: VIEW; Schema: public; Owner: prosper-dev_owner
--

CREATE VIEW public.resource_utilization_view AS
 SELECT e.employee_id,
    e.employee_name,
    e.department_id,
    CURRENT_DATE AS report_date,
    COALESCE(sum(
        CASE
            WHEN ((ra.start_date <= CURRENT_DATE) AND (ra.end_date >= CURRENT_DATE)) THEN ra.allocation_percentage
            ELSE (0)::numeric
        END), (0)::numeric) AS current_allocation_percentage,
    count(DISTINCT pa.project_code) AS active_projects,
    sum(
        CASE
            WHEN pa.billable THEN pa.weekly_hours
            ELSE (0)::numeric
        END) AS billable_hours,
    sum(
        CASE
            WHEN (NOT pa.billable) THEN pa.weekly_hours
            ELSE (0)::numeric
        END) AS non_billable_hours
   FROM ((public.employee_manager_hierarchy e
     LEFT JOIN public.resource_allocation ra ON ((e.employee_id = ra.employee_id)))
     LEFT JOIN public.project_assignments pa ON (((e.employee_id = pa.employee_id) AND ((pa.assignment_status)::text = 'active'::text))))
  WHERE (e.active = true)
  GROUP BY e.employee_id, e.employee_name, e.department_id;


ALTER VIEW public.resource_utilization_view OWNER TO "prosper-dev_owner";

--
-- TOC entry 460 (class 1259 OID 197667)
-- Name: review_cycles; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.review_cycles (
    cycle_id integer NOT NULL,
    cycle_name character varying(100),
    start_date date,
    end_date date,
    status character varying(50),
    participants jsonb,
    completion_status jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.review_cycles OWNER TO "prosper-dev_owner";

--
-- TOC entry 461 (class 1259 OID 197673)
-- Name: review_cycles_cycle_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.review_cycles_cycle_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.review_cycles_cycle_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5284 (class 0 OID 0)
-- Dependencies: 461
-- Name: review_cycles_cycle_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.review_cycles_cycle_id_seq OWNED BY public.review_cycles.cycle_id;


--
-- TOC entry 462 (class 1259 OID 197674)
-- Name: review_templates; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.review_templates (
    template_id integer NOT NULL,
    template_name character varying(100),
    category character varying(50),
    sections jsonb[],
    scoring_criteria jsonb,
    required_approvers integer[],
    active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.review_templates OWNER TO "prosper-dev_owner";

--
-- TOC entry 463 (class 1259 OID 197681)
-- Name: review_templates_template_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.review_templates_template_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.review_templates_template_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5285 (class 0 OID 0)
-- Dependencies: 463
-- Name: review_templates_template_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.review_templates_template_id_seq OWNED BY public.review_templates.template_id;


--
-- TOC entry 464 (class 1259 OID 197682)
-- Name: satisfaction_survey_metrics; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.satisfaction_survey_metrics (
    metric_id integer NOT NULL,
    survey_period character varying(50),
    survey_date date,
    total_respondents integer,
    average_score numeric(3,2),
    target_score numeric(3,2) DEFAULT 4.00,
    response_distribution jsonb,
    CONSTRAINT valid_score CHECK (((average_score >= (1)::numeric) AND (average_score <= (5)::numeric)))
);


ALTER TABLE public.satisfaction_survey_metrics OWNER TO "prosper-dev_owner";

--
-- TOC entry 465 (class 1259 OID 197689)
-- Name: satisfaction_survey_metrics_metric_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.satisfaction_survey_metrics_metric_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.satisfaction_survey_metrics_metric_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5286 (class 0 OID 0)
-- Dependencies: 465
-- Name: satisfaction_survey_metrics_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.satisfaction_survey_metrics_metric_id_seq OWNED BY public.satisfaction_survey_metrics.metric_id;


--
-- TOC entry 466 (class 1259 OID 197690)
-- Name: scheduled_jobs; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.scheduled_jobs (
    job_id bigint NOT NULL,
    job_name text NOT NULL,
    job_type text NOT NULL,
    description text,
    schedule_type text NOT NULL,
    cron_expression text,
    interval_value interval,
    target_type text NOT NULL,
    target_id bigint NOT NULL,
    parameters jsonb DEFAULT '{}'::jsonb,
    is_active boolean DEFAULT true,
    last_run timestamp without time zone,
    next_run timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT valid_job_type CHECK ((job_type = ANY (ARRAY['WORKFLOW'::text, 'REPORT'::text, 'MAINTENANCE'::text, 'CUSTOM'::text]))),
    CONSTRAINT valid_schedule_type CHECK ((schedule_type = ANY (ARRAY['CRON'::text, 'INTERVAL'::text, 'FIXED_TIME'::text]))),
    CONSTRAINT valid_target_type CHECK ((target_type = ANY (ARRAY['WORKFLOW'::text, 'REPORT'::text, 'FUNCTION'::text, 'SQL'::text])))
);


ALTER TABLE public.scheduled_jobs OWNER TO "prosper-dev_owner";

--
-- TOC entry 467 (class 1259 OID 197702)
-- Name: scheduled_jobs_job_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.scheduled_jobs_job_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.scheduled_jobs_job_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5287 (class 0 OID 0)
-- Dependencies: 467
-- Name: scheduled_jobs_job_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.scheduled_jobs_job_id_seq OWNED BY public.scheduled_jobs.job_id;


--
-- TOC entry 468 (class 1259 OID 197703)
-- Name: schema_versions; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.schema_versions (
    version_id bigint NOT NULL,
    version_number text NOT NULL,
    is_current boolean DEFAULT false,
    deployed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deployment_id bigint,
    schema_snapshot jsonb,
    metadata jsonb
);


ALTER TABLE public.schema_versions OWNER TO "prosper-dev_owner";

--
-- TOC entry 469 (class 1259 OID 197710)
-- Name: schema_versions_version_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.schema_versions_version_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.schema_versions_version_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5288 (class 0 OID 0)
-- Dependencies: 469
-- Name: schema_versions_version_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.schema_versions_version_id_seq OWNED BY public.schema_versions.version_id;


--
-- TOC entry 470 (class 1259 OID 197711)
-- Name: score_history; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.score_history (
    history_id integer NOT NULL,
    employee_id integer,
    category character varying(50),
    score_type character varying(50),
    old_value numeric(5,2),
    new_value numeric(5,2),
    change_date timestamp without time zone,
    changed_by integer,
    reason text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.score_history OWNER TO "prosper-dev_owner";

--
-- TOC entry 471 (class 1259 OID 197717)
-- Name: score_history_history_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.score_history_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.score_history_history_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5289 (class 0 OID 0)
-- Dependencies: 471
-- Name: score_history_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.score_history_history_id_seq OWNED BY public.score_history.history_id;


--
-- TOC entry 472 (class 1259 OID 197718)
-- Name: security_events; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.security_events (
    event_id bigint NOT NULL,
    event_type text NOT NULL,
    event_time timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ip_address inet,
    user_id integer,
    event_details jsonb,
    severity text DEFAULT 'NORMAL'::text,
    CONSTRAINT valid_severity CHECK ((severity = ANY (ARRAY['NORMAL'::text, 'HIGH'::text, 'CRITICAL'::text])))
);


ALTER TABLE public.security_events OWNER TO "prosper-dev_owner";

--
-- TOC entry 5290 (class 0 OID 0)
-- Dependencies: 472
-- Name: TABLE security_events; Type: COMMENT; Schema: public; Owner: prosper-dev_owner
--

COMMENT ON TABLE public.security_events IS 'Stores security-related events for monitoring and analysis';


--
-- TOC entry 473 (class 1259 OID 197726)
-- Name: security_events_event_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.security_events_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.security_events_event_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5291 (class 0 OID 0)
-- Dependencies: 473
-- Name: security_events_event_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.security_events_event_id_seq OWNED BY public.security_events.event_id;


--
-- TOC entry 474 (class 1259 OID 197727)
-- Name: security_events_summary; Type: VIEW; Schema: public; Owner: prosper-dev_owner
--

CREATE VIEW public.security_events_summary AS
 SELECT event_type,
    count(*) AS event_count,
    min(event_time) AS first_occurrence,
    max(event_time) AS last_occurrence,
    count(DISTINCT user_id) AS unique_users,
    count(DISTINCT ip_address) AS unique_ips,
    mode() WITHIN GROUP (ORDER BY severity) AS most_common_severity
   FROM public.security_events
  WHERE (event_time > (CURRENT_TIMESTAMP - '24:00:00'::interval))
  GROUP BY event_type;


ALTER VIEW public.security_events_summary OWNER TO "prosper-dev_owner";

--
-- TOC entry 475 (class 1259 OID 197731)
-- Name: security_monitoring_log; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.security_monitoring_log (
    log_id bigint NOT NULL,
    execution_time timestamp without time zone NOT NULL,
    lookback_hours integer NOT NULL,
    alert_threshold integer NOT NULL,
    execution_duration interval NOT NULL,
    findings jsonb NOT NULL
);


ALTER TABLE public.security_monitoring_log OWNER TO "prosper-dev_owner";

--
-- TOC entry 5292 (class 0 OID 0)
-- Dependencies: 475
-- Name: TABLE security_monitoring_log; Type: COMMENT; Schema: public; Owner: prosper-dev_owner
--

COMMENT ON TABLE public.security_monitoring_log IS 'Logs the execution of security monitoring functions';


--
-- TOC entry 476 (class 1259 OID 197736)
-- Name: security_monitoring_log_log_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.security_monitoring_log_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.security_monitoring_log_log_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5293 (class 0 OID 0)
-- Dependencies: 476
-- Name: security_monitoring_log_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.security_monitoring_log_log_id_seq OWNED BY public.security_monitoring_log.log_id;


--
-- TOC entry 477 (class 1259 OID 197737)
-- Name: security_notifications; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.security_notifications (
    notification_id bigint NOT NULL,
    notification_type text NOT NULL,
    severity text NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    processed_at timestamp without time zone,
    notification_status text DEFAULT 'PENDING'::text NOT NULL,
    recipient_list jsonb,
    message_content jsonb,
    CONSTRAINT valid_notification_status CHECK ((notification_status = ANY (ARRAY['PENDING'::text, 'SENT'::text, 'FAILED'::text, 'CANCELLED'::text])))
);


ALTER TABLE public.security_notifications OWNER TO "prosper-dev_owner";

--
-- TOC entry 478 (class 1259 OID 197745)
-- Name: security_notifications_notification_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.security_notifications_notification_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.security_notifications_notification_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5294 (class 0 OID 0)
-- Dependencies: 478
-- Name: security_notifications_notification_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.security_notifications_notification_id_seq OWNED BY public.security_notifications.notification_id;


--
-- TOC entry 479 (class 1259 OID 197746)
-- Name: skill_requirements; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.skill_requirements (
    requirement_id integer NOT NULL,
    role_name character varying(100),
    category character varying(50),
    required_skills jsonb,
    minimum_proficiency numeric(5,2),
    preferred_certifications text[],
    experience_level character varying(50),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.skill_requirements OWNER TO "prosper-dev_owner";

--
-- TOC entry 480 (class 1259 OID 197752)
-- Name: skill_requirements_requirement_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.skill_requirements_requirement_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.skill_requirements_requirement_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5295 (class 0 OID 0)
-- Dependencies: 480
-- Name: skill_requirements_requirement_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.skill_requirements_requirement_id_seq OWNED BY public.skill_requirements.requirement_id;


--
-- TOC entry 481 (class 1259 OID 197753)
-- Name: skills_gap_analysis; Type: VIEW; Schema: public; Owner: prosper-dev_owner
--

CREATE VIEW public.skills_gap_analysis AS
 SELECT d.department_name,
    si.category,
    sr.role_name,
    sr.required_skills,
    count(DISTINCT
        CASE
            WHEN (si.proficiency_level >= sr.minimum_proficiency) THEN si.employee_id
            ELSE NULL::integer
        END) AS qualified_employees,
    count(DISTINCT emh.employee_id) AS total_employees,
    round(avg(si.proficiency_level), 2) AS avg_proficiency,
    jsonb_agg(DISTINCT jsonb_build_object('skill_name', si.skill_name, 'gap_size', (sr.minimum_proficiency - si.proficiency_level))) FILTER (WHERE (si.proficiency_level < sr.minimum_proficiency)) AS skill_gaps
   FROM (((public.department d
     JOIN public.employee_manager_hierarchy emh ON ((d.department_id = emh.department_id)))
     JOIN public.skills_inventory si ON ((emh.employee_id = si.employee_id)))
     JOIN public.skill_requirements sr ON (((si.category)::text = (sr.category)::text)))
  GROUP BY d.department_name, si.category, sr.role_name, sr.required_skills;


ALTER VIEW public.skills_gap_analysis OWNER TO "prosper-dev_owner";

--
-- TOC entry 482 (class 1259 OID 197758)
-- Name: skills_inventory_skill_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.skills_inventory_skill_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.skills_inventory_skill_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5296 (class 0 OID 0)
-- Dependencies: 482
-- Name: skills_inventory_skill_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.skills_inventory_skill_id_seq OWNED BY public.skills_inventory.skill_id;


--
-- TOC entry 483 (class 1259 OID 197759)
-- Name: stakeholder_relationship_history; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.stakeholder_relationship_history (
    history_id integer NOT NULL,
    employee_id integer,
    stakeholder_id integer,
    relationship_type character varying(50),
    quality_score numeric(3,2),
    interaction_date date,
    notes text
);


ALTER TABLE public.stakeholder_relationship_history OWNER TO "prosper-dev_owner";

--
-- TOC entry 484 (class 1259 OID 197764)
-- Name: stakeholder_relationship_history_history_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.stakeholder_relationship_history_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.stakeholder_relationship_history_history_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5297 (class 0 OID 0)
-- Dependencies: 484
-- Name: stakeholder_relationship_history_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.stakeholder_relationship_history_history_id_seq OWNED BY public.stakeholder_relationship_history.history_id;


--
-- TOC entry 485 (class 1259 OID 197765)
-- Name: system_configurations; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.system_configurations (
    config_id bigint NOT NULL,
    config_name text NOT NULL,
    config_value text,
    config_type text NOT NULL,
    is_active boolean DEFAULT true,
    description text,
    validation_rules jsonb,
    last_modified timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_by text NOT NULL,
    CONSTRAINT valid_config_type CHECK ((config_type = ANY (ARRAY['DATABASE'::text, 'APPLICATION'::text, 'SECURITY'::text, 'MAINTENANCE'::text, 'CUSTOM'::text])))
);


ALTER TABLE public.system_configurations OWNER TO "prosper-dev_owner";

--
-- TOC entry 486 (class 1259 OID 197773)
-- Name: system_configurations_config_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.system_configurations_config_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.system_configurations_config_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5298 (class 0 OID 0)
-- Dependencies: 486
-- Name: system_configurations_config_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.system_configurations_config_id_seq OWNED BY public.system_configurations.config_id;


--
-- TOC entry 487 (class 1259 OID 197774)
-- Name: system_integration_mapping; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.system_integration_mapping (
    mapping_id integer NOT NULL,
    source_system character varying(50),
    source_field character varying(100),
    target_table character varying(100),
    target_field character varying(100),
    transformation_rule jsonb,
    is_active boolean DEFAULT true
);


ALTER TABLE public.system_integration_mapping OWNER TO "prosper-dev_owner";

--
-- TOC entry 488 (class 1259 OID 197780)
-- Name: system_integration_mapping_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.system_integration_mapping_mapping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.system_integration_mapping_mapping_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5299 (class 0 OID 0)
-- Dependencies: 488
-- Name: system_integration_mapping_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.system_integration_mapping_mapping_id_seq OWNED BY public.system_integration_mapping.mapping_id;


--
-- TOC entry 489 (class 1259 OID 197781)
-- Name: system_integrations; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.system_integrations (
    integration_id integer NOT NULL,
    system_name character varying(100),
    integration_type character varying(50),
    configuration jsonb,
    status character varying(50),
    last_sync timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.system_integrations OWNER TO "prosper-dev_owner";

--
-- TOC entry 490 (class 1259 OID 197787)
-- Name: system_integrations_integration_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.system_integrations_integration_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.system_integrations_integration_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5300 (class 0 OID 0)
-- Dependencies: 490
-- Name: system_integrations_integration_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.system_integrations_integration_id_seq OWNED BY public.system_integrations.integration_id;


--
-- TOC entry 491 (class 1259 OID 197788)
-- Name: system_metrics_history; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.system_metrics_history (
    metric_id bigint NOT NULL,
    metric_name text NOT NULL,
    metric_value numeric NOT NULL,
    metric_type text NOT NULL,
    collection_time timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    granularity text NOT NULL,
    dimensions jsonb,
    CONSTRAINT valid_granularity CHECK ((granularity = ANY (ARRAY['MINUTE'::text, 'HOUR'::text, 'DAY'::text, 'MONTH'::text]))),
    CONSTRAINT valid_metric_type CHECK ((metric_type = ANY (ARRAY['PERFORMANCE'::text, 'RESOURCE'::text, 'BUSINESS'::text, 'CUSTOM'::text])))
);


ALTER TABLE public.system_metrics_history OWNER TO "prosper-dev_owner";

--
-- TOC entry 492 (class 1259 OID 197796)
-- Name: system_metrics_history_metric_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.system_metrics_history_metric_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.system_metrics_history_metric_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5301 (class 0 OID 0)
-- Dependencies: 492
-- Name: system_metrics_history_metric_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.system_metrics_history_metric_id_seq OWNED BY public.system_metrics_history.metric_id;


--
-- TOC entry 493 (class 1259 OID 197797)
-- Name: system_settings; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.system_settings (
    setting_id integer NOT NULL,
    setting_name character varying(100),
    setting_value jsonb,
    category character varying(50),
    description text,
    last_modified timestamp without time zone,
    modified_by integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.system_settings OWNER TO "prosper-dev_owner";

--
-- TOC entry 494 (class 1259 OID 197803)
-- Name: system_settings_setting_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.system_settings_setting_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.system_settings_setting_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5302 (class 0 OID 0)
-- Dependencies: 494
-- Name: system_settings_setting_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.system_settings_setting_id_seq OWNED BY public.system_settings.setting_id;


--
-- TOC entry 495 (class 1259 OID 197804)
-- Name: team_collaboration; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.team_collaboration (
    collaboration_id integer NOT NULL,
    team_id integer,
    project_id integer,
    collaboration_type character varying(50),
    effectiveness_score numeric(5,2),
    challenges text[],
    success_factors jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.team_collaboration OWNER TO "prosper-dev_owner";

--
-- TOC entry 496 (class 1259 OID 197810)
-- Name: team_collaboration_collaboration_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.team_collaboration_collaboration_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.team_collaboration_collaboration_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5303 (class 0 OID 0)
-- Dependencies: 496
-- Name: team_collaboration_collaboration_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.team_collaboration_collaboration_id_seq OWNED BY public.team_collaboration.collaboration_id;


--
-- TOC entry 497 (class 1259 OID 197811)
-- Name: team_dynamics; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.team_dynamics (
    dynamics_id integer NOT NULL,
    team_id integer,
    assessment_date date,
    collaboration_score numeric(5,2),
    communication_score numeric(5,2),
    innovation_score numeric(5,2),
    conflict_resolution_score numeric(5,2),
    team_metrics jsonb,
    interaction_patterns jsonb[],
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.team_dynamics OWNER TO "prosper-dev_owner";

--
-- TOC entry 498 (class 1259 OID 197817)
-- Name: team_dynamics_dynamics_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.team_dynamics_dynamics_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.team_dynamics_dynamics_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5304 (class 0 OID 0)
-- Dependencies: 498
-- Name: team_dynamics_dynamics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.team_dynamics_dynamics_id_seq OWNED BY public.team_dynamics.dynamics_id;


--
-- TOC entry 499 (class 1259 OID 197818)
-- Name: team_structure; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.team_structure (
    team_id integer NOT NULL,
    team_name character varying(100),
    manager_id integer,
    department_id integer,
    team_type character varying(50),
    formation_date date,
    status character varying(50),
    team_metrics jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    team_size integer,
    team_level character varying(50),
    parent_team_id integer,
    team_objectives jsonb,
    budget_center character varying(100),
    last_modified_by integer,
    last_modified_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.team_structure OWNER TO "prosper-dev_owner";

--
-- TOC entry 500 (class 1259 OID 197825)
-- Name: team_performance_dashboard; Type: VIEW; Schema: public; Owner: prosper-dev_owner
--

CREATE VIEW public.team_performance_dashboard AS
 SELECT ts.team_id,
    ts.team_name,
    ts.manager_id,
    count(DISTINCT emh.employee_id) AS team_size,
    round(avg(ps.average_score), 2) AS avg_team_score,
    min(ps.average_score) AS min_score,
    max(ps.average_score) AS max_score,
    count(DISTINCT
        CASE
            WHEN (ps.average_score >= (8)::numeric) THEN emh.employee_id
            ELSE NULL::integer
        END) AS high_performers,
    count(DISTINCT
        CASE
            WHEN (ps.average_score < (6)::numeric) THEN emh.employee_id
            ELSE NULL::integer
        END) AS needs_improvement
   FROM ((public.team_structure ts
     JOIN public.employee_manager_hierarchy emh ON ((ts.team_id = emh.team_id)))
     LEFT JOIN public.performance_scores ps ON ((emh.employee_id = ps.employee_id)))
  GROUP BY ts.team_id, ts.team_name, ts.manager_id;


ALTER VIEW public.team_performance_dashboard OWNER TO "prosper-dev_owner";

--
-- TOC entry 501 (class 1259 OID 197830)
-- Name: team_performance_summary; Type: MATERIALIZED VIEW; Schema: public; Owner: prosper-dev_owner
--

CREATE MATERIALIZED VIEW public.team_performance_summary AS
 WITH categorytrends AS (
         SELECT ts_1.team_id,
            ps_1.category,
            ps_1.evaluation_date,
            avg(ps_1.average_score) AS avg_score,
            lag(avg(ps_1.average_score)) OVER (PARTITION BY ts_1.team_id, ps_1.category ORDER BY ps_1.evaluation_date) AS prev_score
           FROM ((public.team_structure ts_1
             JOIN public.employee_manager_hierarchy emh_1 ON ((ts_1.team_id = emh_1.team_id)))
             JOIN public.performance_scores ps_1 ON ((emh_1.employee_id = ps_1.employee_id)))
          GROUP BY ts_1.team_id, ps_1.category, ps_1.evaluation_date
        )
 SELECT ts.team_id,
    ts.team_name,
    d.department_name,
    count(DISTINCT emh.employee_id) AS team_size,
    round(avg(ps.average_score), 2) AS avg_performance,
    count(DISTINCT
        CASE
            WHEN (ps.average_score >= (8)::numeric) THEN emh.employee_id
            ELSE NULL::integer
        END) AS high_performers,
    jsonb_object_agg(ct.category, jsonb_build_object('avg_score', round(ct.avg_score, 2), 'trend',
        CASE
            WHEN (ct.avg_score > ct.prev_score) THEN 'Improving'::text
            WHEN (ct.avg_score < ct.prev_score) THEN 'Declining'::text
            ELSE 'Stable'::text
        END)) AS category_performance,
    count(DISTINCT cr.cert_id) AS total_certifications,
    jsonb_agg(DISTINCT si.skill_name) FILTER (WHERE (si.proficiency_level >= (8)::numeric)) AS team_strengths
   FROM ((((((public.team_structure ts
     JOIN public.employee_manager_hierarchy emh ON ((ts.team_id = emh.team_id)))
     JOIN public.department d ON ((emh.department_id = d.department_id)))
     LEFT JOIN public.performance_scores ps ON ((emh.employee_id = ps.employee_id)))
     LEFT JOIN categorytrends ct ON ((ts.team_id = ct.team_id)))
     LEFT JOIN public.certification_registry cr ON ((emh.employee_id = cr.employee_id)))
     LEFT JOIN public.skills_inventory si ON ((emh.employee_id = si.employee_id)))
  GROUP BY ts.team_id, ts.team_name, d.department_name
  WITH NO DATA;


ALTER MATERIALIZED VIEW public.team_performance_summary OWNER TO "prosper-dev_owner";

--
-- TOC entry 502 (class 1259 OID 197837)
-- Name: team_structure_team_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.team_structure_team_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.team_structure_team_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5305 (class 0 OID 0)
-- Dependencies: 502
-- Name: team_structure_team_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.team_structure_team_id_seq OWNED BY public.team_structure.team_id;


--
-- TOC entry 503 (class 1259 OID 197838)
-- Name: test_cases; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.test_cases (
    test_id bigint NOT NULL,
    suite_id bigint,
    test_name text NOT NULL,
    test_query text NOT NULL,
    expected_result jsonb NOT NULL,
    timeout interval DEFAULT '00:00:30'::interval,
    retry_count integer DEFAULT 0,
    is_active boolean DEFAULT true,
    tags text[]
);


ALTER TABLE public.test_cases OWNER TO "prosper-dev_owner";

--
-- TOC entry 504 (class 1259 OID 197846)
-- Name: test_cases_test_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.test_cases_test_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.test_cases_test_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5306 (class 0 OID 0)
-- Dependencies: 504
-- Name: test_cases_test_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.test_cases_test_id_seq OWNED BY public.test_cases.test_id;


--
-- TOC entry 505 (class 1259 OID 197847)
-- Name: test_executions; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.test_executions (
    execution_id bigint NOT NULL,
    test_id bigint,
    execution_start timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    execution_end timestamp without time zone,
    status text NOT NULL,
    actual_result jsonb,
    execution_details jsonb,
    CONSTRAINT valid_status CHECK ((status = ANY (ARRAY['PENDING'::text, 'RUNNING'::text, 'PASSED'::text, 'FAILED'::text, 'ERROR'::text, 'SKIPPED'::text])))
);


ALTER TABLE public.test_executions OWNER TO "prosper-dev_owner";

--
-- TOC entry 506 (class 1259 OID 197854)
-- Name: test_executions_execution_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.test_executions_execution_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.test_executions_execution_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5307 (class 0 OID 0)
-- Dependencies: 506
-- Name: test_executions_execution_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.test_executions_execution_id_seq OWNED BY public.test_executions.execution_id;


--
-- TOC entry 507 (class 1259 OID 197855)
-- Name: test_suites; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.test_suites (
    suite_id bigint NOT NULL,
    suite_name text NOT NULL,
    suite_type text NOT NULL,
    is_active boolean DEFAULT true,
    execution_order integer,
    dependencies jsonb,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT valid_suite_type CHECK ((suite_type = ANY (ARRAY['UNIT'::text, 'INTEGRATION'::text, 'PERFORMANCE'::text, 'SECURITY'::text, 'CUSTOM'::text])))
);


ALTER TABLE public.test_suites OWNER TO "prosper-dev_owner";

--
-- TOC entry 508 (class 1259 OID 197863)
-- Name: test_suites_suite_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.test_suites_suite_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.test_suites_suite_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5308 (class 0 OID 0)
-- Dependencies: 508
-- Name: test_suites_suite_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.test_suites_suite_id_seq OWNED BY public.test_suites.suite_id;


--
-- TOC entry 509 (class 1259 OID 197864)
-- Name: training_records; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.training_records (
    training_id integer NOT NULL,
    employee_id integer,
    training_name character varying(100),
    category character varying(50),
    completion_date date,
    score numeric(5,2),
    duration_hours integer,
    effectiveness_rating numeric(5,2),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.training_records OWNER TO "prosper-dev_owner";

--
-- TOC entry 510 (class 1259 OID 197868)
-- Name: training_completion_metrics; Type: VIEW; Schema: public; Owner: prosper-dev_owner
--

CREATE VIEW public.training_completion_metrics AS
 SELECT e.employee_name,
    e.department_id,
    count(t.training_id) AS total_trainings,
    round(avg(t.score), 2) AS avg_training_score,
    round(avg(t.effectiveness_rating), 2) AS avg_effectiveness,
    sum(t.duration_hours) AS total_training_hours,
    count(
        CASE
            WHEN (t.completion_date >= (CURRENT_DATE - '1 year'::interval)) THEN 1
            ELSE NULL::integer
        END) AS trainings_last_12_months
   FROM (public.employee_manager_hierarchy e
     LEFT JOIN public.training_records t ON ((e.employee_id = t.employee_id)))
  GROUP BY e.employee_name, e.department_id;


ALTER VIEW public.training_completion_metrics OWNER TO "prosper-dev_owner";

--
-- TOC entry 511 (class 1259 OID 197873)
-- Name: training_records_training_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.training_records_training_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.training_records_training_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5309 (class 0 OID 0)
-- Dependencies: 511
-- Name: training_records_training_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.training_records_training_id_seq OWNED BY public.training_records.training_id;


--
-- TOC entry 512 (class 1259 OID 197874)
-- Name: trend_analysis; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.trend_analysis (
    analysis_id integer NOT NULL,
    metric_type character varying(50),
    period_start date,
    period_end date,
    trend_direction character varying(20),
    change_percentage numeric(5,2),
    contributing_factors jsonb,
    recommendations text
);


ALTER TABLE public.trend_analysis OWNER TO "prosper-dev_owner";

--
-- TOC entry 513 (class 1259 OID 197879)
-- Name: trend_analysis_analysis_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.trend_analysis_analysis_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.trend_analysis_analysis_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5310 (class 0 OID 0)
-- Dependencies: 513
-- Name: trend_analysis_analysis_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.trend_analysis_analysis_id_seq OWNED BY public.trend_analysis.analysis_id;


--
-- TOC entry 514 (class 1259 OID 197880)
-- Name: user_sessions; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.user_sessions (
    session_id text NOT NULL,
    user_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamp without time zone NOT NULL,
    is_valid boolean DEFAULT true,
    ip_address inet,
    user_agent text
);


ALTER TABLE public.user_sessions OWNER TO "prosper-dev_owner";

--
-- TOC entry 515 (class 1259 OID 197887)
-- Name: users; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.users (
    user_id integer NOT NULL,
    username character varying(50) NOT NULL,
    email character varying(255) NOT NULL,
    password_hash text NOT NULL,
    salt text NOT NULL,
    role character varying(20) DEFAULT 'user'::character varying NOT NULL,
    is_active boolean DEFAULT true,
    last_login timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.users OWNER TO "prosper-dev_owner";

--
-- TOC entry 516 (class 1259 OID 197896)
-- Name: users_user_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.users_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_user_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5311 (class 0 OID 0)
-- Dependencies: 516
-- Name: users_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.users_user_id_seq OWNED BY public.users.user_id;


--
-- TOC entry 517 (class 1259 OID 197897)
-- Name: workflow_definitions; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.workflow_definitions (
    workflow_id integer NOT NULL,
    workflow_name character varying(100),
    category character varying(50),
    steps jsonb[],
    approvers jsonb,
    sla_hours integer,
    active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    workflow_type character varying(50)
);


ALTER TABLE public.workflow_definitions OWNER TO "prosper-dev_owner";

--
-- TOC entry 518 (class 1259 OID 197904)
-- Name: workflow_instances; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.workflow_instances (
    instance_id integer NOT NULL,
    workflow_id integer,
    initiator_id integer,
    current_step integer,
    status character varying(50),
    start_date timestamp without time zone,
    completion_date timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    priority character varying(20) DEFAULT 'medium'::character varying,
    due_date timestamp without time zone,
    last_action_date timestamp without time zone,
    current_assignee integer,
    escalation_level integer DEFAULT 0,
    workflow_data jsonb,
    step_history jsonb[],
    last_modified_by integer,
    last_modified_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.workflow_instances OWNER TO "prosper-dev_owner";

--
-- TOC entry 519 (class 1259 OID 197913)
-- Name: workflow_step_history; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.workflow_step_history (
    history_id integer NOT NULL,
    instance_id integer,
    step_number integer,
    step_name character varying(100),
    assignee_id integer,
    action_taken character varying(50),
    action_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    comments text,
    time_spent interval,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.workflow_step_history OWNER TO "prosper-dev_owner";

--
-- TOC entry 520 (class 1259 OID 197920)
-- Name: workflow_bottleneck_analysis; Type: VIEW; Schema: public; Owner: prosper-dev_owner
--

CREATE VIEW public.workflow_bottleneck_analysis AS
 WITH step_timing AS (
         SELECT wi.workflow_id,
            wsh.step_number,
            wsh.step_name,
            avg(wsh.time_spent) AS avg_time_spent,
            count(*) AS total_occurrences,
            count(
                CASE
                    WHEN (wi.escalation_level > 0) THEN 1
                    ELSE NULL::integer
                END) AS escalation_count
           FROM (public.workflow_instances wi
             JOIN public.workflow_step_history wsh ON ((wi.instance_id = wsh.instance_id)))
          WHERE (wi.start_date >= (CURRENT_DATE - '90 days'::interval))
          GROUP BY wi.workflow_id, wsh.step_number, wsh.step_name
        )
 SELECT COALESCE(wd.workflow_type, wd.workflow_name) AS workflow_type,
    st.step_number,
    st.step_name,
    st.avg_time_spent,
    st.total_occurrences,
    st.escalation_count,
    round((((st.escalation_count)::numeric / (NULLIF(st.total_occurrences, 0))::numeric) * (100)::numeric), 2) AS escalation_percentage
   FROM (step_timing st
     JOIN public.workflow_definitions wd ON ((st.workflow_id = wd.workflow_id)))
  ORDER BY COALESCE(wd.workflow_type, wd.workflow_name), st.step_number;


ALTER VIEW public.workflow_bottleneck_analysis OWNER TO "prosper-dev_owner";

--
-- TOC entry 521 (class 1259 OID 197925)
-- Name: workflow_definitions_workflow_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.workflow_definitions_workflow_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.workflow_definitions_workflow_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5312 (class 0 OID 0)
-- Dependencies: 521
-- Name: workflow_definitions_workflow_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.workflow_definitions_workflow_id_seq OWNED BY public.workflow_definitions.workflow_id;


--
-- TOC entry 522 (class 1259 OID 197926)
-- Name: workflow_executions; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.workflow_executions (
    execution_id bigint NOT NULL,
    workflow_id bigint,
    trigger_source text NOT NULL,
    started_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    completed_at timestamp without time zone,
    status text DEFAULT 'RUNNING'::text NOT NULL,
    execution_data jsonb,
    error_details jsonb,
    CONSTRAINT valid_status CHECK ((status = ANY (ARRAY['RUNNING'::text, 'COMPLETED'::text, 'FAILED'::text, 'CANCELLED'::text])))
);


ALTER TABLE public.workflow_executions OWNER TO "prosper-dev_owner";

--
-- TOC entry 523 (class 1259 OID 197934)
-- Name: workflow_executions_execution_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.workflow_executions_execution_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.workflow_executions_execution_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5313 (class 0 OID 0)
-- Dependencies: 523
-- Name: workflow_executions_execution_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.workflow_executions_execution_id_seq OWNED BY public.workflow_executions.execution_id;


--
-- TOC entry 524 (class 1259 OID 197935)
-- Name: workflow_instances_instance_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.workflow_instances_instance_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.workflow_instances_instance_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5314 (class 0 OID 0)
-- Dependencies: 524
-- Name: workflow_instances_instance_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.workflow_instances_instance_id_seq OWNED BY public.workflow_instances.instance_id;


--
-- TOC entry 525 (class 1259 OID 197936)
-- Name: workflow_performance_metrics; Type: VIEW; Schema: public; Owner: prosper-dev_owner
--

CREATE VIEW public.workflow_performance_metrics AS
 SELECT COALESCE(wd.workflow_type, wd.workflow_name) AS workflow_type,
    count(wi.instance_id) AS total_instances,
    round(avg(
        CASE
            WHEN (wi.completion_date IS NOT NULL) THEN (EXTRACT(epoch FROM (wi.completion_date - wi.start_date)) / (3600)::numeric)
            ELSE NULL::numeric
        END), 2) AS avg_completion_hours,
    count(
        CASE
            WHEN ((wi.status)::text = 'completed'::text) THEN 1
            ELSE NULL::integer
        END) AS completed_count,
    count(
        CASE
            WHEN (((wi.status)::text = 'active'::text) AND (wi.start_date < CURRENT_DATE)) THEN 1
            ELSE NULL::integer
        END) AS overdue_count,
    round(avg(COALESCE(wi.escalation_level, 0)), 2) AS avg_escalation_level
   FROM (public.workflow_definitions wd
     LEFT JOIN public.workflow_instances wi ON ((wd.workflow_id = wi.workflow_id)))
  WHERE (wi.start_date >= (CURRENT_DATE - '30 days'::interval))
  GROUP BY COALESCE(wd.workflow_type, wd.workflow_name);


ALTER VIEW public.workflow_performance_metrics OWNER TO "prosper-dev_owner";

--
-- TOC entry 526 (class 1259 OID 197941)
-- Name: workflow_step_history_history_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.workflow_step_history_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.workflow_step_history_history_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5315 (class 0 OID 0)
-- Dependencies: 526
-- Name: workflow_step_history_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.workflow_step_history_history_id_seq OWNED BY public.workflow_step_history.history_id;


--
-- TOC entry 527 (class 1259 OID 197942)
-- Name: workflow_step_logs; Type: TABLE; Schema: public; Owner: prosper-dev_owner
--

CREATE TABLE public.workflow_step_logs (
    log_id bigint NOT NULL,
    execution_id bigint,
    step_number integer NOT NULL,
    step_name text NOT NULL,
    started_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    completed_at timestamp without time zone,
    status text DEFAULT 'RUNNING'::text NOT NULL,
    output_data jsonb,
    error_details jsonb,
    CONSTRAINT valid_status CHECK ((status = ANY (ARRAY['RUNNING'::text, 'COMPLETED'::text, 'FAILED'::text, 'SKIPPED'::text])))
);


ALTER TABLE public.workflow_step_logs OWNER TO "prosper-dev_owner";

--
-- TOC entry 528 (class 1259 OID 197950)
-- Name: workflow_step_logs_log_id_seq; Type: SEQUENCE; Schema: public; Owner: prosper-dev_owner
--

CREATE SEQUENCE public.workflow_step_logs_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.workflow_step_logs_log_id_seq OWNER TO "prosper-dev_owner";

--
-- TOC entry 5316 (class 0 OID 0)
-- Dependencies: 528
-- Name: workflow_step_logs_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: prosper-dev_owner
--

ALTER SEQUENCE public.workflow_step_logs_log_id_seq OWNED BY public.workflow_step_logs.log_id;


--
-- TOC entry 4097 (class 2604 OID 237576)
-- Name: access_control access_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.access_control ALTER COLUMN access_id SET DEFAULT nextval('public.access_control_access_id_seq'::regclass);


--
-- TOC entry 4100 (class 2604 OID 237577)
-- Name: achievement_badges badge_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.achievement_badges ALTER COLUMN badge_id SET DEFAULT nextval('public.achievement_badges_badge_id_seq'::regclass);


--
-- TOC entry 4102 (class 2604 OID 237578)
-- Name: achievement_tracking achievement_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.achievement_tracking ALTER COLUMN achievement_id SET DEFAULT nextval('public.achievement_tracking_achievement_id_seq'::regclass);


--
-- TOC entry 4103 (class 2604 OID 237579)
-- Name: action_items item_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.action_items ALTER COLUMN item_id SET DEFAULT nextval('public.action_items_item_id_seq'::regclass);


--
-- TOC entry 4105 (class 2604 OID 237580)
-- Name: alert_configuration alert_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.alert_configuration ALTER COLUMN alert_id SET DEFAULT nextval('public.alert_configuration_alert_id_seq'::regclass);


--
-- TOC entry 4108 (class 2604 OID 237581)
-- Name: alert_notifications notification_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.alert_notifications ALTER COLUMN notification_id SET DEFAULT nextval('public.alert_notifications_notification_id_seq'::regclass);


--
-- TOC entry 4109 (class 2604 OID 237582)
-- Name: analytics_dashboard dashboard_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.analytics_dashboard ALTER COLUMN dashboard_id SET DEFAULT nextval('public.analytics_dashboard_dashboard_id_seq'::regclass);


--
-- TOC entry 4111 (class 2604 OID 237583)
-- Name: api_endpoints endpoint_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.api_endpoints ALTER COLUMN endpoint_id SET DEFAULT nextval('public.api_endpoints_endpoint_id_seq'::regclass);


--
-- TOC entry 4116 (class 2604 OID 237584)
-- Name: api_keys key_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.api_keys ALTER COLUMN key_id SET DEFAULT nextval('public.api_keys_key_id_seq'::regclass);


--
-- TOC entry 4119 (class 2604 OID 237585)
-- Name: api_requests request_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.api_requests ALTER COLUMN request_id SET DEFAULT nextval('public.api_requests_request_id_seq'::regclass);


--
-- TOC entry 4121 (class 2604 OID 237586)
-- Name: audit_log log_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.audit_log ALTER COLUMN log_id SET DEFAULT nextval('public.audit_log_log_id_seq'::regclass);


--
-- TOC entry 4123 (class 2604 OID 237587)
-- Name: automation_workflows workflow_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.automation_workflows ALTER COLUMN workflow_id SET DEFAULT nextval('public.automation_workflows_workflow_id_seq'::regclass);


--
-- TOC entry 4127 (class 2604 OID 237588)
-- Name: backup_catalog backup_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.backup_catalog ALTER COLUMN backup_id SET DEFAULT nextval('public.backup_catalog_backup_id_seq'::regclass);


--
-- TOC entry 4130 (class 2604 OID 237589)
-- Name: backup_configurations config_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.backup_configurations ALTER COLUMN config_id SET DEFAULT nextval('public.backup_configurations_config_id_seq'::regclass);


--
-- TOC entry 4135 (class 2604 OID 237590)
-- Name: backup_files file_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.backup_files ALTER COLUMN file_id SET DEFAULT nextval('public.backup_files_file_id_seq'::regclass);


--
-- TOC entry 4138 (class 2604 OID 237591)
-- Name: backup_history backup_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.backup_history ALTER COLUMN backup_id SET DEFAULT nextval('public.backup_history_backup_id_seq'::regclass);


--
-- TOC entry 4141 (class 2604 OID 237592)
-- Name: backup_verification_log verification_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.backup_verification_log ALTER COLUMN verification_id SET DEFAULT nextval('public.backup_verification_log_verification_id_seq'::regclass);


--
-- TOC entry 4143 (class 2604 OID 237593)
-- Name: baseline_measurements baseline_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.baseline_measurements ALTER COLUMN baseline_id SET DEFAULT nextval('public.baseline_measurements_baseline_id_seq'::regclass);


--
-- TOC entry 4144 (class 2604 OID 237594)
-- Name: capacity_planning planning_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.capacity_planning ALTER COLUMN planning_id SET DEFAULT nextval('public.capacity_planning_planning_id_seq'::regclass);


--
-- TOC entry 4162 (class 2604 OID 237595)
-- Name: career_development_plans plan_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.career_development_plans ALTER COLUMN plan_id SET DEFAULT nextval('public.career_development_plans_plan_id_seq'::regclass);


--
-- TOC entry 4164 (class 2604 OID 237596)
-- Name: career_progression progression_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.career_progression ALTER COLUMN progression_id SET DEFAULT nextval('public.career_progression_progression_id_seq'::regclass);


--
-- TOC entry 4166 (class 2604 OID 237597)
-- Name: certification_registry cert_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.certification_registry ALTER COLUMN cert_id SET DEFAULT nextval('public.certification_registry_cert_id_seq'::regclass);


--
-- TOC entry 4168 (class 2604 OID 237598)
-- Name: communication_log log_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.communication_log ALTER COLUMN log_id SET DEFAULT nextval('public.communication_log_log_id_seq'::regclass);


--
-- TOC entry 4171 (class 2604 OID 237599)
-- Name: communication_metrics metric_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.communication_metrics ALTER COLUMN metric_id SET DEFAULT nextval('public.communication_metrics_metric_id_seq'::regclass);


--
-- TOC entry 4173 (class 2604 OID 237600)
-- Name: communication_templates template_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.communication_templates ALTER COLUMN template_id SET DEFAULT nextval('public.communication_templates_template_id_seq'::regclass);


--
-- TOC entry 4175 (class 2604 OID 237601)
-- Name: competency_framework framework_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.competency_framework ALTER COLUMN framework_id SET DEFAULT nextval('public.competency_framework_framework_id_seq'::regclass);


--
-- TOC entry 4177 (class 2604 OID 237602)
-- Name: configuration_history history_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.configuration_history ALTER COLUMN history_id SET DEFAULT nextval('public.configuration_history_history_id_seq'::regclass);


--
-- TOC entry 4179 (class 2604 OID 237603)
-- Name: custom_reports report_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.custom_reports ALTER COLUMN report_id SET DEFAULT nextval('public.custom_reports_report_id_seq'::regclass);


--
-- TOC entry 4181 (class 2604 OID 237604)
-- Name: customer_success_metrics metric_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.customer_success_metrics ALTER COLUMN metric_id SET DEFAULT nextval('public.customer_success_metrics_metric_id_seq'::regclass);


--
-- TOC entry 4183 (class 2604 OID 237605)
-- Name: dashboard_color_scheme scheme_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.dashboard_color_scheme ALTER COLUMN scheme_id SET DEFAULT nextval('public.dashboard_color_scheme_scheme_id_seq'::regclass);


--
-- TOC entry 4185 (class 2604 OID 237606)
-- Name: dashboard_configuration config_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.dashboard_configuration ALTER COLUMN config_id SET DEFAULT nextval('public.dashboard_configuration_config_id_seq'::regclass);


--
-- TOC entry 4146 (class 2604 OID 237607)
-- Name: department department_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.department ALTER COLUMN department_id SET DEFAULT nextval('public.department_department_id_seq'::regclass);


--
-- TOC entry 4205 (class 2604 OID 237608)
-- Name: deployment_steps step_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.deployment_steps ALTER COLUMN step_id SET DEFAULT nextval('public.deployment_steps_step_id_seq'::regclass);


--
-- TOC entry 4207 (class 2604 OID 237609)
-- Name: deployments deployment_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.deployments ALTER COLUMN deployment_id SET DEFAULT nextval('public.deployments_deployment_id_seq'::regclass);


--
-- TOC entry 4209 (class 2604 OID 237610)
-- Name: development_paths path_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.development_paths ALTER COLUMN path_id SET DEFAULT nextval('public.development_paths_path_id_seq'::regclass);


--
-- TOC entry 4210 (class 2604 OID 237611)
-- Name: employee_achievements id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.employee_achievements ALTER COLUMN id SET DEFAULT nextval('public.employee_achievements_id_seq'::regclass);


--
-- TOC entry 4212 (class 2604 OID 237612)
-- Name: employee_goals goal_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.employee_goals ALTER COLUMN goal_id SET DEFAULT nextval('public.employee_goals_goal_id_seq'::regclass);


--
-- TOC entry 4149 (class 2604 OID 237613)
-- Name: employee_manager_hierarchy employee_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.employee_manager_hierarchy ALTER COLUMN employee_id SET DEFAULT nextval('public.employee_manager_hierarchy_employee_id_seq'::regclass);


--
-- TOC entry 4214 (class 2604 OID 237614)
-- Name: employee_recognition recognition_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.employee_recognition ALTER COLUMN recognition_id SET DEFAULT nextval('public.employee_recognition_recognition_id_seq'::regclass);


--
-- TOC entry 4216 (class 2604 OID 237615)
-- Name: employee_risk_assessment assessment_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.employee_risk_assessment ALTER COLUMN assessment_id SET DEFAULT nextval('public.employee_risk_assessment_assessment_id_seq'::regclass);


--
-- TOC entry 4219 (class 2604 OID 237616)
-- Name: enablement_activities_catalog activity_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.enablement_activities_catalog ALTER COLUMN activity_id SET DEFAULT nextval('public.enablement_activities_catalog_activity_id_seq'::regclass);


--
-- TOC entry 4221 (class 2604 OID 237617)
-- Name: enablement_points_tracking tracking_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.enablement_points_tracking ALTER COLUMN tracking_id SET DEFAULT nextval('public.enablement_points_tracking_tracking_id_seq'::regclass);


--
-- TOC entry 4222 (class 2604 OID 237618)
-- Name: enablement_progress_metrics metric_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.enablement_progress_metrics ALTER COLUMN metric_id SET DEFAULT nextval('public.enablement_progress_metrics_metric_id_seq'::regclass);


--
-- TOC entry 4223 (class 2604 OID 237619)
-- Name: engagement_predictions prediction_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.engagement_predictions ALTER COLUMN prediction_id SET DEFAULT nextval('public.engagement_predictions_prediction_id_seq'::regclass);


--
-- TOC entry 4224 (class 2604 OID 237620)
-- Name: engagement_risk_factors factor_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.engagement_risk_factors ALTER COLUMN factor_id SET DEFAULT nextval('public.engagement_risk_factors_factor_id_seq'::regclass);


--
-- TOC entry 4225 (class 2604 OID 237621)
-- Name: evaluation_periods period_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.evaluation_periods ALTER COLUMN period_id SET DEFAULT nextval('public.evaluation_periods_period_id_seq'::regclass);


--
-- TOC entry 4227 (class 2604 OID 237622)
-- Name: evaluation_submissions submission_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.evaluation_submissions ALTER COLUMN submission_id SET DEFAULT nextval('public.evaluation_submissions_submission_id_seq'::regclass);


--
-- TOC entry 4233 (class 2604 OID 237623)
-- Name: feedback_actions action_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.feedback_actions ALTER COLUMN action_id SET DEFAULT nextval('public.feedback_actions_action_id_seq'::regclass);


--
-- TOC entry 4236 (class 2604 OID 237624)
-- Name: form_submission_windows window_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.form_submission_windows ALTER COLUMN window_id SET DEFAULT nextval('public.form_submission_windows_window_id_seq'::regclass);


--
-- TOC entry 4237 (class 2604 OID 237625)
-- Name: goal_achievement_metrics metric_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.goal_achievement_metrics ALTER COLUMN metric_id SET DEFAULT nextval('public.goal_achievement_metrics_metric_id_seq'::regclass);


--
-- TOC entry 4239 (class 2604 OID 237626)
-- Name: goal_dependencies dependency_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.goal_dependencies ALTER COLUMN dependency_id SET DEFAULT nextval('public.goal_dependencies_dependency_id_seq'::regclass);


--
-- TOC entry 4240 (class 2604 OID 237627)
-- Name: goal_milestones milestone_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.goal_milestones ALTER COLUMN milestone_id SET DEFAULT nextval('public.goal_milestones_milestone_id_seq'::regclass);


--
-- TOC entry 4241 (class 2604 OID 237628)
-- Name: goal_reviews review_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.goal_reviews ALTER COLUMN review_id SET DEFAULT nextval('public.goal_reviews_review_id_seq'::regclass);


--
-- TOC entry 4243 (class 2604 OID 237629)
-- Name: health_checks check_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.health_checks ALTER COLUMN check_id SET DEFAULT nextval('public.health_checks_check_id_seq'::regclass);


--
-- TOC entry 4245 (class 2604 OID 237630)
-- Name: implementation_milestones milestone_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.implementation_milestones ALTER COLUMN milestone_id SET DEFAULT nextval('public.implementation_milestones_milestone_id_seq'::regclass);


--
-- TOC entry 4246 (class 2604 OID 237631)
-- Name: improvement_initiatives initiative_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.improvement_initiatives ALTER COLUMN initiative_id SET DEFAULT nextval('public.improvement_initiatives_initiative_id_seq'::regclass);


--
-- TOC entry 4248 (class 2604 OID 237632)
-- Name: improvement_suggestions suggestion_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.improvement_suggestions ALTER COLUMN suggestion_id SET DEFAULT nextval('public.improvement_suggestions_suggestion_id_seq'::regclass);


--
-- TOC entry 4251 (class 2604 OID 237633)
-- Name: job_executions execution_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.job_executions ALTER COLUMN execution_id SET DEFAULT nextval('public.job_executions_execution_id_seq'::regclass);


--
-- TOC entry 4254 (class 2604 OID 237634)
-- Name: knowledge_transfer transfer_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.knowledge_transfer ALTER COLUMN transfer_id SET DEFAULT nextval('public.knowledge_transfer_transfer_id_seq'::regclass);


--
-- TOC entry 4256 (class 2604 OID 237635)
-- Name: kpi_calculation_rules rule_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.kpi_calculation_rules ALTER COLUMN rule_id SET DEFAULT nextval('public.kpi_calculation_rules_rule_id_seq'::regclass);


--
-- TOC entry 4258 (class 2604 OID 237636)
-- Name: kpi_relationship_metrics metric_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.kpi_relationship_metrics ALTER COLUMN metric_id SET DEFAULT nextval('public.kpi_relationship_metrics_metric_id_seq'::regclass);


--
-- TOC entry 4259 (class 2604 OID 237637)
-- Name: kpi_weight_config config_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.kpi_weight_config ALTER COLUMN config_id SET DEFAULT nextval('public.kpi_weight_config_config_id_seq'::regclass);


--
-- TOC entry 4260 (class 2604 OID 237638)
-- Name: learning_paths path_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.learning_paths ALTER COLUMN path_id SET DEFAULT nextval('public.learning_paths_path_id_seq'::regclass);


--
-- TOC entry 4262 (class 2604 OID 237639)
-- Name: login_attempts attempt_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.login_attempts ALTER COLUMN attempt_id SET DEFAULT nextval('public.login_attempts_attempt_id_seq'::regclass);


--
-- TOC entry 4264 (class 2604 OID 237640)
-- Name: maintenance_history history_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.maintenance_history ALTER COLUMN history_id SET DEFAULT nextval('public.maintenance_history_history_id_seq'::regclass);


--
-- TOC entry 4266 (class 2604 OID 237641)
-- Name: maintenance_schedule schedule_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.maintenance_schedule ALTER COLUMN schedule_id SET DEFAULT nextval('public.maintenance_schedule_schedule_id_seq'::regclass);


--
-- TOC entry 4268 (class 2604 OID 237642)
-- Name: maintenance_tasks task_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.maintenance_tasks ALTER COLUMN task_id SET DEFAULT nextval('public.maintenance_tasks_task_id_seq'::regclass);


--
-- TOC entry 4275 (class 2604 OID 237643)
-- Name: manager_engagement_metrics metric_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.manager_engagement_metrics ALTER COLUMN metric_id SET DEFAULT nextval('public.manager_engagement_metrics_metric_id_seq'::regclass);


--
-- TOC entry 4276 (class 2604 OID 237644)
-- Name: mentorship_interactions interaction_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.mentorship_interactions ALTER COLUMN interaction_id SET DEFAULT nextval('public.mentorship_interactions_interaction_id_seq'::regclass);


--
-- TOC entry 4277 (class 2604 OID 237645)
-- Name: mentorship_matching match_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.mentorship_matching ALTER COLUMN match_id SET DEFAULT nextval('public.mentorship_matching_match_id_seq'::regclass);


--
-- TOC entry 4278 (class 2604 OID 237646)
-- Name: mentorship_programs program_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.mentorship_programs ALTER COLUMN program_id SET DEFAULT nextval('public.mentorship_programs_program_id_seq'::regclass);


--
-- TOC entry 4280 (class 2604 OID 237647)
-- Name: metric_aggregations aggregation_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.metric_aggregations ALTER COLUMN aggregation_id SET DEFAULT nextval('public.metric_aggregations_aggregation_id_seq'::regclass);


--
-- TOC entry 4281 (class 2604 OID 237648)
-- Name: metric_alerts alert_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.metric_alerts ALTER COLUMN alert_id SET DEFAULT nextval('public.metric_alerts_alert_id_seq'::regclass);


--
-- TOC entry 4283 (class 2604 OID 237649)
-- Name: metric_correlations correlation_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.metric_correlations ALTER COLUMN correlation_id SET DEFAULT nextval('public.metric_correlations_correlation_id_seq'::regclass);


--
-- TOC entry 4284 (class 2604 OID 237650)
-- Name: notification_channels channel_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.notification_channels ALTER COLUMN channel_id SET DEFAULT nextval('public.notification_channels_channel_id_seq'::regclass);


--
-- TOC entry 4288 (class 2604 OID 237651)
-- Name: notification_history notification_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.notification_history ALTER COLUMN notification_id SET DEFAULT nextval('public.notification_history_notification_id_seq'::regclass);


--
-- TOC entry 4290 (class 2604 OID 237652)
-- Name: notification_log log_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.notification_log ALTER COLUMN log_id SET DEFAULT nextval('public.notification_log_log_id_seq'::regclass);


--
-- TOC entry 4292 (class 2604 OID 237653)
-- Name: notification_templates template_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.notification_templates ALTER COLUMN template_id SET DEFAULT nextval('public.notification_templates_template_id_seq'::regclass);


--
-- TOC entry 4297 (class 2604 OID 237654)
-- Name: operational_efficiency_metrics metric_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.operational_efficiency_metrics ALTER COLUMN metric_id SET DEFAULT nextval('public.operational_efficiency_metrics_metric_id_seq'::regclass);


--
-- TOC entry 4298 (class 2604 OID 237655)
-- Name: opt_in_metrics metric_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.opt_in_metrics ALTER COLUMN metric_id SET DEFAULT nextval('public.opt_in_metrics_metric_id_seq'::regclass);


--
-- TOC entry 4300 (class 2604 OID 237656)
-- Name: opt_in_tracking tracking_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.opt_in_tracking ALTER COLUMN tracking_id SET DEFAULT nextval('public.opt_in_tracking_tracking_id_seq'::regclass);


--
-- TOC entry 4301 (class 2604 OID 237657)
-- Name: optimization_recommendations recommendation_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.optimization_recommendations ALTER COLUMN recommendation_id SET DEFAULT nextval('public.optimization_recommendations_recommendation_id_seq'::regclass);


--
-- TOC entry 4304 (class 2604 OID 237658)
-- Name: participation_metrics metric_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.participation_metrics ALTER COLUMN metric_id SET DEFAULT nextval('public.participation_metrics_metric_id_seq'::regclass);


--
-- TOC entry 4305 (class 2604 OID 237659)
-- Name: performance_alerts alert_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_alerts ALTER COLUMN alert_id SET DEFAULT nextval('public.performance_alerts_alert_id_seq'::regclass);


--
-- TOC entry 4309 (class 2604 OID 237660)
-- Name: performance_baselines baseline_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_baselines ALTER COLUMN baseline_id SET DEFAULT nextval('public.performance_baselines_baseline_id_seq'::regclass);


--
-- TOC entry 4311 (class 2604 OID 237661)
-- Name: performance_delta_tracking delta_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_delta_tracking ALTER COLUMN delta_id SET DEFAULT nextval('public.performance_delta_tracking_delta_id_seq'::regclass);


--
-- TOC entry 4234 (class 2604 OID 237662)
-- Name: performance_feedback feedback_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_feedback ALTER COLUMN feedback_id SET DEFAULT nextval('public.performance_feedback_feedback_id_seq'::regclass);


--
-- TOC entry 4313 (class 2604 OID 237663)
-- Name: performance_impact impact_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_impact ALTER COLUMN impact_id SET DEFAULT nextval('public.performance_impact_impact_id_seq'::regclass);


--
-- TOC entry 4315 (class 2604 OID 237664)
-- Name: performance_improvement_metrics metric_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_improvement_metrics ALTER COLUMN metric_id SET DEFAULT nextval('public.performance_improvement_metrics_metric_id_seq'::regclass);


--
-- TOC entry 4316 (class 2604 OID 237665)
-- Name: performance_improvements improvement_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_improvements ALTER COLUMN improvement_id SET DEFAULT nextval('public.performance_improvements_improvement_id_seq'::regclass);


--
-- TOC entry 4318 (class 2604 OID 237666)
-- Name: performance_metrics metric_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_metrics ALTER COLUMN metric_id SET DEFAULT nextval('public.performance_metrics_metric_id_seq'::regclass);


--
-- TOC entry 4320 (class 2604 OID 237667)
-- Name: performance_patterns pattern_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_patterns ALTER COLUMN pattern_id SET DEFAULT nextval('public.performance_patterns_pattern_id_seq'::regclass);


--
-- TOC entry 4229 (class 2604 OID 237668)
-- Name: performance_scores score_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_scores ALTER COLUMN score_id SET DEFAULT nextval('public.performance_scores_score_id_seq'::regclass);


--
-- TOC entry 4322 (class 2604 OID 237669)
-- Name: portfolio_base score_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_base ALTER COLUMN score_id SET DEFAULT nextval('public.portfolio_base_score_id_seq'::regclass);


--
-- TOC entry 4327 (class 2604 OID 237670)
-- Name: portfolio_brownfield score_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_brownfield ALTER COLUMN score_id SET DEFAULT nextval('public.portfolio_brownfield_score_id_seq'::regclass);


--
-- TOC entry 4187 (class 2604 OID 237671)
-- Name: portfolio_cloud_services score_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_cloud_services ALTER COLUMN score_id SET DEFAULT nextval('public.portfolio_cloud_services_score_id_seq'::regclass);


--
-- TOC entry 4193 (class 2604 OID 237672)
-- Name: portfolio_design_success score_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_design_success ALTER COLUMN score_id SET DEFAULT nextval('public.portfolio_design_success_score_id_seq'::regclass);


--
-- TOC entry 4333 (class 2604 OID 237673)
-- Name: portfolio_preferred_success score_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_preferred_success ALTER COLUMN score_id SET DEFAULT nextval('public.portfolio_preferred_success_score_id_seq'::regclass);


--
-- TOC entry 4199 (class 2604 OID 237674)
-- Name: portfolio_premium_engagement score_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_premium_engagement ALTER COLUMN score_id SET DEFAULT nextval('public.portfolio_premium_engagement_score_id_seq'::regclass);


--
-- TOC entry 4339 (class 2604 OID 237675)
-- Name: portfolio_services service_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_services ALTER COLUMN service_id SET DEFAULT nextval('public.portfolio_services_service_id_seq'::regclass);


--
-- TOC entry 4340 (class 2604 OID 237676)
-- Name: portfolio_training score_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_training ALTER COLUMN score_id SET DEFAULT nextval('public.portfolio_training_score_id_seq'::regclass);


--
-- TOC entry 4343 (class 2604 OID 237677)
-- Name: program_retention_metrics metric_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.program_retention_metrics ALTER COLUMN metric_id SET DEFAULT nextval('public.program_retention_metrics_metric_id_seq'::regclass);


--
-- TOC entry 4152 (class 2604 OID 237678)
-- Name: project_assignments assignment_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.project_assignments ALTER COLUMN assignment_id SET DEFAULT nextval('public.project_assignments_assignment_id_seq'::regclass);


--
-- TOC entry 4344 (class 2604 OID 237679)
-- Name: prosper_score_metrics metric_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.prosper_score_metrics ALTER COLUMN metric_id SET DEFAULT nextval('public.prosper_score_metrics_metric_id_seq'::regclass);


--
-- TOC entry 4346 (class 2604 OID 237680)
-- Name: query_patterns pattern_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.query_patterns ALTER COLUMN pattern_id SET DEFAULT nextval('public.query_patterns_pattern_id_seq'::regclass);


--
-- TOC entry 4357 (class 2604 OID 237681)
-- Name: rate_limit_tracking tracking_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.rate_limit_tracking ALTER COLUMN tracking_id SET DEFAULT nextval('public.rate_limit_tracking_tracking_id_seq'::regclass);


--
-- TOC entry 4359 (class 2604 OID 237682)
-- Name: relationship_assessment assessment_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.relationship_assessment ALTER COLUMN assessment_id SET DEFAULT nextval('public.relationship_assessment_assessment_id_seq'::regclass);


--
-- TOC entry 4360 (class 2604 OID 237683)
-- Name: relationship_improvement_metrics metric_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.relationship_improvement_metrics ALTER COLUMN metric_id SET DEFAULT nextval('public.relationship_improvement_metrics_metric_id_seq'::regclass);


--
-- TOC entry 4361 (class 2604 OID 237684)
-- Name: report_definitions report_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.report_definitions ALTER COLUMN report_id SET DEFAULT nextval('public.report_definitions_report_id_seq'::regclass);


--
-- TOC entry 4365 (class 2604 OID 237685)
-- Name: report_executions execution_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.report_executions ALTER COLUMN execution_id SET DEFAULT nextval('public.report_executions_execution_id_seq'::regclass);


--
-- TOC entry 4368 (class 2604 OID 237686)
-- Name: report_history report_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.report_history ALTER COLUMN report_id SET DEFAULT nextval('public.report_history_report_id_seq'::regclass);


--
-- TOC entry 4371 (class 2604 OID 237687)
-- Name: report_templates template_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.report_templates ALTER COLUMN template_id SET DEFAULT nextval('public.report_templates_template_id_seq'::regclass);


--
-- TOC entry 4157 (class 2604 OID 237688)
-- Name: resource_allocation allocation_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.resource_allocation ALTER COLUMN allocation_id SET DEFAULT nextval('public.resource_allocation_allocation_id_seq'::regclass);


--
-- TOC entry 4375 (class 2604 OID 237689)
-- Name: resource_allocation_history history_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.resource_allocation_history ALTER COLUMN history_id SET DEFAULT nextval('public.resource_allocation_history_history_id_seq'::regclass);


--
-- TOC entry 4377 (class 2604 OID 237690)
-- Name: review_cycles cycle_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.review_cycles ALTER COLUMN cycle_id SET DEFAULT nextval('public.review_cycles_cycle_id_seq'::regclass);


--
-- TOC entry 4379 (class 2604 OID 237691)
-- Name: review_templates template_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.review_templates ALTER COLUMN template_id SET DEFAULT nextval('public.review_templates_template_id_seq'::regclass);


--
-- TOC entry 4382 (class 2604 OID 237692)
-- Name: satisfaction_survey_metrics metric_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.satisfaction_survey_metrics ALTER COLUMN metric_id SET DEFAULT nextval('public.satisfaction_survey_metrics_metric_id_seq'::regclass);


--
-- TOC entry 4384 (class 2604 OID 237693)
-- Name: scheduled_jobs job_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.scheduled_jobs ALTER COLUMN job_id SET DEFAULT nextval('public.scheduled_jobs_job_id_seq'::regclass);


--
-- TOC entry 4389 (class 2604 OID 237694)
-- Name: schema_versions version_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.schema_versions ALTER COLUMN version_id SET DEFAULT nextval('public.schema_versions_version_id_seq'::regclass);


--
-- TOC entry 4392 (class 2604 OID 237695)
-- Name: score_history history_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.score_history ALTER COLUMN history_id SET DEFAULT nextval('public.score_history_history_id_seq'::regclass);


--
-- TOC entry 4394 (class 2604 OID 237696)
-- Name: security_events event_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.security_events ALTER COLUMN event_id SET DEFAULT nextval('public.security_events_event_id_seq'::regclass);


--
-- TOC entry 4397 (class 2604 OID 237697)
-- Name: security_monitoring_log log_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.security_monitoring_log ALTER COLUMN log_id SET DEFAULT nextval('public.security_monitoring_log_log_id_seq'::regclass);


--
-- TOC entry 4398 (class 2604 OID 237698)
-- Name: security_notifications notification_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.security_notifications ALTER COLUMN notification_id SET DEFAULT nextval('public.security_notifications_notification_id_seq'::regclass);


--
-- TOC entry 4401 (class 2604 OID 237699)
-- Name: skill_requirements requirement_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.skill_requirements ALTER COLUMN requirement_id SET DEFAULT nextval('public.skill_requirements_requirement_id_seq'::regclass);


--
-- TOC entry 4217 (class 2604 OID 237700)
-- Name: skills_inventory skill_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.skills_inventory ALTER COLUMN skill_id SET DEFAULT nextval('public.skills_inventory_skill_id_seq'::regclass);


--
-- TOC entry 4403 (class 2604 OID 237701)
-- Name: stakeholder_relationship_history history_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.stakeholder_relationship_history ALTER COLUMN history_id SET DEFAULT nextval('public.stakeholder_relationship_history_history_id_seq'::regclass);


--
-- TOC entry 4404 (class 2604 OID 237702)
-- Name: system_configurations config_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.system_configurations ALTER COLUMN config_id SET DEFAULT nextval('public.system_configurations_config_id_seq'::regclass);


--
-- TOC entry 4407 (class 2604 OID 237703)
-- Name: system_integration_mapping mapping_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.system_integration_mapping ALTER COLUMN mapping_id SET DEFAULT nextval('public.system_integration_mapping_mapping_id_seq'::regclass);


--
-- TOC entry 4409 (class 2604 OID 237704)
-- Name: system_integrations integration_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.system_integrations ALTER COLUMN integration_id SET DEFAULT nextval('public.system_integrations_integration_id_seq'::regclass);


--
-- TOC entry 4411 (class 2604 OID 237705)
-- Name: system_metrics_history metric_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.system_metrics_history ALTER COLUMN metric_id SET DEFAULT nextval('public.system_metrics_history_metric_id_seq'::regclass);


--
-- TOC entry 4413 (class 2604 OID 237706)
-- Name: system_settings setting_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.system_settings ALTER COLUMN setting_id SET DEFAULT nextval('public.system_settings_setting_id_seq'::regclass);


--
-- TOC entry 4415 (class 2604 OID 237707)
-- Name: team_collaboration collaboration_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.team_collaboration ALTER COLUMN collaboration_id SET DEFAULT nextval('public.team_collaboration_collaboration_id_seq'::regclass);


--
-- TOC entry 4417 (class 2604 OID 237708)
-- Name: team_dynamics dynamics_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.team_dynamics ALTER COLUMN dynamics_id SET DEFAULT nextval('public.team_dynamics_dynamics_id_seq'::regclass);


--
-- TOC entry 4419 (class 2604 OID 237709)
-- Name: team_structure team_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.team_structure ALTER COLUMN team_id SET DEFAULT nextval('public.team_structure_team_id_seq'::regclass);


--
-- TOC entry 4422 (class 2604 OID 237710)
-- Name: test_cases test_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.test_cases ALTER COLUMN test_id SET DEFAULT nextval('public.test_cases_test_id_seq'::regclass);


--
-- TOC entry 4426 (class 2604 OID 237711)
-- Name: test_executions execution_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.test_executions ALTER COLUMN execution_id SET DEFAULT nextval('public.test_executions_execution_id_seq'::regclass);


--
-- TOC entry 4428 (class 2604 OID 237712)
-- Name: test_suites suite_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.test_suites ALTER COLUMN suite_id SET DEFAULT nextval('public.test_suites_suite_id_seq'::regclass);


--
-- TOC entry 4431 (class 2604 OID 237713)
-- Name: training_records training_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.training_records ALTER COLUMN training_id SET DEFAULT nextval('public.training_records_training_id_seq'::regclass);


--
-- TOC entry 4433 (class 2604 OID 237714)
-- Name: trend_analysis analysis_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.trend_analysis ALTER COLUMN analysis_id SET DEFAULT nextval('public.trend_analysis_analysis_id_seq'::regclass);


--
-- TOC entry 4436 (class 2604 OID 237715)
-- Name: users user_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.users ALTER COLUMN user_id SET DEFAULT nextval('public.users_user_id_seq'::regclass);


--
-- TOC entry 4441 (class 2604 OID 237716)
-- Name: workflow_definitions workflow_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.workflow_definitions ALTER COLUMN workflow_id SET DEFAULT nextval('public.workflow_definitions_workflow_id_seq'::regclass);


--
-- TOC entry 4452 (class 2604 OID 237717)
-- Name: workflow_executions execution_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.workflow_executions ALTER COLUMN execution_id SET DEFAULT nextval('public.workflow_executions_execution_id_seq'::regclass);


--
-- TOC entry 4444 (class 2604 OID 237718)
-- Name: workflow_instances instance_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.workflow_instances ALTER COLUMN instance_id SET DEFAULT nextval('public.workflow_instances_instance_id_seq'::regclass);


--
-- TOC entry 4449 (class 2604 OID 237719)
-- Name: workflow_step_history history_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.workflow_step_history ALTER COLUMN history_id SET DEFAULT nextval('public.workflow_step_history_history_id_seq'::regclass);


--
-- TOC entry 4455 (class 2604 OID 237720)
-- Name: workflow_step_logs log_id; Type: DEFAULT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.workflow_step_logs ALTER COLUMN log_id SET DEFAULT nextval('public.workflow_step_logs_log_id_seq'::regclass);


--
-- TOC entry 4872 (class 2606 OID 237722)
-- Name: User User_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public."User"
    ADD CONSTRAINT "User_pkey" PRIMARY KEY (id);


--
-- TOC entry 4537 (class 2606 OID 198099)
-- Name: _prisma_migrations _prisma_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public._prisma_migrations
    ADD CONSTRAINT _prisma_migrations_pkey PRIMARY KEY (id);


--
-- TOC entry 4539 (class 2606 OID 198101)
-- Name: access_control access_control_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.access_control
    ADD CONSTRAINT access_control_pkey PRIMARY KEY (access_id);


--
-- TOC entry 4541 (class 2606 OID 198103)
-- Name: achievement_badges achievement_badges_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.achievement_badges
    ADD CONSTRAINT achievement_badges_pkey PRIMARY KEY (badge_id);


--
-- TOC entry 4543 (class 2606 OID 198105)
-- Name: achievement_tracking achievement_tracking_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.achievement_tracking
    ADD CONSTRAINT achievement_tracking_pkey PRIMARY KEY (achievement_id);


--
-- TOC entry 4545 (class 2606 OID 198107)
-- Name: action_items action_items_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.action_items
    ADD CONSTRAINT action_items_pkey PRIMARY KEY (item_id);


--
-- TOC entry 4547 (class 2606 OID 198109)
-- Name: alert_configuration alert_configuration_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.alert_configuration
    ADD CONSTRAINT alert_configuration_pkey PRIMARY KEY (alert_id);


--
-- TOC entry 4550 (class 2606 OID 198111)
-- Name: alert_notifications alert_notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.alert_notifications
    ADD CONSTRAINT alert_notifications_pkey PRIMARY KEY (notification_id);


--
-- TOC entry 4552 (class 2606 OID 198113)
-- Name: analytics_dashboard analytics_dashboard_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.analytics_dashboard
    ADD CONSTRAINT analytics_dashboard_pkey PRIMARY KEY (dashboard_id);


--
-- TOC entry 4554 (class 2606 OID 198115)
-- Name: api_endpoints api_endpoints_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.api_endpoints
    ADD CONSTRAINT api_endpoints_pkey PRIMARY KEY (endpoint_id);


--
-- TOC entry 4556 (class 2606 OID 198117)
-- Name: api_keys api_keys_api_key_key; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT api_keys_api_key_key UNIQUE (api_key);


--
-- TOC entry 4558 (class 2606 OID 198119)
-- Name: api_keys api_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT api_keys_pkey PRIMARY KEY (key_id);


--
-- TOC entry 4560 (class 2606 OID 198121)
-- Name: api_requests api_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.api_requests
    ADD CONSTRAINT api_requests_pkey PRIMARY KEY (request_id);


--
-- TOC entry 4562 (class 2606 OID 198123)
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (log_id);


--
-- TOC entry 4564 (class 2606 OID 198125)
-- Name: automation_workflows automation_workflows_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.automation_workflows
    ADD CONSTRAINT automation_workflows_pkey PRIMARY KEY (workflow_id);


--
-- TOC entry 4566 (class 2606 OID 198127)
-- Name: backup_catalog backup_catalog_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.backup_catalog
    ADD CONSTRAINT backup_catalog_pkey PRIMARY KEY (backup_id);


--
-- TOC entry 4568 (class 2606 OID 198129)
-- Name: backup_configurations backup_configurations_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.backup_configurations
    ADD CONSTRAINT backup_configurations_pkey PRIMARY KEY (config_id);


--
-- TOC entry 4570 (class 2606 OID 198131)
-- Name: backup_files backup_files_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.backup_files
    ADD CONSTRAINT backup_files_pkey PRIMARY KEY (file_id);


--
-- TOC entry 4572 (class 2606 OID 198133)
-- Name: backup_history backup_history_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.backup_history
    ADD CONSTRAINT backup_history_pkey PRIMARY KEY (backup_id);


--
-- TOC entry 4574 (class 2606 OID 198135)
-- Name: backup_verification_log backup_verification_log_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.backup_verification_log
    ADD CONSTRAINT backup_verification_log_pkey PRIMARY KEY (verification_id);


--
-- TOC entry 4576 (class 2606 OID 198137)
-- Name: baseline_measurements baseline_measurements_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.baseline_measurements
    ADD CONSTRAINT baseline_measurements_pkey PRIMARY KEY (baseline_id);


--
-- TOC entry 4578 (class 2606 OID 198139)
-- Name: capacity_planning capacity_planning_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.capacity_planning
    ADD CONSTRAINT capacity_planning_pkey PRIMARY KEY (planning_id);


--
-- TOC entry 4590 (class 2606 OID 198141)
-- Name: career_development_plans career_development_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.career_development_plans
    ADD CONSTRAINT career_development_plans_pkey PRIMARY KEY (plan_id);


--
-- TOC entry 4592 (class 2606 OID 198143)
-- Name: career_progression career_progression_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.career_progression
    ADD CONSTRAINT career_progression_pkey PRIMARY KEY (progression_id);


--
-- TOC entry 4595 (class 2606 OID 198145)
-- Name: certification_registry certification_registry_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.certification_registry
    ADD CONSTRAINT certification_registry_pkey PRIMARY KEY (cert_id);


--
-- TOC entry 4597 (class 2606 OID 198147)
-- Name: communication_log communication_log_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.communication_log
    ADD CONSTRAINT communication_log_pkey PRIMARY KEY (log_id);


--
-- TOC entry 4599 (class 2606 OID 198149)
-- Name: communication_metrics communication_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.communication_metrics
    ADD CONSTRAINT communication_metrics_pkey PRIMARY KEY (metric_id);


--
-- TOC entry 4601 (class 2606 OID 198151)
-- Name: communication_templates communication_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.communication_templates
    ADD CONSTRAINT communication_templates_pkey PRIMARY KEY (template_id);


--
-- TOC entry 4603 (class 2606 OID 198153)
-- Name: competency_framework competency_framework_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.competency_framework
    ADD CONSTRAINT competency_framework_pkey PRIMARY KEY (framework_id);


--
-- TOC entry 4605 (class 2606 OID 198155)
-- Name: configuration_history configuration_history_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.configuration_history
    ADD CONSTRAINT configuration_history_pkey PRIMARY KEY (history_id);


--
-- TOC entry 4607 (class 2606 OID 198157)
-- Name: custom_reports custom_reports_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.custom_reports
    ADD CONSTRAINT custom_reports_pkey PRIMARY KEY (report_id);


--
-- TOC entry 4609 (class 2606 OID 198159)
-- Name: customer_success_metrics customer_success_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.customer_success_metrics
    ADD CONSTRAINT customer_success_metrics_pkey PRIMARY KEY (metric_id);


--
-- TOC entry 4611 (class 2606 OID 198161)
-- Name: dashboard_color_scheme dashboard_color_scheme_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.dashboard_color_scheme
    ADD CONSTRAINT dashboard_color_scheme_pkey PRIMARY KEY (scheme_id);


--
-- TOC entry 4613 (class 2606 OID 198163)
-- Name: dashboard_configuration dashboard_configuration_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.dashboard_configuration
    ADD CONSTRAINT dashboard_configuration_pkey PRIMARY KEY (config_id);


--
-- TOC entry 4580 (class 2606 OID 198165)
-- Name: department department_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.department
    ADD CONSTRAINT department_pkey PRIMARY KEY (department_id);


--
-- TOC entry 4627 (class 2606 OID 198167)
-- Name: deployment_steps deployment_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.deployment_steps
    ADD CONSTRAINT deployment_steps_pkey PRIMARY KEY (step_id);


--
-- TOC entry 4629 (class 2606 OID 198169)
-- Name: deployments deployments_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.deployments
    ADD CONSTRAINT deployments_pkey PRIMARY KEY (deployment_id);


--
-- TOC entry 4631 (class 2606 OID 198171)
-- Name: development_paths development_paths_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.development_paths
    ADD CONSTRAINT development_paths_pkey PRIMARY KEY (path_id);


--
-- TOC entry 4634 (class 2606 OID 198173)
-- Name: employee_achievements employee_achievements_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.employee_achievements
    ADD CONSTRAINT employee_achievements_pkey PRIMARY KEY (id);


--
-- TOC entry 4636 (class 2606 OID 198175)
-- Name: employee_goals employee_goals_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.employee_goals
    ADD CONSTRAINT employee_goals_pkey PRIMARY KEY (goal_id);


--
-- TOC entry 4582 (class 2606 OID 198177)
-- Name: employee_manager_hierarchy employee_manager_hierarchy_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.employee_manager_hierarchy
    ADD CONSTRAINT employee_manager_hierarchy_pkey PRIMARY KEY (employee_id);


--
-- TOC entry 4638 (class 2606 OID 198179)
-- Name: employee_recognition employee_recognition_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.employee_recognition
    ADD CONSTRAINT employee_recognition_pkey PRIMARY KEY (recognition_id);


--
-- TOC entry 4640 (class 2606 OID 198181)
-- Name: employee_risk_assessment employee_risk_assessment_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.employee_risk_assessment
    ADD CONSTRAINT employee_risk_assessment_pkey PRIMARY KEY (assessment_id);


--
-- TOC entry 4644 (class 2606 OID 198183)
-- Name: enablement_activities_catalog enablement_activities_catalog_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.enablement_activities_catalog
    ADD CONSTRAINT enablement_activities_catalog_pkey PRIMARY KEY (activity_id);


--
-- TOC entry 4646 (class 2606 OID 198185)
-- Name: enablement_points_tracking enablement_points_tracking_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.enablement_points_tracking
    ADD CONSTRAINT enablement_points_tracking_pkey PRIMARY KEY (tracking_id);


--
-- TOC entry 4648 (class 2606 OID 198187)
-- Name: enablement_progress_metrics enablement_progress_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.enablement_progress_metrics
    ADD CONSTRAINT enablement_progress_metrics_pkey PRIMARY KEY (metric_id);


--
-- TOC entry 4650 (class 2606 OID 198189)
-- Name: engagement_predictions engagement_predictions_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.engagement_predictions
    ADD CONSTRAINT engagement_predictions_pkey PRIMARY KEY (prediction_id);


--
-- TOC entry 4652 (class 2606 OID 198191)
-- Name: engagement_risk_factors engagement_risk_factors_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.engagement_risk_factors
    ADD CONSTRAINT engagement_risk_factors_pkey PRIMARY KEY (factor_id);


--
-- TOC entry 4654 (class 2606 OID 198193)
-- Name: evaluation_periods evaluation_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.evaluation_periods
    ADD CONSTRAINT evaluation_periods_pkey PRIMARY KEY (period_id);


--
-- TOC entry 4656 (class 2606 OID 198195)
-- Name: evaluation_submissions evaluation_submissions_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.evaluation_submissions
    ADD CONSTRAINT evaluation_submissions_pkey PRIMARY KEY (submission_id);


--
-- TOC entry 4661 (class 2606 OID 198197)
-- Name: feedback_actions feedback_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.feedback_actions
    ADD CONSTRAINT feedback_actions_pkey PRIMARY KEY (action_id);


--
-- TOC entry 4665 (class 2606 OID 198199)
-- Name: form_submission_windows form_submission_windows_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.form_submission_windows
    ADD CONSTRAINT form_submission_windows_pkey PRIMARY KEY (window_id);


--
-- TOC entry 4667 (class 2606 OID 198201)
-- Name: goal_achievement_metrics goal_achievement_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.goal_achievement_metrics
    ADD CONSTRAINT goal_achievement_metrics_pkey PRIMARY KEY (metric_id);


--
-- TOC entry 4669 (class 2606 OID 198203)
-- Name: goal_dependencies goal_dependencies_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.goal_dependencies
    ADD CONSTRAINT goal_dependencies_pkey PRIMARY KEY (dependency_id);


--
-- TOC entry 4671 (class 2606 OID 198205)
-- Name: goal_milestones goal_milestones_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.goal_milestones
    ADD CONSTRAINT goal_milestones_pkey PRIMARY KEY (milestone_id);


--
-- TOC entry 4673 (class 2606 OID 198207)
-- Name: goal_reviews goal_reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.goal_reviews
    ADD CONSTRAINT goal_reviews_pkey PRIMARY KEY (review_id);


--
-- TOC entry 4675 (class 2606 OID 198209)
-- Name: health_checks health_checks_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.health_checks
    ADD CONSTRAINT health_checks_pkey PRIMARY KEY (check_id);


--
-- TOC entry 4677 (class 2606 OID 198211)
-- Name: implementation_milestones implementation_milestones_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.implementation_milestones
    ADD CONSTRAINT implementation_milestones_pkey PRIMARY KEY (milestone_id);


--
-- TOC entry 4679 (class 2606 OID 198213)
-- Name: improvement_initiatives improvement_initiatives_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.improvement_initiatives
    ADD CONSTRAINT improvement_initiatives_pkey PRIMARY KEY (initiative_id);


--
-- TOC entry 4681 (class 2606 OID 198215)
-- Name: improvement_suggestions improvement_suggestions_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.improvement_suggestions
    ADD CONSTRAINT improvement_suggestions_pkey PRIMARY KEY (suggestion_id);


--
-- TOC entry 4683 (class 2606 OID 198217)
-- Name: job_executions job_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.job_executions
    ADD CONSTRAINT job_executions_pkey PRIMARY KEY (execution_id);


--
-- TOC entry 4685 (class 2606 OID 198219)
-- Name: knowledge_transfer knowledge_transfer_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.knowledge_transfer
    ADD CONSTRAINT knowledge_transfer_pkey PRIMARY KEY (transfer_id);


--
-- TOC entry 4687 (class 2606 OID 198221)
-- Name: kpi_calculation_rules kpi_calculation_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.kpi_calculation_rules
    ADD CONSTRAINT kpi_calculation_rules_pkey PRIMARY KEY (rule_id);


--
-- TOC entry 4689 (class 2606 OID 198223)
-- Name: kpi_relationship_metrics kpi_relationship_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.kpi_relationship_metrics
    ADD CONSTRAINT kpi_relationship_metrics_pkey PRIMARY KEY (metric_id);


--
-- TOC entry 4691 (class 2606 OID 198225)
-- Name: kpi_weight_config kpi_weight_config_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.kpi_weight_config
    ADD CONSTRAINT kpi_weight_config_pkey PRIMARY KEY (config_id);


--
-- TOC entry 4693 (class 2606 OID 198227)
-- Name: learning_paths learning_paths_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.learning_paths
    ADD CONSTRAINT learning_paths_pkey PRIMARY KEY (path_id);


--
-- TOC entry 4695 (class 2606 OID 198229)
-- Name: login_attempts login_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.login_attempts
    ADD CONSTRAINT login_attempts_pkey PRIMARY KEY (attempt_id);


--
-- TOC entry 4697 (class 2606 OID 198231)
-- Name: maintenance_history maintenance_history_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.maintenance_history
    ADD CONSTRAINT maintenance_history_pkey PRIMARY KEY (history_id);


--
-- TOC entry 4699 (class 2606 OID 198233)
-- Name: maintenance_schedule maintenance_schedule_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.maintenance_schedule
    ADD CONSTRAINT maintenance_schedule_pkey PRIMARY KEY (schedule_id);


--
-- TOC entry 4701 (class 2606 OID 198235)
-- Name: maintenance_tasks maintenance_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.maintenance_tasks
    ADD CONSTRAINT maintenance_tasks_pkey PRIMARY KEY (task_id);


--
-- TOC entry 4706 (class 2606 OID 198237)
-- Name: manager_engagement_metrics manager_engagement_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.manager_engagement_metrics
    ADD CONSTRAINT manager_engagement_metrics_pkey PRIMARY KEY (metric_id);


--
-- TOC entry 4704 (class 2606 OID 198239)
-- Name: manager manager_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.manager
    ADD CONSTRAINT manager_pkey PRIMARY KEY (manager_id);


--
-- TOC entry 4708 (class 2606 OID 198241)
-- Name: mentorship_interactions mentorship_interactions_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.mentorship_interactions
    ADD CONSTRAINT mentorship_interactions_pkey PRIMARY KEY (interaction_id);


--
-- TOC entry 4710 (class 2606 OID 198243)
-- Name: mentorship_matching mentorship_matching_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.mentorship_matching
    ADD CONSTRAINT mentorship_matching_pkey PRIMARY KEY (match_id);


--
-- TOC entry 4712 (class 2606 OID 198245)
-- Name: mentorship_programs mentorship_programs_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.mentorship_programs
    ADD CONSTRAINT mentorship_programs_pkey PRIMARY KEY (program_id);


--
-- TOC entry 4714 (class 2606 OID 198247)
-- Name: metric_aggregations metric_aggregations_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.metric_aggregations
    ADD CONSTRAINT metric_aggregations_pkey PRIMARY KEY (aggregation_id);


--
-- TOC entry 4716 (class 2606 OID 198249)
-- Name: metric_alerts metric_alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.metric_alerts
    ADD CONSTRAINT metric_alerts_pkey PRIMARY KEY (alert_id);


--
-- TOC entry 4718 (class 2606 OID 198251)
-- Name: metric_correlations metric_correlations_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.metric_correlations
    ADD CONSTRAINT metric_correlations_pkey PRIMARY KEY (correlation_id);


--
-- TOC entry 4720 (class 2606 OID 198253)
-- Name: notification_channels notification_channels_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.notification_channels
    ADD CONSTRAINT notification_channels_pkey PRIMARY KEY (channel_id);


--
-- TOC entry 4722 (class 2606 OID 198255)
-- Name: notification_history notification_history_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.notification_history
    ADD CONSTRAINT notification_history_pkey PRIMARY KEY (notification_id);


--
-- TOC entry 4724 (class 2606 OID 198257)
-- Name: notification_log notification_log_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.notification_log
    ADD CONSTRAINT notification_log_pkey PRIMARY KEY (log_id);


--
-- TOC entry 4726 (class 2606 OID 198259)
-- Name: notification_templates notification_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.notification_templates
    ADD CONSTRAINT notification_templates_pkey PRIMARY KEY (template_id);


--
-- TOC entry 4728 (class 2606 OID 198261)
-- Name: operational_efficiency_metrics operational_efficiency_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.operational_efficiency_metrics
    ADD CONSTRAINT operational_efficiency_metrics_pkey PRIMARY KEY (metric_id);


--
-- TOC entry 4730 (class 2606 OID 198263)
-- Name: opt_in_metrics opt_in_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.opt_in_metrics
    ADD CONSTRAINT opt_in_metrics_pkey PRIMARY KEY (metric_id);


--
-- TOC entry 4732 (class 2606 OID 198265)
-- Name: opt_in_tracking opt_in_tracking_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.opt_in_tracking
    ADD CONSTRAINT opt_in_tracking_pkey PRIMARY KEY (tracking_id);


--
-- TOC entry 4734 (class 2606 OID 198267)
-- Name: optimization_recommendations optimization_recommendations_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.optimization_recommendations
    ADD CONSTRAINT optimization_recommendations_pkey PRIMARY KEY (recommendation_id);


--
-- TOC entry 4736 (class 2606 OID 198269)
-- Name: participation_metrics participation_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.participation_metrics
    ADD CONSTRAINT participation_metrics_pkey PRIMARY KEY (metric_id);


--
-- TOC entry 4738 (class 2606 OID 198271)
-- Name: performance_alerts performance_alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_alerts
    ADD CONSTRAINT performance_alerts_pkey PRIMARY KEY (alert_id);


--
-- TOC entry 4740 (class 2606 OID 198273)
-- Name: performance_baselines performance_baselines_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_baselines
    ADD CONSTRAINT performance_baselines_pkey PRIMARY KEY (baseline_id);


--
-- TOC entry 4742 (class 2606 OID 198275)
-- Name: performance_delta_tracking performance_delta_tracking_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_delta_tracking
    ADD CONSTRAINT performance_delta_tracking_pkey PRIMARY KEY (delta_id);


--
-- TOC entry 4663 (class 2606 OID 198277)
-- Name: performance_feedback performance_feedback_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_feedback
    ADD CONSTRAINT performance_feedback_pkey PRIMARY KEY (feedback_id);


--
-- TOC entry 4744 (class 2606 OID 198279)
-- Name: performance_impact performance_impact_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_impact
    ADD CONSTRAINT performance_impact_pkey PRIMARY KEY (impact_id);


--
-- TOC entry 4746 (class 2606 OID 198281)
-- Name: performance_improvement_metrics performance_improvement_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_improvement_metrics
    ADD CONSTRAINT performance_improvement_metrics_pkey PRIMARY KEY (metric_id);


--
-- TOC entry 4748 (class 2606 OID 198283)
-- Name: performance_improvements performance_improvements_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_improvements
    ADD CONSTRAINT performance_improvements_pkey PRIMARY KEY (improvement_id);


--
-- TOC entry 4750 (class 2606 OID 198285)
-- Name: performance_metrics performance_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_metrics
    ADD CONSTRAINT performance_metrics_pkey PRIMARY KEY (metric_id);


--
-- TOC entry 4752 (class 2606 OID 198287)
-- Name: performance_patterns performance_patterns_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_patterns
    ADD CONSTRAINT performance_patterns_pkey PRIMARY KEY (pattern_id);


--
-- TOC entry 4658 (class 2606 OID 198289)
-- Name: performance_scores performance_scores_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_scores
    ADD CONSTRAINT performance_scores_pkey PRIMARY KEY (score_id);


--
-- TOC entry 4757 (class 2606 OID 198291)
-- Name: portfolio_base portfolio_base_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_base
    ADD CONSTRAINT portfolio_base_pkey PRIMARY KEY (score_id);


--
-- TOC entry 4761 (class 2606 OID 198293)
-- Name: portfolio_brownfield portfolio_brownfield_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_brownfield
    ADD CONSTRAINT portfolio_brownfield_pkey PRIMARY KEY (score_id);


--
-- TOC entry 4617 (class 2606 OID 198295)
-- Name: portfolio_cloud_services portfolio_cloud_services_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_cloud_services
    ADD CONSTRAINT portfolio_cloud_services_pkey PRIMARY KEY (score_id);


--
-- TOC entry 4621 (class 2606 OID 198297)
-- Name: portfolio_design_success portfolio_design_success_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_design_success
    ADD CONSTRAINT portfolio_design_success_pkey PRIMARY KEY (score_id);


--
-- TOC entry 4765 (class 2606 OID 198299)
-- Name: portfolio_preferred_success portfolio_preferred_success_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_preferred_success
    ADD CONSTRAINT portfolio_preferred_success_pkey PRIMARY KEY (score_id);


--
-- TOC entry 4625 (class 2606 OID 198301)
-- Name: portfolio_premium_engagement portfolio_premium_engagement_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_premium_engagement
    ADD CONSTRAINT portfolio_premium_engagement_pkey PRIMARY KEY (score_id);


--
-- TOC entry 4767 (class 2606 OID 198303)
-- Name: portfolio_services portfolio_services_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_services
    ADD CONSTRAINT portfolio_services_pkey PRIMARY KEY (service_id);


--
-- TOC entry 4769 (class 2606 OID 198305)
-- Name: portfolio_services portfolio_services_service_name_key; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_services
    ADD CONSTRAINT portfolio_services_service_name_key UNIQUE (service_name);


--
-- TOC entry 4772 (class 2606 OID 198307)
-- Name: portfolio_training portfolio_training_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_training
    ADD CONSTRAINT portfolio_training_pkey PRIMARY KEY (score_id);


--
-- TOC entry 4774 (class 2606 OID 198309)
-- Name: program_retention_metrics program_retention_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.program_retention_metrics
    ADD CONSTRAINT program_retention_metrics_pkey PRIMARY KEY (metric_id);


--
-- TOC entry 4586 (class 2606 OID 198311)
-- Name: project_assignments project_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.project_assignments
    ADD CONSTRAINT project_assignments_pkey PRIMARY KEY (assignment_id);


--
-- TOC entry 4776 (class 2606 OID 198313)
-- Name: prosper_score_metrics prosper_score_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.prosper_score_metrics
    ADD CONSTRAINT prosper_score_metrics_pkey PRIMARY KEY (metric_id);


--
-- TOC entry 4778 (class 2606 OID 198315)
-- Name: query_patterns query_patterns_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.query_patterns
    ADD CONSTRAINT query_patterns_pkey PRIMARY KEY (pattern_id);


--
-- TOC entry 4781 (class 2606 OID 198317)
-- Name: rate_limit_tracking rate_limit_identifier_idx; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.rate_limit_tracking
    ADD CONSTRAINT rate_limit_identifier_idx UNIQUE (identifier, action_type, "timestamp");


--
-- TOC entry 4783 (class 2606 OID 198319)
-- Name: rate_limit_tracking rate_limit_tracking_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.rate_limit_tracking
    ADD CONSTRAINT rate_limit_tracking_pkey PRIMARY KEY (tracking_id);


--
-- TOC entry 4785 (class 2606 OID 198321)
-- Name: relationship_assessment relationship_assessment_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.relationship_assessment
    ADD CONSTRAINT relationship_assessment_pkey PRIMARY KEY (assessment_id);


--
-- TOC entry 4787 (class 2606 OID 198323)
-- Name: relationship_improvement_metrics relationship_improvement_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.relationship_improvement_metrics
    ADD CONSTRAINT relationship_improvement_metrics_pkey PRIMARY KEY (metric_id);


--
-- TOC entry 4789 (class 2606 OID 198325)
-- Name: report_definitions report_definitions_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.report_definitions
    ADD CONSTRAINT report_definitions_pkey PRIMARY KEY (report_id);


--
-- TOC entry 4791 (class 2606 OID 198327)
-- Name: report_executions report_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.report_executions
    ADD CONSTRAINT report_executions_pkey PRIMARY KEY (execution_id);


--
-- TOC entry 4793 (class 2606 OID 198329)
-- Name: report_history report_history_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.report_history
    ADD CONSTRAINT report_history_pkey PRIMARY KEY (report_id);


--
-- TOC entry 4795 (class 2606 OID 198331)
-- Name: report_templates report_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.report_templates
    ADD CONSTRAINT report_templates_pkey PRIMARY KEY (template_id);


--
-- TOC entry 4797 (class 2606 OID 198333)
-- Name: resource_allocation_history resource_allocation_history_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.resource_allocation_history
    ADD CONSTRAINT resource_allocation_history_pkey PRIMARY KEY (history_id);


--
-- TOC entry 4588 (class 2606 OID 198335)
-- Name: resource_allocation resource_allocation_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.resource_allocation
    ADD CONSTRAINT resource_allocation_pkey PRIMARY KEY (allocation_id);


--
-- TOC entry 4799 (class 2606 OID 198337)
-- Name: review_cycles review_cycles_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.review_cycles
    ADD CONSTRAINT review_cycles_pkey PRIMARY KEY (cycle_id);


--
-- TOC entry 4801 (class 2606 OID 198339)
-- Name: review_templates review_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.review_templates
    ADD CONSTRAINT review_templates_pkey PRIMARY KEY (template_id);


--
-- TOC entry 4803 (class 2606 OID 198341)
-- Name: satisfaction_survey_metrics satisfaction_survey_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.satisfaction_survey_metrics
    ADD CONSTRAINT satisfaction_survey_metrics_pkey PRIMARY KEY (metric_id);


--
-- TOC entry 4805 (class 2606 OID 198343)
-- Name: scheduled_jobs scheduled_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.scheduled_jobs
    ADD CONSTRAINT scheduled_jobs_pkey PRIMARY KEY (job_id);


--
-- TOC entry 4807 (class 2606 OID 198345)
-- Name: schema_versions schema_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.schema_versions
    ADD CONSTRAINT schema_versions_pkey PRIMARY KEY (version_id);


--
-- TOC entry 4809 (class 2606 OID 198347)
-- Name: score_history score_history_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.score_history
    ADD CONSTRAINT score_history_pkey PRIMARY KEY (history_id);


--
-- TOC entry 4814 (class 2606 OID 198349)
-- Name: security_events security_events_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.security_events
    ADD CONSTRAINT security_events_pkey PRIMARY KEY (event_id);


--
-- TOC entry 4816 (class 2606 OID 198351)
-- Name: security_monitoring_log security_monitoring_log_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.security_monitoring_log
    ADD CONSTRAINT security_monitoring_log_pkey PRIMARY KEY (log_id);


--
-- TOC entry 4819 (class 2606 OID 198353)
-- Name: security_notifications security_notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.security_notifications
    ADD CONSTRAINT security_notifications_pkey PRIMARY KEY (notification_id);


--
-- TOC entry 4821 (class 2606 OID 198355)
-- Name: skill_requirements skill_requirements_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.skill_requirements
    ADD CONSTRAINT skill_requirements_pkey PRIMARY KEY (requirement_id);


--
-- TOC entry 4642 (class 2606 OID 198357)
-- Name: skills_inventory skills_inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.skills_inventory
    ADD CONSTRAINT skills_inventory_pkey PRIMARY KEY (skill_id);


--
-- TOC entry 4823 (class 2606 OID 198359)
-- Name: stakeholder_relationship_history stakeholder_relationship_history_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.stakeholder_relationship_history
    ADD CONSTRAINT stakeholder_relationship_history_pkey PRIMARY KEY (history_id);


--
-- TOC entry 4825 (class 2606 OID 198361)
-- Name: system_configurations system_configurations_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.system_configurations
    ADD CONSTRAINT system_configurations_pkey PRIMARY KEY (config_id);


--
-- TOC entry 4827 (class 2606 OID 198363)
-- Name: system_integration_mapping system_integration_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.system_integration_mapping
    ADD CONSTRAINT system_integration_mapping_pkey PRIMARY KEY (mapping_id);


--
-- TOC entry 4829 (class 2606 OID 198365)
-- Name: system_integrations system_integrations_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.system_integrations
    ADD CONSTRAINT system_integrations_pkey PRIMARY KEY (integration_id);


--
-- TOC entry 4831 (class 2606 OID 198367)
-- Name: system_metrics_history system_metrics_history_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.system_metrics_history
    ADD CONSTRAINT system_metrics_history_pkey PRIMARY KEY (metric_id);


--
-- TOC entry 4833 (class 2606 OID 198369)
-- Name: system_settings system_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.system_settings
    ADD CONSTRAINT system_settings_pkey PRIMARY KEY (setting_id);


--
-- TOC entry 4835 (class 2606 OID 198371)
-- Name: team_collaboration team_collaboration_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.team_collaboration
    ADD CONSTRAINT team_collaboration_pkey PRIMARY KEY (collaboration_id);


--
-- TOC entry 4837 (class 2606 OID 198373)
-- Name: team_dynamics team_dynamics_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.team_dynamics
    ADD CONSTRAINT team_dynamics_pkey PRIMARY KEY (dynamics_id);


--
-- TOC entry 4840 (class 2606 OID 198375)
-- Name: team_structure team_structure_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.team_structure
    ADD CONSTRAINT team_structure_pkey PRIMARY KEY (team_id);


--
-- TOC entry 4843 (class 2606 OID 198377)
-- Name: test_cases test_cases_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.test_cases
    ADD CONSTRAINT test_cases_pkey PRIMARY KEY (test_id);


--
-- TOC entry 4845 (class 2606 OID 198379)
-- Name: test_executions test_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.test_executions
    ADD CONSTRAINT test_executions_pkey PRIMARY KEY (execution_id);


--
-- TOC entry 4847 (class 2606 OID 198381)
-- Name: test_suites test_suites_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.test_suites
    ADD CONSTRAINT test_suites_pkey PRIMARY KEY (suite_id);


--
-- TOC entry 4849 (class 2606 OID 198383)
-- Name: training_records training_records_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.training_records
    ADD CONSTRAINT training_records_pkey PRIMARY KEY (training_id);


--
-- TOC entry 4851 (class 2606 OID 198385)
-- Name: trend_analysis trend_analysis_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.trend_analysis
    ADD CONSTRAINT trend_analysis_pkey PRIMARY KEY (analysis_id);


--
-- TOC entry 4853 (class 2606 OID 198387)
-- Name: user_sessions user_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_pkey PRIMARY KEY (session_id);


--
-- TOC entry 4855 (class 2606 OID 198389)
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- TOC entry 4857 (class 2606 OID 198391)
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- TOC entry 4859 (class 2606 OID 198393)
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- TOC entry 4861 (class 2606 OID 198395)
-- Name: workflow_definitions workflow_definitions_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.workflow_definitions
    ADD CONSTRAINT workflow_definitions_pkey PRIMARY KEY (workflow_id);


--
-- TOC entry 4867 (class 2606 OID 198397)
-- Name: workflow_executions workflow_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.workflow_executions
    ADD CONSTRAINT workflow_executions_pkey PRIMARY KEY (execution_id);


--
-- TOC entry 4863 (class 2606 OID 198399)
-- Name: workflow_instances workflow_instances_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.workflow_instances
    ADD CONSTRAINT workflow_instances_pkey PRIMARY KEY (instance_id);


--
-- TOC entry 4865 (class 2606 OID 198401)
-- Name: workflow_step_history workflow_step_history_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.workflow_step_history
    ADD CONSTRAINT workflow_step_history_pkey PRIMARY KEY (history_id);


--
-- TOC entry 4869 (class 2606 OID 198403)
-- Name: workflow_step_logs workflow_step_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.workflow_step_logs
    ADD CONSTRAINT workflow_step_logs_pkey PRIMARY KEY (log_id);


--
-- TOC entry 4870 (class 1259 OID 237723)
-- Name: User_email_key; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE UNIQUE INDEX "User_email_key" ON public."User" USING btree (email);


--
-- TOC entry 4548 (class 1259 OID 198405)
-- Name: idx_alert_config_type; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_alert_config_type ON public.alert_configuration USING btree (alert_type);


--
-- TOC entry 4593 (class 1259 OID 198406)
-- Name: idx_career_progression_employee; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_career_progression_employee ON public.career_progression USING btree (employee_id);


--
-- TOC entry 4632 (class 1259 OID 198407)
-- Name: idx_development_paths_category; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_development_paths_category ON public.development_paths USING btree (category);


--
-- TOC entry 4659 (class 1259 OID 198408)
-- Name: idx_exec_summary_dept; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_exec_summary_dept ON public.executive_prosper_summary USING btree (department_name);


--
-- TOC entry 4702 (class 1259 OID 198409)
-- Name: idx_manager_dept; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_manager_dept ON public.manager USING btree (department_id);


--
-- TOC entry 4758 (class 1259 OID 198410)
-- Name: idx_portfolio_brownfield_employee_date; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_portfolio_brownfield_employee_date ON public.portfolio_brownfield USING btree (employee_id, evaluation_date);


--
-- TOC entry 4759 (class 1259 OID 198411)
-- Name: idx_portfolio_brownfield_scores; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_portfolio_brownfield_scores ON public.portfolio_brownfield USING btree (self_score, manager_score, challenge_score);


--
-- TOC entry 4614 (class 1259 OID 198412)
-- Name: idx_portfolio_cloud_services_employee_date; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_portfolio_cloud_services_employee_date ON public.portfolio_cloud_services USING btree (employee_id, evaluation_date);


--
-- TOC entry 4615 (class 1259 OID 198413)
-- Name: idx_portfolio_cloud_services_scores; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_portfolio_cloud_services_scores ON public.portfolio_cloud_services USING btree (self_score, manager_score, challenge_score);


--
-- TOC entry 4753 (class 1259 OID 198414)
-- Name: idx_portfolio_dates; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_portfolio_dates ON public.portfolio_base USING btree (evaluation_date);


--
-- TOC entry 4618 (class 1259 OID 198415)
-- Name: idx_portfolio_design_success_employee_date; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_portfolio_design_success_employee_date ON public.portfolio_design_success USING btree (employee_id, evaluation_date);


--
-- TOC entry 4619 (class 1259 OID 198416)
-- Name: idx_portfolio_design_success_scores; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_portfolio_design_success_scores ON public.portfolio_design_success USING btree (self_score, manager_score, challenge_score);


--
-- TOC entry 4754 (class 1259 OID 198417)
-- Name: idx_portfolio_employee; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_portfolio_employee ON public.portfolio_base USING btree (employee_id);


--
-- TOC entry 4762 (class 1259 OID 198418)
-- Name: idx_portfolio_preferred_success_employee_date; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_portfolio_preferred_success_employee_date ON public.portfolio_preferred_success USING btree (employee_id, evaluation_date);


--
-- TOC entry 4763 (class 1259 OID 198419)
-- Name: idx_portfolio_preferred_success_scores; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_portfolio_preferred_success_scores ON public.portfolio_preferred_success USING btree (self_score, manager_score, challenge_score);


--
-- TOC entry 4622 (class 1259 OID 198420)
-- Name: idx_portfolio_premium_engagement_employee_date; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_portfolio_premium_engagement_employee_date ON public.portfolio_premium_engagement USING btree (employee_id, evaluation_date);


--
-- TOC entry 4623 (class 1259 OID 198421)
-- Name: idx_portfolio_premium_engagement_scores; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_portfolio_premium_engagement_scores ON public.portfolio_premium_engagement USING btree (self_score, manager_score, challenge_score);


--
-- TOC entry 4755 (class 1259 OID 198422)
-- Name: idx_portfolio_scores; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_portfolio_scores ON public.portfolio_base USING btree (average_score);


--
-- TOC entry 4770 (class 1259 OID 198423)
-- Name: idx_portfolio_training_employee; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_portfolio_training_employee ON public.portfolio_training USING btree (employee_id);


--
-- TOC entry 4583 (class 1259 OID 198424)
-- Name: idx_project_assignment_dates; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_project_assignment_dates ON public.project_assignments USING btree (start_date, end_date);


--
-- TOC entry 4584 (class 1259 OID 198425)
-- Name: idx_project_assignment_status; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_project_assignment_status ON public.project_assignments USING btree (assignment_status, billable);


--
-- TOC entry 4779 (class 1259 OID 198426)
-- Name: idx_rate_limit_lookup; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_rate_limit_lookup ON public.rate_limit_tracking USING btree (identifier, action_type, "timestamp");


--
-- TOC entry 4810 (class 1259 OID 198427)
-- Name: idx_security_events_ip; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_security_events_ip ON public.security_events USING btree (ip_address) WHERE (ip_address IS NOT NULL);


--
-- TOC entry 4811 (class 1259 OID 198428)
-- Name: idx_security_events_type_time; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_security_events_type_time ON public.security_events USING btree (event_type, event_time);


--
-- TOC entry 4812 (class 1259 OID 198429)
-- Name: idx_security_events_user; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_security_events_user ON public.security_events USING btree (user_id) WHERE (user_id IS NOT NULL);


--
-- TOC entry 4817 (class 1259 OID 198430)
-- Name: idx_security_notifications_status_severity; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_security_notifications_status_severity ON public.security_notifications USING btree (notification_status, severity, created_at);


--
-- TOC entry 4838 (class 1259 OID 198431)
-- Name: idx_team_hierarchy; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE INDEX idx_team_hierarchy ON public.team_structure USING btree (parent_team_id, team_id);


--
-- TOC entry 4841 (class 1259 OID 198432)
-- Name: team_performance_summary_idx; Type: INDEX; Schema: public; Owner: prosper-dev_owner
--

CREATE UNIQUE INDEX team_performance_summary_idx ON public.team_performance_summary USING btree (team_id);


--
-- TOC entry 4990 (class 2620 OID 198433)
-- Name: resource_allocation allocation_history_trigger; Type: TRIGGER; Schema: public; Owner: prosper-dev_owner
--

CREATE TRIGGER allocation_history_trigger AFTER UPDATE ON public.resource_allocation FOR EACH ROW EXECUTE FUNCTION public.track_allocation_changes();


--
-- TOC entry 4995 (class 2620 OID 198434)
-- Name: system_configurations configuration_audit_trigger; Type: TRIGGER; Schema: public; Owner: prosper-dev_owner
--

CREATE TRIGGER configuration_audit_trigger AFTER UPDATE ON public.system_configurations FOR EACH ROW EXECUTE FUNCTION public.audit_configuration_changes();


--
-- TOC entry 4992 (class 2620 OID 198435)
-- Name: performance_scores performance_scores_audit; Type: TRIGGER; Schema: public; Owner: prosper-dev_owner
--

CREATE TRIGGER performance_scores_audit AFTER INSERT OR DELETE OR UPDATE ON public.performance_scores FOR EACH ROW EXECUTE FUNCTION public.create_audit_log();


--
-- TOC entry 4994 (class 2620 OID 198436)
-- Name: security_events security_event_monitor; Type: TRIGGER; Schema: public; Owner: prosper-dev_owner
--

CREATE TRIGGER security_event_monitor AFTER INSERT ON public.security_events FOR EACH ROW EXECUTE FUNCTION public.security_event_monitor_trigger();


--
-- TOC entry 4991 (class 2620 OID 198437)
-- Name: skills_inventory skills_inventory_audit; Type: TRIGGER; Schema: public; Owner: prosper-dev_owner
--

CREATE TRIGGER skills_inventory_audit AFTER INSERT OR DELETE OR UPDATE ON public.skills_inventory FOR EACH ROW EXECUTE FUNCTION public.create_audit_log();


--
-- TOC entry 4993 (class 2620 OID 198438)
-- Name: performance_scores track_performance_scores; Type: TRIGGER; Schema: public; Owner: prosper-dev_owner
--

CREATE TRIGGER track_performance_scores AFTER UPDATE ON public.performance_scores FOR EACH ROW EXECUTE FUNCTION public.track_score_history();


--
-- TOC entry 4989 (class 2620 OID 198439)
-- Name: employee_manager_hierarchy track_team_size; Type: TRIGGER; Schema: public; Owner: prosper-dev_owner
--

CREATE TRIGGER track_team_size AFTER INSERT OR DELETE OR UPDATE ON public.employee_manager_hierarchy FOR EACH ROW EXECUTE FUNCTION public.update_team_size();


--
-- TOC entry 4873 (class 2606 OID 198440)
-- Name: achievement_badges achievement_badges_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.achievement_badges
    ADD CONSTRAINT achievement_badges_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4874 (class 2606 OID 198445)
-- Name: action_items action_items_assigned_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.action_items
    ADD CONSTRAINT action_items_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4875 (class 2606 OID 198450)
-- Name: action_items action_items_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.action_items
    ADD CONSTRAINT action_items_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4876 (class 2606 OID 198455)
-- Name: alert_notifications alert_notifications_alert_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.alert_notifications
    ADD CONSTRAINT alert_notifications_alert_id_fkey FOREIGN KEY (alert_id) REFERENCES public.metric_alerts(alert_id);


--
-- TOC entry 4877 (class 2606 OID 198460)
-- Name: alert_notifications alert_notifications_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.alert_notifications
    ADD CONSTRAINT alert_notifications_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4878 (class 2606 OID 198465)
-- Name: api_requests api_requests_api_key_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.api_requests
    ADD CONSTRAINT api_requests_api_key_id_fkey FOREIGN KEY (api_key_id) REFERENCES public.api_keys(key_id);


--
-- TOC entry 4879 (class 2606 OID 198470)
-- Name: api_requests api_requests_endpoint_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.api_requests
    ADD CONSTRAINT api_requests_endpoint_id_fkey FOREIGN KEY (endpoint_id) REFERENCES public.api_endpoints(endpoint_id);


--
-- TOC entry 4880 (class 2606 OID 198475)
-- Name: audit_log audit_log_performed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4881 (class 2606 OID 198480)
-- Name: backup_files backup_files_backup_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.backup_files
    ADD CONSTRAINT backup_files_backup_id_fkey FOREIGN KEY (backup_id) REFERENCES public.backup_history(backup_id);


--
-- TOC entry 4882 (class 2606 OID 198485)
-- Name: backup_history backup_history_config_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.backup_history
    ADD CONSTRAINT backup_history_config_id_fkey FOREIGN KEY (config_id) REFERENCES public.backup_configurations(config_id);


--
-- TOC entry 4883 (class 2606 OID 198490)
-- Name: backup_verification_log backup_verification_log_backup_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.backup_verification_log
    ADD CONSTRAINT backup_verification_log_backup_id_fkey FOREIGN KEY (backup_id) REFERENCES public.backup_catalog(backup_id);


--
-- TOC entry 4884 (class 2606 OID 198495)
-- Name: capacity_planning capacity_planning_team_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.capacity_planning
    ADD CONSTRAINT capacity_planning_team_id_fkey FOREIGN KEY (team_id) REFERENCES public.team_structure(team_id);


--
-- TOC entry 4891 (class 2606 OID 198500)
-- Name: career_development_plans career_development_plans_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.career_development_plans
    ADD CONSTRAINT career_development_plans_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4892 (class 2606 OID 198505)
-- Name: career_progression career_progression_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.career_progression
    ADD CONSTRAINT career_progression_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4893 (class 2606 OID 198510)
-- Name: certification_registry certification_registry_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.certification_registry
    ADD CONSTRAINT certification_registry_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4894 (class 2606 OID 198515)
-- Name: communication_log communication_log_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.communication_log
    ADD CONSTRAINT communication_log_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4895 (class 2606 OID 198520)
-- Name: communication_log communication_log_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.communication_log
    ADD CONSTRAINT communication_log_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.communication_templates(template_id);


--
-- TOC entry 4896 (class 2606 OID 198525)
-- Name: communication_metrics communication_metrics_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.communication_metrics
    ADD CONSTRAINT communication_metrics_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4897 (class 2606 OID 198530)
-- Name: configuration_history configuration_history_config_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.configuration_history
    ADD CONSTRAINT configuration_history_config_id_fkey FOREIGN KEY (config_id) REFERENCES public.system_configurations(config_id);


--
-- TOC entry 4898 (class 2606 OID 198535)
-- Name: customer_success_metrics customer_success_metrics_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.customer_success_metrics
    ADD CONSTRAINT customer_success_metrics_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4885 (class 2606 OID 198540)
-- Name: department department_parent_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.department
    ADD CONSTRAINT department_parent_department_id_fkey FOREIGN KEY (parent_department_id) REFERENCES public.department(department_id);


--
-- TOC entry 4905 (class 2606 OID 198545)
-- Name: deployment_steps deployment_steps_deployment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.deployment_steps
    ADD CONSTRAINT deployment_steps_deployment_id_fkey FOREIGN KEY (deployment_id) REFERENCES public.deployments(deployment_id);


--
-- TOC entry 4906 (class 2606 OID 198550)
-- Name: employee_achievements employee_achievements_achievement_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.employee_achievements
    ADD CONSTRAINT employee_achievements_achievement_id_fkey FOREIGN KEY (achievement_id) REFERENCES public.achievement_tracking(achievement_id);


--
-- TOC entry 4907 (class 2606 OID 198555)
-- Name: employee_achievements employee_achievements_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.employee_achievements
    ADD CONSTRAINT employee_achievements_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4908 (class 2606 OID 198560)
-- Name: employee_goals employee_goals_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.employee_goals
    ADD CONSTRAINT employee_goals_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4909 (class 2606 OID 198565)
-- Name: employee_goals employee_goals_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.employee_goals
    ADD CONSTRAINT employee_goals_period_id_fkey FOREIGN KEY (period_id) REFERENCES public.evaluation_periods(period_id);


--
-- TOC entry 4886 (class 2606 OID 198570)
-- Name: employee_manager_hierarchy employee_manager_hierarchy_manager_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.employee_manager_hierarchy
    ADD CONSTRAINT employee_manager_hierarchy_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4910 (class 2606 OID 198575)
-- Name: employee_recognition employee_recognition_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.employee_recognition
    ADD CONSTRAINT employee_recognition_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4911 (class 2606 OID 198580)
-- Name: employee_recognition employee_recognition_recognizer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.employee_recognition
    ADD CONSTRAINT employee_recognition_recognizer_id_fkey FOREIGN KEY (recognizer_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4912 (class 2606 OID 198585)
-- Name: employee_risk_assessment employee_risk_assessment_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.employee_risk_assessment
    ADD CONSTRAINT employee_risk_assessment_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4914 (class 2606 OID 198590)
-- Name: enablement_points_tracking enablement_points_tracking_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.enablement_points_tracking
    ADD CONSTRAINT enablement_points_tracking_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4915 (class 2606 OID 198595)
-- Name: evaluation_submissions evaluation_submissions_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.evaluation_submissions
    ADD CONSTRAINT evaluation_submissions_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4916 (class 2606 OID 198600)
-- Name: evaluation_submissions evaluation_submissions_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.evaluation_submissions
    ADD CONSTRAINT evaluation_submissions_period_id_fkey FOREIGN KEY (period_id) REFERENCES public.evaluation_periods(period_id);


--
-- TOC entry 4917 (class 2606 OID 198605)
-- Name: feedback_actions feedback_actions_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.feedback_actions
    ADD CONSTRAINT feedback_actions_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4918 (class 2606 OID 198610)
-- Name: feedback_actions feedback_actions_suggestion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.feedback_actions
    ADD CONSTRAINT feedback_actions_suggestion_id_fkey FOREIGN KEY (suggestion_id) REFERENCES public.improvement_suggestions(suggestion_id);


--
-- TOC entry 4921 (class 2606 OID 198620)
-- Name: goal_achievement_metrics goal_achievement_metrics_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.goal_achievement_metrics
    ADD CONSTRAINT goal_achievement_metrics_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4922 (class 2606 OID 198625)
-- Name: goal_dependencies goal_dependencies_dependent_goal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.goal_dependencies
    ADD CONSTRAINT goal_dependencies_dependent_goal_id_fkey FOREIGN KEY (dependent_goal_id) REFERENCES public.employee_goals(goal_id);


--
-- TOC entry 4923 (class 2606 OID 198630)
-- Name: goal_dependencies goal_dependencies_goal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.goal_dependencies
    ADD CONSTRAINT goal_dependencies_goal_id_fkey FOREIGN KEY (goal_id) REFERENCES public.employee_goals(goal_id);


--
-- TOC entry 4924 (class 2606 OID 198635)
-- Name: goal_milestones goal_milestones_goal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.goal_milestones
    ADD CONSTRAINT goal_milestones_goal_id_fkey FOREIGN KEY (goal_id) REFERENCES public.employee_goals(goal_id);


--
-- TOC entry 4925 (class 2606 OID 198640)
-- Name: goal_reviews goal_reviews_goal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.goal_reviews
    ADD CONSTRAINT goal_reviews_goal_id_fkey FOREIGN KEY (goal_id) REFERENCES public.employee_goals(goal_id);


--
-- TOC entry 4926 (class 2606 OID 198645)
-- Name: goal_reviews goal_reviews_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.goal_reviews
    ADD CONSTRAINT goal_reviews_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4927 (class 2606 OID 198650)
-- Name: improvement_initiatives improvement_initiatives_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.improvement_initiatives
    ADD CONSTRAINT improvement_initiatives_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4928 (class 2606 OID 198655)
-- Name: improvement_suggestions improvement_suggestions_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.improvement_suggestions
    ADD CONSTRAINT improvement_suggestions_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4929 (class 2606 OID 198660)
-- Name: job_executions job_executions_job_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.job_executions
    ADD CONSTRAINT job_executions_job_id_fkey FOREIGN KEY (job_id) REFERENCES public.scheduled_jobs(job_id);


--
-- TOC entry 4930 (class 2606 OID 198665)
-- Name: knowledge_transfer knowledge_transfer_source_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.knowledge_transfer
    ADD CONSTRAINT knowledge_transfer_source_employee_id_fkey FOREIGN KEY (source_employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4931 (class 2606 OID 198670)
-- Name: knowledge_transfer knowledge_transfer_target_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.knowledge_transfer
    ADD CONSTRAINT knowledge_transfer_target_employee_id_fkey FOREIGN KEY (target_employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4932 (class 2606 OID 198675)
-- Name: learning_paths learning_paths_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.learning_paths
    ADD CONSTRAINT learning_paths_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4933 (class 2606 OID 198680)
-- Name: maintenance_history maintenance_history_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.maintenance_history
    ADD CONSTRAINT maintenance_history_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES public.maintenance_schedule(schedule_id);


--
-- TOC entry 4934 (class 2606 OID 198685)
-- Name: manager manager_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.manager
    ADD CONSTRAINT manager_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.department(department_id);


--
-- TOC entry 4936 (class 2606 OID 198690)
-- Name: manager_engagement_metrics manager_engagement_metrics_manager_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.manager_engagement_metrics
    ADD CONSTRAINT manager_engagement_metrics_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4935 (class 2606 OID 198695)
-- Name: manager manager_manager_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.manager
    ADD CONSTRAINT manager_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4937 (class 2606 OID 198700)
-- Name: mentorship_interactions mentorship_interactions_match_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.mentorship_interactions
    ADD CONSTRAINT mentorship_interactions_match_id_fkey FOREIGN KEY (match_id) REFERENCES public.mentorship_matching(match_id);


--
-- TOC entry 4938 (class 2606 OID 198705)
-- Name: mentorship_matching mentorship_matching_mentee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.mentorship_matching
    ADD CONSTRAINT mentorship_matching_mentee_id_fkey FOREIGN KEY (mentee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4939 (class 2606 OID 198710)
-- Name: mentorship_matching mentorship_matching_mentor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.mentorship_matching
    ADD CONSTRAINT mentorship_matching_mentor_id_fkey FOREIGN KEY (mentor_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4940 (class 2606 OID 198715)
-- Name: mentorship_programs mentorship_programs_mentee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.mentorship_programs
    ADD CONSTRAINT mentorship_programs_mentee_id_fkey FOREIGN KEY (mentee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4941 (class 2606 OID 198720)
-- Name: mentorship_programs mentorship_programs_mentor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.mentorship_programs
    ADD CONSTRAINT mentorship_programs_mentor_id_fkey FOREIGN KEY (mentor_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4942 (class 2606 OID 198725)
-- Name: notification_history notification_history_channel_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.notification_history
    ADD CONSTRAINT notification_history_channel_id_fkey FOREIGN KEY (channel_id) REFERENCES public.notification_channels(channel_id);


--
-- TOC entry 4943 (class 2606 OID 204839)
-- Name: notification_history notification_history_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.notification_history
    ADD CONSTRAINT notification_history_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.notification_templates(template_id);


--
-- TOC entry 4944 (class 2606 OID 198735)
-- Name: notification_log notification_log_recipient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.notification_log
    ADD CONSTRAINT notification_log_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4945 (class 2606 OID 198740)
-- Name: notification_templates notification_templates_last_modified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.notification_templates
    ADD CONSTRAINT notification_templates_last_modified_by_fkey FOREIGN KEY (last_modified_by) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4946 (class 2606 OID 198745)
-- Name: operational_efficiency_metrics operational_efficiency_metrics_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.operational_efficiency_metrics
    ADD CONSTRAINT operational_efficiency_metrics_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4947 (class 2606 OID 198750)
-- Name: opt_in_tracking opt_in_tracking_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.opt_in_tracking
    ADD CONSTRAINT opt_in_tracking_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4948 (class 2606 OID 198755)
-- Name: performance_delta_tracking performance_delta_tracking_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_delta_tracking
    ADD CONSTRAINT performance_delta_tracking_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4949 (class 2606 OID 198760)
-- Name: performance_delta_tracking performance_delta_tracking_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_delta_tracking
    ADD CONSTRAINT performance_delta_tracking_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4919 (class 2606 OID 198765)
-- Name: performance_feedback performance_feedback_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_feedback
    ADD CONSTRAINT performance_feedback_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4920 (class 2606 OID 198770)
-- Name: performance_feedback performance_feedback_provider_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_feedback
    ADD CONSTRAINT performance_feedback_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4950 (class 2606 OID 198775)
-- Name: performance_impact performance_impact_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_impact
    ADD CONSTRAINT performance_impact_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4951 (class 2606 OID 198780)
-- Name: performance_improvement_metrics performance_improvement_metrics_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_improvement_metrics
    ADD CONSTRAINT performance_improvement_metrics_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4952 (class 2606 OID 198785)
-- Name: performance_improvements performance_improvements_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_improvements
    ADD CONSTRAINT performance_improvements_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4953 (class 2606 OID 198790)
-- Name: performance_metrics performance_metrics_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.performance_metrics
    ADD CONSTRAINT performance_metrics_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4954 (class 2606 OID 198795)
-- Name: portfolio_base portfolio_base_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_base
    ADD CONSTRAINT portfolio_base_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4955 (class 2606 OID 198800)
-- Name: portfolio_brownfield portfolio_brownfield_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_brownfield
    ADD CONSTRAINT portfolio_brownfield_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4956 (class 2606 OID 198805)
-- Name: portfolio_brownfield portfolio_brownfield_last_modified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_brownfield
    ADD CONSTRAINT portfolio_brownfield_last_modified_by_fkey FOREIGN KEY (last_modified_by) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4899 (class 2606 OID 198810)
-- Name: portfolio_cloud_services portfolio_cloud_services_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_cloud_services
    ADD CONSTRAINT portfolio_cloud_services_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4900 (class 2606 OID 198815)
-- Name: portfolio_cloud_services portfolio_cloud_services_last_modified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_cloud_services
    ADD CONSTRAINT portfolio_cloud_services_last_modified_by_fkey FOREIGN KEY (last_modified_by) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4901 (class 2606 OID 198820)
-- Name: portfolio_design_success portfolio_design_success_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_design_success
    ADD CONSTRAINT portfolio_design_success_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4902 (class 2606 OID 198825)
-- Name: portfolio_design_success portfolio_design_success_last_modified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_design_success
    ADD CONSTRAINT portfolio_design_success_last_modified_by_fkey FOREIGN KEY (last_modified_by) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4957 (class 2606 OID 198830)
-- Name: portfolio_preferred_success portfolio_preferred_success_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_preferred_success
    ADD CONSTRAINT portfolio_preferred_success_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4958 (class 2606 OID 198835)
-- Name: portfolio_preferred_success portfolio_preferred_success_last_modified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_preferred_success
    ADD CONSTRAINT portfolio_preferred_success_last_modified_by_fkey FOREIGN KEY (last_modified_by) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4903 (class 2606 OID 198840)
-- Name: portfolio_premium_engagement portfolio_premium_engagement_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_premium_engagement
    ADD CONSTRAINT portfolio_premium_engagement_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4904 (class 2606 OID 198845)
-- Name: portfolio_premium_engagement portfolio_premium_engagement_last_modified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_premium_engagement
    ADD CONSTRAINT portfolio_premium_engagement_last_modified_by_fkey FOREIGN KEY (last_modified_by) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4959 (class 2606 OID 198850)
-- Name: portfolio_training portfolio_training_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.portfolio_training
    ADD CONSTRAINT portfolio_training_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4887 (class 2606 OID 198855)
-- Name: project_assignments project_assignments_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.project_assignments
    ADD CONSTRAINT project_assignments_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4888 (class 2606 OID 198860)
-- Name: project_assignments project_assignments_last_modified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.project_assignments
    ADD CONSTRAINT project_assignments_last_modified_by_fkey FOREIGN KEY (last_modified_by) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4960 (class 2606 OID 198865)
-- Name: relationship_assessment relationship_assessment_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.relationship_assessment
    ADD CONSTRAINT relationship_assessment_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4961 (class 2606 OID 198870)
-- Name: relationship_improvement_metrics relationship_improvement_metrics_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.relationship_improvement_metrics
    ADD CONSTRAINT relationship_improvement_metrics_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4962 (class 2606 OID 198875)
-- Name: report_executions report_executions_report_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.report_executions
    ADD CONSTRAINT report_executions_report_id_fkey FOREIGN KEY (report_id) REFERENCES public.report_definitions(report_id);


--
-- TOC entry 4963 (class 2606 OID 198880)
-- Name: report_history report_history_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.report_history
    ADD CONSTRAINT report_history_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.report_templates(template_id);


--
-- TOC entry 4889 (class 2606 OID 198885)
-- Name: resource_allocation resource_allocation_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.resource_allocation
    ADD CONSTRAINT resource_allocation_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4964 (class 2606 OID 198890)
-- Name: resource_allocation_history resource_allocation_history_allocation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.resource_allocation_history
    ADD CONSTRAINT resource_allocation_history_allocation_id_fkey FOREIGN KEY (allocation_id) REFERENCES public.resource_allocation(allocation_id);


--
-- TOC entry 4965 (class 2606 OID 198895)
-- Name: resource_allocation_history resource_allocation_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.resource_allocation_history
    ADD CONSTRAINT resource_allocation_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4966 (class 2606 OID 198900)
-- Name: resource_allocation_history resource_allocation_history_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.resource_allocation_history
    ADD CONSTRAINT resource_allocation_history_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4890 (class 2606 OID 198905)
-- Name: resource_allocation resource_allocation_last_modified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.resource_allocation
    ADD CONSTRAINT resource_allocation_last_modified_by_fkey FOREIGN KEY (last_modified_by) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4967 (class 2606 OID 198910)
-- Name: schema_versions schema_versions_deployment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.schema_versions
    ADD CONSTRAINT schema_versions_deployment_id_fkey FOREIGN KEY (deployment_id) REFERENCES public.deployments(deployment_id);


--
-- TOC entry 4968 (class 2606 OID 198915)
-- Name: score_history score_history_changed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.score_history
    ADD CONSTRAINT score_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4969 (class 2606 OID 198920)
-- Name: score_history score_history_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.score_history
    ADD CONSTRAINT score_history_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4913 (class 2606 OID 198925)
-- Name: skills_inventory skills_inventory_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.skills_inventory
    ADD CONSTRAINT skills_inventory_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4970 (class 2606 OID 198930)
-- Name: stakeholder_relationship_history stakeholder_relationship_history_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.stakeholder_relationship_history
    ADD CONSTRAINT stakeholder_relationship_history_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4971 (class 2606 OID 198935)
-- Name: system_settings system_settings_modified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.system_settings
    ADD CONSTRAINT system_settings_modified_by_fkey FOREIGN KEY (modified_by) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4972 (class 2606 OID 198942)
-- Name: team_collaboration team_collaboration_team_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.team_collaboration
    ADD CONSTRAINT team_collaboration_team_id_fkey FOREIGN KEY (team_id) REFERENCES public.team_structure(team_id);


--
-- TOC entry 4973 (class 2606 OID 198947)
-- Name: team_structure team_structure_department_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.team_structure
    ADD CONSTRAINT team_structure_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.department(department_id);


--
-- TOC entry 4974 (class 2606 OID 198952)
-- Name: team_structure team_structure_last_modified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.team_structure
    ADD CONSTRAINT team_structure_last_modified_by_fkey FOREIGN KEY (last_modified_by) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4975 (class 2606 OID 198957)
-- Name: team_structure team_structure_manager_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.team_structure
    ADD CONSTRAINT team_structure_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4976 (class 2606 OID 198962)
-- Name: team_structure team_structure_parent_team_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.team_structure
    ADD CONSTRAINT team_structure_parent_team_id_fkey FOREIGN KEY (parent_team_id) REFERENCES public.team_structure(team_id);


--
-- TOC entry 4977 (class 2606 OID 198967)
-- Name: test_cases test_cases_suite_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.test_cases
    ADD CONSTRAINT test_cases_suite_id_fkey FOREIGN KEY (suite_id) REFERENCES public.test_suites(suite_id);


--
-- TOC entry 4978 (class 2606 OID 198972)
-- Name: test_executions test_executions_test_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.test_executions
    ADD CONSTRAINT test_executions_test_id_fkey FOREIGN KEY (test_id) REFERENCES public.test_cases(test_id);


--
-- TOC entry 4979 (class 2606 OID 198977)
-- Name: training_records training_records_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.training_records
    ADD CONSTRAINT training_records_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4980 (class 2606 OID 245760)
-- Name: user_sessions user_sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(user_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 4987 (class 2606 OID 198982)
-- Name: workflow_executions workflow_executions_workflow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.workflow_executions
    ADD CONSTRAINT workflow_executions_workflow_id_fkey FOREIGN KEY (workflow_id) REFERENCES public.automation_workflows(workflow_id);


--
-- TOC entry 4981 (class 2606 OID 198987)
-- Name: workflow_instances workflow_instances_current_assignee_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.workflow_instances
    ADD CONSTRAINT workflow_instances_current_assignee_fkey FOREIGN KEY (current_assignee) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4982 (class 2606 OID 198992)
-- Name: workflow_instances workflow_instances_initiator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.workflow_instances
    ADD CONSTRAINT workflow_instances_initiator_id_fkey FOREIGN KEY (initiator_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4983 (class 2606 OID 198997)
-- Name: workflow_instances workflow_instances_last_modified_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.workflow_instances
    ADD CONSTRAINT workflow_instances_last_modified_by_fkey FOREIGN KEY (last_modified_by) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4984 (class 2606 OID 199002)
-- Name: workflow_instances workflow_instances_workflow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.workflow_instances
    ADD CONSTRAINT workflow_instances_workflow_id_fkey FOREIGN KEY (workflow_id) REFERENCES public.workflow_definitions(workflow_id);


--
-- TOC entry 4985 (class 2606 OID 199007)
-- Name: workflow_step_history workflow_step_history_assignee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.workflow_step_history
    ADD CONSTRAINT workflow_step_history_assignee_id_fkey FOREIGN KEY (assignee_id) REFERENCES public.employee_manager_hierarchy(employee_id);


--
-- TOC entry 4986 (class 2606 OID 199012)
-- Name: workflow_step_history workflow_step_history_instance_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.workflow_step_history
    ADD CONSTRAINT workflow_step_history_instance_id_fkey FOREIGN KEY (instance_id) REFERENCES public.workflow_instances(instance_id);


--
-- TOC entry 4988 (class 2606 OID 199017)
-- Name: workflow_step_logs workflow_step_logs_execution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: prosper-dev_owner
--

ALTER TABLE ONLY public.workflow_step_logs
    ADD CONSTRAINT workflow_step_logs_execution_id_fkey FOREIGN KEY (execution_id) REFERENCES public.workflow_executions(execution_id);


--
-- TOC entry 5166 (class 0 OID 0)
-- Dependencies: 5165
-- Name: DATABASE "propser-sbx"; Type: ACL; Schema: -; Owner: prosper-dev_owner
--

GRANT ALL ON DATABASE "propser-sbx" TO neon_superuser;


--
-- TOC entry 5168 (class 0 OID 0)
-- Dependencies: 5
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: prosper-dev_owner
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;


--
-- TOC entry 2953 (class 826 OID 212993)
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: cloud_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE cloud_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO neon_superuser WITH GRANT OPTION;


--
-- TOC entry 2952 (class 826 OID 212992)
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: cloud_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE cloud_admin IN SCHEMA public GRANT ALL ON TABLES TO neon_superuser WITH GRANT OPTION;


-- Completed on 2024-11-23 23:38:58

--
-- PostgreSQL database dump complete
--

