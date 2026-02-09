# Court Booking Platform — Database Schema

Single PostgreSQL 15 instance with PostGIS extension. Two schemas with strict write boundaries.

- **Database**: `courtbooking`
- **Engine**: PostgreSQL 15 + PostGIS 3.3
- **Schemas**: `platform` (Platform Service), `transaction` (Transaction Service)
- **Cross-schema access**: Transaction Service has READ-ONLY access to Platform views
- **Migrations**: Flyway (each service manages its own schema)
- **Currency**: All monetary amounts stored as INTEGER in euro cents (e.g., €25.50 = 2550). Matches API contracts and Stripe convention. Avoids floating-point rounding.
- **Languages**: el (Greek), en (English)
- **Timezone handling**: All timestamps stored as `TIMESTAMPTZ` (UTC). Court-level timezone stored for display.
- **Phase 2 tables**: Tables for Phase 2 features are included but marked with ⏳. They should be created in initial migrations to avoid ALTER TABLE later.

---

## Platform Schema

Owned by Platform Service. Manages users, authentication, courts, availability, pricing, feature flags, support, verification, audit logs, court owner settings, and security monitoring.

### `users`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| email | VARCHAR(255) | NOT NULL, UNIQUE | |
| name | VARCHAR(255) | NOT NULL | |
| phone | VARCHAR(50) | | |
| role | VARCHAR(20) | NOT NULL, CHECK (role IN ('CUSTOMER', 'COURT_OWNER', 'SUPPORT_AGENT', 'PLATFORM_ADMIN')) | |
| language | VARCHAR(5) | NOT NULL DEFAULT 'el', CHECK (language IN ('el', 'en')) | |
| verified | BOOLEAN | NOT NULL DEFAULT FALSE | Court owner verification status |
| stripe_connect_account_id | VARCHAR(255) | | Stripe Connect account ID (court owners) |
| stripe_connect_status | VARCHAR(20) | DEFAULT 'NOT_STARTED', CHECK IN ('NOT_STARTED','PENDING','ACTIVE','RESTRICTED','DISABLED') | |
| stripe_customer_id | VARCHAR(255) | | Stripe Customer ID (customers — created on first payment) |
| payout_schedule | VARCHAR(10) | CHECK IN ('DAILY','WEEKLY','MONTHLY') | |
| subscription_status | VARCHAR(10) | NOT NULL DEFAULT 'NONE', CHECK IN ('TRIAL','ACTIVE','EXPIRED','NONE') | ⏳ Phase 2 (Req 9a) |
| trial_ends_at | TIMESTAMPTZ | | ⏳ Phase 2 |
| stripe_subscription_id | VARCHAR(255) | | ⏳ Phase 2 — Stripe Billing subscription ID |
| business_name | VARCHAR(255) | | Court owner business name |
| tax_id | VARCHAR(50) | | Court owner tax ID (AFM) |
| business_type | VARCHAR(30) | CHECK IN ('SOLE_PROPRIETOR','COMPANY','ASSOCIATION') | |
| business_address | VARCHAR(500) | | |
| vat_registered | BOOLEAN | NOT NULL DEFAULT FALSE | Whether the court owner is VAT-registered |
| vat_number | VARCHAR(50) | | Greek VAT number (ΑΦΜ with EL prefix for EU VIES, e.g., 'EL123456789') |
| contact_phone | VARCHAR(50) | | Business contact phone |
| profile_image_url | VARCHAR(500) | | Profile photo / business logo |
| status | VARCHAR(20) | NOT NULL DEFAULT 'ACTIVE', CHECK IN ('ACTIVE','SUSPENDED','DELETED') | |
| terms_accepted_at | TIMESTAMPTZ | NOT NULL | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| updated_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_users_email` — UNIQUE on `email`
- `idx_users_role` — on `role`
- `idx_users_status` — on `status`
- `idx_users_stripe_connect` — on `stripe_connect_account_id` WHERE NOT NULL
- `idx_users_stripe_customer` — on `stripe_customer_id` WHERE NOT NULL

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
| device_info | VARCHAR(500) | | Device type, browser, OS (for session list display) |
| ip_address | VARCHAR(45) | | Last known IP (for session list) |
| invalidated | BOOLEAN | NOT NULL DEFAULT FALSE | Set true on rotation |
| last_used_at | TIMESTAMPTZ | | Last activity timestamp |
| expires_at | TIMESTAMPTZ | NOT NULL | 30-day lifetime |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_refresh_tokens_user_id` — on `user_id`
- `idx_refresh_tokens_token_hash` — UNIQUE on `token_hash`
- `idx_refresh_tokens_expires_at` — on `expires_at` (for cleanup jobs)

---

### `verification_requests`

