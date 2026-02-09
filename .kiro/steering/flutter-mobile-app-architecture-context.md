---
inclusion: manual
---

# Flutter Mobile App Architecture Context

> When designing or implementing the Flutter mobile application, follow the patterns and standards in this document. It codifies best practices from popular GitHub repositories (guilherme-v/flutter-clean-architecture-example, ResoCoder patterns), official Flutter/Dart guidelines, and modern Flutter 3.x patterns from the community.

## 1. Project Structure (Feature-First Clean Architecture)

### Recommended Directory Structure

```
lib/
├── app/                          # Application bootstrap
│   ├── app.dart                  # Root MaterialApp widget
│   ├── router/                   # GoRouter configuration
│   └── di/                       # Dependency injection setup
│
├── core/                         # Shared core utilities
│   ├── constants/                # App-wide constants
│   ├── errors/                   # Custom exceptions and failures
│   ├── network/                  # Dio client, interceptors
│   ├── storage/                  # Local storage abstractions
│   ├── theme/                    # ThemeData, colors, typography
│   └── utils/                    # Helper functions
│
├── features/                     # Feature modules (domain-driven)
│   ├── auth/
│   │   ├── data/
│   │   │   ├── datasources/      # Remote and local data sources
│   │   │   ├── models/           # DTOs with JSON serialization
│   │   │   └── repositories/     # Repository implementations
│   │   ├── domain/
│   │   │   ├── entities/         # Business objects
│   │   │   ├── repositories/     # Repository interfaces
│   │   │   └── usecases/         # Business logic
│   │   └── presentation/
│   │       ├── bloc/             # BLoC/Cubit state management
│   │       ├── pages/            # Screen widgets
│   │       └── widgets/          # Feature-specific widgets
│   ├── bookings/
│   ├── courts/
│   └── profile/
│
├── shared/                       # Shared UI components
│   ├── widgets/                  # Reusable widgets
│   └── extensions/               # Dart extensions
│
└── main.dart                     # Entry point
```


### Feature Module Structure

Each feature follows Clean Architecture with three layers:

```
features/bookings/
├── data/
│   ├── datasources/
│   │   ├── booking_remote_datasource.dart
│   │   └── booking_local_datasource.dart
│   ├── models/
│   │   └── booking_model.dart        # DTO with fromJson/toJson
│   └── repositories/
│       └── booking_repository_impl.dart
├── domain/
│   ├── entities/
│   │   └── booking.dart              # Pure business object
│   ├── repositories/
│   │   └── booking_repository.dart   # Abstract interface
│   └── usecases/
│       ├── get_bookings.dart
│       ├── create_booking.dart
│       └── cancel_booking.dart
└── presentation/
    ├── bloc/
    │   ├── booking_bloc.dart
    │   ├── booking_event.dart
    │   └── booking_state.dart
    ├── pages/
    │   ├── bookings_page.dart
    │   └── booking_detail_page.dart
    └── widgets/
        ├── booking_card.dart
        └── booking_list.dart
```

### Import Rules

| Import Type | Pattern | Example |
|-------------|---------|---------|
| Within feature | Relative `./` | `import 'widgets/booking_card.dart'` |
| Cross-feature | Package import | `import 'package:app/features/auth/auth.dart'` |
| Core utilities | Package import | `import 'package:app/core/network/api_client.dart'` |
| Shared widgets | Package import | `import 'package:app/shared/widgets/widgets.dart'` |

## 2. Clean Architecture Layers

### Domain Layer (Innermost - No Dependencies)

```dart
// ✅ Entity - Pure business object, no framework dependencies
@freezed
class Booking with _$Booking {
  const factory Booking({
    required String id,
    required String courtId,
    required String userId,
    required DateTime startTime,
    required DateTime endTime,
    required BookingStatus status,
    String? notes,
  }) = _Booking;
}

enum BookingStatus { pending, confirmed, cancelled, completed }

// ✅ Repository interface - Defines contract
abstract class BookingRepository {
  Future<Either<Failure, List<Booking>>> getBookings();
  Future<Either<Failure, Booking>> getBookingById(String id);
  Future<Either<Failure, Booking>> createBooking(CreateBookingParams params);
  Future<Either<Failure, Unit>> cancelBooking(String id);
}

// ✅ Use Case - Single responsibility business logic
class GetBookings {
  final BookingRepository repository;

  GetBookings(this.repository);

  Future<Either<Failure, List<Booking>>> call() {
    return repository.getBookings();
  }
}

class CreateBooking {
  final BookingRepository repository;

  CreateBooking(this.repository);

  Future<Either<Failure, Booking>> call(CreateBookingParams params) {
    return repository.createBooking(params);
  }
}

@freezed
class CreateBookingParams with _$CreateBookingParams {
  const factory CreateBookingParams({
    required String courtId,
    required DateTime startTime,
    required DateTime endTime,
    String? notes,
  }) = _CreateBookingParams;
}
```


### Data Layer (Implements Domain Contracts)

