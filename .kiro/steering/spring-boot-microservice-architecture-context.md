---
inclusion: manual
---

# Spring Boot 3.x & Java 21+ Microservice Architecture Context

This document provides architectural patterns, best practices, and design principles extracted from production-grade Spring Boot microservices repositories to guide the design of our field booking platform microservice.

**Primary References:**
- **Buckpal (thombergs)**: Hexagonal Architecture implementation
- **Testing Spring Boot Applications Masterclass (rieckpil)**: Comprehensive testing standards
- **Spring PetClinic Microservices**: Official Spring Cloud patterns
- **Spring Boot Microservice Best Practices**: DevSecOps integration

## Core Architectural Philosophy

### 1. Hexagonal Architecture (Ports & Adapters)

**Strict Layer Separation:**
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

**Key Principles:**
- **Domain Independence**: Domain layer has ZERO dependencies on frameworks or infrastructure
- **Dependency Inversion**: All dependencies point INWARD toward the domain
- **Ports**: Interfaces defined in Application layer
- **Adapters**: Implementations in Infrastructure layer

### 2. Package Structure (Buckpal Style)

```
src/main/java/com/company/bookingplatform/
├── domain/                          # Pure business logic
│   ├── Booking.java                 # Entity
│   ├── BookingId.java              # Value Object (Record)
│   ├── BookingStatus.java          # Enum
│   └── BookingService.java         # Domain Service
│
├── application/                     # Use Cases & Ports
│   ├── port/
│   │   ├── in/                     # Incoming Ports (Use Cases)
│   │   │   ├── CreateBookingUseCase.java
│   │   │   ├── CancelBookingUseCase.java
│   │   │   └── GetBookingUseCase.java
│   │   └── out/                    # Outgoing Ports (SPI)
│   │       ├── LoadBookingPort.java
│   │       ├── SaveBookingPort.java
│   │       └── SendNotificationPort.java
│   └── service/                    # Use Case Implementations
│       ├── CreateBookingService.java
│       └── CancelBookingService.java
│
└── adapter/                        # Infrastructure Adapters
    ├── in/                         # Incoming Adapters
    │   └── web/
    │       ├── BookingController.java
    │       └── BookingRequest.java
    ├── out/                        # Outgoing Adapters
    │   ├── persistence/
    │   │   ├── BookingJpaEntity.java
    │   │   ├── BookingRepository.java
    │   │   └── BookingPersistenceAdapter.java
    │   └── notification/
    │       └── EmailNotificationAdapter.java
    └── config/                     # Configuration
        └── BeanConfiguration.java
```

### 3. Dependency Rules

**ALLOWED:**
- Domain → Nothing (pure Java)
- Application → Domain
- Adapter → Application + Domain

**FORBIDDEN:**
- Domain → Application ❌
- Domain → Adapter ❌
- Application → Adapter ❌

### 4. Immutability & Modern Java

**Use Java Records for:**
- DTOs (Request/Response objects)
- Value Objects (BookingId, Money, DateRange)
- Command objects
- Query results

**Example:**
```java
// Value Object
public record BookingId(Long value) {
    public BookingId {
        if (value == null || value <= 0) {
            throw new IllegalArgumentException("Invalid booking ID");
        }
    }
}

// DTO
public record CreateBookingRequest(
    @NotNull Long fieldId,
    @NotNull Long userId,
    @NotNull LocalDateTime startTime,
    @NotNull LocalDateTime endTime
) {}
```

## Testing Standards (rieckpil Masterclass)

### Test Pyramid Strategy

```
        /\
       /E2E\      ← Few (Full @SpringBootTest)
      /------\
     /  Slice  \  ← Some (@WebMvcTest, @DataJpaTest)
    /----------\
   /   Unit     \ ← Many (Pure Java, no Spring)
  /--------------\
```

### 1. Unit Tests (Fast, Isolated)

**Characteristics:**
- NO Spring Context
- Pure Java/JUnit 5
- Mock dependencies with Mockito
- Test domain logic in isolation