Court owner verification workflow (Req 2.21–2.28).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| court_owner_id | UUID | NOT NULL, FK → users(id) | |
| business_name | VARCHAR(255) | NOT NULL | |
| tax_id | VARCHAR(50) | NOT NULL | |
| business_type | VARCHAR(30) | NOT NULL, CHECK IN ('SOLE_PROPRIETOR','COMPANY','ASSOCIATION') | |
| business_address | VARCHAR(500) | NOT NULL | |
| proof_document_url | VARCHAR(500) | NOT NULL | DO Spaces URL |
| status | VARCHAR(20) | NOT NULL DEFAULT 'PENDING_REVIEW', CHECK IN ('PENDING_REVIEW','APPROVED','REJECTED') | |
| reviewed_by | UUID | FK → users(id) | PLATFORM_ADMIN who reviewed |
| review_notes | TEXT | | Admin notes (approval) |
| rejection_reason | TEXT | | Displayed to court owner |
| previous_request_id | UUID | FK → verification_requests(id) | Links re-submissions |
| submitted_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| reviewed_at | TIMESTAMPTZ | | |

**Indexes:**
- `idx_verification_requests_owner` — on `court_owner_id`
- `idx_verification_requests_status` — on `status` WHERE `status = 'PENDING_REVIEW'`
- `idx_verification_requests_submitted` — on `submitted_at`

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
| base_price_cents | INTEGER | NOT NULL | Base price in euro cents |
| duration_minutes | INTEGER | NOT NULL | Default slot duration |
| max_capacity | INTEGER | NOT NULL | Max players |
| confirmation_mode | VARCHAR(10) | NOT NULL DEFAULT 'INSTANT', CHECK IN ('INSTANT','MANUAL') | |
| confirmation_timeout_hours | INTEGER | DEFAULT 24 | Hours before auto-cancel (MANUAL mode) |
| waitlist_enabled | BOOLEAN | NOT NULL DEFAULT FALSE | ⏳ Phase 2 (Req 26) |
| amenities | TEXT[] | | Array of amenity strings |
| image_urls | TEXT[] | | Array of image URLs (DO Spaces) |
| average_rating | DECIMAL(3,2) | | ⏳ Phase 2 — Cached average rating |
| total_reviews | INTEGER | NOT NULL DEFAULT 0 | ⏳ Phase 2 — Cached review count |
| visible | BOOLEAN | NOT NULL DEFAULT FALSE | Public visibility (depends on owner verification + Stripe) |
| version | INTEGER | NOT NULL DEFAULT 0 | Optimistic locking |
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

### ⏳ `court_ratings` — Phase 2 (Req 2.19–2.20)

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| court_id | UUID | NOT NULL, FK → courts(id) ON DELETE CASCADE | |
| user_id | UUID | NOT NULL, FK → users(id) | |
| booking_id | UUID | NOT NULL | Reference to completed booking |
| rating | INTEGER | NOT NULL, CHECK (rating BETWEEN 1 AND 5) | |
| comment | TEXT | | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_court_ratings_court_id` — on `court_id`
- `uq_court_ratings_booking` — UNIQUE on `booking_id` (one rating per booking)

---

### `pricing_rules` — ⏳ Dynamic pricing is Phase 2 (Req 27.7–27.11), but table holds base price overrides

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| court_id | UUID | NOT NULL, FK → courts(id) ON DELETE CASCADE | |
| day_of_week | VARCHAR(10) | NOT NULL, CHECK IN ('MONDAY'...'SUNDAY') | |
| start_time | TIME | NOT NULL | |
| end_time | TIME | NOT NULL, CHECK (end_time > start_time) | |
| multiplier | DECIMAL(3,2) | NOT NULL, CHECK (multiplier BETWEEN 0.10 AND 5.00) | Price multiplier (1.00 = base price) |
| label | VARCHAR(50) | | e.g., 'Peak', 'Off-Peak', 'Weekend' |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_pricing_rules_court_id` — on `court_id`

---

### ⏳ `special_date_pricing` — Phase 2 (Req 27.9)

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| court_id | UUID | NOT NULL, FK → courts(id) ON DELETE CASCADE | |
| date | DATE | NOT NULL | |
| multiplier | DECIMAL(3,2) | NOT NULL, CHECK (multiplier BETWEEN 0.10 AND 5.00) | |
| label | VARCHAR(100) | | e.g., 'Easter', 'National Holiday' |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_special_date_pricing_court_date` — UNIQUE on `(court_id, date)`

---

### `cancellation_tiers`

Per-court cancellation policy tiers (Req 12.7).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| court_id | UUID | NOT NULL, FK → courts(id) ON DELETE CASCADE | |
| threshold_hours | INTEGER | NOT NULL | Hours before booking start |
| refund_percent | INTEGER | NOT NULL, CHECK (refund_percent BETWEEN 0 AND 100) | |
| sort_order | INTEGER | NOT NULL | Descending by threshold_hours |

**Indexes:**
- `idx_cancellation_tiers_court_id` — on `court_id`
- `uq_cancellation_tiers_court_threshold` — UNIQUE on `(court_id, threshold_hours)`

---

### ⏳ `promo_codes` — Phase 2 (Req 27.1–27.6)

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| court_owner_id | UUID | NOT NULL, FK → users(id) | |
| code | VARCHAR(50) | NOT NULL | |
| discount_type | VARCHAR(20) | NOT NULL, CHECK IN ('PERCENTAGE','FIXED_AMOUNT') | |
| discount_value | INTEGER | NOT NULL | Percentage (0–100) or fixed amount in cents |
| min_booking_cents | INTEGER | | Minimum booking amount to apply |
| max_discount_cents | INTEGER | | Cap for percentage discounts |
| valid_from | TIMESTAMPTZ | NOT NULL | |
| valid_until | TIMESTAMPTZ | NOT NULL | |
| max_uses | INTEGER | | NULL = unlimited |
| current_uses | INTEGER | NOT NULL DEFAULT 0 | |
| max_uses_per_user | INTEGER | DEFAULT 1 | |
| applicable_court_ids | UUID[] | | NULL = all courts of this owner |
| applicable_court_types | TEXT[] | | NULL = all types |
| active | BOOLEAN | NOT NULL DEFAULT TRUE | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_promo_codes_owner` — on `court_owner_id`
- `uq_promo_codes_owner_code` — UNIQUE on `(court_owner_id, code)`
- `idx_promo_codes_active` — on `(court_owner_id, active)` WHERE `active = TRUE`

