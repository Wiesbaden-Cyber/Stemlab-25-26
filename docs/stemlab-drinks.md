# stemlab-drinks — Drink Ordering Service

**Host:** dolus (Ubuntu 24.04) | `172.16.10.58` | VLAN 10 (Lab)
**Source on server:** `/home/ferry/stemlab-drinks/`
**Repo:** [Wiesbaden-Cyber/stemlab-drinks](https://github.com/Wiesbaden-Cyber/stemlab-drinks)
**Access:** `http://172.16.10.58:3000` (internal) | `drinks.velocit.ee` (Cloudflare Tunnel)

---

## Pages

| Page | URL | Access | Description |
|------|-----|--------|-------------|
| Customer Order Page | `/` | Public | Browse menu, add to cart, submit order by name |
| Staff Dashboard | `/staff.html` | PIN required | Live order queue — fulfill, cancel, or clear all |
| Menu Editor | `/menu.html` | PIN required | Add, edit, remove drinks, toggle availability |
| Group / Bulk Order | `/inventory.html` | PIN required | Place large orders on behalf of a group |

---

## Architecture

```
Browser (student / staff)
        │
        │ HTTP :3000
        ▼
┌──────────────────────────────────────┐
│       Node.js / Express Backend      │  stemlab-drinks-backend-1
│                                      │  (Docker container, node:20-alpine)
│  Middleware:                         │
│    Helmet (CSP, security headers)   │
│    express-rate-limit (per-IP)       │
│  Static files: /app/public (ro)     │
└──────────────────┬───────────────────┘
                   │ SQL (pg driver)
                   ▼
┌──────────────────────────────────────┐
│           PostgreSQL 16              │  stemlab-drinks-db-1
│           DB: stemlab                │  (Docker container)
│           User: stemlab              │
│           Volume: pgdata             │
└──────────────────────────────────────┘
```

Deployed via Docker Compose (`compose.yml`). Both containers managed together.

---

## Project Structure

```
stemlab-drinks/
├── compose.yml                  # Docker Compose stack definition
├── .env                         # Secrets (not in repo)
├── .env.example                 # Template for .env
├── backend/
│   ├── Dockerfile               # node:20-alpine, installs deps, runs server.js
│   ├── package.json             # express, express-rate-limit, helmet, pg
│   └── src/
│       ├── server.js            # Express app — all routes, rate limiting, purge job
│       └── db.js                # pg Pool via DATABASE_URL env var
├── db/
│   └── init/
│       └── 001_schema.sql       # Schema + seed data (runs once on first container start)
└── public/                      # Static files served directly by Express
    ├── index.html               # Customer order page
    ├── staff.html               # Staff order dashboard (PIN-gated)
    ├── menu.html                # Menu editor (PIN-gated)
    └── inventory.html           # Group/bulk order tool (PIN-gated)
```

---

## Environment Variables

| Variable | Default | Notes |
|----------|---------|-------|
| `POSTGRES_DB` | — | PostgreSQL database name (`stemlab`) |
| `POSTGRES_USER` | — | PostgreSQL username (`stemlab`) |
| `POSTGRES_PASSWORD` | — | PostgreSQL password (set in `.env`) |
| `ADMIN_PIN` | `4321` | Staff PIN for all admin endpoints |
| `ORDER_RETENTION_HOURS` | `24` | Orders older than this are auto-purged (min: 1) |
| `PORT` | `3000` | Port the backend listens on |

---

## Database Schema

### `drinks`
| Column | Type | Notes |
|--------|------|-------|
| `id` | BIGSERIAL PK | |
| `name` | TEXT UNIQUE NOT NULL | Drink name |
| `price` | NUMERIC(10,2) | Must be ≥ 0 |
| `is_available` | BOOLEAN | When false, hidden from public menu |
| `sort_order` | INT | Controls display order (ASC) |
| `category` | TEXT | e.g. `Soda`, `Water`, `Juice` |
| `notes` | TEXT | Optional note shown on menu card (e.g. `Counts as one item`) |
| `updated_at` | TIMESTAMPTZ | Auto-updated on every PATCH |

### `orders`
| Column | Type | Notes |
|--------|------|-------|
| `id` | BIGSERIAL PK | Internal ID |
| `order_number` | BIGINT | Customer-facing number, starts at 1000 |
| `customer_name` | TEXT NOT NULL | Trimmed, required |
| `total_cost` | NUMERIC(10,2) | Calculated server-side — not from client |
| `status` | ENUM | `new` → `in_progress` → `fulfilled` / `cancelled` |
| `created_at` | TIMESTAMPTZ | |
| `fulfilled_at` | TIMESTAMPTZ | Set when status = `fulfilled` |

### `order_items`
| Column | Type | Notes |
|--------|------|-------|
| `id` | BIGSERIAL PK | |
| `order_id` | FK → orders | CASCADE delete |
| `drink_id` | FK → drinks | SET NULL if drink deleted (preserves history) |
| `drink_name` | TEXT | Snapshot of name at order time |
| `unit_price` | NUMERIC(10,2) | Snapshot of price at order time |
| `quantity` | INT | |
| `line_total` | NUMERIC(10,2) | |

Price and name are snapshotted at order time so history stays accurate even if the menu changes.

---

## API Reference

All admin endpoints require the `X-Admin-Pin: <PIN>` request header.

### Auth
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/auth` | Admin | Verify PIN — returns `{ok: true}` or 401 |

### Menu
| Method | Endpoint | Auth | Body | Description |
|--------|----------|------|------|-------------|
| GET | `/api/menu` | Public | `?all=1` includes unavailable | List drinks |
| POST | `/api/menu` | Admin | `{name, price, is_available, sort_order, category, notes}` | Add a drink |
| PATCH | `/api/menu/:id` | Admin | Any subset of drink fields | Update a drink |
| DELETE | `/api/menu/:id` | Admin | — | Remove a drink |

### Orders
| Method | Endpoint | Auth | Body | Description |
|--------|----------|------|------|-------------|
| POST | `/api/orders` | Public | `{customerName, items:[{drinkId, quantity}]}` | Place an order |
| GET | `/api/orders` | Admin | `?status=new\|in_progress\|fulfilled\|cancelled` | List orders (last 200) |
| PATCH | `/api/orders/:id/fulfill` | Admin | — | Mark order fulfilled |
| PATCH | `/api/orders/:id/cancel` | Admin | — | Cancel an open order |
| DELETE | `/api/orders` | Admin | — | Flush all orders permanently |

#### How order placement works (`POST /api/orders`)
1. Server validates `customerName` (non-empty string) and `items` array
2. Each `drinkId` is looked up in the DB — rejected if not found or `is_available = false`
3. Prices are read from the DB — the client cannot influence pricing
4. `line_total` and `total_cost` are computed server-side
5. `orders` and `order_items` are inserted in a single transaction (rolls back on any error)
6. Returns `{ok, orderId, orderNumber, status, createdAt}`

---

## Security

| Control | Detail |
|---------|--------|
| Rate limiting — PIN | 5 attempts / IP / 15 min |
| Rate limiting — orders | 20 orders / IP / 10 min |
| Helmet CSP | `default-src 'self'`, `script-src 'self' 'unsafe-inline'`, no external resources |
| Admin auth | `X-Admin-Pin` header — never in URL or response body |
| Price integrity | Prices always pulled from DB at order time |
| SQL injection | Parameterized queries throughout (`$1, $2, ...`) |
| Input validation | All fields validated before any DB query |

---

## Auto-Purge

Orders older than `ORDER_RETENTION_HOURS` (default 24 h) are automatically deleted.

- Runs once at startup
- Then every hour via `setInterval`
- Staff can also manually flush all orders via the "Clear All Orders" button or `DELETE /api/orders`

---

## Default Menu (seeded on first start)

| Name | Price | Category | Notes |
|------|-------|----------|-------|
| Coke | $1.00 | Soda | |
| Cherry Coke | $1.00 | Soda | |
| Sprite | $1.00 | Soda | |
| Canada Dry Gingerale | $1.00 | Soda | |
| Orange Sunkist | $1.00 | Soda | |
| Grape Sunkist | $1.00 | Soda | |
| Dr. Pepper | $1.00 | Soda | |
| A&W Root Beer | $1.00 | Soda | |
| Mt. Dew | $1.00 | Soda | |
| Water | $1.00 | Water | |
| Sparkling Water | $1.00 | Water | |
| La Croix | $1.00 | Water | |
| Capri-Sun (2-pack) | $1.00 | Juice | Counts as one item |

Accepts USD and EUR 1:1.

---

## Useful Commands

```bash
# SSH to the server
ssh ferry@172.16.10.58

# View running containers
docker ps

# View backend logs (live)
docker logs stemlab-drinks-backend-1 -f

# Restart the stack
cd /home/ferry/stemlab-drinks && docker compose restart

# Rebuild after code changes
docker compose up -d --build

# Connect to the database
docker exec -it stemlab-drinks-db-1 psql -U stemlab -d stemlab

# Query current menu
docker exec -it stemlab-drinks-db-1 psql -U stemlab -d stemlab \
  -c "SELECT name, price, is_available, category FROM drinks ORDER BY sort_order;"

# Query open orders
docker exec -it stemlab-drinks-db-1 psql -U stemlab -d stemlab \
  -c "SELECT order_number, customer_name, total_cost, status FROM orders WHERE status='new' ORDER BY created_at;"
```