```dart
// ✅ Model (DTO) - Handles serialization
@freezed
class BookingModel with _$BookingModel {
  const BookingModel._();

  const factory BookingModel({
    required String id,
    @JsonKey(name: 'court_id') required String courtId,
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(name: 'start_time') required DateTime startTime,
    @JsonKey(name: 'end_time') required DateTime endTime,
    required String status,
    String? notes,
  }) = _BookingModel;

  factory BookingModel.fromJson(Map<String, dynamic> json) =>
      _$BookingModelFromJson(json);

  // ✅ Mapper to domain entity
  Booking toEntity() => Booking(
        id: id,
        courtId: courtId,
        userId: userId,
        startTime: startTime,
        endTime: endTime,
        status: BookingStatus.values.byName(status),
        notes: notes,
      );

  factory BookingModel.fromEntity(Booking entity) => BookingModel(
        id: entity.id,
        courtId: entity.courtId,
        userId: entity.userId,
        startTime: entity.startTime,
        endTime: entity.endTime,
        status: entity.status.name,
        notes: entity.notes,
      );
}

// ✅ Remote Data Source - API calls
abstract class BookingRemoteDataSource {
  Future<List<BookingModel>> getBookings();
  Future<BookingModel> getBookingById(String id);
  Future<BookingModel> createBooking(Map<String, dynamic> data);
  Future<void> cancelBooking(String id);
}

class BookingRemoteDataSourceImpl implements BookingRemoteDataSource {
  final Dio dio;

  BookingRemoteDataSourceImpl(this.dio);

  @override
  Future<List<BookingModel>> getBookings() async {
    final response = await dio.get('/api/v1/bookings');
    return (response.data as List)
        .map((json) => BookingModel.fromJson(json))
        .toList();
  }

  @override
  Future<BookingModel> createBooking(Map<String, dynamic> data) async {
    final response = await dio.post('/api/v1/bookings', data: data);
    return BookingModel.fromJson(response.data);
  }
  
  // ... other methods
}

// ✅ Repository Implementation - Coordinates data sources
class BookingRepositoryImpl implements BookingRepository {
  final BookingRemoteDataSource remoteDataSource;
  final BookingLocalDataSource localDataSource;
  final NetworkInfo networkInfo;

  BookingRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.networkInfo,
  });

  @override
  Future<Either<Failure, List<Booking>>> getBookings() async {
    if (await networkInfo.isConnected) {
      try {
        final models = await remoteDataSource.getBookings();
        await localDataSource.cacheBookings(models);
        return Right(models.map((m) => m.toEntity()).toList());
      } on DioException catch (e) {
        return Left(ServerFailure(e.message ?? 'Server error'));
      }
    } else {
      try {
        final cached = await localDataSource.getCachedBookings();
        return Right(cached.map((m) => m.toEntity()).toList());
      } on CacheException {
        return Left(CacheFailure('No cached data available'));
      }
    }
  }
}
```


### Presentation Layer (UI + State Management)

```dart
// ✅ BLoC with Freezed states
@freezed
class BookingState with _$BookingState {
  const factory BookingState.initial() = _Initial;
  const factory BookingState.loading() = _Loading;
  const factory BookingState.loaded(List<Booking> bookings) = _Loaded;
  const factory BookingState.error(String message) = _Error;
}

@freezed
class BookingEvent with _$BookingEvent {
  const factory BookingEvent.loadBookings() = _LoadBookings;
  const factory BookingEvent.createBooking(CreateBookingParams params) = _CreateBooking;
  const factory BookingEvent.cancelBooking(String id) = _CancelBooking;
}

class BookingBloc extends Bloc<BookingEvent, BookingState> {
  final GetBookings getBookings;
  final CreateBooking createBooking;
  final CancelBooking cancelBooking;

  BookingBloc({
    required this.getBookings,
    required this.createBooking,
    required this.cancelBooking,
  }) : super(const BookingState.initial()) {
    on<_LoadBookings>(_onLoadBookings);
    on<_CreateBooking>(_onCreateBooking);
    on<_CancelBooking>(_onCancelBooking);
  }

  Future<void> _onLoadBookings(
    _LoadBookings event,
    Emitter<BookingState> emit,
  ) async {
    emit(const BookingState.loading());
    final result = await getBookings();
    result.fold(
      (failure) => emit(BookingState.error(failure.message)),
      (bookings) => emit(BookingState.loaded(bookings)),
    );
  }
}
```

## 3. State Management

### State Management Decision Tree

```
Is it server/async state?
├── YES → Use BLoC/Cubit (recommended) or Riverpod
└── NO → Is it shared across multiple widgets?
    ├── YES → Is it truly global (auth, theme, locale)?
    │   ├── YES → Use BLoC with BlocProvider at app level
    │   └── NO → Lift state up or use scoped BlocProvider
    └── NO → Use local StatefulWidget or ValueNotifier
```

### BLoC Pattern (Recommended for Enterprise)

```dart
// ✅ Cubit for simple state (no events)
class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);

  void increment() => emit(state + 1);
  void decrement() => emit(state - 1);
}

// ✅ BLoC for complex state with events
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final LoginUseCase loginUseCase;
  final LogoutUseCase logoutUseCase;
  final GetCurrentUserUseCase getCurrentUser;

  AuthBloc({
    required this.loginUseCase,
    required this.logoutUseCase,
    required this.getCurrentUser,
  }) : super(const AuthState.initial()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<LoginRequested>(_onLoginRequested);
    on<LogoutRequested>(_onLogoutRequested);
  }

  Future<void> _onLoginRequested(
    LoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthState.loading());
    final result = await loginUseCase(
      LoginParams(email: event.email, password: event.password),
    );
    result.fold(
      (failure) => emit(AuthState.error(failure.message)),
      (user) => emit(AuthState.authenticated(user)),
    );
  }
}

// ✅ BlocBuilder for reactive UI
class BookingsPage extends StatelessWidget {
  const BookingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BookingBloc, BookingState>(
      builder: (context, state) {
        return state.when(
          initial: () => const SizedBox.shrink(),
          loading: () => const Center(child: CircularProgressIndicator()),
          loaded: (bookings) => BookingList(bookings: bookings),
          error: (message) => ErrorWidget(message: message),
        );
      },
    );
  }
}

// ✅ BlocListener for side effects (navigation, snackbars)
BlocListener<AuthBloc, AuthState>(
  listener: (context, state) {
    state.maybeWhen(
      authenticated: (_) => context.go('/home'),
      error: (message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      ),
      orElse: () {},
    );
  },
  child: const LoginForm(),
)
```