---

### `translations`

Static UI translations and system messages.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| key | VARCHAR(255) | NOT NULL | Translation key |
| language | VARCHAR(5) | NOT NULL, CHECK IN ('el','en') | |
| value | TEXT | NOT NULL | |

**Indexes:**
- `uq_translations_key_lang` — UNIQUE on `(key, language)`

---

### `feature_flags`

Platform-wide feature toggles (Req 19.17–19.19).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| flag_key | VARCHAR(100) | NOT NULL, UNIQUE | e.g., 'OPEN_MATCHES_ENABLED' |
| enabled | BOOLEAN | NOT NULL DEFAULT FALSE | |
| description | VARCHAR(500) | | |
| updated_by | UUID | FK → users(id) | PLATFORM_ADMIN who last changed |
| updated_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

---

### `support_tickets`

In-app support system (Req 17).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| user_id | UUID | NOT NULL, FK → users(id) | Ticket creator |
| category | VARCHAR(30) | NOT NULL, CHECK IN ('BOOKING','PAYMENT','COURT','ACCOUNT','TECHNICAL','OTHER') | |
| subject | VARCHAR(255) | NOT NULL | |
| status | VARCHAR(20) | NOT NULL DEFAULT 'OPEN', CHECK IN ('OPEN','IN_PROGRESS','WAITING_ON_USER','RESOLVED','CLOSED') | |
| priority | VARCHAR(10) | NOT NULL DEFAULT 'NORMAL', CHECK IN ('LOW','NORMAL','HIGH','URGENT') | |
| assigned_to | UUID | FK → users(id) | PLATFORM_ADMIN |
| related_booking_id | UUID | | Optional booking reference |
| related_court_id | UUID | | Optional court reference |
| diagnostic_data | JSONB | | App version, device info, logs |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| updated_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| resolved_at | TIMESTAMPTZ | | |

**Indexes:**
- `idx_support_tickets_user_id` — on `user_id`
- `idx_support_tickets_status` — on `status`
- `idx_support_tickets_assigned` — on `assigned_to` WHERE `assigned_to IS NOT NULL`
- `idx_support_tickets_created` — on `created_at`

---

### `support_messages`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| ticket_id | UUID | NOT NULL, FK → support_tickets(id) ON DELETE CASCADE | |
| sender_id | UUID | NOT NULL, FK → users(id) | |
| body | TEXT | NOT NULL | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_support_messages_ticket_id` — on `ticket_id`

---

### `support_attachments`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| message_id | UUID | NOT NULL, FK → support_messages(id) ON DELETE CASCADE | |
| file_url | VARCHAR(500) | NOT NULL | DO Spaces URL |
| file_name | VARCHAR(255) | NOT NULL | |
| file_size_bytes | INTEGER | NOT NULL | |
| mime_type | VARCHAR(100) | NOT NULL | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_support_attachments_message_id` — on `message_id`

---

### `court_owner_audit_logs`

Immutable audit trail for court owner actions (Req 15c). Separate from transaction.audit_logs which tracks booking changes.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| court_owner_id | UUID | NOT NULL, FK → users(id) | |
| court_id | UUID | FK → courts(id) | NULL for account-level actions |
| action | VARCHAR(50) | NOT NULL | e.g., 'COURT_CREATED', 'PRICING_UPDATED', 'AVAILABILITY_CHANGED', 'SETTINGS_UPDATED' |
| entity_type | VARCHAR(30) | NOT NULL | e.g., 'COURT', 'PRICING_RULE', 'AVAILABILITY', 'CANCELLATION_POLICY' |
| entity_id | UUID | | ID of the affected entity |
| changes | JSONB | NOT NULL | Before/after snapshot of changed fields |
| ip_address | VARCHAR(45) | | |
| user_agent | VARCHAR(500) | | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_court_owner_audit_logs_owner` — on `court_owner_id`
- `idx_court_owner_audit_logs_court` — on `court_id` WHERE `court_id IS NOT NULL`
- `idx_court_owner_audit_logs_created` — on `created_at`
- `idx_court_owner_audit_logs_action` — on `(court_owner_id, action)`

**Note:** This table is append-only. No UPDATE or DELETE operations permitted. Enforced at application level.

---

### `reminder_rules`

Configurable smart alert rules per court owner (Req 15b). MVP feature.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| court_owner_id | UUID | NOT NULL, FK → users(id) | |
| court_id | UUID | FK → courts(id) ON DELETE CASCADE | NULL = applies to all courts |
| rule_type | VARCHAR(30) | NOT NULL, CHECK IN ('BOOKING_REMINDER','PENDING_CONFIRMATION','LOW_OCCUPANCY','DAILY_SUMMARY') | |
| trigger_hours_before | INTEGER | | Hours before event to trigger (for BOOKING_REMINDER, PENDING_CONFIRMATION) |
| trigger_time | TIME | | Time of day to trigger (for DAILY_SUMMARY) |
| threshold_percent | INTEGER | | Occupancy threshold (for LOW_OCCUPANCY) |
| channels | TEXT[] | NOT NULL DEFAULT '{PUSH,EMAIL}' | Delivery channels |
| enabled | BOOLEAN | NOT NULL DEFAULT TRUE | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| updated_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_reminder_rules_owner` — on `court_owner_id`
- `idx_reminder_rules_court` — on `court_id` WHERE `court_id IS NOT NULL`
- `idx_reminder_rules_type` — on `(court_owner_id, rule_type)` WHERE `enabled = TRUE`

