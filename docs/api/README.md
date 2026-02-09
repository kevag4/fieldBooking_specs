# API Contracts

OpenAPI 3.1 specifications defining the REST API contracts between frontend and backend services.

These files are the **single source of truth** for API interfaces. All services and clients generate code from these specs.

## Files

| File | Service | Description |
|------|---------|-------------|
| `openapi-platform-service.yaml` | Platform Service | Auth, users, courts, availability, weather, analytics, support, admin |
| `openapi-transaction-service.yaml` | Transaction Service | Bookings, payments, notifications, waitlist, matches, split payments |
| `kafka-event-contracts.json` | Both | Kafka event schemas for async communication between services |
| `websocket-message-contracts.json` | Transaction Service | WebSocket message schemas for real-time client communication |

## Usage

### Backend (Spring Boot)
Services use `springdoc-openapi` to validate implementations match these contracts.

### Flutter Mobile App
```bash
openapi-generator generate -i openapi-platform-service.yaml -g dart -o ../../court-booking-mobile-app/lib/api/platform
openapi-generator generate -i openapi-transaction-service.yaml -g dart -o ../../court-booking-mobile-app/lib/api/transaction
```

### React Admin Web
```bash
openapi-generator generate -i openapi-platform-service.yaml -g typescript-fetch -o ../../court-booking-admin-web/src/api/platform
openapi-generator generate -i openapi-transaction-service.yaml -g typescript-fetch -o ../../court-booking-admin-web/src/api/transaction
```

## Kafka Event Contracts

`kafka-event-contracts.json` defines the async event schemas exchanged between services via Upstash Kafka.

### Topics

| Topic | Partition Key | Producer | Consumer(s) | Purpose |
|-------|--------------|----------|-------------|---------|
| `booking-events` | `courtId` | Transaction Service | Platform Service | Availability cache invalidation, WebSocket broadcasts |
| `notification-events` | `userId` | Transaction Service | Transaction Service | Notification dispatch (FCM, WebSocket, SendGrid) |
| `court-update-events` | `courtId` | Platform Service | Transaction Service | Pricing/availability/policy sync, Stripe Connect status |
| `match-events` | `matchId` | Transaction Service | Platform Service | Open match map display updates |
| `waitlist-events` | `courtId` | Transaction Service | Transaction Service | Waitlist FIFO processing on cancellations |
| `analytics-events` | `courtId` | Both | Platform Service | Dashboard metrics, revenue tracking |

### Event Envelope

Every Kafka message value follows a common envelope with `eventId`, `eventType`, `source`, `timestamp`, `traceId`, `spanId`, and `payload`. The `traceId` enables end-to-end distributed tracing across async boundaries.

### Shared Library

Event schemas are implemented as Java classes in `court-booking-common` and published to GitHub Packages. Both services depend on this library for serialization/deserialization.

## WebSocket Message Contracts

`websocket-message-contracts.json` defines the real-time message schemas exchanged between Transaction Service and connected clients (mobile app, admin web) via STOMP over WebSocket.

### Connection

- Endpoint: `/ws?token=<jwt>`
- Protocol: STOMP over WebSocket (SockJS fallback)
- Scaling: Redis Pub/Sub across Transaction Service pods

### STOMP Destinations

| Destination | Direction | Auth | Description |
|-------------|-----------|------|-------------|
| `/topic/courts/{courtId}/availability` | Server → Client | Any authenticated user | Real-time slot availability updates |
| `/user/queue/bookings` | Server → Client | Booking customer or court owner | Booking status changes |
| `/user/queue/notifications` | Server → Client | Authenticated user (own only) | In-app notifications |
| `/topic/courts/{courtId}/matches` | Server → Client | Any authenticated user | Open match updates (Phase 2) |
| `/user/queue/matches` | Server → Client | Match participants only | Personal match updates (Phase 2) |
| `/user/queue/system` | Server → Client | All connections | Token expiry, shutdown, errors |
| `/app/token-refresh` | Client → Server | Authenticated user | Refresh JWT without reconnecting |

### Message Types

**Server → Client:** `AVAILABILITY_UPDATE`, `AVAILABILITY_SNAPSHOT`, `BOOKING_STATUS_UPDATE`, `NOTIFICATION`, `MATCH_UPDATE`, `TOKEN_EXPIRING`, `SERVER_SHUTDOWN`, `ERROR`

**Client → Server:** `TOKEN_REFRESH`

## Editing

1. Edit the spec file first
2. Get PR review
3. Regenerate client code
4. Implement backend changes
5. CI validates contract compliance
