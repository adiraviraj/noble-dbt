{{
    config(
        materialized='incremental',
        unique_key='date',
        incremental_strategy='delete+insert'
    )
}}

-- USDN Circulating Supply with daily mint/burn/yield flows
-- Combines staging models and calculates running total

WITH all_dates AS (
    SELECT date FROM {{ ref('stg_usdn_daily_mints') }}
    UNION
    SELECT date FROM {{ ref('stg_usdn_daily_burns') }}
    UNION 
    SELECT date FROM {{ ref('stg_usdn_daily_yields') }}
),

daily_flows AS (
    SELECT 
        ad.date,
        COALESCE(m.usdn_minted, 0) AS daily_minted,
        COALESCE(b.usdn_burned, 0) AS daily_burned,
        COALESCE(y.usdn_yield, 0) AS daily_yield,
        COALESCE(m.usdn_minted, 0) + COALESCE(y.usdn_yield, 0) - COALESCE(b.usdn_burned, 0) AS daily_net_flow
    FROM all_dates ad
    LEFT JOIN {{ ref('stg_usdn_daily_mints') }} m ON ad.date = m.date
    LEFT JOIN {{ ref('stg_usdn_daily_burns') }} b ON ad.date = b.date
    LEFT JOIN {{ ref('stg_usdn_daily_yields') }} y ON ad.date = y.date
    {% if is_incremental() %}
    WHERE ad.date > (SELECT MAX(date) FROM {{ this }})
    {% endif %}
)

SELECT 
    date,
    daily_minted,
    daily_burned,
    daily_yield,
    daily_net_flow,
    SUM(daily_net_flow) OVER (ORDER BY date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS total_circulating
FROM daily_flows
ORDER BY date ASC