---

### `court_owner_notification_preferences`

Per-event-type notification channel preferences for court owners (Req 15a.6–15a.9).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| court_owner_id | UUID | NOT NULL, FK → users(id) | |
| event_type | VARCHAR(50) | NOT NULL | Matches notification_type enum from Kafka contracts |
| push_enabled | BOOLEAN | NOT NULL DEFAULT TRUE | |
| email_enabled | BOOLEAN | NOT NULL DEFAULT TRUE | |
| in_app_enabled | BOOLEAN | NOT NULL DEFAULT TRUE | |

**Indexes:**
- `uq_notification_prefs_owner_event` — UNIQUE on `(court_owner_id, event_type)`

---

### `court_defaults`

Default settings applied to new courts created by a court owner (Req 15a.10–15a.11).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| court_owner_id | UUID | PK, FK → users(id) ON DELETE CASCADE | |
| default_duration_minutes | INTEGER | | |
| default_confirmation_mode | VARCHAR(10) | CHECK IN ('INSTANT','MANUAL') | |
| default_confirmation_timeout_hours | INTEGER | | |
| default_cancellation_tiers | JSONB | | Array of {thresholdHours, refundPercent} |
| default_amenities | TEXT[] | | |
| updated_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

---

### `security_alerts`

Security monitoring and abuse detection alerts (Req 32).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| alert_type | VARCHAR(50) | NOT NULL, CHECK IN ('BOOKING_ABUSE','PAYMENT_FRAUD','SCRAPING','BRUTE_FORCE','SUSPICIOUS_LOGIN','RATE_LIMIT_EXCEEDED','WEBHOOK_REPLAY','ACCOUNT_TAKEOVER') | |
| severity | VARCHAR(10) | NOT NULL, CHECK IN ('LOW','MEDIUM','HIGH','CRITICAL') | |
| user_id | UUID | FK → users(id) | NULL for IP-based alerts without identified user |
| ip_address | VARCHAR(45) | | Source IP address |
| description | TEXT | NOT NULL | Human-readable alert description |
| metadata | JSONB | | Alert-specific structured data (thresholds, patterns, request details) |
| status | VARCHAR(20) | NOT NULL DEFAULT 'OPEN', CHECK IN ('OPEN','ACKNOWLEDGED','INVESTIGATING','RESOLVED','FALSE_POSITIVE') | |
| acknowledged_by | UUID | FK → users(id) | PLATFORM_ADMIN who acknowledged |
| resolved_by | UUID | FK → users(id) | PLATFORM_ADMIN who resolved |
| resolution_notes | TEXT | | Notes on resolution |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| acknowledged_at | TIMESTAMPTZ | | |
| resolved_at | TIMESTAMPTZ | | |

**Indexes:**
- `idx_security_alerts_status` — on `status` WHERE `status IN ('OPEN','ACKNOWLEDGED','INVESTIGATING')`
- `idx_security_alerts_severity` — on `severity` WHERE `status NOT IN ('RESOLVED','FALSE_POSITIVE')`
- `idx_security_alerts_user_id` — on `user_id` WHERE `user_id IS NOT NULL`
- `idx_security_alerts_ip` — on `ip_address` WHERE `ip_address IS NOT NULL`
- `idx_security_alerts_type` — on `alert_type`
- `idx_security_alerts_created` — on `created_at`

**Note:** This table is append-only for the alert record itself. Only `status`, `acknowledged_by`, `resolved_by`, `resolution_notes`, `acknowledged_at`, and `resolved_at` may be updated.

---

### `ip_blocklist`