**Example:**
```java
class BookingTest {
    
    @Test
    void shouldNotAllowBookingInThePast() {
        // Given
        LocalDateTime pastDate = LocalDateTime.now().minusDays(1);
        
        // When & Then
        assertThatThrownBy(() -> 
            new Booking(pastDate, LocalDateTime.now())
        ).isInstanceOf(IllegalArgumentException.class)
         .hasMessageContaining("past");
    }
}
```

### 2. Slice Tests (Focused, Fast)

**@WebMvcTest** - Test Controllers in Isolation
```java
@WebMvcTest(BookingController.class)
class BookingControllerTest {
    
    @Autowired
    private MockMvc mockMvc;
    
    @MockBean
    private CreateBookingUseCase createBookingUseCase;
    
    @Test
    void shouldCreateBooking() throws Exception {
        // Given
        CreateBookingRequest request = new CreateBookingRequest(/*...*/);
        
        // When & Then
        mockMvc.perform(post("/api/v1/bookings")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.id").exists());
    }
}
```

**@DataJpaTest** - Test Repository Layer
```java
@DataJpaTest
@AutoConfigureTestDatabase(replace = Replace.NONE)
@Testcontainers
class BookingRepositoryTest {
    
    @Container
    static PostgreSQLContainer<?> postgres = 
        new PostgreSQLContainer<>("postgres:15-alpine");
    
    @Autowired
    private BookingRepository repository;
    
    @Test
    void shouldSaveAndRetrieveBooking() {
        // Given
        BookingJpaEntity booking = new BookingJpaEntity(/*...*/);
        
        // When
        BookingJpaEntity saved = repository.save(booking);
        
        // Then
        assertThat(saved.getId()).isNotNull();
        assertThat(repository.findById(saved.getId()))
            .isPresent()
            .hasValueSatisfying(b -> 
                assertThat(b.getStatus()).isEqualTo(BookingStatus.CONFIRMED)
            );
    }
}
```

### 3. Integration Tests (Testcontainers)

**CRITICAL RULES:**
- ✅ Use Testcontainers for real databases
- ❌ NO H2 for integration tests
- ✅ Test with production-like environment
- ✅ Use @SpringBootTest sparingly (slow)

**Example with Testcontainers:**
```java
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
@Testcontainers
class BookingIntegrationTest {
    
    @Container
    static PostgreSQLContainer<?> postgres = 
        new PostgreSQLContainer<>("postgres:15-alpine")
            .withDatabaseName("testdb")
            .withUsername("test")
            .withPassword("test");
    
    @Container
    static LocalStackContainer localstack = 
        new LocalStackContainer(DockerImageName.parse("localstack/localstack:3.0"))
            .withServices(LocalStackContainer.Service.SQS);
    
    @Autowired
    private TestRestTemplate restTemplate;
    
    @DynamicPropertySource
    static void properties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
        registry.add("aws.sqs.endpoint", () -> 
            localstack.getEndpointOverride(LocalStackContainer.Service.SQS));
    }
    
    @Test
    void shouldCreateBookingEndToEnd() {
        // Given
        CreateBookingRequest request = new CreateBookingRequest(/*...*/);
        
        // When
        ResponseEntity<BookingResponse> response = restTemplate.postForEntity(
            "/api/v1/bookings",
            request,
            BookingResponse.class
        );
        
        // Then
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(response.getBody().id()).isNotNull();
    }
}
```

### 4. Testing External APIs

**WireMock for HTTP Mocking:**
```java
@SpringBootTest
@AutoConfigureWireMock(port = 0)
class ExternalApiTest {
    
    @Autowired
    private PaymentServiceClient paymentClient;
    
    @Test
    void shouldProcessPayment() {
        // Given
        stubFor(post("/payments")
            .willReturn(aResponse()
                .withStatus(200)
                .withHeader("Content-Type", "application/json")
                .withBody("{\"status\":\"SUCCESS\"}")));
        
        // When
        PaymentResult result = paymentClient.processPayment(/*...*/);
        
        // Then
        assertThat(result.status()).isEqualTo(PaymentStatus.SUCCESS);
    }
}
```

### 5. Testing Async Operations

**Awaitility for Async Testing:**
```java
@Test
void shouldProcessMessageAsynchronously() {
    // Given
    BookingCreatedEvent event = new BookingCreatedEvent(/*...*/);
    
    // When
    eventPublisher.publish(event);
    
    // Then
    await()
        .atMost(Duration.ofSeconds(5))
        .untilAsserted(() -> {
            verify(notificationService).sendEmail(any());
        });
}
```

