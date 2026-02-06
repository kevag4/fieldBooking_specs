---
inclusion: manual
---

# Spring Boot 3.x & Java 21+ Microservice Architecture Context

> When designing or implementing any Spring Boot microservice in this project, follow the patterns and standards in this document. It codifies the hexagonal architecture from Buckpal (thombergs), the testing rigor from rieckpil's Masterclass, and operational best practices from Spring PetClinic Microservices and abhisheksr01's best-practices repo.

## 1. Hexagonal Architecture (Ports & Adapters)

### Layer Separation

```
┌─────────────────────────────────────────┐
│         Infrastructure Layer            │
│  (Adapters: Web, Persistence, External) │
├─────────────────────────────────────────┤
│         Application Layer               │
│    (Use Cases, Ports/Interfaces)        │
├─────────────────────────────────────────┤
│           Domain Layer                  │
│  (Entities, Value Objects, Logic)       │
└─────────────────────────────────────────┘
```

### Dependency Rules

| Direction | Allowed? |
|-----------|----------|
| Domain → Nothing (pure Java) | ✅ |
| Application → Domain | ✅ |
| Adapter → Application + Domain | ✅ |
| Domain → Application | ❌ |
| Domain → Adapter | ❌ |
| Application → Adapter | ❌ |

### Package Structure (Buckpal Style)

```
src/main/java/com/company/bookingplatform/
├── domain/                          # Pure business logic — NO framework imports
│   ├── model/
│   │   ├── Booking.java            # Entity (rich, with business methods)
│   │   ├── BookingId.java          # Value Object (Record)
│   │   ├── BookingStatus.java      # Enum
│   │   ├── DateRange.java          # Value Object (Record)
│   │   └── Money.java              # Value Object (Record)
│   ├── exception/
│   │   └── BookingConflictException.java
│   └── service/
│       └── BookingDomainService.java  # Cross-entity domain logic
│
├── application/                     # Use Cases & Ports
│   ├── port/
│   │   ├── in/                     # Incoming Ports (Use Case interfaces)
│   │   │   ├── CreateBookingUseCase.java
│   │   │   ├── CancelBookingUseCase.java
│   │   │   └── GetBookingQuery.java
│   │   └── out/                    # Outgoing Ports (SPI interfaces)
│   │       ├── LoadBookingPort.java
│   │       ├── SaveBookingPort.java
│   │       └── SendNotificationPort.java
│   └── service/                    # Use Case implementations
│       ├── CreateBookingService.java
│       └── CancelBookingService.java
│
└── adapter/                        # Infrastructure implementations
    ├── in/
    │   └── web/
    │       ├── BookingController.java
    │       ├── dto/
    │       │   ├── CreateBookingRequest.java   # Record
    │       │   └── BookingResponse.java        # Record
    │       └── mapper/
    │           └── BookingWebMapper.java
    ├── out/
    │   ├── persistence/
    │   │   ├── entity/
    │   │   │   └── BookingJpaEntity.java
    │   │   ├── repository/
    │   │   │   └── BookingRepository.java
    │   │   ├── mapper/
    │   │   │   └── BookingPersistenceMapper.java
    │   │   └── BookingPersistenceAdapter.java
    │   ├── messaging/
    │   │   └── KafkaNotificationAdapter.java
    │   └── external/
    │       └── StripePaymentAdapter.java
    └── config/
        └── BeanConfiguration.java
```


## 2. Domain Layer Patterns

### Rich Domain Entities (NOT anemic)

Business logic lives inside domain objects. Entities are not just data holders.

Domain entities should provide two construction paths (Buckpal pattern):
1. **Creation**: Constructor for new entities (no ID yet, assigned by persistence)
2. **Reconstitution**: Static factory method for loading existing entities from the database