Blocked IP addresses for abuse prevention (Req 32).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| ip_address | VARCHAR(45) | NOT NULL | IPv4 or IPv6 address |
| cidr_range | VARCHAR(49) | | Optional CIDR notation for range blocks (e.g., '192.168.1.0/24') |
| reason | VARCHAR(255) | NOT NULL | Reason for blocking |
| blocked_by | UUID | NOT NULL, FK → users(id) | PLATFORM_ADMIN who blocked |
| related_alert_id | UUID | FK → security_alerts(id) | Optional link to triggering alert |
| expires_at | TIMESTAMPTZ | | NULL = permanent block |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_ip_blocklist_ip` — UNIQUE on `ip_address`
- `idx_ip_blocklist_expires` — on `expires_at` WHERE `expires_at IS NOT NULL` (for cleanup/expiry jobs)

---

### `failed_auth_attempts`

Tracks failed authentication attempts for brute-force detection (Req 32, Req 33).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| ip_address | VARCHAR(45) | NOT NULL | |
| email | VARCHAR(255) | | Target email (if provided in attempt) |
| attempt_count | INTEGER | NOT NULL DEFAULT 1 | Rolling count within window |
| window_start | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | Start of the current counting window |
| locked_until | TIMESTAMPTZ | | If set, all auth attempts from this IP are rejected until this time |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| updated_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_failed_auth_ip` — on `ip_address`
- `idx_failed_auth_email` — on `email` WHERE `email IS NOT NULL`
- `idx_failed_auth_locked` — on `locked_until` WHERE `locked_until IS NOT NULL`

---

## Transaction Schema

Owned by Transaction Service. Manages bookings, payments, notifications, device tokens, audit logs, waitlists, open matches, split payments, and scheduled jobs.

### `bookings`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| court_id | UUID | NOT NULL | FK conceptual → platform.courts(id) |
| user_id | UUID | | FK conceptual → platform.users(id). NULL for manual bookings without linked customer |
| court_owner_id | UUID | NOT NULL | Denormalized for query performance |
| idempotency_key | VARCHAR(255) | NOT NULL, UNIQUE | Client-generated key for duplicate prevention (Req 8) |
| date | DATE | NOT NULL | Booking date in court's local timezone |
| start_time | TIME | NOT NULL | |
| end_time | TIME | NOT NULL, CHECK (end_time > start_time) | |
| duration_minutes | INTEGER | NOT NULL | |
| status | VARCHAR(25) | NOT NULL, CHECK IN ('PENDING_CONFIRMATION','CONFIRMED','CANCELLED','COMPLETED','REJECTED') | |
| booking_type | VARCHAR(10) | NOT NULL DEFAULT 'CUSTOMER', CHECK IN ('CUSTOMER','MANUAL') | |
| confirmation_mode | VARCHAR(10) | NOT NULL, CHECK IN ('INSTANT','MANUAL') | Snapshot from court at booking time |
| total_amount_cents | INTEGER | | NULL for manual bookings |
| platform_fee_cents | INTEGER | | Platform commission |
| court_owner_net_cents | INTEGER | | Amount after platform fee |
| discount_cents | INTEGER | DEFAULT 0 | Promo code discount applied |
| promo_code_id | UUID | | ⏳ Phase 2 — FK conceptual → platform.promo_codes(id) |
| payment_status | VARCHAR(20) | NOT NULL DEFAULT 'NOT_REQUIRED', CHECK IN ('NOT_REQUIRED','PENDING','AUTHORIZED','CAPTURED','REFUNDED','PARTIALLY_REFUNDED','FAILED','PAID_EXTERNALLY') | |
| stripe_payment_intent_id | VARCHAR(255) | | Stripe PaymentIntent ID |
| paid_externally | BOOLEAN | NOT NULL DEFAULT FALSE | Court owner marked as paid outside platform (Req 14.14) |
| external_payment_method | VARCHAR(50) | | e.g., 'CASH', 'BANK_TRANSFER' |
| external_payment_notes | VARCHAR(500) | | Court owner notes |
| no_show | BOOLEAN | NOT NULL DEFAULT FALSE | Court owner flagged as no-show (Req 14.10) |
| no_show_flagged_at | TIMESTAMPTZ | | When no-show was flagged |
| customer_name | VARCHAR(255) | | For manual bookings — free-text name |
| customer_phone | VARCHAR(50) | | For manual bookings — free-text phone |
| notes | TEXT | | Booking notes |
| recurring_group_id | UUID | | Links recurring booking instances |
| recurring_pattern | JSONB | | {dayOfWeek, startTime, endTime, startDate, endDate, weeksAhead} |
| cancelled_by | VARCHAR(15) | CHECK IN ('CUSTOMER','COURT_OWNER','SYSTEM') | |
| cancellation_reason | TEXT | | |
| cancelled_at | TIMESTAMPTZ | | |
| refund_amount_cents | INTEGER | | Refund amount on cancellation |
| confirmed_at | TIMESTAMPTZ | | When court owner confirmed (MANUAL mode) |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| updated_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_bookings_court_date` — on `(court_id, date)` — primary availability query
- `idx_bookings_user_id` — on `user_id`
- `idx_bookings_court_owner_id` — on `court_owner_id`
- `idx_bookings_status` — on `status`
- `idx_bookings_date` — on `date`
- `idx_bookings_recurring_group` — on `recurring_group_id` WHERE `recurring_group_id IS NOT NULL`
- `idx_bookings_idempotency` — UNIQUE on `idempotency_key`
- `idx_bookings_payment_status` — on `payment_status` WHERE `payment_status IN ('PENDING','AUTHORIZED')`
- `idx_bookings_pending_confirmation` — on `(court_owner_id, status)` WHERE `status = 'PENDING_CONFIRMATION'`

**Constraint:** `chk_bookings_manual_or_customer` — CHECK that if `booking_type = 'MANUAL'` then `payment_status IN ('NOT_REQUIRED','PAID_EXTERNALLY')` OR `user_id IS NOT NULL`

---

### `payments`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| booking_id | UUID | NOT NULL, FK → bookings(id) | |
| user_id | UUID | NOT NULL | Payer |
| amount_cents | INTEGER | NOT NULL | Gross amount in euro cents |
| platform_fee_cents | INTEGER | NOT NULL | Platform commission |
| court_owner_net_cents | INTEGER | NOT NULL | Net to court owner |
| currency | VARCHAR(3) | NOT NULL DEFAULT 'EUR' | |
| status | VARCHAR(20) | NOT NULL, CHECK IN ('PENDING','AUTHORIZED','CAPTURED','REFUNDED','PARTIALLY_REFUNDED','FAILED','DISPUTED') | |
| stripe_payment_intent_id | VARCHAR(255) | NOT NULL | |
| stripe_charge_id | VARCHAR(255) | | |
| stripe_transfer_id | VARCHAR(255) | | Stripe Connect transfer to court owner |
| stripe_refund_id | VARCHAR(255) | | |
| payment_method_type | VARCHAR(20) | | e.g., 'CARD', 'APPLE_PAY', 'GOOGLE_PAY' |
| refund_amount_cents | INTEGER | | |
| refund_reason | TEXT | | |
| refunded_at | TIMESTAMPTZ | | |
| failure_reason | TEXT | | Stripe error message |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| updated_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_payments_booking_id` — on `booking_id`
- `idx_payments_user_id` — on `user_id`
- `idx_payments_stripe_pi` — UNIQUE on `stripe_payment_intent_id`
- `idx_payments_status` — on `status`