### Riverpod Alternative (Modern, Compile-Safe)

```dart
// ✅ Riverpod 3.x with code generation
@riverpod
class BookingNotifier extends _$BookingNotifier {
  @override
  Future<List<Booking>> build() async {
    final repository = ref.watch(bookingRepositoryProvider);
    final result = await repository.getBookings();
    return result.fold(
      (failure) => throw failure,
      (bookings) => bookings,
    );
  }

  Future<void> createBooking(CreateBookingParams params) async {
    state = const AsyncLoading();
    final repository = ref.read(bookingRepositoryProvider);
    final result = await repository.createBooking(params);
    result.fold(
      (failure) => state = AsyncError(failure, StackTrace.current),
      (booking) => ref.invalidateSelf(),
    );
  }
}

// ✅ Usage in widget
class BookingsPage extends ConsumerWidget {
  const BookingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(bookingNotifierProvider);

    return bookingsAsync.when(
      data: (bookings) => BookingList(bookings: bookings),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => ErrorWidget(message: error.toString()),
    );
  }
}
```

## 4. Dependency Injection

### GetIt + Injectable (Recommended)

```dart
// ✅ injection.dart - Setup
final getIt = GetIt.instance;

@InjectableInit(preferRelativeImports: false)
Future<void> configureDependencies() async => getIt.init();

// ✅ Module registration with Injectable
@module
abstract class RegisterModule {
  @lazySingleton
  Dio get dio => Dio(BaseOptions(
        baseUrl: Environment.apiBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
      ))
        ..interceptors.addAll([
          AuthInterceptor(getIt()),
          LoggingInterceptor(),
          ErrorInterceptor(),
        ]);

  @lazySingleton
  SharedPreferences get prefs => getIt.getAsync<SharedPreferences>();

  @preResolve
  Future<SharedPreferences> get sharedPreferences =>
      SharedPreferences.getInstance();
}

// ✅ Auto-registration with annotations
@lazySingleton
class BookingRemoteDataSourceImpl implements BookingRemoteDataSource {
  final Dio dio;

  BookingRemoteDataSourceImpl(this.dio);
  // ...
}

@LazySingleton(as: BookingRepository)
class BookingRepositoryImpl implements BookingRepository {
  final BookingRemoteDataSource remoteDataSource;
  final BookingLocalDataSource localDataSource;
  final NetworkInfo networkInfo;

  BookingRepositoryImpl(
    this.remoteDataSource,
    this.localDataSource,
    this.networkInfo,
  );
  // ...
}

@injectable
class GetBookings {
  final BookingRepository repository;

  GetBookings(this.repository);
  // ...
}

@injectable
class BookingBloc extends Bloc<BookingEvent, BookingState> {
  BookingBloc(
    GetBookings getBookings,
    CreateBooking createBooking,
    CancelBooking cancelBooking,
  ) : super(const BookingState.initial()) {
    // ...
  }
}
```

## 5. Navigation (GoRouter)

### Router Configuration

```dart
// ✅ Type-safe routing with GoRouter
final goRouter = GoRouter(
  initialLocation: '/',
  debugLogDiagnostics: true,
  refreshListenable: authNotifier,
  redirect: (context, state) {
    final isAuthenticated = authNotifier.isAuthenticated;
    final isAuthRoute = state.matchedLocation.startsWith('/auth');

    if (!isAuthenticated && !isAuthRoute) {
      return '/auth/login';
    }
    if (isAuthenticated && isAuthRoute) {
      return '/';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomePage(),
      routes: [
        GoRoute(
          path: 'bookings',
          builder: (context, state) => const BookingsPage(),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) {
                final id = state.pathParameters['id']!;
                return BookingDetailPage(bookingId: id);
              },
            ),
          ],
        ),
        GoRoute(
          path: 'courts',
          builder: (context, state) => const CourtsPage(),
        ),
        GoRoute(
          path: 'profile',
          builder: (context, state) => const ProfilePage(),
        ),
      ],
    ),
    GoRoute(
      path: '/auth',
      builder: (context, state) => const AuthPage(),
      routes: [
        GoRoute(
          path: 'login',
          builder: (context, state) => const LoginPage(),
        ),
        GoRoute(
          path: 'register',
          builder: (context, state) => const RegisterPage(),
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) => ErrorPage(error: state.error),
);

// ✅ Navigation usage
context.go('/bookings');                    // Replace entire stack
context.push('/bookings/123');              // Push onto stack
context.pop();                              // Go back
context.goNamed('bookingDetail', pathParameters: {'id': '123'});
```


## 6. Network Layer (Dio)

### API Client Setup

