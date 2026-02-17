{{ config(materialized='table') }}

SELECT 
    DATE_TRUNC('day', block_timestamp) AS date,
    SUM(CAST(REPLACE(attribute_value, '"', '') AS DOUBLE)) / 1e6 AS usdn_minted
FROM noble.block_events
WHERE event_type = 'noble.dollar.portal.v1.MTokenReceived'
    AND attribute_key = 'amount'
    AND block_timestamp >= TIMESTAMP '2025-03-01'
GROUP BY DATE_TRUNC('day', block_timestamp)