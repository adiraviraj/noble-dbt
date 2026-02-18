# noble-dbt

dbt models for Noble data on Dune Analytics.

## Models

| Model | Description |
|-------|-------------|
| `usdn_circulating_supply` | Daily USDN circulating supply with mint/burn/yield breakdown |
| `usdc_circulating_supply` | Current USDC circulating supply (all-time aggregate) |
| `usdc_circulating_supply_daily` | Daily USDC circulating supply with mint/burn breakdown |
| `usdn_dau` | USDN daily active users and cumulative unique users |
| `usdc_dau` | USDC daily active users and cumulative unique users |
| `usdn_daily_vol` | Daily USDN volume by type (swaps, mints, burns, vault, bridge, sends) |
| `usdc_daily_vol` | Daily USDC volume by type (CCTP, IBC, swaps, sends) |

## Setup

### 1. Install dependencies

```bash
uv sync
```

### 2. Set environment variables

```bash
export DUNE_API_KEY=your_api_key
export DUNE_TEAM_NAME=noble
```

### 3. Run

```bash
uv run dbt deps      # Install dbt packages
uv run dbt debug     # Test connection
uv run dbt run       # Run models (dev schema)
uv run dbt run --target prod  # Run models (prod schema)
```

## Querying

Models are queryable on Dune with the `dune.` catalog prefix:

```sql
-- Dev schema
SELECT * FROM dune.noble__tmp_.usdn_circulating_supply

-- Prod schema
SELECT * FROM dune.noble.usdn_circulating_supply
```

## Common Commands

```bash
uv run dbt run --select model_name              # Run specific model
uv run dbt run --select model_name --full-refresh  # Full refresh
uv run dbt test                                 # Run tests
```

## Automated Refreshes

The GitHub Action in `.github/workflows/dbt_prod.yml` runs daily at 8am UTC.