```dart
// ✅ Dio configuration with interceptors
class ApiClient {
  late final Dio _dio;

  ApiClient({required String baseUrl, required TokenStorage tokenStorage}) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    _dio.interceptors.addAll([
      AuthInterceptor(tokenStorage),
      LoggingInterceptor(),
      RetryInterceptor(dio: _dio, retries: 3),
    ]);
  }

  Dio get dio => _dio;
}

// ✅ Auth interceptor for token injection
class AuthInterceptor extends Interceptor {
  final TokenStorage tokenStorage;

  AuthInterceptor(this.tokenStorage);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = tokenStorage.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      // Attempt token refresh
      try {
        await tokenStorage.refreshToken();
        final newToken = tokenStorage.accessToken;
        err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
        
        final response = await _dio.fetch(err.requestOptions);
        handler.resolve(response);
        return;
      } catch (e) {
        // Refresh failed, logout user
        tokenStorage.clear();
      }
    }
    handler.next(err);
  }
}

// ✅ Error handling interceptor
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final failure = switch (err.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        NetworkFailure('Connection timeout'),
      DioExceptionType.connectionError =>
        NetworkFailure('No internet connection'),
      DioExceptionType.badResponse => _handleBadResponse(err.response),
      _ => ServerFailure(err.message ?? 'Unknown error'),
    };
    
    handler.reject(DioException(
      requestOptions: err.requestOptions,
      error: failure,
    ));
  }

  Failure _handleBadResponse(Response? response) {
    return switch (response?.statusCode) {
      400 => ValidationFailure(response?.data['message'] ?? 'Bad request'),
      401 => AuthFailure('Unauthorized'),
      403 => AuthFailure('Forbidden'),
      404 => NotFoundFailure('Resource not found'),
      422 => ValidationFailure(response?.data['message'] ?? 'Validation error'),
      500 => ServerFailure('Internal server error'),
      _ => ServerFailure('Server error: ${response?.statusCode}'),
    };
  }
}
```

### Error Handling with Either (fpdart)

```dart
// ✅ Failure types
sealed class Failure {
  final String message;
  const Failure(this.message);
}

class ServerFailure extends Failure {
  const ServerFailure(super.message);
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

class CacheFailure extends Failure {
  const CacheFailure(super.message);
}

class ValidationFailure extends Failure {
  final Map<String, List<String>>? fieldErrors;
  const ValidationFailure(super.message, {this.fieldErrors});
}

class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

// ✅ Repository returns Either<Failure, Success>
Future<Either<Failure, List<Booking>>> getBookings() async {
  try {
    final response = await dio.get('/bookings');
    final bookings = (response.data as List)
        .map((json) => BookingModel.fromJson(json).toEntity())
        .toList();
    return Right(bookings);
  } on DioException catch (e) {
    if (e.error is Failure) {
      return Left(e.error as Failure);
    }
    return Left(ServerFailure(e.message ?? 'Unknown error'));
  }
}
```


## 7. Code Generation (Freezed + JSON Serializable)

### Model Definition with Freezed

```dart
// ✅ Immutable data class with Freezed
import 'package:freezed_annotation/freezed_annotation.dart';

part 'booking.freezed.dart';
part 'booking.g.dart';

@freezed
class Booking with _$Booking {
  const factory Booking({
    required String id,
    required String courtId,
    required String userId,
    required DateTime startTime,
    required DateTime endTime,
    @Default(BookingStatus.pending) BookingStatus status,
    String? notes,
    @Default([]) List<String> participants,
  }) = _Booking;

  // ✅ Custom methods on freezed class
  const Booking._();

  bool get isPast => endTime.isBefore(DateTime.now());
  bool get isActive => status == BookingStatus.confirmed && !isPast;
  Duration get duration => endTime.difference(startTime);

  factory Booking.fromJson(Map<String, dynamic> json) =>
      _$BookingFromJson(json);
}

// ✅ Union types for state
@freezed
sealed class BookingState with _$BookingState {
  const factory BookingState.initial() = BookingInitial;
  const factory BookingState.loading() = BookingLoading;
  const factory BookingState.loaded(List<Booking> bookings) = BookingLoaded;
  const factory BookingState.error(String message) = BookingError;
}

// ✅ Pattern matching with when/map
Widget buildContent(BookingState state) {
  return state.when(
    initial: () => const SizedBox.shrink(),
    loading: () => const CircularProgressIndicator(),
    loaded: (bookings) => BookingList(bookings: bookings),
    error: (message) => Text('Error: $message'),
  );
}

// ✅ copyWith for immutable updates
final updatedBooking = booking.copyWith(
  status: BookingStatus.confirmed,
  notes: 'Updated notes',
);
```

### Build Runner Commands

```bash
# Generate code once
dart run build_runner build --delete-conflicting-outputs

# Watch for changes (development)
dart run build_runner watch --delete-conflicting-outputs

# Clean generated files
dart run build_runner clean
```

## 8. Testing Standards

### Test Pyramid

```
        /\
       /E2E\      ← Few: integration_test (critical user flows)
      /------\
     /Widget \   ← Some: Widget tests with mocked dependencies
    /----------\
   /   Unit     \ ← Many: Use cases, BLoCs, repositories
  /--------------\
```

### Unit Testing

