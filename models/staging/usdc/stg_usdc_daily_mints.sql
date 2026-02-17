{{ config(materialized='table') }}

SELECT 
    DATE_TRUNC('day', block_timestamp) AS date,
    SUM(TRY_CAST(JSON_EXTRACT_SCALAR(attribute_value, '$.amount') AS DOUBLE)) / 1e6 AS usdc_minted
FROM noble.message_events
WHERE event_type IN ('noble.fiattokenfactory.MsgMint', 'circle.fiattokenfactory.v1.MsgMint')
    AND attribute_key = 'amount'
GROUP BY DATE_TRUNC('day', block_timestamp)