```java
public class Booking {
    private final BookingId id;
    private final FieldId fieldId;
    private final UserId userId;
    private final DateRange dateRange;
    private BookingStatus status;

    // Creation — new booking, no ID yet
    public Booking(FieldId fieldId, UserId userId, DateRange dateRange) {
        this.id = null;
        this.fieldId = requireNonNull(fieldId);
        this.userId = requireNonNull(userId);
        this.dateRange = requireNonNull(dateRange);
        this.status = BookingStatus.PENDING;
        validateBooking();
    }

    // Reconstitution — loading from database (used by persistence mapper)
    public static Booking withId(BookingId id, FieldId fieldId, UserId userId,
                                  DateRange dateRange, BookingStatus status) {
        Booking booking = new Booking(fieldId, userId, dateRange);
        // Use reflection or package-private setter to assign id and status
        return booking;
    }

    public Optional<BookingId> getId() {
        return Optional.ofNullable(this.id);
    }

    public void confirm() {
        if (status != BookingStatus.PENDING) {
            throw new IllegalStateException("Only pending bookings can be confirmed");
        }
        this.status = BookingStatus.CONFIRMED;
    }

    public void cancel() {
        if (status == BookingStatus.CANCELLED) {
            throw new IllegalStateException("Booking already cancelled");
        }
        this.status = BookingStatus.CANCELLED;
    }

    private void validateBooking() {
        if (dateRange.isInPast()) {
            throw new IllegalArgumentException("Cannot book in the past");
        }
    }
}
```

### Value Objects as Java Records

Records enforce immutability and include validation in compact constructors.

```java
public record BookingId(Long value) {
    public BookingId {
        if (value == null || value <= 0) {
            throw new IllegalArgumentException("Invalid booking ID");
        }
    }
}

public record DateRange(LocalDateTime start, LocalDateTime end) {
    public DateRange {
        requireNonNull(start, "Start time cannot be null");
        requireNonNull(end, "End time cannot be null");
        if (start.isAfter(end)) {
            throw new IllegalArgumentException("Start must be before end");
        }
    }

    public boolean isInPast() {
        return end.isBefore(LocalDateTime.now());
    }

    public boolean overlaps(DateRange other) {
        return !this.end.isBefore(other.start) && !other.end.isBefore(this.start);
    }
}
```

## 3. Application Layer Patterns

### Incoming Ports (one interface per use case)

```java
public interface CreateBookingUseCase {
    BookingId createBooking(CreateBookingCommand command);
}
```

### Self-Validating Commands (Buckpal Pattern)

Commands validate their own inputs in the constructor. This keeps validation noise out of use case code.

```java
public record CreateBookingCommand(
    FieldId fieldId,
    UserId userId,
    DateRange dateRange
) {
    public CreateBookingCommand {
        requireNonNull(fieldId, "fieldId must not be null");
        requireNonNull(userId, "userId must not be null");
        requireNonNull(dateRange, "dateRange must not be null");
    }
}
```

### Outgoing Ports (SPI)

```java
public interface LoadBookingPort {
    Optional<Booking> loadById(BookingId id);
    List<Booking> loadByFieldAndDateRange(FieldId fieldId, DateRange dateRange);
}

public interface SaveBookingPort {
    BookingId save(Booking booking);
}
```

### Use Case Implementation

Use cases orchestrate domain objects and outgoing ports. They are annotated with `@Component` (or `@Service`) and `@Transactional`. The use case owns the transaction boundary — not the adapter.

```java
@Service
@Transactional
@RequiredArgsConstructor
public class CreateBookingService implements CreateBookingUseCase {

    private final LoadBookingPort loadBookingPort;
    private final SaveBookingPort saveBookingPort;
    private final SendNotificationPort notificationPort;

    @Override
    public BookingId createBooking(CreateBookingCommand command) {
        List<Booking> conflicts = loadBookingPort
            .loadByFieldAndDateRange(command.fieldId(), command.dateRange());

        if (!conflicts.isEmpty()) {
            throw new BookingConflictException("Field already booked for this time");
        }

        Booking booking = new Booking(
            command.fieldId(), command.userId(), command.dateRange()
        );

        BookingId bookingId = saveBookingPort.save(booking);
        notificationPort.sendBookingConfirmation(booking);
        return bookingId;
    }
}
```

### Locking Pattern (from Buckpal's SendMoneyService)