---

### `audit_logs`

Booking lifecycle audit trail. Every status change, modification, or cancellation is recorded.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| booking_id | UUID | NOT NULL, FK → bookings(id) | |
| action | VARCHAR(30) | NOT NULL | e.g., 'CREATED', 'CONFIRMED', 'CANCELLED', 'MODIFIED', 'NO_SHOW_FLAGGED', 'PAYMENT_CAPTURED' |
| performed_by | UUID | | User who performed the action |
| performed_by_role | VARCHAR(20) | | 'CUSTOMER', 'COURT_OWNER', 'SYSTEM' |
| details | JSONB | | Action-specific data (before/after for modifications) |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_audit_logs_booking_id` — on `booking_id`
- `idx_audit_logs_created` — on `created_at`

**Note:** Append-only table. No UPDATE or DELETE.

---

### `notifications`

Notification delivery log. Tracks every notification sent to users.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| user_id | UUID | NOT NULL | Target user |
| notification_type | VARCHAR(50) | NOT NULL | Matches NOTIFICATION_REQUESTED.notificationType enum |
| channel | VARCHAR(10) | NOT NULL, CHECK IN ('PUSH','EMAIL','IN_APP','WEB_PUSH') | Delivery channel |
| title | VARCHAR(255) | NOT NULL | |
| body | TEXT | NOT NULL | |
| language | VARCHAR(5) | NOT NULL DEFAULT 'el', CHECK IN ('el','en') | Language used for this notification |
| data | JSONB | | Deep link and reference IDs |
| status | VARCHAR(15) | NOT NULL DEFAULT 'PENDING', CHECK IN ('PENDING','SENT','DELIVERED','FAILED','READ') | |
| read_at | TIMESTAMPTZ | | |
| failure_reason | TEXT | | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_notifications_user_id` — on `user_id`
- `idx_notifications_user_unread` — on `(user_id, status)` WHERE `status != 'READ'`
- `idx_notifications_type` — on `notification_type`
- `idx_notifications_created` — on `created_at`

---

### `device_tokens`

Push notification device registrations. Supports FCM (mobile) and Web Push API (browser).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| user_id | UUID | NOT NULL | |
| token | VARCHAR(500) | NOT NULL | FCM token or Web Push endpoint |
| platform | VARCHAR(10) | NOT NULL, CHECK IN ('IOS','ANDROID','WEB_PUSH') | |
| device_id | VARCHAR(255) | | Device identifier |
| push_subscription_endpoint | VARCHAR(500) | | Web Push API subscription endpoint (WEB_PUSH only) |
| push_subscription_keys | JSONB | | Web Push API keys {p256dh, auth} (WEB_PUSH only) |
| active | BOOLEAN | NOT NULL DEFAULT TRUE | Set false on FCM unregister or invalid token |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| updated_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_device_tokens_user_id` — on `user_id` WHERE `active = TRUE`
- `uq_device_tokens_token` — UNIQUE on `token`

---

### ⏳ `waitlists` — Phase 2 (Req 26)

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| court_id | UUID | NOT NULL | |
| user_id | UUID | NOT NULL | |
| date | DATE | NOT NULL | |
| start_time | TIME | NOT NULL | |
| end_time | TIME | NOT NULL | |
| status | VARCHAR(20) | NOT NULL DEFAULT 'WAITING', CHECK IN ('WAITING','NOTIFIED','HOLD_ACTIVE','BOOKED','EXPIRED','CANCELLED') | |
| position | INTEGER | NOT NULL | FIFO queue position |
| hold_expires_at | TIMESTAMPTZ | | Set when NOTIFIED → HOLD_ACTIVE |
| notified_at | TIMESTAMPTZ | | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_waitlists_court_slot` — on `(court_id, date, start_time)` WHERE `status IN ('WAITING','NOTIFIED','HOLD_ACTIVE')`
- `idx_waitlists_user_id` — on `user_id`
- `idx_waitlists_hold_expires` — on `hold_expires_at` WHERE `status = 'HOLD_ACTIVE'`