```dart
// ✅ Use case test
void main() {
  late GetBookings useCase;
  late MockBookingRepository mockRepository;

  setUp(() {
    mockRepository = MockBookingRepository();
    useCase = GetBookings(mockRepository);
  });

  group('GetBookings', () {
    final tBookings = [
      Booking(
        id: '1',
        courtId: 'court-1',
        userId: 'user-1',
        startTime: DateTime(2026, 3, 15, 10, 0),
        endTime: DateTime(2026, 3, 15, 11, 0),
        status: BookingStatus.confirmed,
      ),
    ];

    test('should return list of bookings from repository', () async {
      // Arrange
      when(() => mockRepository.getBookings())
          .thenAnswer((_) async => Right(tBookings));

      // Act
      final result = await useCase();

      // Assert
      expect(result, Right(tBookings));
      verify(() => mockRepository.getBookings()).called(1);
      verifyNoMoreInteractions(mockRepository);
    });

    test('should return failure when repository fails', () async {
      // Arrange
      when(() => mockRepository.getBookings())
          .thenAnswer((_) async => Left(ServerFailure('Server error')));

      // Act
      final result = await useCase();

      // Assert
      expect(result, isA<Left<Failure, List<Booking>>>());
    });
  });
}

// ✅ BLoC test with bloc_test
void main() {
  late BookingBloc bloc;
  late MockGetBookings mockGetBookings;

  setUp(() {
    mockGetBookings = MockGetBookings();
    bloc = BookingBloc(getBookings: mockGetBookings);
  });

  tearDown(() => bloc.close());

  group('BookingBloc', () {
    final tBookings = [/* ... */];

    blocTest<BookingBloc, BookingState>(
      'emits [loading, loaded] when LoadBookings is successful',
      build: () {
        when(() => mockGetBookings())
            .thenAnswer((_) async => Right(tBookings));
        return bloc;
      },
      act: (bloc) => bloc.add(const BookingEvent.loadBookings()),
      expect: () => [
        const BookingState.loading(),
        BookingState.loaded(tBookings),
      ],
    );

    blocTest<BookingBloc, BookingState>(
      'emits [loading, error] when LoadBookings fails',
      build: () {
        when(() => mockGetBookings())
            .thenAnswer((_) async => Left(ServerFailure('Error')));
        return bloc;
      },
      act: (bloc) => bloc.add(const BookingEvent.loadBookings()),
      expect: () => [
        const BookingState.loading(),
        const BookingState.error('Error'),
      ],
    );
  });
}
```


### Widget Testing

```dart
// ✅ Widget test with mocked BLoC
void main() {
  late MockBookingBloc mockBloc;

  setUp(() {
    mockBloc = MockBookingBloc();
  });

  Widget buildTestWidget() {
    return MaterialApp(
      home: BlocProvider<BookingBloc>.value(
        value: mockBloc,
        child: const BookingsPage(),
      ),
    );
  }

  group('BookingsPage', () {
    testWidgets('shows loading indicator when state is loading', (tester) async {
      when(() => mockBloc.state).thenReturn(const BookingState.loading());

      await tester.pumpWidget(buildTestWidget());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows booking list when state is loaded', (tester) async {
      final bookings = [/* ... */];
      when(() => mockBloc.state).thenReturn(BookingState.loaded(bookings));

      await tester.pumpWidget(buildTestWidget());

      expect(find.byType(BookingCard), findsNWidgets(bookings.length));
    });

    testWidgets('shows error message when state is error', (tester) async {
      when(() => mockBloc.state)
          .thenReturn(const BookingState.error('Something went wrong'));

      await tester.pumpWidget(buildTestWidget());

      expect(find.text('Something went wrong'), findsOneWidget);
    });
  });
}
```

### Integration Testing

```dart
// integration_test/booking_flow_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Booking Flow', () {
    testWidgets('user can create a new booking', (tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // Navigate to bookings
      await tester.tap(find.byIcon(Icons.calendar_today));
      await tester.pumpAndSettle();

      // Tap create button
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Fill form
      await tester.tap(find.byKey(const Key('court_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Court A').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('date_picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.text('Create Booking'));
      await tester.pumpAndSettle();

      // Verify success
      expect(find.text('Booking created successfully'), findsOneWidget);
    });
  });
}
```

## 9. Performance Optimization

### Widget Optimization

```dart
// ✅ Use const constructors
class BookingCard extends StatelessWidget {
  const BookingCard({super.key, required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return const Card(  // const where possible
      child: Padding(
        padding: EdgeInsets.all(16),  // const
        child: Column(
          children: [
            // ...
          ],
        ),
      ),
    );
  }
}

// ✅ Split widgets to minimize rebuilds
class BookingsPage extends StatelessWidget {
  const BookingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BookingsAppBar(),  // Separate widget, won't rebuild
      body: const BookingsList(),       // Only this rebuilds on state change
      floatingActionButton: const CreateBookingFab(),
    );
  }
}

// ✅ Use ListView.builder for long lists
ListView.builder(
  itemCount: bookings.length,
  itemBuilder: (context, index) => BookingCard(
    key: ValueKey(bookings[index].id),  // Stable keys
    booking: bookings[index],
  ),
)

// ✅ Use RepaintBoundary for complex widgets
RepaintBoundary(
  child: ComplexAnimatedWidget(),
)

// ✅ Avoid rebuilding entire tree - use selectors
BlocSelector<BookingBloc, BookingState, int>(
  selector: (state) => state.maybeWhen(
    loaded: (bookings) => bookings.length,
    orElse: () => 0,
  ),
  builder: (context, count) => Text('$count bookings'),
)
```

### Image Optimization

```dart
// ✅ Use cached_network_image
CachedNetworkImage(
  imageUrl: court.imageUrl,
  placeholder: (context, url) => const Shimmer(),
  errorWidget: (context, url, error) => const Icon(Icons.error),
  memCacheWidth: 300,  // Resize in memory
  memCacheHeight: 200,
)

// ✅ Precache images
@override
void didChangeDependencies() {
  super.didChangeDependencies();
  precacheImage(AssetImage('assets/images/logo.png'), context);
}
```

### Async Operations