For operations requiring concurrency control (like booking a time slot), acquire a lock before mutating state and release it after persisting:

```java
@Override
public BookingId createBooking(CreateBookingCommand command) {
    timeSlotLock.lockSlot(command.fieldId(), command.dateRange());
    try {
        // ... validate, create, persist
        return bookingId;
    } finally {
        timeSlotLock.releaseSlot(command.fieldId(), command.dateRange());
    }
}
```

## 4. Adapter Layer Patterns

### Web Adapter (Incoming)

```java
@RestController
@RequestMapping("/api/v1/bookings")
@RequiredArgsConstructor
public class BookingController {

    private final CreateBookingUseCase createBookingUseCase;
    private final GetBookingQuery getBookingQuery;

    @PostMapping
    public ResponseEntity<BookingResponse> createBooking(
            @Valid @RequestBody CreateBookingRequest request) {
        CreateBookingCommand command = new CreateBookingCommand(
            new FieldId(request.fieldId()),
            new UserId(request.userId()),
            new DateRange(request.startTime(), request.endTime())
        );
        BookingId bookingId = createBookingUseCase.createBooking(command);
        return ResponseEntity.status(HttpStatus.CREATED)
            .body(new BookingResponse(bookingId.value()));
    }

    @GetMapping("/{id}")
    public ResponseEntity<BookingResponse> getBooking(@PathVariable Long id) {
        return getBookingQuery.getBooking(new BookingId(id))
            .map(BookingWebMapper::toResponse)
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
    }
}
```

### Persistence Adapter (Outgoing)

```java
@Component
@RequiredArgsConstructor
class BookingPersistenceAdapter implements LoadBookingPort, SaveBookingPort {

    private final BookingRepository repository;
    private final BookingPersistenceMapper mapper;

    @Override
    public Optional<Booking> loadById(BookingId id) {
        return repository.findById(id.value()).map(mapper::toDomain);
    }

    @Override
    public List<Booking> loadByFieldAndDateRange(FieldId fieldId, DateRange dateRange) {
        return repository.findByFieldIdAndDateRange(
                fieldId.value(), dateRange.start(), dateRange.end())
            .stream()
            .map(mapper::toDomain)
            .toList();
    }

    @Override
    public BookingId save(Booking booking) {
        BookingJpaEntity saved = repository.save(mapper.toEntity(booking));
        return new BookingId(saved.getId());
    }
}
```

### JPA Entity (Adapter-only, never leaks into Domain)

```java
@Entity
@Table(name = "bookings", indexes = {
    @Index(name = "idx_field_date", columnList = "field_id,start_time,end_time"),
    @Index(name = "idx_user", columnList = "user_id")
})
@Getter
@Setter
@NoArgsConstructor
public class BookingJpaEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "field_id", nullable = false)
    private Long fieldId;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "start_time", nullable = false)
    private LocalDateTime startTime;

    @Column(name = "end_time", nullable = false)
    private LocalDateTime endTime;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private BookingStatus status;

    @Version
    private Long version;

    @CreatedDate
    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @LastModifiedDate
    @Column(nullable = false)
    private LocalDateTime updatedAt;
}
```

### Boundary Mapping (MapStruct)

```java
@Mapper(componentModel = "spring")
public interface BookingPersistenceMapper {
    Booking toDomain(BookingJpaEntity entity);
    BookingJpaEntity toEntity(Booking domain);
}
```


## 5. Code Style Rules

### Constructor Injection Only

```java
// ✅ CORRECT
@Service
@RequiredArgsConstructor
public class BookingService {
    private final BookingRepository repository;
    private final NotificationService notificationService;
}

// ❌ FORBIDDEN — no field injection
@Autowired private BookingRepository repository;
```

### Functional Programming Over Imperative

```java
// ✅ Streams and Optionals
public List<BookingResponse> getActiveBookings(Long userId) {
    return repository.findByUserId(userId).stream()
        .filter(b -> b.getStatus() != BookingStatus.CANCELLED)
        .map(this::toResponse)
        .toList();
}

// ❌ No imperative loops with mutable lists
```