### 6. Test Naming Convention

**Pattern:** `should[ExpectedBehavior]When[StateUnderTest]`

Examples:
- `shouldCreateBookingWhenValidRequest()`
- `shouldThrowExceptionWhenBookingInPast()`
- `shouldReturnEmptyWhenNoBookingsFound()`

### 7. Test Coverage Goals

- **Unit Tests**: 80%+ coverage
- **Integration Tests**: Critical paths
- **E2E Tests**: Happy paths only

## Architecture Patterns

### 1. Domain Layer (Pure Business Logic)

**Entities:**
```java
public class Booking {
    private final BookingId id;
    private final FieldId fieldId;
    private final UserId userId;
    private final DateRange dateRange;
    private BookingStatus status;
    
    // Constructor with validation
    public Booking(FieldId fieldId, UserId userId, DateRange dateRange) {
        this.id = null; // Generated by persistence
        this.fieldId = requireNonNull(fieldId);
        this.userId = requireNonNull(userId);
        this.dateRange = requireNonNull(dateRange);
        this.status = BookingStatus.PENDING;
        
        validateBooking();
    }
    
    // Business logic methods
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

**Value Objects (Records):**
```java
public record DateRange(LocalDateTime start, LocalDateTime end) {
    public DateRange {
        if (start == null || end == null) {
            throw new IllegalArgumentException("Dates cannot be null");
        }
        if (start.isAfter(end)) {
            throw new IllegalArgumentException("Start must be before end");
        }
    }
    
    public boolean isInPast() {
        return end.isBefore(LocalDateTime.now());
    }
    
    public boolean overlaps(DateRange other) {
        return !this.end.isBefore(other.start) && 
               !other.end.isBefore(this.start);
    }
}
```

### 2. Application Layer (Use Cases & Ports)

**Incoming Port (Use Case Interface):**
```java
public interface CreateBookingUseCase {
    BookingId createBooking(CreateBookingCommand command);
}

public record CreateBookingCommand(
    FieldId fieldId,
    UserId userId,
    DateRange dateRange
) {}
```

**Outgoing Ports (SPI):**
```java
public interface LoadBookingPort {
    Optional<Booking> loadById(BookingId id);
    List<Booking> loadByFieldAndDateRange(FieldId fieldId, DateRange dateRange);
}

public interface SaveBookingPort {
    BookingId save(Booking booking);
}

public interface SendNotificationPort {
    void sendBookingConfirmation(Booking booking);
}
```

**Use Case Implementation:**
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
        // Check for conflicts
        List<Booking> existingBookings = loadBookingPort
            .loadByFieldAndDateRange(command.fieldId(), command.dateRange());
        
        if (!existingBookings.isEmpty()) {
            throw new BookingConflictException("Field already booked for this time");
        }
        
        // Create domain object
        Booking booking = new Booking(
            command.fieldId(),
            command.userId(),
            command.dateRange()
        );
        
        // Persist
        BookingId bookingId = saveBookingPort.save(booking);
        
        // Send notification
        notificationPort.sendBookingConfirmation(booking);
        
        return bookingId;
    }
}
```

### 3. Adapter Layer (Infrastructure)

**Web Adapter (Incoming):**
```java
@RestController
@RequestMapping("/api/v1/bookings")
@RequiredArgsConstructor
public class BookingController {
    
    private final CreateBookingUseCase createBookingUseCase;
    private final GetBookingUseCase getBookingUseCase;
    
    @PostMapping
    public ResponseEntity<BookingResponse> createBooking(
            @Valid @RequestBody CreateBookingRequest request) {
        
        CreateBookingCommand command = new CreateBookingCommand(
            new FieldId(request.fieldId()),
            new UserId(request.userId()),
            new DateRange(request.startTime(), request.endTime())
        );
        
        BookingId bookingId = createBookingUseCase.createBooking(command);
        
        return ResponseEntity
            .status(HttpStatus.CREATED)
            .body(new BookingResponse(bookingId.value()));
    }
    
    @GetMapping("/{id}")
    public ResponseEntity<BookingResponse> getBooking(@PathVariable Long id) {
        return getBookingUseCase.getBooking(new BookingId(id))
            .map(this::toResponse)
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
    }
    
    private BookingResponse toResponse(Booking booking) {
        return new BookingResponse(
            booking.getId().value(),
            booking.getFieldId().value(),
            booking.getUserId().value(),
            booking.getDateRange().start(),
            booking.getDateRange().end(),
            booking.getStatus()
        );
    }
}
```

