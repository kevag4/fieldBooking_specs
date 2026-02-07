# API Contracts

OpenAPI 3.1 specifications defining the REST API contracts between frontend and backend services.

These files are the **single source of truth** for API interfaces. All services and clients generate code from these specs.

## Files

| File | Service | Description |
|------|---------|-------------|
| `openapi-platform-service.yaml` | Platform Service | Auth, users, courts, availability, weather, analytics, support, admin |
| `openapi-transaction-service.yaml` | Transaction Service | Bookings, payments, notifications, waitlist, matches, split payments |

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

## Editing

1. Edit the spec file first
2. Get PR review
3. Regenerate client code
4. Implement backend changes
5. CI validates contract compliance