### Optional Over Null

```java
// ✅ Return Optional, chain with map/orElseThrow
public BookingResponse getBookingOrThrow(BookingId id) {
    return findBooking(id)
        .map(this::toResponse)
        .orElseThrow(() -> new BookingNotFoundException(id));
}

// ❌ Never return null from a method
```

### Lombok — Sparingly

| Annotation | Where | Allowed? |
|------------|-------|----------|
| `@Slf4j` | Any Spring bean | ✅ |
| `@RequiredArgsConstructor` | Services, adapters | ✅ |
| `@Getter` / `@Setter` | JPA entities only | ✅ |
| `@NoArgsConstructor` | JPA entities only | ✅ |
| `@Data` | Anywhere | ❌ |
| `@Builder` | Anywhere | ❌ Use Records |
| `@AllArgsConstructor` | Anywhere | ❌ |

### Validation Strategy

- **Domain layer**: Validate in constructors and compact record constructors
- **API layer**: Use Bean Validation annotations (`@NotNull`, `@Positive`, `@Future`)
- **Both layers validate independently** — never trust the adapter to validate for the domain

```java
// API-level validation (adapter)
public record CreateBookingRequest(
    @NotNull @Positive Long fieldId,
    @NotNull @Positive Long userId,
    @NotNull @Future LocalDateTime startTime,
    @NotNull @Future LocalDateTime endTime
) {}

// Domain-level validation (domain)
public record DateRange(LocalDateTime start, LocalDateTime end) {
    public DateRange {
        requireNonNull(start, "Start time cannot be null");
        requireNonNull(end, "End time cannot be null");
        if (start.isAfter(end)) {
            throw new IllegalArgumentException("Start must be before end");
        }
    }
}
```

## 6. Testing Standards (rieckpil Masterclass)

### Test Pyramid

```
        /\
       /E2E\      ← Few: Full @SpringBootTest (only for critical end-to-end flows)
      /------\
     /  Slice  \  ← Some: @WebMvcTest, @DataJpaTest (fast, focused)
    /----------\
   /   Unit     \ ← Many: Pure Java, no Spring context (fastest)
  /--------------\
```

### Critical Testing Rules

| Rule | Detail |
|------|--------|
| No H2 for integration tests | Use Testcontainers with real PostgreSQL |
| Avoid @SpringBootTest | Use slice tests (@WebMvcTest, @DataJpaTest) unless testing full flow |
| Test naming | `should[Behavior]When[Condition]()` |
| Assertions | Use AssertJ fluent assertions |
| Coverage target | 80%+ unit test coverage |

### Which Test Slice to Use

| What you're testing | Annotation | Mocking |
|---------------------|-----------|---------|
| Controller endpoints | `@WebMvcTest` | `@MockBean` for use cases |
| JPA repositories / queries | `@DataJpaTest` + Testcontainers | Real PostgreSQL |
| JSON serialization | `@JsonTest` | None |
| REST clients (RestTemplate) | `@RestClientTest` | `MockRestServiceServer` |
| External HTTP APIs | `@SpringBootTest` + `@AutoConfigureWireMock` | WireMock stubs |
| Kafka / async messaging | `@SpringBootTest` + Testcontainers | Awaitility for assertions |
| Full end-to-end flow | `@SpringBootTest(RANDOM_PORT)` + Testcontainers | `TestRestTemplate` |

### Unit Tests (Domain Logic)

No Spring context. Pure Java. Fast.

```java
class BookingTest {

    @Test
    void shouldRejectBookingInThePast() {
        LocalDateTime pastDate = LocalDateTime.now().minusDays(1);
        assertThatThrownBy(() -> new Booking(
            new FieldId(1L), new UserId(1L),
            new DateRange(pastDate, pastDate.plusHours(1))
        )).isInstanceOf(IllegalArgumentException.class)
          .hasMessageContaining("past");
    }
}
```

### Slice Tests

