{{
    config(
        materialized='incremental',
        unique_key='date',
        incremental_strategy='delete+insert'
    )
}}

WITH all_dates AS (
    SELECT date FROM {{ ref('stg_usdc_daily_mints') }}
    UNION
    SELECT date FROM {{ ref('stg_usdc_daily_burns') }}
),

daily_flows AS (
    SELECT 
        ad.date,
        COALESCE(m.usdc_minted, 0) AS daily_minted,
        COALESCE(b.usdc_burned, 0) AS daily_burned,
        COALESCE(m.usdc_minted, 0) - COALESCE(b.usdc_burned, 0) AS daily_net_flow
    FROM all_dates ad
    LEFT JOIN {{ ref('stg_usdc_daily_mints') }} m ON ad.date = m.date
    LEFT JOIN {{ ref('stg_usdc_daily_burns') }} b ON ad.date = b.date
    {% if is_incremental() %}
    WHERE ad.date > (SELECT MAX(date) FROM {{ this }})
    {% endif %}
)

SELECT 
    date,
    daily_minted,
    daily_burned,
    daily_net_flow,
    SUM(daily_net_flow) OVER (ORDER BY date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS total_circulating
FROM daily_flows
ORDER BY date ASC