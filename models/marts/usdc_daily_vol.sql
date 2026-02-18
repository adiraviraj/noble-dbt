{{ config(materialized='table') }}

WITH dates AS (
  SELECT DISTINCT DATE(block_timestamp) AS date
  FROM noble.block_events
  WHERE block_timestamp >= TIMESTAMP '2023-11-17'
),

-- CCTP volume (after Nov 2024)
cctp_new AS (
  SELECT 
    DATE(ct.block_timestamp) AS date,
    SUM(token_amount / 1e6) AS volume
  FROM noble.cctp_transactions ct
  JOIN noble.transactions tx ON ct.tx_id = tx.tx_id
  WHERE (
    (ct.dst_domain = '4' AND ct.token_denom = 'uusdc') OR
    (ct.src_domain = '4' AND ct.token_denom = '487039debedbf32d260137b0a6f66b90962bec777250910d253781de326a716d')
  )
    AND ct.src_domain != ct.dst_domain
    AND ct.block_timestamp >= TIMESTAMP '2024-11-01'
    AND tx.tx_code = 0
  GROUP BY DATE(ct.block_timestamp)
),

-- CCTP volume (before Nov 2024 - inbound)
cctp_old_inbound AS (
  SELECT 
    DATE(me.block_timestamp) AS date,
    SUM(CAST(REPLACE(me.attribute_value, '"', '') AS BIGINT) / 1e6) AS volume
  FROM noble.message_events me
  JOIN noble.transactions tx ON me.tx_id = tx.tx_id
  WHERE me.event_type = 'circle.cctp.v1.MintAndWithdraw'
    AND me.attribute_key = 'amount'
    AND me.block_timestamp >= TIMESTAMP '2023-11-17'
    AND me.block_timestamp < TIMESTAMP '2024-11-01'
    AND tx.tx_code = 0
    AND REGEXP_LIKE(REPLACE(me.attribute_value, '"', ''), '^[0-9]+$')
  GROUP BY DATE(me.block_timestamp)
),

-- CCTP volume (before Nov 2024 - outbound)
cctp_old_outbound AS (
  SELECT 
    DATE(ct.block_timestamp) AS date,
    SUM(token_amount / 1e6) AS volume
  FROM noble.cctp_transactions ct
  JOIN noble.transactions tx ON ct.tx_id = tx.tx_id
  WHERE ct.src_domain = '4'
    AND ct.dst_domain != '4'
    AND ct.token_denom = '487039debedbf32d260137b0a6f66b90962bec777250910d253781de326a716d'
    AND ct.block_timestamp >= TIMESTAMP '2023-11-17'
    AND ct.block_timestamp < TIMESTAMP '2024-11-01'
    AND tx.tx_code = 0
  GROUP BY DATE(ct.block_timestamp)
),

-- IBC volume
ibc_vol AS (
  SELECT 
    DATE(br.block_timestamp) AS date,
    SUM(token_amount / 1e6) AS volume
  FROM noble.bridge_transfers br
  JOIN noble.transactions tx ON br.tx_id = tx.tx_id
  WHERE br.protocol = 'ibc'
    AND br.token_denom = 'uusdc'
    AND (br.sender LIKE 'noble%' OR br.receiver LIKE 'noble%')
    AND br.sender != br.receiver
    AND br.block_timestamp >= TIMESTAMP '2023-11-17'
    AND tx.tx_code = 0
  GROUP BY DATE(br.block_timestamp)
),

-- Swap volume
swap_vol AS (
  SELECT 
    DATE(s.block_timestamp) AS date,
    SUM(
      CASE 
        WHEN token_denom_in = 'uusdc' THEN token_amount_in / 1e6
        WHEN token_denom_out = 'uusdc' THEN token_amount_out / 1e6
        ELSE 0
      END
    ) AS volume
  FROM noble.swaps s
  JOIN noble.transactions tx ON s.tx_id = tx.tx_id
  WHERE (s.token_denom_in = 'uusdc' OR s.token_denom_out = 'uusdc')
    AND s.block_timestamp >= TIMESTAMP '2023-11-17'
    AND tx.tx_code = 0
  GROUP BY DATE(s.block_timestamp)
),

-- Internal sends volume
send_vol AS (
  SELECT 
    DATE(tm.block_timestamp) AS date,
    SUM(CAST(JSON_EXTRACT_SCALAR(amount_item, '$.amount') AS DOUBLE) / 1e6) AS volume
  FROM noble.tx_messages tm
  JOIN noble.transactions t ON tm.tx_id = t.tx_id
  CROSS JOIN UNNEST(CAST(JSON_EXTRACT(tm.message, '$.amount') AS ARRAY(JSON))) AS amounts(amount_item)
  WHERE tm.message_type = '/cosmos.bank.v1beta1.MsgSend'
    AND t.tx_code = 0
    AND tm.block_timestamp >= TIMESTAMP '2023-11-17'
    AND JSON_EXTRACT_SCALAR(amount_item, '$.denom') = 'uusdc'
    AND JSON_EXTRACT_SCALAR(tm.message, '$.from_address') LIKE 'noble%'
    AND JSON_EXTRACT_SCALAR(tm.message, '$.to_address') LIKE 'noble%'
    AND JSON_EXTRACT_SCALAR(tm.message, '$.from_address') != JSON_EXTRACT_SCALAR(tm.message, '$.to_address')
  GROUP BY DATE(tm.block_timestamp)
)

SELECT 
  d.date,
  COALESCE(cn.volume, 0) + COALESCE(coi.volume, 0) + COALESCE(coo.volume, 0) AS cctp_volume,
  COALESCE(i.volume, 0) AS ibc_volume,
  COALESCE(sw.volume, 0) AS swap_volume,
  COALESCE(se.volume, 0) AS send_volume,
  COALESCE(cn.volume, 0) + COALESCE(coi.volume, 0) + COALESCE(coo.volume, 0) + 
    COALESCE(i.volume, 0) + COALESCE(sw.volume, 0) + COALESCE(se.volume, 0) AS total_daily_volume,
  SUM(COALESCE(cn.volume, 0) + COALESCE(coi.volume, 0) + COALESCE(coo.volume, 0) + 
    COALESCE(i.volume, 0) + COALESCE(sw.volume, 0) + COALESCE(se.volume, 0)) 
    OVER (ORDER BY d.date) AS cumulative_volume
FROM dates d
LEFT JOIN cctp_new cn ON d.date = cn.date
LEFT JOIN cctp_old_inbound coi ON d.date = coi.date
LEFT JOIN cctp_old_outbound coo ON d.date = coo.date
LEFT JOIN ibc_vol i ON d.date = i.date
LEFT JOIN swap_vol sw ON d.date = sw.date
LEFT JOIN send_vol se ON d.date = se.date
WHERE d.date >= DATE '2023-11-17'
ORDER BY d.date DESC