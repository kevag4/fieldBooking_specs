# Court Booking Platform — Database Schema

Single PostgreSQL 15 instance with PostGIS extension. Two schemas with strict write boundaries.

- **Database**: `courtbooking`
- **Engine**: PostgreSQL 15 + PostGIS 3.3
- **Schemas**: `platform` (Platform Service), `transaction` (Transaction Service)
- **Cross-schema access**: Transaction Service has READ-ONLY access to Platform views
- **Migrations**: Flyway (each service manages its own schema)
- **Currency**: EUR
- **Languages**: el (Greek), en (English)
- **Timezone handling**: All timestamps stored as `TIMESTAMPTZ` (UTC). Court-level timezone stored for display.

---

## Platform Schema

Owned by Platform Service. Manages users, authentication, courts, availability, pricing, promo codes, feature flags, and support.

### `users`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| email | VARCHAR(255) | NOT NULL, UNIQUE | |
| name | VARCHAR(255) | NOT NULL | |
| phone | VARCHAR(50) | | |
| role | VARCHAR(20) | NOT NULL, CHECK (role IN ('CUSTOMER', 'COURT_OWNER', 'PLATFORM_ADMIN')) | |
| language | VARCHAR(5) | NOT NULL DEFAULT 'en', CHECK (language IN ('el', 'en')) | |
| verified | BOOLEAN | NOT NULL DEFAULT FALSE | Court owner verification status |
| stripe_connect_account_id | VARCHAR(255) | | Stripe Connect account ID |
| stripe_account_status | VARCHAR(20) | DEFAULT 'NOT_STARTED', CHECK IN ('PENDING','ACTIVE','RESTRICTED','DISABLED','NOT_STARTED') | |
| payout_schedule | VARCHAR(10) | CHECK IN ('DAILY','WEEKLY','MONTHLY') | |
| subscription_status | VARCHAR(10) | NOT NULL DEFAULT 'NONE', CHECK IN ('TRIAL','ACTIVE','EXPIRED','NONE') | |
| trial_ends_at | TIMESTAMPTZ | | |
| status | VARCHAR(20) | NOT NULL DEFAULT 'ACTIVE', CHECK IN ('ACTIVE','SUSPENDED','DELETED') | |
| terms_accepted_at | TIMESTAMPTZ | NOT NULL | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| updated_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_users_email` — UNIQUE on `email`
- `idx_users_role` — on `role`
- `idx_users_status` — on `status`
- `idx_users_stripe_connect` — on `stripe_connect_account_id` WHERE NOT NULL

---

### `oauth_providers`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| user_id | UUID | NOT NULL, FK → users(id) ON DELETE CASCADE | |
| provider | VARCHAR(20) | NOT NULL, CHECK IN ('GOOGLE','FACEBOOK','APPLE') | |
| provider_user_id | VARCHAR(255) | NOT NULL | OAuth provider's user ID |
| email | VARCHAR(255) | | Email from OAuth provider |
| linked_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `uq_oauth_provider_user` — UNIQUE on `(provider, provider_user_id)`
- `idx_oauth_providers_user_id` — on `user_id`

---

### `refresh_tokens`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| user_id | UUID | NOT NULL, FK → users(id) ON DELETE CASCADE | |
| token_hash | VARCHAR(255) | NOT NULL, UNIQUE | SHA-256 hash of the refresh token |
| device_id | VARCHAR(255) | | Device identifier |
| invalidated | BOOLEAN | NOT NULL DEFAULT FALSE | Set true on rotation |
| expires_at | TIMESTAMPTZ | NOT NULL | 30-day lifetime |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_refresh_tokens_user_id` — on `user_id`
- `idx_refresh_tokens_token_hash` — UNIQUE on `token_hash`
- `idx_refresh_tokens_expires_at` — on `expires_at` (for cleanup jobs)

---

