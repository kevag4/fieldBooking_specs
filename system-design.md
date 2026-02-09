# Court Booking Platform — System Design Blueprint

## 1. System Overview

The Court Booking Platform is a multi-tenant sports court reservation system serving three user types through two frontend applications backed by two microservices. The platform enables court owners to manage sports facilities while customers discover, book, and pay for court reservations.

```
┌─────────────────────────────────────────────────────────────────────┐
│                        CLIENT LAYER                                 │
│                                                                     │
│   ┌─────────────────────┐          ┌─────────────────────────┐     │
│   │   Mobile App         │          │   Admin Web Portal       │     │
│   │   (Flutter)          │          │   (React)                │     │
│   │                      │          │                          │     │
│   │   • Court discovery  │          │   • Court management     │     │
│   │   • Booking flow     │          │   • Booking management   │     │
│   │   • Payments         │          │   • Analytics/revenue    │     │
│   │   • Open matches     │          │   • Pricing/policies     │     │
│   │   • Notifications    │          │   • Support management   │     │
│   │   • Support tickets  │          │                          │     │
│   └────────┬────────────┘          └────────────┬─────────────┘     │
│            │                                     │                   │
└────────────┼─────────────────────────────────────┼───────────────────┘
             │          HTTPS / WSS                │
             ▼                                     ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     INGRESS LAYER                                   │
│                                                                     │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │   DigitalOcean Load Balancer + NGINX Ingress Controller     │   │
│   │   • SSL termination (Let's Encrypt)                         │   │
│   │   • Path-based routing                                      │   │
│   │   • Rate limiting                                           │   │
│   │   • JWT presence check                                      │   │
│   └──────────────┬──────────────────────────┬───────────────────┘   │
│                  │                          │                        │
└──────────────────┼──────────────────────────┼────────────────────────┘
                   │                          │
                   ▼                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   APPLICATION LAYER (DOKS)                          │
│                                                                     │
│   ┌─────────────────────┐          ┌─────────────────────────┐     │
│   │  Platform Service    │          │  Transaction Service     │     │
│   │  (Spring Boot)       │◄────────►│  (Spring Boot)           │     │
│   │                      │ internal │                          │     │
│   │  Auth, Users, Courts │  HTTP    │  Bookings, Payments,     │     │
│   │  Weather, Analytics  │          │  Notifications, Waitlist │     │
│   │  Support, Flags      │          │  Matches, Split Pay      │     │
│   └──────────┬───────────┘          └──────────┬──────────────┘     │
│              │                                  │                    │
└──────────────┼──────────────────────────────────┼────────────────────┘
               │                                  │
               ▼                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      DATA LAYER                                     │
│                                                                     │
│   ┌──────────────┐  ┌────────┐  ┌──────────┐  ┌────────────────┐  │
│   │ PostgreSQL    │  │ Redis  │  │ Upstash  │  │ DO Spaces      │  │
│   │ + PostGIS     │  │ 2GB    │  │ Kafka    │  │ (S3-compat)    │  │
│   │               │  │        │  │          │  │                │  │
│   │ • platform    │  │ Cache  │  │ 6 topics │  │ Court images   │  │
│   │   schema      │  │ Queues │  │ 20 event │  │ Attachments    │  │
│   │ • transaction │  │ PubSub │  │ types    │  │ Assets         │  │
│   │   schema      │  │ Flags  │  │          │  │                │  │
│   └──────────────┘  └────────┘  └──────────┘  └────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## 2. Frontend Applications

### Mobile App (Flutter) — `court-booking-mobile-app`

Target users: Customers (CUSTOMER role)

| Capability | Backend Service | Protocol |
|------------|----------------|----------|
| OAuth login + biometric auth | Platform Service | REST |
| Court search (map, filters, geospatial) | Platform Service | REST |
| Weather forecast display | Platform Service | REST |
| Favorites and preferences | Platform Service | REST |
| Booking creation and management | Transaction Service | REST |
| Payments (Stripe, Apple Pay, Google Pay) | Transaction Service | REST |
| Open match join/create | Transaction Service | REST |
| Waitlist join | Transaction Service | REST |
| Split payments | Transaction Service | REST |
| Real-time availability updates | Transaction Service | WebSocket |
| Push notifications | Transaction Service | FCM |
| In-app notifications | Transaction Service | WebSocket |
| Support tickets + diagnostic logs | Platform Service | REST |

### Admin Web Portal (React) — `court-booking-admin-web`

Target users: Court Owners (COURT_OWNER role), Platform Admins (PLATFORM_ADMIN role)

| Capability | Backend Service | Protocol |
|------------|----------------|----------|
| OAuth login | Platform Service | REST |
| Court CRUD + availability management | Platform Service | REST |
| Court verification (admin) | Platform Service | REST |
| Stripe Connect onboarding | Platform Service | REST (redirect to Stripe) |
| Booking calendar + confirm/reject | Transaction Service | REST |
| Manual booking creation | Transaction Service | REST |
| Analytics and revenue dashboards | Platform Service | REST (read replica) |
| Dynamic pricing configuration | Platform Service | REST |
| Cancellation policy management | Platform Service | REST |
| Promo code management | Platform Service | REST |
| Feature flag management (admin) | Platform Service | REST |
| User management (admin) | Platform Service | REST |
| Support ticket management (admin) | Platform Service | REST |
| Real-time booking updates | Transaction Service | WebSocket |

## 3. API Routing

NGINX Ingress routes requests by URL path prefix:

```
                    ┌─────────────────────────────────┐
                    │       NGINX Ingress              │
                    │       (path-based routing)       │
                    └───────────┬──────────────────────┘
                                │
            ┌───────────────────┼───────────────────────┐
            │                   │                       │
            ▼                   ▼                       ▼
   Platform Service    Transaction Service      Transaction Service
                                                   (WebSocket)
   /api/auth/*          /api/bookings/*
   /api/users/*         /api/payments/*            /ws/*
   /api/courts/*        /api/notifications/*
   /api/weather/*       /api/waitlist/*
   /api/analytics/*     /api/matches/*
   /api/promo-codes/*   /api/split-payments/*
   /api/feature-flags/*
   /api/admin/*
   /api/support/*
```

Both services validate JWT tokens independently using a shared RS256 public key. NGINX performs initial token presence check; services do full signature verification, expiration, and role-based authorization.

## 4. Service Interaction Patterns

### Synchronous (REST)

```
Mobile App ──REST──► NGINX ──► Platform Service
                           ──► Transaction Service

Admin Web  ──REST──► NGINX ──► Platform Service
                           ──► Transaction Service

Transaction Service ──internal HTTP──► Platform Service
  (court validation, pricing rules, player skill levels)
  Auth: mTLS via Istio (staging/prod), API key (dev/test)
```

### Asynchronous (Kafka Events)

Formal event schemas are defined in [`docs/api/kafka-event-contracts.json`](docs/api/kafka-event-contracts.json) — the single source of truth for all async interfaces. Both services share event classes via `court-booking-common`.

```
┌────────────────────┐                    ┌────────────────────┐
│ Transaction Service │                    │ Platform Service    │
│                     │                    │                     │
│  booking-events ────┼──► Kafka ────────►─┤  cache invalidation │
│  notification-events┼──► Kafka ──► FCM   │  availability update│
│  waitlist-events ───┼──► Kafka           │                     │
│  match-events ──────┼──► Kafka ────────►─┤  map display update │
│                     │                    │                     │
│                     │    Kafka ◄─────────┤  court-update-events│
│  pricing/policy ◄───┤                    │  (pricing, avail,   │
│  cache update       │    Kafka ◄─────────┤   policy, deletion) │
│                     │                    │  analytics-events   │
└────────────────────┘                    └────────────────────┘
```

#### Topics and Partitioning

| Topic | Partition Key | Producer | Consumer(s) | Events | Purpose |
|-------|--------------|----------|-------------|--------|---------|
| `booking-events` | `courtId` | Transaction | Platform | BOOKING_CREATED, BOOKING_CONFIRMED, BOOKING_CANCELLED, BOOKING_MODIFIED, BOOKING_COMPLETED, SLOT_HELD, SLOT_RELEASED | Availability cache invalidation, WebSocket broadcasts |
| `notification-events` | `userId` | Transaction | Transaction | NOTIFICATION_REQUESTED | Notification dispatch routing (FCM, WebSocket, SendGrid, email) |
| `court-update-events` | `courtId` | Platform | Transaction | COURT_UPDATED, PRICING_UPDATED, AVAILABILITY_UPDATED, CANCELLATION_POLICY_UPDATED, COURT_DELETED | Pricing/availability/policy sync to Transaction Service |
| `match-events` | `matchId` | Transaction | Platform | MATCH_CREATED, MATCH_UPDATED, MATCH_CLOSED | Open match map display and search index updates |
| `waitlist-events` | `courtId` | Transaction | Transaction | WAITLIST_SLOT_FREED, WAITLIST_HOLD_EXPIRED | FIFO waitlist processing on cancellations |
| `analytics-events` | `courtId` | Both | Platform | BOOKING_ANALYTICS, REVENUE_ANALYTICS, PROMO_CODE_REDEEMED | Dashboard metrics, revenue tracking, promo code usage |

#### Event Envelope

Every Kafka message value follows a common envelope schema:

```json
{
  "eventId": "uuid — consumer-side idempotency key",
  "eventType": "discriminator — determines payload schema",
  "source": "platform-service | transaction-service",
  "timestamp": "ISO 8601 UTC",
  "traceId": "W3C Trace Context ID (Req 16.7)",
  "spanId": "OpenTelemetry span ID",
  "correlationId": "optional — links related events across topics",
  "payload": { }
}
```

- `eventId` enables consumer-side deduplication (at-least-once delivery with Upstash Kafka)
- `traceId` / `spanId` enable end-to-end distributed tracing across async boundaries
- `correlationId` links related events (e.g., a booking cancellation → waitlist slot freed → notification)

### Real-Time (WebSocket + Redis Pub/Sub)

```
┌──────────┐    WSS     ┌─────────────────────────────────────┐
│ Mobile   │◄──────────►│  Transaction Service (Pod 1)        │
│ App      │            │       │                              │
└──────────┘            │       ▼                              │
                        │  Redis Pub/Sub ◄──► Pod 2, Pod 3... │
┌──────────┐    WSS     │       │                              │
│ Admin    │◄──────────►│       ▼                              │
│ Web      │            │  Broadcasts: availability updates,   │
└──────────┘            │  booking status, match events,       │
                        │  in-app notifications                │
                        └─────────────────────────────────────┘
```

### Scheduled Jobs (Quartz in Transaction Service)

- Pending booking confirmation timeouts
- Split payment deadlines
- Waitlist slot hold expiration
- Recurring booking creation (weekly advance)
- Booking reminders
- Clustered via JDBC job store (`isClustered=true`)

## 5. Data Ownership

Shared PostgreSQL instance, separate schemas with strict write boundaries:

```
┌─────────────────────────────────────────────────────────────┐
│                    PostgreSQL + PostGIS                       │
│                                                              │
│  ┌──────────────────────┐    ┌────────────────────────────┐ │
│  │  platform schema      │    │  transaction schema         │ │
│  │  (owned by Platform)  │    │  (owned by Transaction)     │ │
│  │                       │    │                             │ │
│  │  users                │    │  bookings                   │ │
│  │  roles                │    │  payments                   │ │
│  │  refresh_tokens       │    │  notifications              │ │
│  │  courts               │    │  device_tokens              │ │
│  │  availability_windows │    │  audit_logs                 │ │
│  │  favorites            │    │  waitlists                  │ │
│  │  preferences          │    │  open_matches               │ │
│  │  oauth_providers      │    │  split_payments             │ │
│  │  skill_levels         │    │  scheduled_jobs             │ │
│  │  court_ratings        │    │                             │ │
│  │  promo_codes          │    │                             │ │
│  │  pricing_rules        │    │                             │ │
│  │  translations         │    │                             │ │
│  │  feature_flags        │    │                             │ │
│  │  support_tickets      │    │                             │ │
│  │  support_messages     │    │                             │ │
│  │  support_attachments  │    │                             │ │
│  └──────────────────────┘    └────────────────────────────┘ │
│                                                              │
│  Cross-schema: Transaction has READ-ONLY access to Platform  │
│  via database views (v_court_summary, v_user_basic)          │
│                                                              │
│  Read replica used by Platform Service for analytics queries │
└─────────────────────────────────────────────────────────────┘
```

## 6. External Service Integration

```
┌──────────────────┐     ┌──────────────────────────────────────────┐
│ Platform Service  │────►│ OAuth Providers (Google, Facebook, Apple) │
│                   │────►│ OpenWeatherMap (forecast data)            │
└──────────────────┘     └──────────────────────────────────────────┘

┌──────────────────┐     ┌──────────────────────────────────────────┐
│ Transaction       │────►│ Stripe (payments, Connect, webhooks)     │
│ Service           │────►│ SendGrid (email notifications)           │
│                   │────►│ Firebase Cloud Messaging (push notifs)   │
└──────────────────┘     └──────────────────────────────────────────┘
```

## 7. Authentication and Authorization Flow

```
┌────────┐   1. OAuth login    ┌──────────────┐   2. Validate    ┌──────────┐
│ Client │ ──────────────────► │ Platform     │ ◄──────────────► │ OAuth    │
│        │                     │ Service      │                   │ Provider │
│        │ ◄────────────────── │              │                   └──────────┘
│        │   3. JWT access     │              │
│        │      + refresh      └──────────────┘
│        │
│        │   4. API request    ┌──────────────┐
│        │   (Bearer token)    │ Any Service  │
│        │ ──────────────────► │              │
│        │                     │ 5. Validate  │
│        │                     │    JWT sig   │
│        │                     │    + role    │
│        │ ◄────────────────── │    + claims  │
│        │   6. Response       └──────────────┘
└────────┘
```

- Access tokens: 15-min lifetime, RS256 signed, validated independently by both services
- Refresh tokens: 30-day lifetime, server-side storage, rotation with replay detection
- Biometric auth: refresh token stored in device secure enclave, gated by fingerprint/face ID
- Three roles: CUSTOMER, COURT_OWNER (with sub-states), PLATFORM_ADMIN

## 8. Infrastructure Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                    DigitalOcean (FRA1 Region)                    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Shared DOKS Cluster (dev / test / staging)                 │ │
│  │  2-4 nodes × 4GB RAM, auto-scaling                          │ │
│  │                                                              │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────────────────────┐  │ │
│  │  │ dev ns   │  │ test ns  │  │ staging ns               │  │ │
│  │  │ 1 replica│  │ 1 replica│  │ 3 replicas + Istio       │  │ │
│  │  └──────────┘  └──────────┘  └──────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Production DOKS Cluster (dedicated)                        │ │
│  │  3-6 nodes × 8GB RAM, auto-scaling + Istio                 │ │
│  │  + dedicated observability node pool                        │ │
│  │                                                              │ │
│  │  ┌──────────────────────────────────────────────────────┐   │ │
│  │  │ Platform Service (3 pods) + Transaction Service (3)  │   │ │
│  │  │ Prometheus + Grafana + Jaeger + Loki + Kiali         │   │ │
│  │  └──────────────────────────────────────────────────────┘   │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌──────────────┐  ┌────────┐  ┌──────────┐  ┌──────────────┐ │
│  │ Managed PG   │  │Managed │  │ Spaces   │  │ Container    │ │
│  │ + PostGIS    │  │ Redis  │  │ (CDN)    │  │ Registry     │ │
│  │ + replica    │  │        │  │          │  │              │ │
│  └──────────────┘  └────────┘  └──────────┘  └──────────────┘ │
│                                                                  │
│  Upstash Kafka (serverless, external)                           │
└─────────────────────────────────────────────────────────────────┘
```

## 9. CI/CD and Deployment Pipeline

```
Developer ──► GitHub PR ──► GitHub Actions Pipeline:

  ┌─────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
  │ Lint    │───►│ Test     │───►│ Scan     │───►│ Docker   │
  │ Check   │    │ Unit     │    │ Trivy    │    │ Build    │
  │         │    │ PBT      │    │ OWASP    │    │ Push     │
  └─────────┘    │ Integr.  │    │ Sonar    │    └────┬─────┘
                 │ Flyway   │    └──────────┘         │
                 │ validate │                         ▼
                 └──────────┘                  ┌──────────────┐
                                               │ PR Approved  │
                                               │ Merge to     │
                                               │ develop      │
                                               └──────┬───────┘
                                                      │
  ┌──────────────────────────────────────────────────┐│
  │           Progressive Deployment                  ││
  │                                                   ▼│
  │  ┌──────────┐    ┌──────────┐    ┌─────────────┐ │
  │  │ Deploy   │───►│ Deploy   │───►│ QA Func.    │ │
  │  │ dev      │    │ test     │    │ Regression  │ │
  │  │ (auto)   │    │ (auto)   │    │ (repo_disp.)│ │
  │  └──────────┘    └──────────┘    └──────┬──────┘ │
  │                                         │ pass   │
  │  ┌──────────┐    ┌──────────┐    ┌──────▼──────┐ │
  │  │ Tag      │◄───│ QA Stress│◄───│ Deploy      │ │
  │  │ rc-v1.x  │    │ Suite    │    │ staging     │ │
  │  │          │    │ (Locust) │    │ + Smoke     │ │
  │  └────┬─────┘    └──────────┘    └─────────────┘ │
  │       │                                           │
  └───────┼───────────────────────────────────────────┘
          │
          ▼
  ┌──────────────┐
  │ Deploy prod  │
  │ (manual)     │
  │ Tag v1.x     │
  │ + Smoke      │
  └──────────────┘
```

## 10. Repository Map

| Repository | Tech Stack | Purpose |
|------------|-----------|---------|
| `court-booking-platform-service` | Spring Boot, Java 21 | Auth, users, courts, weather, analytics, support |
| `court-booking-transaction-service` | Spring Boot, Java 21 | Bookings, payments, notifications, waitlist, matches |
| `court-booking-mobile-app` | Flutter (Dart) | iOS, Android, Web customer app |
| `court-booking-admin-web` | React, TypeScript | Court owner + platform admin portal |
| `court-booking-qa` | pytest, Locust, Playwright, Patrol | Functional, stress, contract, UI tests |
| `court-booking-infrastructure` | Terraform, Kubernetes, Helm | DigitalOcean provisioning, K8s manifests, Istio |
| `court-booking-common` | Java 21 | Shared DTOs, Kafka event envelope + payload classes, exceptions |

## 11. Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Cloud provider | DigitalOcean | Cost-effective for MVP, managed K8s/PG/Redis |
| Service split | 2 services (Platform + Transaction) | Clear domain boundaries, independent scaling |
| Event streaming | Upstash Kafka (serverless) | Zero ops for MVP, migration path to Strimzi |
| Payments | Stripe Connect Express | Marketplace payouts, hosted onboarding |
| Mobile framework | Flutter | Single codebase for iOS, Android, Web |
| Admin framework | React | Rich ecosystem, TypeScript support |
| Service mesh | Istio (staging + prod only) | mTLS, traffic management, observability |
| Database | Single PG instance, separate schemas | Cost-effective, cross-schema views for reads |
| Real-time | WebSocket + Redis Pub/Sub | Horizontal scaling across pods |
| API contracts | OpenAPI 3.1 + Kafka JSON Schema (contract-first) | Code generation for clients, CI validation. See [`docs/api/`](docs/api/README.md) |