**Controller (@WebMvcTest)**
```java
@WebMvcTest(BookingController.class)
class BookingControllerTest {

    @Autowired private MockMvc mockMvc;
    @MockBean private CreateBookingUseCase createBookingUseCase;

    @Test
    void shouldReturn201WhenBookingCreated() throws Exception {
        given(createBookingUseCase.createBooking(any()))
            .willReturn(new BookingId(1L));

        mockMvc.perform(post("/api/v1/bookings")
                .contentType(APPLICATION_JSON)
                .content("""
                    {"fieldId":1,"userId":1,"startTime":"2026-03-01T10:00","endTime":"2026-03-01T11:30"}
                    """))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.id").value(1));
    }
}
```

**Repository (@DataJpaTest + Testcontainers)**
```java
@DataJpaTest
@AutoConfigureTestDatabase(replace = Replace.NONE)
@Testcontainers
class BookingRepositoryTest {

    @Container
    static PostgreSQLContainer<?> postgres =
        new PostgreSQLContainer<>("postgres:15-alpine");

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }

    @Autowired private BookingRepository repository;

    @Test
    void shouldFindConflictingBookings() {
        // test with real PostgreSQL
    }
}
```

### Integration Tests (Sparingly)

```java
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
@Testcontainers
class BookingIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres =
        new PostgreSQLContainer<>("postgres:15-alpine");

    @DynamicPropertySource
    static void props(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }

    @Autowired private TestRestTemplate restTemplate;

    @Test
    void shouldCreateBookingEndToEnd() {
        ResponseEntity<BookingResponse> response = restTemplate.postForEntity(
            "/api/v1/bookings", request, BookingResponse.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }
}
```

### External API Testing (WireMock)

```java
@SpringBootTest
@AutoConfigureWireMock(port = 0)
class StripePaymentAdapterTest {

    @Test
    void shouldProcessPaymentSuccessfully() {
        stubFor(post("/payments").willReturn(aResponse()
            .withStatus(200)
            .withBody("{\"status\":\"SUCCESS\"}")));

        PaymentResult result = paymentAdapter.processPayment(/*...*/);
        assertThat(result.status()).isEqualTo(PaymentStatus.SUCCESS);
    }
}
```

### JSON Serialization Testing (@JsonTest)

Test Jackson annotations, custom serializers, and JSON format without loading the full context.

```java
@JsonTest
class BookingResponseTest {

    @Autowired
    private JacksonTester<BookingResponse> jacksonTester;

    @Test
    void shouldSerializeBookingResponse() throws IOException {
        BookingResponse response = new BookingResponse(1L, "CONFIRMED", "2026-03-01T10:00");
        JsonContent<BookingResponse> result = jacksonTester.write(response);

        assertThat(result).extractingJsonPathNumberValue("$.id").isEqualTo(1);
        assertThat(result).extractingJsonPathStringValue("$.status").isEqualTo("CONFIRMED");
    }
}
```

### HTTP Client Testing (@RestClientTest)

Test REST clients in isolation with a mock server — no WireMock needed.

```java
@RestClientTest(WeatherApiClient.class)
class WeatherApiClientTest {

    @Autowired private WeatherApiClient client;
    @Autowired private MockRestServiceServer mockServer;

    @Test
    void shouldReturnWeatherForecast() {
        mockServer.expect(requestTo("/forecast?lat=40.0&lon=3.0"))
            .andRespond(withSuccess("{\"temp\":22}", APPLICATION_JSON));

        WeatherForecast result = client.getForecast(40.0, 3.0);
        assertThat(result.temp()).isEqualTo(22);
    }
}
```

### Async Testing (Awaitility)

```java
@Test
void shouldSendNotificationAfterBookingCreated() {
    eventPublisher.publish(new BookingCreatedEvent(/*...*/));

    await().atMost(Duration.ofSeconds(5)).untilAsserted(() ->
        verify(notificationService).sendEmail(any())
    );
}
```


## 7. API Design Standards

### Spring Cloud Infrastructure (PetClinic Microservices)