### `courts`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| owner_id | UUID | NOT NULL, FK → users(id) | |
| name_el | VARCHAR(255) | NOT NULL | Greek name |
| name_en | VARCHAR(255) | | English name |
| description_el | TEXT | | Greek description |
| description_en | TEXT | | English description |
| court_type | VARCHAR(20) | NOT NULL, CHECK IN ('TENNIS','PADEL','BASKETBALL','FOOTBALL_5X5') | |
| location_type | VARCHAR(10) | NOT NULL, CHECK IN ('INDOOR','OUTDOOR') | |
| location | GEOMETRY(Point, 4326) | NOT NULL | PostGIS point (longitude, latitude) |
| address | VARCHAR(500) | NOT NULL | |
| timezone | VARCHAR(50) | NOT NULL DEFAULT 'Europe/Athens' | |
| base_price | DECIMAL(10,2) | NOT NULL | Base price in EUR |
| duration_minutes | INTEGER | NOT NULL | Default slot duration |
| max_capacity | INTEGER | NOT NULL | Max players |
| confirmation_mode | VARCHAR(10) | NOT NULL DEFAULT 'INSTANT', CHECK IN ('INSTANT','MANUAL') | |
| confirmation_timeout_hours | INTEGER | DEFAULT 24 | Hours before auto-cancel (MANUAL mode) |
| waitlist_enabled | BOOLEAN | NOT NULL DEFAULT FALSE | |
| amenities | TEXT[] | | Array of amenity strings |
| image_urls | TEXT[] | | Array of image URLs (DO Spaces) |
| average_rating | DECIMAL(3,2) | | Cached average rating |
| total_reviews | INTEGER | NOT NULL DEFAULT 0 | Cached review count |
| visible | BOOLEAN | NOT NULL DEFAULT FALSE | Public visibility (depends on owner verification) |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| updated_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_courts_owner_id` — on `owner_id`
- `idx_courts_location` — GIST on `location` (geospatial queries)
- `idx_courts_court_type` — on `court_type`
- `idx_courts_location_type` — on `location_type`
- `idx_courts_visible` — on `visible` WHERE `visible = TRUE`
- `idx_courts_type_location` — on `(court_type, location_type)` WHERE `visible = TRUE`

---

### `availability_windows`

Recurring weekly schedule for a court.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| court_id | UUID | NOT NULL, FK → courts(id) ON DELETE CASCADE | |
| day_of_week | VARCHAR(10) | NOT NULL, CHECK IN ('MONDAY'...'SUNDAY') | |
| start_time | TIME | NOT NULL | |
| end_time | TIME | NOT NULL, CHECK (end_time > start_time) | |

**Indexes:**
- `idx_availability_windows_court_id` — on `court_id`
- `uq_availability_no_overlap` — EXCLUDE constraint preventing overlapping windows per court per day

---

### `availability_overrides`

Manual date/time blocks (maintenance, holidays, private events).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| court_id | UUID | NOT NULL, FK → courts(id) ON DELETE CASCADE | |
| date | DATE | NOT NULL | |
| start_time | TIME | | NULL = blocks entire day |
| end_time | TIME | | |
| reason | VARCHAR(255) | | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_availability_overrides_court_date` — on `(court_id, date)`

---

### `favorites`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| user_id | UUID | NOT NULL, FK → users(id) ON DELETE CASCADE | |
| court_id | UUID | NOT NULL, FK → courts(id) ON DELETE CASCADE | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Primary Key:** `(user_id, court_id)`

---

### `preferences`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| user_id | UUID | PK, FK → users(id) ON DELETE CASCADE | |
| preferred_days | TEXT[] | | Array of day names |
| preferred_start_time | TIME | | |
| preferred_end_time | TIME | | |
| max_search_distance_km | DECIMAL(5,1) | DEFAULT 10.0 | |
| notify_booking_events | BOOLEAN | DEFAULT TRUE | |
| notify_favorite_alerts | BOOLEAN | DEFAULT TRUE | |
| notify_promotional | BOOLEAN | DEFAULT TRUE | |
| notify_email | BOOLEAN | DEFAULT TRUE | |
| notify_push | BOOLEAN | DEFAULT TRUE | |
| dnd_start | TIME | | Do not disturb start |
| dnd_end | TIME | | Do not disturb end |

---

### `skill_levels`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| user_id | UUID | NOT NULL, FK → users(id) ON DELETE CASCADE | |
| court_type | VARCHAR(20) | NOT NULL | |
| level | INTEGER | NOT NULL, CHECK (level BETWEEN 1 AND 7) | |

