{{ config(materialized='table') }}

WITH dates AS (
  SELECT DISTINCT DATE(block_timestamp) AS date
  FROM noble.block_events
  WHERE block_timestamp >= TIMESTAMP '2025-03-05'
),

swap_vol AS (
  SELECT 
    DATE(s.block_timestamp) AS date,
    SUM(token_amount_in / 1e6) AS volume
  FROM noble.swaps s
  JOIN noble.transactions t ON s.tx_id = t.tx_id
  WHERE (s.token_denom_in = 'uusdn' OR s.token_denom_out = 'uusdn')
    AND t.tx_code = 0
    AND s.block_timestamp >= TIMESTAMP '2025-03-05'
  GROUP BY DATE(s.block_timestamp)
),

mint_vol AS (
  SELECT 
    DATE(block_timestamp) AS date,
    SUM(CAST(REPLACE(attribute_value, '"', '') AS DOUBLE) / 1e6) AS volume
  FROM noble.block_events
  WHERE event_type = 'noble.dollar.portal.v1.MTokenReceived'
    AND attribute_key = 'amount'
    AND block_timestamp >= TIMESTAMP '2025-03-05'
  GROUP BY DATE(block_timestamp)
),

burn_vol AS (
  SELECT 
    DATE(block_timestamp) AS date,
    SUM(CAST(REPLACE(attribute_value, '"', '') AS DOUBLE) / 1e6) AS volume
  FROM noble.message_events
  WHERE event_type = 'noble.dollar.portal.v1.USDNTokenSent'
    AND attribute_key = 'amount'
    AND block_timestamp >= TIMESTAMP '2025-03-05'
  GROUP BY DATE(block_timestamp)
),

vault_vol AS (
  SELECT 
    DATE(tm.block_timestamp) AS date,
    SUM(CAST(JSON_EXTRACT_SCALAR(tm.message, '$.amount') AS DOUBLE) / 1e6) AS volume
  FROM noble.tx_messages tm
  JOIN noble.transactions t ON tm.tx_id = t.tx_id
  WHERE tm.message_type IN ('/noble.dollar.vaults.v1.MsgLock', '/noble.dollar.vaults.v1.MsgUnlock')
    AND t.tx_code = 0
    AND tm.block_timestamp >= TIMESTAMP '2025-03-05'
  GROUP BY DATE(tm.block_timestamp)
),

send_vol AS (
  SELECT 
    DATE(tm.block_timestamp) AS date,
    SUM(CAST(JSON_EXTRACT_SCALAR(amount_item, '$.amount') AS DOUBLE) / 1e6) AS volume
  FROM noble.tx_messages tm
  JOIN noble.transactions t ON tm.tx_id = t.tx_id
  CROSS JOIN UNNEST(TRY_CAST(JSON_EXTRACT(tm.message, '$.amount') AS ARRAY(JSON))) AS amounts(amount_item)
  WHERE tm.message_type = '/cosmos.bank.v1beta1.MsgSend'
    AND t.tx_code = 0
    AND JSON_EXTRACT_SCALAR(amount_item, '$.denom') = 'uusdn'
    AND tm.block_timestamp >= TIMESTAMP '2025-03-05'
  GROUP BY DATE(tm.block_timestamp)
),

bridge_vol AS (
  SELECT 
    DATE(br.block_timestamp) AS date,
    SUM(token_amount / 1e6) AS volume
  FROM noble.bridge_transfers br
  JOIN noble.transactions t ON br.tx_id = t.tx_id
  WHERE br.token_denom = 'uusdn'
    AND t.tx_code = 0
    AND br.block_timestamp >= TIMESTAMP '2025-03-05'
  GROUP BY DATE(br.block_timestamp)
)

SELECT 
  d.date,
  COALESCE(sw.volume, 0) AS swap_volume,
  COALESCE(m.volume, 0) AS mint_volume,
  COALESCE(b.volume, 0) AS burn_volume,
  COALESCE(v.volume, 0) AS vault_volume,
  COALESCE(se.volume, 0) AS send_volume,
  COALESCE(br.volume, 0) AS bridge_volume,
  COALESCE(sw.volume, 0) + COALESCE(m.volume, 0) + COALESCE(b.volume, 0) + 
    COALESCE(v.volume, 0) + COALESCE(se.volume, 0) + COALESCE(br.volume, 0) AS total_daily_volume,
  SUM(COALESCE(sw.volume, 0) + COALESCE(m.volume, 0) + COALESCE(b.volume, 0) + 
    COALESCE(v.volume, 0) + COALESCE(se.volume, 0) + COALESCE(br.volume, 0)) 
    OVER (ORDER BY d.date) AS cumulative_volume
FROM dates d
LEFT JOIN swap_vol sw ON d.date = sw.date
LEFT JOIN mint_vol m ON d.date = m.date
LEFT JOIN burn_vol b ON d.date = b.date
LEFT JOIN vault_vol v ON d.date = v.date
LEFT JOIN send_vol se ON d.date = se.date
LEFT JOIN bridge_vol br ON d.date = br.date
ORDER BY d.date DESC