**Persistence Adapter (Outgoing):**
```java
@Component
@RequiredArgsConstructor
class BookingPersistenceAdapter implements LoadBookingPort, SaveBookingPort {
    
    private final BookingRepository repository;
    private final BookingMapper mapper;
    
    @Override
    public Optional<Booking> loadById(BookingId id) {
        return repository.findById(id.value())
            .map(mapper::toDomain);
    }
    
    @Override
    public List<Booking> loadByFieldAndDateRange(FieldId fieldId, DateRange dateRange) {
        return repository.findByFieldIdAndDateRange(
                fieldId.value(),
                dateRange.start(),
                dateRange.end()
            )
            .stream()
            .map(mapper::toDomain)
            .toList();
    }
    
    @Override
    public BookingId save(Booking booking) {
        BookingJpaEntity entity = mapper.toEntity(booking);
        BookingJpaEntity saved = repository.save(entity);
        return new BookingId(saved.getId());
    }
}

@Repository
interface BookingRepository extends JpaRepository<BookingJpaEntity, Long> {
    
    @Query("""
        SELECT b FROM BookingJpaEntity b
        WHERE b.fieldId = :fieldId
        AND b.status != 'CANCELLED'
        AND (
            (b.startTime <= :end AND b.endTime >= :start)
        )
        """)
    List<BookingJpaEntity> findByFieldIdAndDateRange(
        @Param("fieldId") Long fieldId,
        @Param("start") LocalDateTime start,
        @Param("end") LocalDateTime end
    );
}
```

**JPA Entity:**
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

### 4. Mapping Between Boundaries

**MapStruct for DTO ↔ Domain:**
```java
@Mapper(componentModel = "spring")
public interface BookingMapper {
    
    Booking toDomain(BookingJpaEntity entity);
    
    BookingJpaEntity toEntity(Booking domain);
    
    @Mapping(target = "id", source = "id.value")
    @Mapping(target = "fieldId", source = "fieldId.value")
    BookingResponse toResponse(Booking domain);
}
```

## Code Style & Best Practices

### 1. Constructor Injection Only

```java
// ✅ CORRECT - Constructor Injection
@Service
@RequiredArgsConstructor  // Lombok generates constructor
public class BookingService {
    private final BookingRepository repository;
    private final NotificationService notificationService;
}

// ❌ WRONG - Field Injection
@Service
public class BookingService {
    @Autowired  // Don't do this!
    private BookingRepository repository;
}
```

### 2. Functional Programming Style

```java
// ✅ CORRECT - Functional style
public List<BookingResponse> getActiveBookings(Long userId) {
    return repository.findByUserId(userId)
        .stream()
        .filter(booking -> booking.getStatus() != BookingStatus.CANCELLED)
        .map(this::toResponse)
        .toList();
}

// ❌ WRONG - Imperative style
public List<BookingResponse> getActiveBookings(Long userId) {
    List<Booking> bookings = repository.findByUserId(userId);
    List<BookingResponse> responses = new ArrayList<>();
    for (Booking booking : bookings) {
        if (booking.getStatus() != BookingStatus.CANCELLED) {
            responses.add(toResponse(booking));
        }
    }
    return responses;
}
```

### 3. Optional Over Null Checks

```java
// ✅ CORRECT - Use Optional
public Optional<Booking> findBooking(BookingId id) {
    return repository.findById(id.value())
        .map(mapper::toDomain);
}

public BookingResponse getBookingOrThrow(BookingId id) {
    return findBooking(id)
        .map(this::toResponse)
        .orElseThrow(() -> new BookingNotFoundException(id));
}

// ❌ WRONG - Null checks
public Booking findBooking(BookingId id) {
    BookingJpaEntity entity = repository.findById(id.value());
    if (entity == null) {
        return null;
    }
    return mapper.toDomain(entity);
}
```