**Primary Key:** `(user_id, court_type)`

---

### `court_ratings`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| court_id | UUID | NOT NULL, FK → courts(id) ON DELETE CASCADE | |
| customer_id | UUID | NOT NULL, FK → users(id) | |
| booking_id | UUID | NOT NULL | References transaction.bookings(id) |
| rating | INTEGER | NOT NULL, CHECK (rating BETWEEN 1 AND 5) | |
| comment | TEXT | | Max 1000 chars (app-enforced) |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_court_ratings_court_id` — on `court_id`
- `uq_court_ratings_booking` — UNIQUE on `booking_id` (one rating per booking)
- `idx_court_ratings_customer` — on `customer_id`

---

### `pricing_rules`

Dynamic pricing multipliers by day/time.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| court_id | UUID | NOT NULL, FK → courts(id) ON DELETE CASCADE | |
| day_of_week | VARCHAR(10) | NOT NULL | |
| start_time | TIME | NOT NULL | |
| end_time | TIME | NOT NULL | |
| multiplier | DECIMAL(4,2) | NOT NULL | e.g. 1.50 for 50% peak surcharge |

**Indexes:**
- `idx_pricing_rules_court_id` — on `court_id`

---

### `special_date_pricing`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| court_id | UUID | NOT NULL, FK → courts(id) ON DELETE CASCADE | |
| date | DATE | NOT NULL | |
| multiplier | DECIMAL(4,2) | NOT NULL | |
| label | VARCHAR(100) | | e.g. "Christmas", "National Holiday" |

**Indexes:**
- `idx_special_date_pricing_court_date` — on `(court_id, date)`

---

### `cancellation_tiers`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| court_id | UUID | NOT NULL, FK → courts(id) ON DELETE CASCADE | |
| threshold_hours | INTEGER | NOT NULL | Hours before booking start |
| refund_percentage | INTEGER | NOT NULL, CHECK (BETWEEN 0 AND 100) | |

**Indexes:**
- `idx_cancellation_tiers_court_id` — on `court_id`

---

### `promo_codes`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| owner_id | UUID | FK → users(id) | NULL for platform-wide codes |
| code | VARCHAR(20) | NOT NULL, UNIQUE | |
| discount_type | VARCHAR(20) | NOT NULL, CHECK IN ('PERCENTAGE','FIXED_AMOUNT') | |
| discount_value | DECIMAL(10,2) | NOT NULL | |
| valid_from | TIMESTAMPTZ | NOT NULL | |
| valid_until | TIMESTAMPTZ | NOT NULL | |
| max_usages | INTEGER | | NULL = unlimited |
| current_usages | INTEGER | NOT NULL DEFAULT 0 | |
| applicable_court_types | TEXT[] | | NULL = all types |
| scope | VARCHAR(20) | NOT NULL, CHECK IN ('COURT_OWNER','PLATFORM') | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `uq_promo_codes_code` — UNIQUE on `code`
- `idx_promo_codes_owner_id` — on `owner_id`
- `idx_promo_codes_valid_range` — on `(valid_from, valid_until)` WHERE `current_usages < max_usages OR max_usages IS NULL`

---

### `translations`

General-purpose translation table for platform content.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| entity_type | VARCHAR(50) | NOT NULL | e.g. 'court', 'promo_code' |
| entity_id | UUID | NOT NULL | |
| field_name | VARCHAR(50) | NOT NULL | e.g. 'name', 'description' |
| language | VARCHAR(5) | NOT NULL | 'el' or 'en' |
| value | TEXT | NOT NULL | |

**Indexes:**
- `uq_translations_entity_field_lang` — UNIQUE on `(entity_type, entity_id, field_name, language)`

---

### `feature_flags`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| key | VARCHAR(100) | PK | Flag identifier |
| enabled | BOOLEAN | NOT NULL DEFAULT FALSE | |
| description | TEXT | | |
| environment | VARCHAR(20) | | NULL = all environments |
| updated_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

---

### `support_tickets`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| reference_number | VARCHAR(30) | NOT NULL, UNIQUE | Human-readable ref (e.g. FB-20260207-001) |
| user_id | UUID | NOT NULL, FK → users(id) | |
| user_role | VARCHAR(20) | NOT NULL | Snapshot of role at submission time |
| category | VARCHAR(20) | NOT NULL, CHECK IN ('BOOKING','PAYMENT','ACCOUNT','TECHNICAL','PAYOUT_ISSUES','OTHER') | |
| subject | VARCHAR(200) | NOT NULL | |
| description | TEXT | NOT NULL | Max 5000 chars |
| status | VARCHAR(20) | NOT NULL DEFAULT 'OPEN', CHECK IN ('OPEN','IN_PROGRESS','AWAITING_USER','RESOLVED','CLOSED') | |
| context_metadata | JSONB | | Auto-attached context (bookingId, paymentId, errorCode, etc.) |
| assigned_admin_id | UUID | FK → users(id) | |
| satisfaction_rating | INTEGER | CHECK (BETWEEN 1 AND 5) | |
| feedback | TEXT | | Max 500 chars |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| updated_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| resolved_at | TIMESTAMPTZ | | |

**Indexes:**
- `idx_support_tickets_user_id` — on `user_id`
- `idx_support_tickets_status` — on `status`
- `idx_support_tickets_category` — on `category`
- `idx_support_tickets_assigned` — on `assigned_admin_id` WHERE NOT NULL
- `idx_support_tickets_created_at` — on `created_at`

---

### `support_messages`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| ticket_id | UUID | NOT NULL, FK → support_tickets(id) ON DELETE CASCADE | |
| sender_id | UUID | NOT NULL, FK → users(id) | |
| sender_role | VARCHAR(10) | NOT NULL, CHECK IN ('USER','ADMIN') | |
| message | TEXT | NOT NULL | Max 5000 chars |
| is_internal_note | BOOLEAN | NOT NULL DEFAULT FALSE | Internal admin notes not visible to user |
| sent_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_support_messages_ticket_id` — on `ticket_id`
- `idx_support_messages_sent_at` — on `(ticket_id, sent_at)`