When deploying as microservices, use these Spring Cloud components:

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Config Server | Spring Cloud Config | Centralized, Git-backed configuration |
| Service Discovery | Eureka Server | Service registration and client-side load balancing |
| API Gateway | Spring Cloud Gateway | Routing, auth, rate limiting |
| Circuit Breaker | Resilience4j | Fault tolerance, fallbacks, bulkhead isolation |
| Distributed Tracing | Micrometer + OpenTelemetry | Request correlation across services |

### RESTful Conventions

```
GET    /api/v1/bookings          - List (paginated)
GET    /api/v1/bookings/{id}     - Get by ID
POST   /api/v1/bookings          - Create
PUT    /api/v1/bookings/{id}     - Full update
PATCH  /api/v1/bookings/{id}     - Partial update
DELETE /api/v1/bookings/{id}     - Delete
```

### Error Response Format

```json
{
  "timestamp": "2026-02-06T10:30:00Z",
  "status": 400,
  "error": "Bad Request",
  "message": "Validation failed",
  "path": "/api/v1/bookings",
  "errors": [
    { "field": "startTime", "message": "Start time must be in the future" }
  ]
}
```

### Global Exception Handler

```java
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {

    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(ResourceNotFoundException ex) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
            .body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(BookingConflictException.class)
    public ResponseEntity<ErrorResponse> handleConflict(BookingConflictException ex) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
            .body(new ErrorResponse(ex.getMessage()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleValidation(MethodArgumentNotValidException ex) {
        List<FieldError> errors = ex.getBindingResult().getFieldErrors().stream()
            .map(e -> new FieldError(e.getField(), e.getDefaultMessage()))
            .toList();
        return ResponseEntity.badRequest()
            .body(new ErrorResponse("Validation failed", errors));
    }
}
```

## 8. Infrastructure & Operations

### Configuration

```yaml
spring:
  application:
    name: field-booking-service
  profiles:
    active: ${SPRING_PROFILES_ACTIVE:local}

server:
  port: ${SERVER_PORT:8080}
  servlet:
    context-path: /api/v1

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
```

**Profile Strategy:**
- `local` — Docker Compose infrastructure
- `dev` — DigitalOcean managed services
- `staging` — Pre-production (mirrors prod)
- `prod` — Production on Kubernetes

### Database

- Flyway for migrations (never Liquibase in this project)
- Optimistic locking via `@Version`
- Proper composite indexes for query patterns
- HikariCP connection pooling (Spring Boot default)

### Observability

- Micrometer + Prometheus for metrics
- OpenTelemetry + Jaeger for distributed tracing
- Loki for log aggregation
- Spring Boot Actuator for health endpoints
- Structured logging with correlation IDs

```java
@Slf4j
@Service
public class CreateBookingService {
    public BookingId createBooking(CreateBookingCommand command) {
        log.info("Creating booking for field={} user={}", command.fieldId(), command.userId());
        // ...
        log.debug("Booking created: {}", bookingId);
        return bookingId;
    }
}
```

### Security

```java
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
            .csrf(AbstractHttpConfigurer::disable)
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/actuator/health").permitAll()
                .requestMatchers("/api/v1/**").authenticated()
                .anyRequest().denyAll()
            )
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()))
            .build();
    }
}
```

### Caching (Redis)

```java
@Service
@CacheConfig(cacheNames = "courtAvailability")
@RequiredArgsConstructor
public class AvailabilityService {

    @Cacheable(key = "#fieldId + '-' + #date")
    public List<TimeSlot> getAvailability(Long fieldId, LocalDate date) {
        return repository.findAvailableSlots(fieldId, date);
    }

    @CacheEvict(key = "#fieldId + '-' + #date")
    public void invalidateAvailability(Long fieldId, LocalDate date) {
        // Cache cleared on booking changes
    }
}
```

### Containerization