### 4. Lombok Usage (Sparingly)

**Recommended Lombok Annotations:**
- `@Slf4j` - Logging
- `@RequiredArgsConstructor` - Constructor injection
- `@Getter` / `@Setter` - JPA entities only
- `@NoArgsConstructor` - JPA entities only

**Avoid:**
- `@Data` - Too much magic
- `@Builder` - Use Records instead
- `@AllArgsConstructor` - Prefer constructor with validation

### 5. Validation

```java
// Domain validation in constructor
public record DateRange(LocalDateTime start, LocalDateTime end) {
    public DateRange {
        requireNonNull(start, "Start time cannot be null");
        requireNonNull(end, "End time cannot be null");
        if (start.isAfter(end)) {
            throw new IllegalArgumentException("Start must be before end");
        }
    }
}

// API validation with Bean Validation
public record CreateBookingRequest(
    @NotNull(message = "Field ID is required")
    @Positive
    Long fieldId,
    
    @NotNull(message = "User ID is required")
    @Positive
    Long userId,
    
    @NotNull(message = "Start time is required")
    @Future(message = "Start time must be in the future")
    LocalDateTime startTime,
    
    @NotNull(message = "End time is required")
    @Future(message = "End time must be in the future")
    LocalDateTime endTime
) {
    @AssertTrue(message = "End time must be after start time")
    public boolean isValidTimeRange() {
        return startTime != null && endTime != null && 
               endTime.isAfter(startTime);
    }
}
```

## Spring Cloud Microservices Components

## Spring Cloud Microservices Components

**Essential Infrastructure Services:**

1. **Config Server** (Spring Cloud Config)
   - Centralized configuration management
   - Environment-specific configurations
   - Git-backed configuration repository
   - Dynamic configuration refresh

2. **Service Discovery** (Eureka Server)
   - Service registration and discovery
   - Client-side load balancing
   - Health checking
   - Failover support

3. **API Gateway** (Spring Cloud Gateway)
   - Single entry point for all clients
   - Request routing and filtering
   - Authentication/Authorization
   - Rate limiting and circuit breaking
   - Request/Response transformation

4. **Circuit Breaker** (Resilience4j)
   - Fault tolerance patterns
   - Fallback mechanisms
   - Bulkhead isolation
   - Retry and timeout strategies

5. **Distributed Tracing** (Micrometer + OpenTelemetry)
   - Request correlation across services
   - Performance monitoring
   - Integration with Zipkin/Jaeger

## Technology Stack Recommendations

### Core Framework
- **Spring Boot 3.4+** with Java 21+
- **Spring Cloud 2023.x** (Hoxton/2020.x successor)
- **Jakarta EE 9+** (javax → jakarta namespace)

### Data Access
- **Spring Data JPA** with Hibernate 6.x
- **Flyway/Liquibase** for database migrations
- **Connection Pooling**: HikariCP (default in Spring Boot)

### API & Documentation
- **SpringDoc OpenAPI 3** (Swagger UI)
  - Automatic API documentation
  - JSR-303 validation support (@NotNull, @Min, @Max, @Size)
  - OAuth 2 integration

### Messaging & Events
- **Apache Kafka** or **RabbitMQ**
- **Spring Cloud Stream** for abstraction
- Event-driven architecture support

### Observability
- **Micrometer** for metrics
- **Prometheus** for metrics collection
- **Grafana** for visualization
- **Zipkin/Jaeger** for distributed tracing
- **Spring Boot Actuator** for health checks

### Security
- **Spring Security 6.x**
- **OAuth 2.0 / OpenID Connect**
- **Keycloak** for identity management
- **JWT** for stateless authentication

### Testing
- **JUnit 5** for unit tests
- **Mockito** for mocking
- **Testcontainers** for integration tests (MANDATORY for DB tests)
- **AssertJ** for fluent assertions
- **WireMock** for HTTP API mocking
- **Awaitility** for async testing
- **@WebMvcTest** for controller slice tests
- **@DataJpaTest** for repository slice tests
- **NO H2** - Use real databases via Testcontainers