```dart
// ✅ Use compute for heavy operations
final result = await compute(parseJsonInBackground, jsonString);

// ✅ Debounce search input
final _searchController = TextEditingController();
Timer? _debounce;

void _onSearchChanged(String query) {
  _debounce?.cancel();
  _debounce = Timer(const Duration(milliseconds: 500), () {
    context.read<SearchBloc>().add(SearchEvent.search(query));
  });
}

@override
void dispose() {
  _debounce?.cancel();
  _searchController.dispose();
  super.dispose();
}
```


## 10. Accessibility (a11y)

### Semantic Widgets

```dart
// ✅ Use Semantics for custom widgets
Semantics(
  label: 'Book court ${court.name}',
  hint: 'Double tap to view available times',
  button: true,
  child: GestureDetector(
    onTap: () => _showBookingDialog(court),
    child: CourtCard(court: court),
  ),
)

// ✅ Exclude decorative elements
Semantics(
  excludeSemantics: true,
  child: DecorativeImage(),
)

// ✅ Merge semantics for grouped content
MergeSemantics(
  child: Row(
    children: [
      Icon(Icons.calendar_today),
      Text('March 15, 2026'),
    ],
  ),
)

// ✅ Provide semantic labels for icons
IconButton(
  icon: const Icon(Icons.delete),
  tooltip: 'Delete booking',  // Also serves as semantic label
  onPressed: _deleteBooking,
)

// ✅ Use semantic properties on images
Image.asset(
  'assets/court.png',
  semanticLabel: 'Tennis court with green surface',
)
```

### Focus Management

```dart
// ✅ Manage focus order
FocusTraversalGroup(
  policy: OrderedTraversalPolicy(),
  child: Column(
    children: [
      FocusTraversalOrder(
        order: const NumericFocusOrder(1),
        child: TextField(decoration: InputDecoration(labelText: 'Email')),
      ),
      FocusTraversalOrder(
        order: const NumericFocusOrder(2),
        child: TextField(decoration: InputDecoration(labelText: 'Password')),
      ),
      FocusTraversalOrder(
        order: const NumericFocusOrder(3),
        child: ElevatedButton(onPressed: _login, child: Text('Login')),
      ),
    ],
  ),
)

// ✅ Request focus programmatically
final _emailFocusNode = FocusNode();

@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _emailFocusNode.requestFocus();
  });
}
```

### Text Scaling

```dart
// ✅ Support dynamic text scaling
Text(
  'Booking confirmed',
  style: Theme.of(context).textTheme.titleLarge,
  // Don't use fixed font sizes
)

// ✅ Test with large text
MediaQuery(
  data: MediaQuery.of(context).copyWith(textScaleFactor: 2.0),
  child: MyWidget(),
)
```

## 11. Code Style & Linting

### analysis_options.yaml

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "**/*.mocks.dart"
  errors:
    invalid_annotation_target: ignore
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true

linter:
  rules:
    # Error rules
    - avoid_dynamic_calls
    - avoid_returning_null_for_future
    - avoid_slow_async_io
    - cancel_subscriptions
    - close_sinks
    - literal_only_boolean_expressions
    - throw_in_finally
    - unnecessary_statements

    # Style rules
    - always_declare_return_types
    - always_put_required_named_parameters_first
    - avoid_bool_literals_in_conditional_expressions
    - avoid_catches_without_on_clauses
    - avoid_catching_errors
    - avoid_classes_with_only_static_members
    - avoid_double_and_int_checks
    - avoid_equals_and_hash_code_on_mutable_classes
    - avoid_escaping_inner_quotes
    - avoid_field_initializers_in_const_classes
    - avoid_final_parameters
    - avoid_implementing_value_types
    - avoid_multiple_declarations_per_line
    - avoid_positional_boolean_parameters
    - avoid_private_typedef_functions
    - avoid_redundant_argument_values
    - avoid_returning_this
    - avoid_setters_without_getters
    - avoid_types_on_closure_parameters
    - avoid_unused_constructor_parameters
    - avoid_void_async
    - cascade_invocations
    - cast_nullable_to_non_nullable
    - combinators_ordering
    - conditional_uri_does_not_exist
    - deprecated_consistency
    - directives_ordering
    - eol_at_end_of_file
    - flutter_style_todos
    - join_return_with_assignment
    - leading_newlines_in_multiline_strings
    - missing_whitespace_between_adjacent_strings
    - no_adjacent_strings_in_list
    - no_runtimeType_toString
    - noop_primitive_operations
    - omit_local_variable_types
    - one_member_abstracts
    - only_throw_errors
    - parameter_assignments
    - prefer_asserts_in_initializer_lists
    - prefer_constructors_over_static_methods
    - prefer_final_in_for_each
    - prefer_final_locals
    - prefer_if_elements_to_conditional_expressions
    - prefer_int_literals
    - prefer_mixin
    - prefer_null_aware_method_calls
    - prefer_single_quotes
    - require_trailing_commas
    - sort_constructors_first
    - sort_unnamed_constructors_first
    - tighten_type_of_initializing_formals
    - type_annotate_public_apis
    - unawaited_futures
    - unnecessary_await_in_return
    - unnecessary_breaks
    - unnecessary_lambdas
    - unnecessary_null_aware_operator_on_extension_on_nullable
    - unnecessary_null_checks
    - unnecessary_parenthesis
    - unnecessary_raw_strings
    - unnecessary_to_list_in_spreads
    - unreachable_from_main
    - use_colored_box
    - use_decorated_box
    - use_enums
    - use_if_null_to_convert_nulls_to_bools
    - use_is_even_rather_than_modulo
    - use_late_for_private_fields_and_variables
    - use_named_constants
    - use_raw_strings
    - use_setters_to_change_properties
    - use_string_buffers
    - use_super_parameters
    - use_test_throws_matchers
    - use_to_and_as_if_applicable
