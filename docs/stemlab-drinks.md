# stemlab-drinks — Drink Ordering Service
**Host:** dolus (Ubuntu 24.04) | `172.16.10.58` | VLAN 10 (Lab)
**Repo:** `/home/ferry/stemlab-drinks/`
**Access:** `http://172.16.10.58:3000` (local) | planned: `drinks.velocit.ee` (Cloudflare Tunnel)

---

## Architecture

```
Browser (student/staff)
        │
        │ HTTP :3000
        ▼
┌──────────────────────────────────┐
│   Node.js / Express Backend      │  stemlab-drinks-backend-1
│   Helmet CSP | Rate limiting     │  (Docker container)
│   Static: /app/public (ro)       │
└───────────────┬──────────────────┘
                │ SQL (pg driver)
                ▼
┌──────────────────────────────────┐
│       PostgreSQL 16              │  stemlab-drinks-db-1
│       DB: stemlab                │  (Docker container)
│       User: stemlab              │
│       Volume: pgdata             │
└──────────────────────────────────┘
```

Deployed via Docker Compose (`/home/ferry/stemlab-drinks/compose.yml`). Both containers managed together.

---

## Environment Variables

| Variable | Value | Notes |
|----------|-------|-------|
| `POSTGRES_DB` | `stemlab` | |
| `POSTGRES_USER` | `stemlab` | |
| `POSTGRES_PASSWORD` | *(set in .env)* | |
| `ADMIN_PIN` | *(set in .env)* | 4-digit PIN for staff access |
| `ORDER_RETENTION_HOURS` | `24` (default) | Orders older than this are auto-purged |
| `PORT` | `3000` | |

---

## Database Schema

### `drinks` table
| Column | Type | Notes |
|--------|------|-------|
| `id` | BIGSERIAL PK | |
| `name` | TEXT UNIQUE | Drink name |
| `price` | NUMERIC(10,2) | Must be ≥ 0 |
| `is_available` | BOOLEAN | Hides from public menu when false |
| `sort_order` | INT | Controls display order |
| `category` | TEXT | e.g. "Soda", "Water", "Juice" |
| `notes` | TEXT | Optional note shown to customers |
| `updated_at` | TIMESTAMPTZ | Auto-updated |

### `orders` table
| Column | Type | Notes |
|--------|------|-------|
| `id` | BIGSERIAL PK | |
| `order_number` | BIGINT | Sequential from 1000, displayed to customer |
| `customer_name` | TEXT | Required, trimmed |
| `total_cost` | NUMERIC(10,2) | Calculated server-side from DB prices |
| `status` | ENUM | `new` → `in_progress` → `fulfilled` / `cancelled` |
| `created_at` | TIMESTAMPTZ | |
| `fulfilled_at` | TIMESTAMPTZ | Set when status = fulfilled |

### `order_items` table
| Column | Type | Notes |
|--------|------|-------|
| `id` | BIGSERIAL PK | |
| `order_id` | FK → orders | Cascades on delete |
| `drink_id` | FK → drinks | SET NULL if drink deleted (preserves history) |
| `drink_name` | TEXT | Snapshot of name at order time |
| `unit_price` | NUMERIC(10,2) | Snapshot of price at order time |
| `quantity` | INT | |
| `line_total` | NUMERIC(10,2) | |

---

## API Reference

All admin endpoints require `X-Admin-Pin: <PIN>` header.

### Auth
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/auth` | Admin | Verify PIN — returns `{ok: true}` or 401 |

### Menu
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/menu` | Public | Active drinks only. `?all=1` includes unavailable (admin) |
| POST | `/api/menu` | Admin | Add a new drink |
| PATCH | `/api/menu/:id` | Admin | Update drink fields |
| DELETE | `/api/menu/:id` | Admin | Remove a drink |

### Orders
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/orders` | Public | Place an order. Prices pulled from DB at order time. |
| GET | `/api/orders` | Admin | List orders (last 200). `?status=new\|fulfilled\|cancelled` |
| PATCH | `/api/orders/:id/fulfill` | Admin | Mark order fulfilled |
| PATCH | `/api/orders/:id/cancel` | Admin | Cancel an open order |
| DELETE | `/api/orders` | Admin | Flush all orders (manual purge) |

---

## Security

- **Rate limiting:** 5 PIN attempts / IP / 15 min | 20 orders / IP / 10 min
- **Helmet CSP:** `default-src 'self'`, `script-src 'self' 'unsafe-inline'`, no external resources
- **Admin PIN:** Header-based (`X-Admin-Pin`), never in URL
- **Price integrity:** Prices are always read from the DB at order time — customers cannot set their own prices
- **Order history:** `drink_name` and `unit_price` are snapshotted in `order_items` so history is preserved if the menu changes

---

## Default Menu (seeded on first start)

| Name | Price | Category |
|------|-------|----------|
| Coke | $1.00 | Soda |
| Cherry Coke | $1.00 | Soda |
| Sprite | $1.00 | Soda |
| Canada Dry Gingerale | $1.00 | Soda |
| Orange Sunkist | $1.00 | Soda |
| Grape Sunkist | $1.00 | Soda |
| Dr. Pepper | $1.00 | Soda |
| A&W Root Beer | $1.00 | Soda |
| Mt. Dew | $1.00 | Soda |
| Water | $1.00 | Water |
| Sparkling Water | $1.00 | Water |
| La Croix | $1.00 | Water |
| Capri-Sun (2-pack) | $1.00 | Juice |

Accepts USD and EUR 1:1.

---

## Auto-Purge

Orders older than `ORDER_RETENTION_HOURS` (default 24h) are automatically deleted. The purge runs once at startup and then every hour. Staff can also manually flush all orders via the admin interface or `DELETE /api/orders`.

---

## Useful Commands

```bash
# SSH to the server
ssh ferry@172.16.10.58

# View running containers
docker ps

# View backend logs
docker logs stemlab-drinks-backend-1 -f

# Restart the stack
cd /home/ferry/stemlab-drinks && docker compose restart

# Rebuild after code changes
docker compose up -d --build

# Connect to the DB
docker exec -it stemlab-drinks-db-1 psql -U stemlab -d stemlab
```