### Code Quality & Analysis
- **Checkstyle** for code style enforcement
- **JaCoCo** for code coverage (minimum 80%)
- **SonarQube** for static analysis
- **OWASP Dependency Check** for vulnerability scanning

### Development Accelerators
- **Lombok** (sparingly: @Slf4j, @RequiredArgsConstructor only)
- **MapStruct** for DTO ↔ Entity mapping
  - Type-safe, compile-time generation
  - Better performance than reflection-based mappers
- **Java Records** for DTOs and Value Objects

## Best Practices Summary

### Architecture
1. **Hexagonal Architecture**: Strict layer separation (Domain → Application → Adapter)
2. **Dependency Inversion**: Dependencies point inward toward domain
3. **Ports & Adapters**: Interfaces in Application, implementations in Adapter
4. **Immutability**: Use Records for DTOs and Value Objects

### Testing
1. **Test Pyramid**: Many unit tests, some slice tests, few E2E tests
2. **Testcontainers**: Always use real databases for integration tests
3. **Slice Testing**: @WebMvcTest for controllers, @DataJpaTest for repositories
4. **No @SpringBootTest**: Unless absolutely necessary (slow)

### Code Style
1. **Constructor Injection**: Only use constructor injection
2. **Functional Style**: Streams and Optionals over imperative code
3. **No Null**: Use Optional instead of null returns
4. **Lombok Sparingly**: Only @Slf4j and @RequiredArgsConstructor

### Domain Design
1. **Rich Domain Models**: Business logic in domain entities
2. **Value Objects**: Immutable Records with validation
3. **Use Cases**: One interface per use case
4. **No Anemic Models**: Avoid entities with only getters/setters

## References

