# API Contracts

OpenAPI 3.1 specifications defining the REST API contracts between frontend and backend services.

These files are the **single source of truth** for API interfaces. All services and clients generate code from these specs.

## Files

| File | Service | Description |
|------|---------|-------------|
| `openapi-platform-service.yaml` | Platform Service | Auth, users, courts, availability, weather, analytics, support, admin |
| `openapi-transaction-service.yaml` | Transaction Service | Bookings, payments, notifications, waitlist, matches, split payments |
| `kafka-event-contracts.json` | Both | Kafka event schemas for async communication between services |

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
| `court-update-events` | `courtId` | Platform Service | Transaction Service | Pricing/availability/policy sync |
| `match-events` | `matchId` | Transaction Service | Platform Service | Open match map display updates |
| `waitlist-events` | `courtId` | Transaction Service | Transaction Service | Waitlist FIFO processing on cancellations |
| `analytics-events` | `courtId` | Both | Platform Service | Dashboard metrics, revenue tracking |

### Event Envelope

Every Kafka message value follows a common envelope with `eventId`, `eventType`, `source`, `timestamp`, `traceId`, `spanId`, and `payload`. The `traceId` enables end-to-end distributed tracing across async boundaries.

### Shared Library

Event schemas are implemented as Java classes in `court-booking-common` and published to GitHub Packages. Both services depend on this library for serialization/deserialization.

## Editing

1. Edit the spec file first
2. Get PR review
3. Regenerate client code
4. Implement backend changes
5. CI validates contract compliance