---

### `support_attachments`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| ticket_id | UUID | FK → support_tickets(id) ON DELETE CASCADE | |
| message_id | UUID | FK → support_messages(id) ON DELETE CASCADE | |
| file_url | VARCHAR(500) | NOT NULL | DO Spaces URL |
| file_type | VARCHAR(20) | NOT NULL | e.g. 'IMAGE', 'DIAGNOSTIC_LOG' |
| file_size_bytes | BIGINT | | |
| uploaded_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_support_attachments_ticket_id` — on `ticket_id`
- `idx_support_attachments_message_id` — on `message_id`

---

## Transaction Schema

Owned by Transaction Service. Manages bookings, payments, notifications, waitlists, open matches, and split payments.

### `bookings`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| court_id | UUID | NOT NULL | References platform.courts(id) |
| customer_id | UUID | | References platform.users(id). NULL for manual bookings |
| date | DATE | NOT NULL | |
| start_time | TIME | NOT NULL | |
| end_time | TIME | NOT NULL | |
| duration_minutes | INTEGER | NOT NULL | |
| number_of_people | INTEGER | NOT NULL DEFAULT 1 | |
| status | VARCHAR(30) | NOT NULL, CHECK IN ('CONFIRMED','PENDING_CONFIRMATION','CANCELLED','COMPLETED','MODIFIED') | |
| confirmation_mode | VARCHAR(10) | NOT NULL | 'INSTANT' or 'MANUAL' |
| amount | DECIMAL(10,2) | NOT NULL | Total charged amount in EUR |
| currency | VARCHAR(3) | NOT NULL DEFAULT 'EUR' | |
| payment_status | VARCHAR(30) | CHECK IN ('AUTHORIZED','CAPTURED','REFUNDED','PARTIALLY_REFUNDED','FAILED','DISPUTED') | |
| is_manual | BOOLEAN | NOT NULL DEFAULT FALSE | Court owner manual booking |
| is_recurring | BOOLEAN | NOT NULL DEFAULT FALSE | |
| recurring_group_id | UUID | | Groups recurring booking instances |
| has_open_match | BOOLEAN | NOT NULL DEFAULT FALSE | |
| has_split_payment | BOOLEAN | NOT NULL DEFAULT FALSE | |
| promo_code_applied | VARCHAR(20) | | |
| discount_amount | DECIMAL(10,2) | | |
| platform_fee | DECIMAL(10,2) | | |
| customer_name | VARCHAR(255) | | For manual bookings |
| customer_phone | VARCHAR(50) | | For manual bookings |
| customer_email | VARCHAR(255) | | For manual bookings |
| notes | TEXT | | For manual bookings |
| timezone | VARCHAR(50) | NOT NULL DEFAULT 'Europe/Athens' | |
| version | INTEGER | NOT NULL DEFAULT 0 | Optimistic locking |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| updated_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_bookings_court_date` — on `(court_id, date, start_time)` — primary conflict detection
- `idx_bookings_customer_id` — on `customer_id`
- `idx_bookings_status` — on `status`
- `idx_bookings_date` — on `date`
- `idx_bookings_recurring_group` — on `recurring_group_id` WHERE NOT NULL
- `uq_bookings_no_overlap` — EXCLUDE constraint on `(court_id, date, tsrange(start_time, end_time))` WHERE `status NOT IN ('CANCELLED')` — prevents double-booking

