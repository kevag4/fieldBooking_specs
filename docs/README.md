# Court Booking Platform — Documentation

## Workspace Structure

This is the root workspace containing specifications, shared documentation, and references to all component repositories.

```
court-booking/
├── .kiro/specs/                    # Feature specifications (requirements, design, tasks)
├── docs/
│   ├── api/                        # OpenAPI specs (source of truth for all API contracts)
│   │   ├── openapi-platform-service.yaml
│   │   └── openapi-transaction-service.yaml
│   └── README.md
├── scripts/                        # Shared scripts (DB init, etc.)
├── docker-compose.yml              # Local dev infrastructure (PostgreSQL, Redis, Kafka)
├── court-booking.code-workspace    # VS Code multi-root workspace
│
├── court-booking-platform-service/ # Spring Boot — auth, users, courts, analytics
├── court-booking-transaction-service/ # Spring Boot — bookings, payments, notifications
├── court-booking-mobile-app/       # Flutter — iOS, Android, Web
├── court-booking-admin-web/        # React — court owner admin portal
├── court-booking-qa/               # pytest, Locust, Playwright, contract tests
├── court-booking-infrastructure/   # Terraform, Kubernetes, Istio
└── court-booking-common/           # Shared Java library (DTOs, events, exceptions)
```

## Getting Started

1. Open `court-booking.code-workspace` in VS Code / Kiro
2. Run `docker-compose up -d` to start local infrastructure
3. Start the backend services with `local` Spring profile
4. Start the mobile app or admin web with local API endpoints

## Key Documents

- **Requirements**: `.kiro/specs/court-booking-platform/requirements.md`
- **Design**: `.kiro/specs/court-booking-platform/design.md`
- **Tasks**: `.kiro/specs/court-booking-platform/tasks.md`
- **Platform API**: `docs/api/openapi-platform-service.yaml`
- **Transaction API**: `docs/api/openapi-transaction-service.yaml`