```


### Naming Conventions

| Category | Convention | Example |
|----------|------------|---------|
| Files | snake_case | `booking_repository.dart`, `booking_bloc.dart` |
| Classes | PascalCase | `BookingRepository`, `BookingBloc` |
| Variables/Functions | camelCase | `getBookings`, `isLoading` |
| Constants | lowerCamelCase | `defaultTimeout`, `maxRetries` |
| Private members | _prefix | `_bookings`, `_handleError` |
| BLoC Events | PascalCase | `LoadBookings`, `CreateBooking` |
| BLoC States | PascalCase | `BookingLoading`, `BookingLoaded` |
| Widgets | PascalCase | `BookingCard`, `BookingList` |
| Extensions | on + Type | `StringExtension`, `DateTimeExtension` |

## 12. Recommended Package Stack

### Core Dependencies

| Category | Package | Version | Purpose |
|----------|---------|---------|---------|
| State Management | flutter_bloc | ^8.1.x | BLoC pattern implementation |
| State Management | bloc | ^8.1.x | BLoC core |
| DI | get_it | ^7.6.x | Service locator |
| DI | injectable | ^2.3.x | Code generation for DI |
| Navigation | go_router | ^14.x | Declarative routing |
| Network | dio | ^5.4.x | HTTP client |
| Serialization | freezed | ^2.4.x | Immutable classes |
| Serialization | json_serializable | ^6.7.x | JSON serialization |
| Functional | fpdart | ^1.1.x | Either, Option types |
| Local Storage | shared_preferences | ^2.2.x | Key-value storage |
| Local Storage | hive_flutter | ^1.1.x | NoSQL database |
| Images | cached_network_image | ^3.3.x | Image caching |

### Dev Dependencies

| Category | Package | Version | Purpose |
|----------|---------|---------|---------|
| Code Gen | build_runner | ^2.4.x | Code generation |
| Code Gen | injectable_generator | ^2.4.x | DI code gen |
| Code Gen | freezed_annotation | ^2.4.x | Freezed annotations |
| Testing | mocktail | ^1.0.x | Mocking |
| Testing | bloc_test | ^9.1.x | BLoC testing |
| Linting | flutter_lints | ^4.0.x | Lint rules |

### pubspec.yaml Example

```yaml
name: court_booking_app
description: Court booking mobile application
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.2.0 <4.0.0'
  flutter: '>=3.16.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter

  # State Management
  flutter_bloc: ^8.1.6
  bloc: ^8.1.4

  # Dependency Injection
  get_it: ^7.6.7
  injectable: ^2.3.2

  # Navigation
  go_router: ^14.0.2

  # Network
  dio: ^5.4.1
  connectivity_plus: ^6.0.2

  # Data Classes
  freezed_annotation: ^2.4.1
  json_annotation: ^4.8.1
  fpdart: ^1.1.0

  # Local Storage
  shared_preferences: ^2.2.2
  hive_flutter: ^1.1.0

  # UI
  cached_network_image: ^3.3.1
  shimmer: ^3.0.0
  flutter_svg: ^2.0.10+1

  # Utils
  intl: ^0.19.0
  equatable: ^2.0.5
  uuid: ^4.3.3

dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter

  # Code Generation
  build_runner: ^2.4.8
  freezed: ^2.4.7
  json_serializable: ^6.7.1
  injectable_generator: ^2.4.1

  # Testing
  mocktail: ^1.0.3
  bloc_test: ^9.1.7

  # Linting
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - assets/icons/
```

## 13. Form Handling & Validation

### Form with Reactive Validation

```dart
// ✅ Form with BLoC validation
@freezed
class LoginFormState with _$LoginFormState {
  const factory LoginFormState({
    @Default('') String email,
    @Default('') String password,
    @Default(null) String? emailError,
    @Default(null) String? passwordError,
    @Default(false) bool isSubmitting,
    @Default(false) bool isValid,
  }) = _LoginFormState;
}

class LoginFormCubit extends Cubit<LoginFormState> {
  LoginFormCubit() : super(const LoginFormState());

  void emailChanged(String value) {
    final error = _validateEmail(value);
    emit(state.copyWith(
      email: value,
      emailError: error,
      isValid: error == null && state.passwordError == null,
    ));
  }

  void passwordChanged(String value) {
    final error = _validatePassword(value);
    emit(state.copyWith(
      password: value,
      passwordError: error,
      isValid: state.emailError == null && error == null,
    ));
  }

  String? _validateEmail(String value) {
    if (value.isEmpty) return 'Email is required';
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
      return 'Invalid email format';
    }
    return null;
  }

  String? _validatePassword(String value) {
    if (value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Password must be at least 8 characters';
    return null;
  }
}

// ✅ Form widget
class LoginForm extends StatelessWidget {
  const LoginForm({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoginFormCubit, LoginFormState>(
      builder: (context, state) {
        return Column(
          children: [
            TextField(
              onChanged: context.read<LoginFormCubit>().emailChanged,
              decoration: InputDecoration(
                labelText: 'Email',
                errorText: state.emailError,
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextField(
              onChanged: context.read<LoginFormCubit>().passwordChanged,
              decoration: InputDecoration(
                labelText: 'Password',
                errorText: state.passwordError,
              ),
              obscureText: true,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: state.isValid && !state.isSubmitting
                  ? () => _submit(context)
                  : null,
              child: state.isSubmitting
                  ? const CircularProgressIndicator()
                  : const Text('Login'),
            ),
          ],
        );
      },
    );
  }
}
```

## 14. Theming

### Theme Configuration

```dart
// ✅ Theme data with Material 3
class AppTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E7D32),  // Primary green
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      cardTheme: CardTheme(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceVariant.withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontWeight: FontWeight.bold),
        titleLarge: TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E7D32),
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // ... similar customizations
    );
  }
}

