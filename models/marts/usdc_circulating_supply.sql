{{
    config(
        materialized='table'
    )
}}

-- USDC Circulating Supply (Outstanding)
-- Combines pre and post SDK50 mint/burn events

WITH usdc_minted_before_sdk50 AS (
    SELECT
        SUM(TRY_CAST(JSON_EXTRACT_SCALAR(attribute_value, '$.amount') AS DOUBLE)) / 1e6 AS total_usdc_minted
    FROM noble.message_events
    WHERE event_type = 'noble.fiattokenfactory.MsgMint' 
        AND attribute_key = 'amount'
),

usdc_minted_after_sdk50 AS (
    SELECT
        SUM(TRY_CAST(JSON_EXTRACT_SCALAR(attribute_value, '$.amount') AS DOUBLE)) / 1e6 AS total_usdc_minted
    FROM noble.message_events
    WHERE event_type = 'circle.fiattokenfactory.v1.MsgMint' 
        AND attribute_key = 'amount'
),

usdc_burnt_before_sdk50 AS (
    SELECT
        SUM(TRY_CAST(JSON_EXTRACT_SCALAR(attribute_value, '$.amount') AS DOUBLE)) / 1e6 AS total_usdc_burnt
    FROM noble.message_events
    WHERE event_type = 'noble.fiattokenfactory.MsgBurn' 
        AND attribute_key = 'amount'
),

usdc_burnt_after_sdk50 AS (
    SELECT
        SUM(TRY_CAST(JSON_EXTRACT_SCALAR(attribute_value, '$.amount') AS DOUBLE)) / 1e6 AS total_usdc_burnt
    FROM noble.message_events
    WHERE event_type = 'circle.fiattokenfactory.v1.MsgBurn' 
        AND attribute_key = 'amount'
)

SELECT
    CURRENT_TIMESTAMP AS updated_at,
    mb.total_usdc_minted + ma.total_usdc_minted AS total_minted,
    bb.total_usdc_burnt + ba.total_usdc_burnt AS total_burned,
    (mb.total_usdc_minted + ma.total_usdc_minted) - (bb.total_usdc_burnt + ba.total_usdc_burnt) AS circulating_supply
FROM usdc_minted_before_sdk50 AS mb
CROSS JOIN usdc_minted_after_sdk50 AS ma
CROSS JOIN usdc_burnt_before_sdk50 AS bb
CROSS JOIN usdc_burnt_after_sdk50 AS ba