---

### `payments`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| booking_id | UUID | NOT NULL, FK → bookings(id) | |
| stripe_payment_intent_id | VARCHAR(255) | UNIQUE | |
| stripe_charge_id | VARCHAR(255) | | |
| amount | DECIMAL(10,2) | NOT NULL | |
| platform_fee | DECIMAL(10,2) | | |
| currency | VARCHAR(3) | NOT NULL DEFAULT 'EUR' | |
| status | VARCHAR(30) | NOT NULL, CHECK IN ('AUTHORIZED','CAPTURED','REFUNDED','PARTIALLY_REFUNDED','FAILED','DISPUTED') | |
| payment_method_type | VARCHAR(20) | | 'CARD', 'APPLE_PAY', 'GOOGLE_PAY' |
| payment_method_last4 | VARCHAR(4) | | |
| payment_method_brand | VARCHAR(20) | | e.g. 'visa', 'mastercard' |
| refund_amount | DECIMAL(10,2) | | |
| refund_status | VARCHAR(20) | CHECK IN ('INITIATED','PROCESSING','COMPLETED','FAILED') | |
| refund_initiated_at | TIMESTAMPTZ | | |
| refund_completed_at | TIMESTAMPTZ | | |
| dispute_reason | TEXT | | |
| dispute_status | VARCHAR(20) | CHECK IN ('OPEN','UNDER_REVIEW','WON','LOST') | |
| dispute_created_at | TIMESTAMPTZ | | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| updated_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_payments_booking_id` — on `booking_id`
- `idx_payments_stripe_pi` — UNIQUE on `stripe_payment_intent_id`
- `idx_payments_status` — on `status`

---

### `audit_logs`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| booking_id | UUID | NOT NULL, FK → bookings(id) | |
| action | VARCHAR(30) | NOT NULL | e.g. CREATED, CONFIRMED, CANCELLED, MODIFIED, REFUNDED |
| performed_by | VARCHAR(255) | NOT NULL | User ID or 'SYSTEM' |
| details | TEXT | | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_audit_logs_booking_id` — on `booking_id`
- `idx_audit_logs_created_at` — on `created_at`

---

### `notifications`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| user_id | UUID | NOT NULL | References platform.users(id) |
| title | VARCHAR(255) | NOT NULL | |
| body | TEXT | NOT NULL | |
| urgency | VARCHAR(15) | NOT NULL, CHECK IN ('CRITICAL','STANDARD','PROMOTIONAL') | |
| read | BOOLEAN | NOT NULL DEFAULT FALSE | |
| data | JSONB | | Additional context (bookingId, courtId, etc.) |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_notifications_user_id` — on `user_id`
- `idx_notifications_user_unread` — on `(user_id, read)` WHERE `read = FALSE`
- `idx_notifications_created_at` — on `created_at`

---

### `device_tokens`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| user_id | UUID | NOT NULL | References platform.users(id) |
| device_token | VARCHAR(500) | NOT NULL | FCM registration token |
| platform | VARCHAR(10) | NOT NULL, CHECK IN ('IOS','ANDROID','WEB') | |
| device_id | VARCHAR(255) | | Unique device identifier |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_device_tokens_user_id` — on `user_id`
- `uq_device_tokens_token` — UNIQUE on `device_token`