```dockerfile
FROM gradle:8.5-jdk21 AS builder
WORKDIR /app
COPY . .
RUN gradle clean build -x test

FROM eclipse-temurin:21-jre-alpine
RUN addgroup -S app && adduser -S app -G app
USER app
WORKDIR /app
COPY --from=builder /app/build/libs/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### CI/CD Pipeline Stages

1. Checkout → 2. Build → 3. Unit tests → 4. Static analysis (Checkstyle, SonarQube) → 5. Security scan (OWASP, Trivy) → 6. Docker build → 7. Integration tests (Testcontainers) → 8. Push image → 9. Deploy staging → 10. Smoke tests → 11. Deploy production

## 9. Technology Stack

| Category | Technology |
|----------|-----------|
| Framework | Spring Boot 3.4+, Java 21+ |
| Cloud | Spring Cloud 2023.x |
| Namespace | Jakarta EE 9+ |
| Data | Spring Data JPA, Hibernate 6.x, Flyway |
| API Docs | SpringDoc OpenAPI 3 |
| Messaging | Apache Kafka, Spring Cloud Stream |
| Metrics | Micrometer, Prometheus, Grafana |
| Tracing | OpenTelemetry, Jaeger |
| Security | Spring Security 6.x, OAuth 2.0, JWT |
| Testing | JUnit 5, Mockito, AssertJ, JSONAssert, Testcontainers, WireMock, Awaitility, LocalStack |
| Quality | Checkstyle, JaCoCo (80%+), SonarQube, OWASP Dependency Check |
| Mapping | MapStruct |
| Logging | @Slf4j (Lombok) |
| DI | Constructor injection via @RequiredArgsConstructor |

## 10. Quick Reference — Decision Rules

| When you need to... | Do this |
|---------------------|---------|
| Create a DTO or Value Object | Use a Java Record with compact constructor validation |
| Add business logic | Put it in the Domain entity, not in a service |
| Access the database | Define an outgoing Port interface, implement in a Persistence Adapter |
| Expose an API | Define an incoming Port (Use Case), implement in Application service, call from Web Adapter |
| Test a controller | Use @WebMvcTest with @MockBean for use cases |
| Test a repository | Use @DataJpaTest + Testcontainers (real PostgreSQL) |
| Test domain logic | Plain JUnit 5, no Spring context |
| Test an external API | Use WireMock or @RestClientTest |
| Test JSON serialization | Use @JsonTest |
| Test async behavior | Use Awaitility |
| Inject a dependency | Constructor injection only (@RequiredArgsConstructor) |
| Handle nulls | Return Optional, never null |
| Write a loop | Use Stream API instead |
| Create a new entity | Constructor (no ID) |
| Load entity from DB | Static factory `withId(...)` method |
| Lock a shared resource | Acquire lock → mutate → persist → release lock (Buckpal pattern) |

### When to Take Shortcuts (from Buckpal)

Not every feature needs full hexagonal ceremony. Buckpal explicitly discusses "taking shortcuts consciously":

| Shortcut | When acceptable |
|----------|----------------|
| Skip incoming port interface | Simple CRUD with no business logic |
| Skip mapping between layers | When domain and persistence models are identical |
| Use @Service directly without port | Internal utility services with no external adapters |
| Use @SpringBootTest | Only for smoke tests or critical E2E paths |

The key is to take shortcuts **consciously** and document the trade-off, not accidentally.

## References

- [Buckpal — thombergs](https://github.com/thombergs/buckpal) — Hexagonal Architecture reference
- [Hexagonal Architecture with Java and Spring — reflectoring.io](https://reflectoring.io/spring-hexagonal/) — Buckpal companion article
- [Testing Spring Boot Applications Masterclass — rieckpil](https://github.com/rieckpil/testing-spring-boot-applications-masterclass) — Testing standards
- [Spring Boot Test Slices — rieckpil](https://rieckpil.de/spring-boot-test-slices-overview-and-usage/) — Complete slice test guide
- [Spring PetClinic Microservices](https://github.com/spring-petclinic/spring-petclinic-microservices) — Spring Cloud patterns
- [Spring Boot Microservice Best Practices — abhisheksr01](https://github.com/abhisheksr01/spring-boot-microservice-best-practices) — DevSecOps
- [Testcontainers](https://testcontainers.com/)

---
*Content rephrased for compliance with licensing restrictions. Original sources cited above.*