**Primary Sources:**
- [Buckpal (thombergs)](https://github.com/thombergs/buckpal) - Hexagonal Architecture
- [Testing Spring Boot Applications Masterclass (rieckpil)](https://github.com/rieckpil/testing-spring-boot-applications-masterclass) - Testing standards
- [Spring PetClinic Microservices](https://github.com/spring-petclinic/spring-petclinic-microservices) - Spring Cloud patterns
- [Spring Boot Microservice Best Practices](https://github.com/abhisheksr01/spring-boot-microservice-best-practices) - DevSecOps

**Additional Resources:**
- Get Your Hands Dirty on Clean Architecture (Tom Hombergs)
- [Spring Boot Test Slices](https://rieckpil.de/spring-boot-test-slices-overview-and-usage/)
- [Testcontainers Documentation](https://testcontainers.com/)
- Spring Boot 3 Documentation: https://spring.io/projects/spring-boot
- Microservices Patterns: https://microservices.io/patterns/

---

*Content rephrased for compliance with licensing restrictions. Original sources cited above.*

**application.yml Structure:**
```yaml
spring:
  application:
    name: field-booking-service
  profiles:
    active: ${SPRING_PROFILES_ACTIVE:dev}
  cloud:
    config:
      uri: ${CONFIG_SERVER_URL:http://localhost:8888}
      fail-fast: true
      retry:
        max-attempts: 6

server:
  port: ${SERVER_PORT:8080}
  servlet:
    context-path: /api/v1

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  metrics:
    export:
      prometheus:
        enabled: true
```

**Profile Strategy:**
- `dev`: Local development
- `test`: Integration testing
- `staging`: Pre-production
- `prod`: Production

### 2. API Design

**RESTful Conventions:**
```
GET    /api/v1/bookings          - List all bookings
GET    /api/v1/bookings/{id}     - Get booking by ID
POST   /api/v1/bookings          - Create new booking
PUT    /api/v1/bookings/{id}     - Update booking
PATCH  /api/v1/bookings/{id}     - Partial update
DELETE /api/v1/bookings/{id}     - Delete booking
```

**Response Standards:**
- Use proper HTTP status codes
- Consistent error response format
- HATEOAS links for discoverability
- Pagination for collections
- API versioning (URL or header-based)

**Error Response Format:**
```json
{
  "timestamp": "2026-02-06T10:30:00Z",
  "status": 400,
  "error": "Bad Request",
  "message": "Validation failed",
  "path": "/api/v1/bookings",
  "errors": [
    {
      "field": "startDate",
      "message": "Start date cannot be in the past"
    }
  ]
}
```

### 3. Database Design

**Best Practices:**
- Use database migrations (Flyway/Liquibase)
- Optimistic locking for concurrency (@Version)
- Soft deletes for audit trails
- Proper indexing strategy
- Connection pooling configuration

**JPA Entity Example:**
```java
@Entity
@Table(name = "bookings", indexes = {
    @Index(name = "idx_booking_date", columnList = "booking_date"),
    @Index(name = "idx_user_id", columnList = "user_id")
})
@Data
@Builder
public class Booking {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Version
    private Long version;
    
    @Column(nullable = false)
    private LocalDateTime bookingDate;
    
    @Column(nullable = false)
    private String status;
    
    @CreatedDate
    private LocalDateTime createdAt;
    
    @LastModifiedDate
    private LocalDateTime updatedAt;
    
    @Column(nullable = false)
    private boolean deleted = false;
}
```

### 4. Exception Handling

**Global Exception Handler:**
```java
@RestControllerAdvice
public class GlobalExceptionHandler {
    
    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleNotFound(
        ResourceNotFoundException ex) {
        return ResponseEntity
            .status(HttpStatus.NOT_FOUND)
            .body(ErrorResponse.builder()
                .message(ex.getMessage())
                .build());
    }
    
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleValidation(
        MethodArgumentNotValidException ex) {
        // Handle validation errors
    }
}
```

### 5. Logging Strategy

**Structured Logging:**
```java
@Slf4j
@Service
public class BookingService {
    
    public Booking createBooking(BookingRequest request) {
        log.info("Creating booking for user: {}", request.getUserId());
        try {
            // Business logic
            log.debug("Booking created successfully: {}", booking.getId());
            return booking;
        } catch (Exception e) {
            log.error("Failed to create booking", e);
            throw new BookingException("Booking creation failed", e);
        }
    }
}
```

**Log Levels:**
- ERROR: System errors requiring immediate attention
- WARN: Potential issues, degraded functionality
- INFO: Important business events
- DEBUG: Detailed diagnostic information
- TRACE: Very detailed diagnostic information

### 6. Testing Strategy

**Test Pyramid:**
```
        /\
       /E2E\      ← Few (Cucumber/Integration)
      /------\
     /  API   \   ← Some (REST API tests)
    /----------\
   /   Unit     \ ← Many (JUnit + Mockito)
  /--------------\
```

**Unit Test Example:**
```java
@ExtendWith(MockitoExtension.class)
class BookingServiceTest {
    
    @Mock
    private BookingRepository repository;
    
    @InjectMocks
    private BookingService service;
    
    @Test
    void shouldCreateBooking() {
        // Given
        BookingRequest request = BookingRequest.builder()
            .userId(1L)
            .fieldId(1L)
            .build();
        
        // When
        Booking result = service.createBooking(request);
        
        // Then
        assertNotNull(result);
        verify(repository).save(any(Booking.class));
    }
}
```

**Integration Test with TestContainers:**
```java
@SpringBootTest
@Testcontainers
class BookingIntegrationTest {
    
    @Container
    static PostgreSQLContainer<?> postgres = 
        new PostgreSQLContainer<>("postgres:15-alpine");
    
    @Autowired
    private BookingRepository repository;
    
    @Test
    void shouldPersistBooking() {
        // Test with real database
    }
}
```

### 7. Security Best Practices

**Authentication & Authorization:**
```java
@Configuration
@EnableWebSecurity
public class SecurityConfig {
    
    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) {
        return http
            .csrf(csrf -> csrf.disable())
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/actuator/health").permitAll()
                .requestMatchers("/api/v1/bookings/**")
                    .hasRole("USER")
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(OAuth2ResourceServerConfigurer::jwt)
            .build();
    }
}
```

**Security Headers:**
- X-Content-Type-Options: nosniff
- X-Frame-Options: DENY
- X-XSS-Protection: 1; mode=block
- Strict-Transport-Security: max-age=31536000

### 8. Performance Optimization

**Caching Strategy:**
```java
@Service
@CacheConfig(cacheNames = "bookings")
public class BookingService {
    
    @Cacheable(key = "#id")
    public Booking getBooking(Long id) {
        return repository.findById(id)
            .orElseThrow(() -> new ResourceNotFoundException());
    }
    
    @CacheEvict(key = "#id")
    public void deleteBooking(Long id) {
        repository.deleteById(id);
    }
}
```

**Database Optimization:**
- Use pagination for large datasets
- Implement query optimization (N+1 problem)
- Use database connection pooling
- Implement read replicas for read-heavy operations

### 9. Containerization

**Multi-stage Dockerfile:**
```dockerfile
# Build stage
FROM gradle:8.5-jdk21 AS builder
WORKDIR /app
COPY . .
RUN gradle clean build -x test

# Runtime stage
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=builder /app/build/libs/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**Docker Best Practices:**
- Use multi-stage builds
- Minimize layer count
- Use specific base image versions
- Run as non-root user
- Scan images for vulnerabilities (Trivy)

### 10. DevSecOps Integration

**Security Scanning:**
- OWASP Dependency Check (vulnerabilities)
- Trivy (container scanning)
- Snyk (dependency & IaC scanning)
- OWASP ZAP (penetration testing)
- Hadolint (Dockerfile linting)

**CI/CD Pipeline Stages:**
1. Code checkout
2. Build & compile
3. Unit tests
4. Static code analysis
5. Security scanning
6. Build Docker image
7. Integration tests
8. Deploy to staging
9. Smoke tests
10. Deploy to production

## Monitoring & Observability

### Custom Metrics with Micrometer

```java
@Service
public class BookingService {
    
    private final Counter bookingCounter;
    private final Timer bookingTimer;
    
    public BookingService(MeterRegistry registry) {
        this.bookingCounter = Counter.builder("bookings.created")
            .description("Total bookings created")
            .tag("service", "booking")
            .register(registry);
            
        this.bookingTimer = Timer.builder("bookings.creation.time")
            .description("Time to create booking")
            .register(registry);
    }
    
    @Timed(value = "bookings.create", percentiles = {0.5, 0.95, 0.99})
    public Booking createBooking(BookingRequest request) {
        return bookingTimer.record(() -> {
            Booking booking = // create booking
            bookingCounter.increment();
            return booking;
        });
    }
}
```

### Health Checks

```java
@Component
public class DatabaseHealthIndicator implements HealthIndicator {
    
    @Override
    public Health health() {
        try {
            // Check database connectivity
            return Health.up()
                .withDetail("database", "Available")
                .build();
        } catch (Exception e) {
            return Health.down()
                .withDetail("error", e.getMessage())
                .build();
        }
    }
}
```

## Deployment Considerations

### Kubernetes Deployment

**Key Resources:**
- Deployment: Application pods
- Service: Internal load balancing
- Ingress: External access
- ConfigMap: Configuration data
- Secret: Sensitive data
- HPA: Horizontal Pod Autoscaling

**Resource Limits:**
```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "500m"
  limits:
    memory: "1Gi"
    cpu: "1000m"
```

### Environment Variables

**Essential Variables:**
- SPRING_PROFILES_ACTIVE
- DATABASE_URL
- REDIS_URL
- KAFKA_BOOTSTRAP_SERVERS
- CONFIG_SERVER_URL
- EUREKA_SERVER_URL
- JWT_SECRET
- API_KEYS

## References

**Source Repositories:**
- [Spring PetClinic Microservices](https://github.com/spring-petclinic/spring-petclinic-microservices) - Official Spring example
- [Spring Boot Microservice Best Practices](https://github.com/abhisheksr01/spring-boot-microservice-best-practices) - Comprehensive patterns
- [Learn Microservices with Spring Boot 3](https://github.com/Book-Microservices-v3) - Book examples
- [Baeldung Clean Architecture](https://www.baeldung.com/spring-boot-clean-architecture) - Clean architecture guide

**Additional Resources:**
- Spring Boot 3 Documentation: https://spring.io/projects/spring-boot
- Spring Cloud Documentation: https://spring.io/projects/spring-cloud
- Microservices Patterns: https://microservices.io/patterns/
- 12-Factor App: https://12factor.net/

---

*Content rephrased for compliance with licensing restrictions. Original sources cited above.*