---

### `waitlists`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| court_id | UUID | NOT NULL | References platform.courts(id) |
| user_id | UUID | NOT NULL | References platform.users(id) |
| date | DATE | NOT NULL | |
| start_time | TIME | NOT NULL | |
| position | INTEGER | NOT NULL | Queue position (1 = next) |
| status | VARCHAR(20) | NOT NULL DEFAULT 'WAITING', CHECK IN ('WAITING','SLOT_OFFERED','EXPIRED','CONVERTED') | |
| hold_expires_at | TIMESTAMPTZ | | Set when slot offered (15-min hold) |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_waitlists_court_date_time` — on `(court_id, date, start_time)`
- `idx_waitlists_user_id` — on `user_id`
- `idx_waitlists_status` — on `status` WHERE `status = 'WAITING'`
- `uq_waitlists_user_slot` — UNIQUE on `(user_id, court_id, date, start_time)` WHERE `status IN ('WAITING','SLOT_OFFERED')`
- `idx_waitlists_hold_expires` — on `hold_expires_at` WHERE `status = 'SLOT_OFFERED'` (for expiration jobs)

---

### `open_matches`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| booking_id | UUID | NOT NULL, FK → bookings(id) | |
| creator_id | UUID | NOT NULL | References platform.users(id) |
| court_id | UUID | NOT NULL | References platform.courts(id) |
| skill_range_min | INTEGER | CHECK (BETWEEN 1 AND 7) | |
| skill_range_max | INTEGER | CHECK (BETWEEN 1 AND 7) | |
| auto_accept | BOOLEAN | NOT NULL DEFAULT FALSE | Auto-accept within skill range |
| current_players | INTEGER | NOT NULL DEFAULT 1 | |
| max_players | INTEGER | NOT NULL | |
| cost_per_player | DECIMAL(10,2) | NOT NULL | |
| status | VARCHAR(15) | NOT NULL DEFAULT 'OPEN', CHECK IN ('OPEN','FULL','CLOSED','COMPLETED') | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_open_matches_booking_id` — on `booking_id`
- `idx_open_matches_court_id` — on `court_id`
- `idx_open_matches_status` — on `status` WHERE `status = 'OPEN'`

---

### `match_players`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| match_id | UUID | NOT NULL, FK → open_matches(id) ON DELETE CASCADE | |
| user_id | UUID | NOT NULL | References platform.users(id) |
| is_creator | BOOLEAN | NOT NULL DEFAULT FALSE | |
| joined_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Primary Key:** `(match_id, user_id)`

---

### `match_join_requests`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| match_id | UUID | NOT NULL, FK → open_matches(id) ON DELETE CASCADE | |
| player_id | UUID | NOT NULL | References platform.users(id) |
| message | TEXT | | Max 500 chars |
| status | VARCHAR(15) | NOT NULL DEFAULT 'PENDING', CHECK IN ('PENDING','APPROVED','DECLINED','EXPIRED') | |
| expires_at | TIMESTAMPTZ | NOT NULL | 4-hour timeout |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_join_requests_match_id` — on `match_id`
- `idx_join_requests_player_id` — on `player_id`
- `idx_join_requests_expires` — on `expires_at` WHERE `status = 'PENDING'`

---

### `match_messages`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| match_id | UUID | NOT NULL, FK → open_matches(id) ON DELETE CASCADE | |
| sender_id | UUID | NOT NULL | References platform.users(id) |
| message | VARCHAR(500) | NOT NULL | |
| sent_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_match_messages_match_id` — on `(match_id, sent_at)`

---