---

### ⏳ `open_matches` — Phase 2 (Req 24)

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| booking_id | UUID | NOT NULL, FK → bookings(id) | |
| court_id | UUID | NOT NULL | |
| creator_user_id | UUID | NOT NULL | |
| court_type | VARCHAR(20) | NOT NULL | |
| max_players | INTEGER | NOT NULL | |
| current_players | INTEGER | NOT NULL DEFAULT 1 | |
| skill_range_min | INTEGER | CHECK (BETWEEN 1 AND 7) | |
| skill_range_max | INTEGER | CHECK (BETWEEN 1 AND 7) | |
| auto_accept | BOOLEAN | NOT NULL DEFAULT FALSE | |
| cost_per_player_cents | INTEGER | NOT NULL | |
| status | VARCHAR(15) | NOT NULL DEFAULT 'OPEN', CHECK IN ('OPEN','FULL','CANCELLED','EXPIRED') | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| updated_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_open_matches_court_id` — on `court_id`
- `idx_open_matches_status` — on `status` WHERE `status = 'OPEN'`
- `idx_open_matches_court_type` — on `court_type` WHERE `status = 'OPEN'`

---

### ⏳ `match_players` — Phase 2

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| match_id | UUID | NOT NULL, FK → open_matches(id) ON DELETE CASCADE | |
| user_id | UUID | NOT NULL | |
| role | VARCHAR(10) | NOT NULL DEFAULT 'PLAYER', CHECK IN ('CREATOR','PLAYER') | |
| joined_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Primary Key:** `(match_id, user_id)`

---

### ⏳ `match_join_requests` — Phase 2

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| match_id | UUID | NOT NULL, FK → open_matches(id) ON DELETE CASCADE | |
| user_id | UUID | NOT NULL | |
| status | VARCHAR(15) | NOT NULL DEFAULT 'PENDING', CHECK IN ('PENDING','APPROVED','DECLINED','CANCELLED') | |
| message | TEXT | | Optional message from requester |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| responded_at | TIMESTAMPTZ | | |

**Indexes:**
- `idx_match_join_requests_match` — on `match_id`
- `idx_match_join_requests_user` — on `user_id`

---

### ⏳ `match_messages` — Phase 2

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| match_id | UUID | NOT NULL, FK → open_matches(id) ON DELETE CASCADE | |
| user_id | UUID | NOT NULL | |
| body | TEXT | NOT NULL | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_match_messages_match` — on `match_id`

---

### ⏳ `split_payments` — Phase 2 (Req 25)

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| booking_id | UUID | NOT NULL, FK → bookings(id) | |
| initiator_user_id | UUID | NOT NULL | |
| total_amount_cents | INTEGER | NOT NULL | |
| per_share_cents | INTEGER | NOT NULL | |
| total_shares | INTEGER | NOT NULL | |
| paid_shares | INTEGER | NOT NULL DEFAULT 0 | |
| status | VARCHAR(20) | NOT NULL DEFAULT 'PENDING', CHECK IN ('PENDING','PARTIALLY_PAID','FULLY_PAID','EXPIRED','CANCELLED') | |
| deadline | TIMESTAMPTZ | NOT NULL | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |
| updated_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_split_payments_booking` — on `booking_id`
- `idx_split_payments_status` — on `status` WHERE `status IN ('PENDING','PARTIALLY_PAID')`

---

### ⏳ `split_payment_shares` — Phase 2

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | UUID | PK, DEFAULT gen_random_uuid() | |
| split_payment_id | UUID | NOT NULL, FK → split_payments(id) ON DELETE CASCADE | |
| user_id | UUID | NOT NULL | |
| amount_cents | INTEGER | NOT NULL | |
| status | VARCHAR(15) | NOT NULL DEFAULT 'PENDING', CHECK IN ('PENDING','PAID','FAILED','EXPIRED') | |
| stripe_payment_intent_id | VARCHAR(255) | | |
| paid_at | TIMESTAMPTZ | | |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW() | |

**Indexes:**
- `idx_split_shares_split_id` — on `split_payment_id`
- `idx_split_shares_user` — on `user_id`

---

### `scheduled_jobs`

Quartz Scheduler JDBC job store tables. Transaction Service uses clustered Quartz for:
- Pending booking confirmation timeouts
- Split payment deadlines (Phase 2)
- Waitlist slot hold expiration (Phase 2)
- Recurring booking creation (weekly advance)
- Booking reminders
- No-show auto-flag window
- Payment reconciliation (daily — reconciles payment state between platform and Stripe)

Standard Quartz tables (`QRTZ_JOB_DETAILS`, `QRTZ_TRIGGERS`, `QRTZ_CRON_TRIGGERS`, `QRTZ_SIMPLE_TRIGGERS`, `QRTZ_FIRED_TRIGGERS`, `QRTZ_LOCKS`, etc.) are created by Quartz's built-in DDL scripts for PostgreSQL.

Configuration: `org.quartz.jobStore.isClustered=true`, `org.quartz.jobStore.driverDelegateClass=org.quartz.impl.jdbcjobstore.PostgreSQLDelegate`

---

## Cross-Schema Views

Transaction Service has READ-ONLY access to Platform schema via these views. Created by Platform Service's Flyway migrations, granted SELECT to Transaction Service's database role.

### `v_court_summary`

```sql
CREATE VIEW platform.v_court_summary AS
SELECT
    id,
    owner_id,
    name_el,
    name_en,
    court_type,
    location_type,
    location,
    timezone,
    base_price_cents,
    duration_minutes,
    max_capacity,
    confirmation_mode,
    confirmation_timeout_hours,
    waitlist_enabled,
    visible,
    version