// ✅ Theme mode management with BLoC
class ThemeCubit extends HydratedCubit<ThemeMode> {
  ThemeCubit() : super(ThemeMode.system);

  void setTheme(ThemeMode mode) => emit(mode);

  @override
  ThemeMode fromJson(Map<String, dynamic> json) {
    return ThemeMode.values.byName(json['mode'] as String);
  }

  @override
  Map<String, dynamic> toJson(ThemeMode state) {
    return {'mode': state.name};
  }
}
```

## 15. Localization (i18n)

### Setup with flutter_localizations

```dart
// ✅ l10n.yaml configuration
// arb-dir: lib/l10n
// template-arb-file: app_en.arb
// output-localization-file: app_localizations.dart

// ✅ lib/l10n/app_en.arb
{
  "@@locale": "en",
  "appTitle": "Court Booking",
  "bookings": "Bookings",
  "courts": "Courts",
  "profile": "Profile",
  "login": "Login",
  "logout": "Logout",
  "email": "Email",
  "password": "Password",
  "bookingConfirmed": "Booking confirmed for {date}",
  "@bookingConfirmed": {
    "placeholders": {
      "date": {
        "type": "DateTime",
        "format": "yMMMd"
      }
    }
  },
  "bookingsCount": "{count, plural, =0{No bookings} =1{1 booking} other{{count} bookings}}",
  "@bookingsCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  }
}

// ✅ Usage in widgets
Text(AppLocalizations.of(context)!.bookings)
Text(AppLocalizations.of(context)!.bookingConfirmed(DateTime.now()))
Text(AppLocalizations.of(context)!.bookingsCount(5))

// ✅ Locale management
class LocaleCubit extends HydratedCubit<Locale> {
  LocaleCubit() : super(const Locale('en'));

  void setLocale(Locale locale) => emit(locale);

  @override
  Locale fromJson(Map<String, dynamic> json) {
    return Locale(json['languageCode'] as String);
  }

  @override
  Map<String, dynamic> toJson(Locale state) {
    return {'languageCode': state.languageCode};
  }
}
```

## 16. App Entry Point

### main.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/di/injection.dart';
import 'app/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize dependencies
  await configureDependencies();
  
  // Initialize Hive for local storage
  await Hive.initFlutter();
  
  // Run app
  runApp(const CourtBookingApp());
}

class CourtBookingApp extends StatelessWidget {
  const CourtBookingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => getIt<AuthBloc>()..add(const AuthCheckRequested())),
        BlocProvider(create: (_) => getIt<ThemeCubit>()),
        BlocProvider(create: (_) => getIt<LocaleCubit>()),
      ],
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) {
          return BlocBuilder<LocaleCubit, Locale>(
            builder: (context, locale) {
              return MaterialApp.router(
                title: 'Court Booking',
                debugShowCheckedModeBanner: false,
                
                // Theme
                theme: AppTheme.light(),
                darkTheme: AppTheme.dark(),
                themeMode: themeMode,
                
                // Localization
                locale: locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                
                // Router
                routerConfig: appRouter,
              );
            },
          );
        },
      ),
    );
  }
}
```

## 17. Environment Configuration

```dart
// ✅ Environment-specific configuration
abstract class Environment {
  static const String dev = 'dev';
  static const String staging = 'staging';
  static const String prod = 'prod';

  static String get current => const String.fromEnvironment(
        'ENV',
        defaultValue: dev,
      );

  static String get apiBaseUrl => switch (current) {
        dev => 'https://api-dev.courtbooking.com',
        staging => 'https://api-staging.courtbooking.com',
        prod => 'https://api.courtbooking.com',
        _ => 'https://api-dev.courtbooking.com',
      };

  static bool get isDebug => current == dev;
}

// ✅ Run with environment
// flutter run --dart-define=ENV=prod
// flutter build apk --dart-define=ENV=prod
```

## 18. Quick Reference

### File Templates

```dart
// ✅ Feature barrel export (features/bookings/bookings.dart)
export 'data/datasources/booking_remote_datasource.dart';
export 'data/models/booking_model.dart';
export 'data/repositories/booking_repository_impl.dart';
export 'domain/entities/booking.dart';
export 'domain/repositories/booking_repository.dart';
export 'domain/usecases/get_bookings.dart';
export 'domain/usecases/create_booking.dart';
export 'presentation/bloc/booking_bloc.dart';
export 'presentation/pages/bookings_page.dart';
```

### Common Commands

```bash
# Run app
flutter run

# Run with environment
flutter run --dart-define=ENV=prod

# Generate code
dart run build_runner build --delete-conflicting-outputs

# Run tests
flutter test

# Run integration tests
flutter test integration_test

# Analyze code
flutter analyze

# Format code
dart format .

# Build release
flutter build apk --release --dart-define=ENV=prod
flutter build ios --release --dart-define=ENV=prod
```

---

> Sources: [guilherme-v/flutter-clean-architecture-example](https://github.com/guilherme-v/flutter-clean-architecture-example), [codewithandrea.com](https://codewithandrea.com/articles/flutter-project-structure/), [Flutter Official Docs](https://docs.flutter.dev), [pub.dev](https://pub.dev). Content was rephrased for compliance with licensing restrictions.