### `split_payments`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| booking_id | UUID | NOT NULL, FK → bookings(id) | |
| total_amount | DECIMAL(10,2) | NOT NULL | |
| creator_hold_amount | DECIMAL(10,2) | NOT NULL | Full amount held from creator |
| creator_hold_released | DECIMAL(10,2) | NOT NULL DEFAULT 0 | Amount released as co-players pay |
| deadline | TIMESTAMPTZ | NOT NULL | 2 hours after match ends |
| status | VARCHAR(20) | NOT NULL DEFAULT 'PENDING', CHECK IN ('PENDING','PARTIALLY_PAID','FULLY_PAID','DEADLINE_ENFORCED') | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_split_payments_booking_id` — on `booking_id`
- `idx_split_payments_deadline` — on `deadline` WHERE `status IN ('PENDING','PARTIALLY_PAID')`

---

### `split_payment_shares`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| split_payment_id | UUID | NOT NULL, FK → split_payments(id) ON DELETE CASCADE | |
| player_id | UUID | | NULL if invited but not yet registered |
| player_identifier | VARCHAR(255) | NOT NULL | Username or email |
| amount | DECIMAL(10,2) | NOT NULL | Min €1.00 |
| status | VARCHAR(15) | NOT NULL DEFAULT 'PENDING', CHECK IN ('PENDING','PAID','OVERDUE','WAIVED') | |
| paid_at | TIMESTAMPTZ | | |

**Indexes:**
- `idx_split_shares_split_payment_id` — on `split_payment_id`
- `idx_split_shares_player_id` — on `player_id` WHERE NOT NULL

---

### `scheduled_jobs`

Quartz JDBC job store tables. Managed by Quartz framework — clustered mode (`isClustered=true`).

Standard Quartz tables: `QRTZ_JOB_DETAILS`, `QRTZ_TRIGGERS`, `QRTZ_SIMPLE_TRIGGERS`, `QRTZ_CRON_TRIGGERS`, `QRTZ_BLOB_TRIGGERS`, `QRTZ_FIRED_TRIGGERS`, `QRTZ_PAUSED_TRIGGER_GRPS`, `QRTZ_SCHEDULER_STATE`, `QRTZ_LOCKS`, `QRTZ_CALENDARS`.

These are created by Quartz auto-DDL and not managed by Flyway.

---

## Cross-Schema Views

Created by Platform Service Flyway migrations. Transaction Service has READ-ONLY access.

### `platform.v_court_summary`

```sql
CREATE VIEW platform.v_court_summary AS
SELECT id, owner_id, name_el, name_en, court_type, location_type,
       location, address, timezone, base_price, duration_minutes,
       max_capacity, confirmation_mode, confirmation_timeout_hours,
       waitlist_enabled, visible
FROM platform.courts;
```

### `platform.v_user_basic`

```sql
CREATE VIEW platform.v_user_basic AS
SELECT id, name, email, role, language, verified, status
FROM platform.users;
```

---

## Entity-Relationship Summary

```
platform.users ──┬── 1:N ──► platform.oauth_providers
                  ├── 1:N ──► platform.refresh_tokens
                  ├── 1:1 ──► platform.preferences
                  ├── 1:N ──► platform.skill_levels
                  ├── M:N ──► platform.courts (via favorites)
                  ├── 1:N ──► platform.courts (ownership)
                  ├── 1:N ──► platform.support_tickets
                  └── 1:N ──► platform.court_ratings

platform.courts ──┬── 1:N ──► platform.availability_windows
                   ├── 1:N ──► platform.availability_overrides
                   ├── 1:N ──► platform.pricing_rules
                   ├── 1:N ──► platform.special_date_pricing
                   ├── 1:N ──► platform.cancellation_tiers
                   └── 1:N ──► platform.court_ratings

transaction.bookings ──┬── 1:N ──► transaction.payments
                        ├── 1:N ──► transaction.audit_logs
                        ├── 1:1 ──► transaction.open_matches
                        └── 1:1 ──► transaction.split_payments

transaction.open_matches ──┬── 1:N ──► transaction.match_players
                            ├── 1:N ──► transaction.match_join_requests
                            └── 1:N ──► transaction.match_messages

transaction.split_payments ── 1:N ──► transaction.split_payment_shares
```