FROM platform.courts
WHERE visible = TRUE;

GRANT SELECT ON platform.v_court_summary TO transaction_service_role;
```

### `v_user_basic`

```sql
CREATE VIEW platform.v_user_basic AS
SELECT
    id,
    email,
    name,
    phone,
    role,
    language,
    stripe_connect_account_id,
    stripe_connect_status,
    stripe_customer_id,
    vat_registered,
    vat_number,
    status
FROM platform.users
WHERE status = 'ACTIVE';

GRANT SELECT ON platform.v_user_basic TO transaction_service_role;
```

### `v_court_cancellation_tiers`

```sql
CREATE VIEW platform.v_court_cancellation_tiers AS
SELECT
    court_id,
    threshold_hours,
    refund_percent,
    sort_order
FROM platform.cancellation_tiers
ORDER BY court_id, sort_order;

GRANT SELECT ON platform.v_court_cancellation_tiers TO transaction_service_role;
```

### `v_user_skill_level`

```sql
CREATE VIEW platform.v_user_skill_level AS
SELECT
    user_id,
    court_type,
    level
FROM platform.skill_levels;

GRANT SELECT ON platform.v_user_skill_level TO transaction_service_role;
```

---

## Entity-Relationship Summary

### Platform Schema Relationships

```
users (1) ──── (N) oauth_providers
users (1) ──── (N) refresh_tokens
users (1) ──── (N) courts                    [owner_id]
users (1) ──── (N) verification_requests     [court_owner_id]
users (1) ──── (N) court_owner_audit_logs    [court_owner_id]
users (1) ──── (N) reminder_rules            [court_owner_id]
users (1) ──── (1) court_owner_notification_preferences  [per event_type]
users (1) ──── (1) court_defaults            [court_owner_id]
users (1) ──── (N) favorites
users (1) ──── (1) preferences
users (1) ──── (N) skill_levels
users (1) ──── (N) support_tickets
users (1) ──── (N) promo_codes               [⏳ Phase 2]
users (1) ──── (N) security_alerts            [user_id, acknowledged_by, resolved_by]
users (1) ──── (N) ip_blocklist               [blocked_by]

courts (1) ──── (N) availability_windows
courts (1) ──── (N) availability_overrides
courts (1) ──── (N) pricing_rules
courts (1) ──── (N) cancellation_tiers
courts (1) ──── (N) court_ratings            [⏳ Phase 2]
courts (1) ──── (N) special_date_pricing     [⏳ Phase 2]
courts (1) ──── (N) court_owner_audit_logs
courts (1) ──── (N) reminder_rules

security_alerts (1) ──── (0..1) ip_blocklist  [related_alert_id]

support_tickets (1) ──── (N) support_messages
support_messages (1) ──── (N) support_attachments
```

### Transaction Schema Relationships

```
bookings (1) ──── (N) payments
bookings (1) ──── (N) audit_logs
bookings (1) ──── (1) open_matches           [⏳ Phase 2]
bookings (1) ──── (1) split_payments         [⏳ Phase 2]

open_matches (1) ──── (N) match_players      [⏳ Phase 2]
open_matches (1) ──── (N) match_join_requests [⏳ Phase 2]
open_matches (1) ──── (N) match_messages      [⏳ Phase 2]

split_payments (1) ──── (N) split_payment_shares [⏳ Phase 2]
```

### Cross-Schema References (conceptual, not enforced by FK)

```
transaction.bookings.court_id       → platform.courts.id
transaction.bookings.user_id        → platform.users.id
transaction.bookings.court_owner_id → platform.users.id
transaction.notifications.user_id   → platform.users.id
transaction.device_tokens.user_id   → platform.users.id
transaction.waitlists.court_id      → platform.courts.id
transaction.waitlists.user_id       → platform.users.id
```

---

## Migration Strategy

- **Flyway** manages migrations per service, per schema
- Platform Service: `db/migration/platform/V{version}__{description}.sql`
- Transaction Service: `db/migration/transaction/V{version}__{description}.sql`
- Phase 2 tables are created in initial migrations (empty) to avoid ALTER TABLE later
- Cross-schema views are created by Platform Service migrations
- Quartz tables are created by Transaction Service using Quartz's built-in PostgreSQL DDL
- All migrations run in CI pipeline (`flyway validate` on PR, `flyway migrate` on deploy)
