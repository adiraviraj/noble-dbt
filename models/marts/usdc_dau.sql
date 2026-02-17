{{ config(materialized='table') }}

WITH daily_usdc_activity AS (
  -- Bridge transfers
  SELECT
    DATE(br.block_timestamp) AS activity_date,
    br.sender AS user_address
  FROM noble.bridge_transfers br
  JOIN noble.transactions tx ON br.tx_id = tx.tx_id
  WHERE br.token_denom = 'uusdc' 
    AND br.block_timestamp >= TIMESTAMP '2023-11-17'
    AND tx.tx_code = 0
    AND br.sender IS NOT NULL
    AND br.sender LIKE 'noble%'
    
  UNION ALL
  
  SELECT
    DATE(br.block_timestamp) AS activity_date,
    br.receiver AS user_address
  FROM noble.bridge_transfers br
  JOIN noble.transactions tx ON br.tx_id = tx.tx_id
  WHERE br.token_denom = 'uusdc' 
    AND br.block_timestamp >= TIMESTAMP '2023-11-17'
    AND tx.tx_code = 0
    AND br.receiver IS NOT NULL
    AND br.receiver LIKE 'noble%'
    
  UNION ALL
  
  -- CCTP transactions (inbound)
  SELECT
    DATE(ct.block_timestamp) AS activity_date,
    ct.receiver AS user_address
  FROM noble.cctp_transactions ct
  JOIN noble.transactions tx ON ct.tx_id = tx.tx_id
  WHERE ct.block_timestamp >= TIMESTAMP '2023-11-17'
    AND tx.tx_code = 0
    AND ct.dst_domain = '4' 
    AND ct.token_denom = 'uusdc'
    AND ct.receiver IS NOT NULL
    
  UNION ALL
  
  -- CCTP transactions (outbound)
  SELECT
    DATE(ct.block_timestamp) AS activity_date,
    ct.sender AS user_address
  FROM noble.cctp_transactions ct
  JOIN noble.transactions tx ON ct.tx_id = tx.tx_id
  WHERE ct.block_timestamp >= TIMESTAMP '2023-11-17'
    AND tx.tx_code = 0
    AND ct.src_domain = '4'
    AND ct.token_denom = '487039debedbf32d260137b0a6f66b90962bec777250910d253781de326a716d'
    AND ct.sender IS NOT NULL
    
  UNION ALL
  
  -- Mint/Burn messages
  SELECT 
    DATE(tm.block_timestamp) AS activity_date,
    JSON_EXTRACT_SCALAR(message, '$.signer') AS user_address
  FROM noble.tx_messages tm
  JOIN noble.transactions t ON tm.tx_id = t.tx_id
  WHERE tm.block_timestamp >= TIMESTAMP '2023-11-17'
    AND t.tx_code = 0
    AND tm.message_type IN (
      '/noble.fiattokenfactory.MsgMint',
      '/noble.fiattokenfactory.MsgBurn'
    )
    
  UNION ALL
  
  -- Bank sends with USDC
  SELECT 
    DATE(tm.block_timestamp) AS activity_date,
    JSON_EXTRACT_SCALAR(message, '$.from_address') AS user_address
  FROM noble.tx_messages tm
  JOIN noble.transactions t ON tm.tx_id = t.tx_id
  WHERE tm.block_timestamp >= TIMESTAMP '2023-11-17'
    AND t.tx_code = 0
    AND tm.message_type = '/cosmos.bank.v1beta1.MsgSend'
    AND JSON_EXTRACT_SCALAR(message, '$.amount[0].denom') = 'uusdc'
    
  UNION ALL
  
  -- Swaps
  SELECT 
    DATE(s.block_timestamp) AS activity_date,
    s.sender AS user_address
  FROM noble.swaps s
  JOIN noble.transactions tx ON s.tx_id = tx.tx_id
  WHERE s.block_timestamp >= TIMESTAMP '2023-11-17'
    AND tx.tx_code = 0
    AND (s.token_denom_in = 'uusdc' OR s.token_denom_out = 'uusdc')
    AND s.sender IS NOT NULL
    AND s.sender LIKE 'noble%'
),

daily_active AS (
  SELECT 
    activity_date AS date,
    COUNT(DISTINCT user_address) AS daily_active_users
  FROM daily_usdc_activity
  WHERE user_address IS NOT NULL
    AND user_address LIKE 'noble%'
  GROUP BY activity_date
),

first_seen AS (
  SELECT 
    user_address,
    MIN(activity_date) AS first_seen_date
  FROM daily_usdc_activity
  WHERE user_address IS NOT NULL
    AND user_address LIKE 'noble%'
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