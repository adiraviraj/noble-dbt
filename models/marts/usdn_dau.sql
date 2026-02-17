{{ config(materialized='table') }}

WITH daily_usdn_activities AS (
  -- Bridge transfers
  SELECT 
    DATE(block_timestamp) AS activity_date,
    sender AS user_address
  FROM noble.bridge_transfers
  WHERE token_denom = 'uusdn' 
    AND block_timestamp >= TIMESTAMP '2025-03-01'
    AND sender IS NOT NULL
    
  UNION ALL
  
  SELECT 
    DATE(block_timestamp) AS activity_date,
    receiver AS user_address
  FROM noble.bridge_transfers
  WHERE token_denom = 'uusdn' 
    AND block_timestamp >= TIMESTAMP '2025-03-01'
    AND receiver IS NOT NULL
    
  UNION ALL
  
  -- Swaps
  SELECT 
    DATE(block_timestamp) AS activity_date,
    sender AS user_address
  FROM noble.swaps
  WHERE (token_denom_in = 'uusdn' OR token_denom_out = 'uusdn')
    AND block_timestamp >= TIMESTAMP '2025-03-01'
    AND sender IS NOT NULL
    
  UNION ALL
  
  -- Portal receives
  SELECT 
    DATE(block_timestamp) AS activity_date,
    REPLACE(attribute_value, '"', '') AS user_address
  FROM noble.block_events
  WHERE event_type = 'noble.dollar.portal.v1.MTokenReceived'
    AND attribute_key = 'recipient'
    AND block_timestamp >= TIMESTAMP '2025-03-01'
    
  UNION ALL
  
  -- Tx messages (transfers, vault locks/unlocks, yield claims)
  SELECT 
    DATE(tm.block_timestamp) AS activity_date,
    JSON_EXTRACT_SCALAR(tm.message, '$.signer') AS user_address
  FROM noble.tx_messages tm
  JOIN noble.transactions t ON tm.tx_id = t.tx_id AND tm.block_height = t.block_height
  WHERE tm.block_timestamp >= TIMESTAMP '2025-03-01'
    AND t.tx_code = 0
    AND tm.message_type IN (
      '/noble.dollar.portal.v1.MsgTransfer',
      '/noble.dollar.vaults.v1.MsgLock',
      '/noble.dollar.vaults.v1.MsgUnlock',
      '/noble.dollar.v1.MsgClaimYield'
    )
    
  UNION ALL
  
  -- Bank sends (from)
  SELECT 
    DATE(tm.block_timestamp) AS activity_date,
    JSON_EXTRACT_SCALAR(tm.message, '$.from_address') AS user_address
  FROM noble.tx_messages tm
  JOIN noble.transactions t ON tm.tx_id = t.tx_id AND tm.block_height = t.block_height
  CROSS JOIN UNNEST(TRY_CAST(JSON_EXTRACT(tm.message, '$.amount') AS ARRAY(JSON))) AS amounts(amount_item)
  WHERE tm.block_timestamp >= TIMESTAMP '2025-03-01'
    AND t.tx_code = 0
    AND tm.message_type = '/cosmos.bank.v1beta1.MsgSend'
    AND JSON_EXTRACT_SCALAR(amount_item, '$.denom') = 'uusdn'
    
  UNION ALL
  
  -- Bank sends (to)
  SELECT 
    DATE(tm.block_timestamp) AS activity_date,
    JSON_EXTRACT_SCALAR(tm.message, '$.to_address') AS user_address
  FROM noble.tx_messages tm
  JOIN noble.transactions t ON tm.tx_id = t.tx_id AND tm.block_height = t.block_height
  CROSS JOIN UNNEST(TRY_CAST(JSON_EXTRACT(tm.message, '$.amount') AS ARRAY(JSON))) AS amounts(amount_item)
  WHERE tm.block_timestamp >= TIMESTAMP '2025-03-01'
    AND t.tx_code = 0
    AND tm.message_type = '/cosmos.bank.v1beta1.MsgSend'
    AND JSON_EXTRACT_SCALAR(amount_item, '$.denom') = 'uusdn'
),

daily_active AS (
  SELECT 
    activity_date AS date,
    COUNT(DISTINCT user_address) AS daily_active_users
  FROM daily_usdn_activities
  WHERE user_address IS NOT NULL
  GROUP BY activity_date
),

first_seen AS (
  SELECT 
    user_address,
    MIN(activity_date) AS first_seen_date
  FROM daily_usdn_activities
  WHERE user_address IS NOT NULL
  GROUP BY user_address
),

daily_new AS (
  SELECT 
    first_seen_date AS date,
    COUNT(*) AS new_users
  FROM first_seen
  GROUP BY first_seen_date
)

SELECT 
  COALESCE(da.date, dn.date) AS date,
  COALESCE(da.daily_active_users, 0) AS daily_active_users,
  COALESCE(dn.new_users, 0) AS new_users,
  SUM(COALESCE(dn.new_users, 0)) OVER (ORDER BY COALESCE(da.date, dn.date)) AS cumulative_users
FROM daily_active da
FULL OUTER JOIN daily_new dn ON da.date = dn.date
WHERE COALESCE(da.date, dn.date) IS NOT NULL
ORDER BY date DESC