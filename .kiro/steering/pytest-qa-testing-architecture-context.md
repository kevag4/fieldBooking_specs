---
inclusion: manual
---

# Pytest QA Testing Architecture Context

> Comprehensive guide for building a production-grade pytest testing suite for mobile cross-platform applications. Based on best practices from pytest official documentation, Appium Python Client, pytest-bdd, Locust, and industry-standard testing patterns.

## 1. Project Structure & Organization

### Recommended Directory Layout (src layout)

```
tests/
├── conftest.py                    # Root fixtures, plugins, hooks
├── pytest.ini                     # Pytest configuration
├── pyproject.toml                 # Project metadata and dependencies
│
├── functional/                    # Functional API tests
│   ├── conftest.py               # Functional test fixtures
│   ├── factories/                # pytest-factoryboy factories
│   │   ├── __init__.py
│   │   ├── user_factory.py
│   │   ├── booking_factory.py
│   │   └── court_factory.py
│   ├── test_auth.py
│   ├── test_bookings.py
│   └── test_payments.py
│
├── stress/                        # Load and stress tests
│   ├── conftest.py
│   ├── locustfile.py             # Locust scenarios
│   └── reports/
│
├── mobile/                        # Mobile cross-platform tests
│   ├── conftest.py               # Appium fixtures
│   ├── pages/                    # Page Object Models
│   │   ├── __init__.py
│   │   ├── base_page.py
│   │   ├── login_page.py
│   │   └── booking_page.py
│   ├── ios/
│   │   └── test_ios_flows.py
│   └── android/
│       └── test_android_flows.py
│
├── bdd/                           # BDD feature tests
│   ├── features/
│   │   ├── booking.feature
│   │   └── payment.feature
│   ├── step_defs/
│   │   ├── conftest.py
│   │   └── test_booking_steps.py
│   └── conftest.py
│
└── utils/                         # Shared utilities
    ├── __init__.py
    ├── api_client.py
    ├── assertions.py
    └── data_generators.py
```


## 2. Pytest Configuration Best Practices

### pytest.ini / pyproject.toml Configuration

```toml
# pyproject.toml
[tool.pytest.ini_options]
minversion = "8.0"
testpaths = ["tests"]
python_files = ["test_*.py", "*_test.py"]
python_classes = ["Test*"]
python_functions = ["test_*"]

# Import mode for better isolation
addopts = [
    "--import-mode=importlib",
    "--strict-markers",
    "--strict-config",
    "-ra",                          # Show extra test summary
    "--tb=short",                   # Shorter tracebacks
]

# Marker definitions (required with strict-markers)
markers = [
    "smoke: Quick sanity tests for deployment verification",
    "slow: Tests that take > 5 seconds",
    "integration: Tests requiring external services",
    "mobile: Mobile device tests (iOS/Android)",
    "ios: iOS-specific tests",
    "android: Android-specific tests",
    "api: API endpoint tests",
    "stress: Load and stress tests",
    "wip: Work in progress tests",
]

# Logging configuration
log_cli = true
log_cli_level = "INFO"
log_cli_format = "%(asctime)s [%(levelname)8s] %(name)s: %(message)s"
log_cli_date_format = "%Y-%m-%d %H:%M:%S"

# Async mode for pytest-asyncio
asyncio_mode = "auto"

# Timeout for hanging tests
timeout = 300
timeout_method = "thread"

# Filter warnings
filterwarnings = [
    "error",
    "ignore::DeprecationWarning",
    "ignore::PendingDeprecationWarning",
]
```

### Strict Mode (Pytest 9.0+)

Enable all strictness options for better test hygiene:

```toml
[tool.pytest.ini_options]
strict = true
# Or individually:
strict_config = true
strict_markers = true
strict_parametrization_ids = true
strict_xfail = true
```


## 3. Fixture Architecture

### Fixture Scopes & Best Practices

| Scope | Use Case | Teardown |
|-------|----------|----------|
| `function` | Default, test isolation | After each test |
| `class` | Shared setup for test class | After last test in class |
| `module` | Expensive setup (DB connections) | After last test in module |
| `session` | One-time setup (Docker containers) | After entire session |

### Fixture Design Patterns

```python
# conftest.py - Root level fixtures

import pytest
from typing import Generator
from dataclasses import dataclass

# ============================================================
# 1. YIELD FIXTURES (Recommended for cleanup)
# ============================================================

@pytest.fixture(scope="session")
def database_connection() -> Generator[DatabaseConnection, None, None]:
    """Session-scoped database connection with proper cleanup."""
    conn = DatabaseConnection.create()
    yield conn
    conn.close()


@pytest.fixture(scope="function")
def clean_database(database_connection: DatabaseConnection) -> Generator[None, None, None]:
    """Reset database state before each test."""
    yield
    database_connection.truncate_all_tables()


# ============================================================
# 2. FACTORY FIXTURES (For dynamic test data)
# ============================================================

@dataclass
class User:
    id: int
    email: str
    name: str

@pytest.fixture
def user_factory(database_connection: DatabaseConnection):
    """Factory fixture for creating test users."""
    created_users: list[User] = []
    
    def _create_user(email: str = "test@example.com", name: str = "Test User") -> User:
        user = User(id=len(created_users) + 1, email=email, name=name)
        database_connection.insert_user(user)
        created_users.append(user)
        return user
    
    yield _create_user
    
    # Cleanup all created users
    for user in created_users:
        database_connection.delete_user(user.id)


# ============================================================
# 3. AUTOUSE FIXTURES (Automatic setup/teardown)
# ============================================================

@pytest.fixture(autouse=True)
def reset_environment_variables(monkeypatch: pytest.MonkeyPatch) -> None:
    """Automatically reset env vars for each test."""
    monkeypatch.setenv("TEST_MODE", "true")
    monkeypatch.setenv("LOG_LEVEL", "DEBUG")


# ============================================================
# 4. PARAMETRIZED FIXTURES
# ============================================================

@pytest.fixture(params=["ios", "android"])
def mobile_platform(request: pytest.FixtureRequest) -> str:
    """Run tests on both iOS and Android."""
    return request.param


@pytest.fixture(params=[
    pytest.param("staging", id="staging-env"),
    pytest.param("production", id="prod-env", marks=pytest.mark.slow),
])
def environment(request: pytest.FixtureRequest) -> str:
    """Test against multiple environments."""
    return request.param
```


### Fixture Dependency Injection

```python
# Fixtures can request other fixtures - pytest handles the dependency graph

@pytest.fixture(scope="session")
def api_base_url() -> str:
    return os.getenv("API_BASE_URL", "http://localhost:8080")


@pytest.fixture(scope="session")
def auth_token(api_base_url: str) -> str:
    """Authenticate once per session."""
    response = requests.post(
        f"{api_base_url}/auth/login",
        json={"email": "test@example.com", "password": "testpass"}
    )
    return response.json()["token"]


@pytest.fixture(scope="function")
def api_client(api_base_url: str, auth_token: str) -> APIClient:
    """Authenticated API client for each test."""
    return APIClient(base_url=api_base_url, token=auth_token)
```

### conftest.py Hierarchy

```
tests/
├── conftest.py              # Session fixtures, hooks, plugins
├── functional/
│   ├── conftest.py          # API client fixtures
│   └── test_bookings.py     # Uses fixtures from both conftest files
└── mobile/
    ├── conftest.py          # Appium driver fixtures
    └── test_ios.py          # Uses mobile + root fixtures
```

Fixtures in parent `conftest.py` are automatically available to child directories.


## 4. Mobile Testing with Appium

### Appium Python Client Setup (v5.x)

```python
# tests/mobile/conftest.py

import pytest
from typing import Generator
from appium import webdriver
from appium.options.android import UiAutomator2Options
from appium.options.ios import XCUITestOptions
from appium.webdriver.appium_service import AppiumService
from appium.webdriver.common.appiumby import AppiumBy

APPIUM_HOST = "127.0.0.1"
APPIUM_PORT = 4723


@pytest.fixture(scope="session")
def appium_service() -> Generator[AppiumService, None, None]:
    """Start Appium server for the test session."""
    service = AppiumService()
    service.start(
        args=["--address", APPIUM_HOST, "-p", str(APPIUM_PORT)],
        timeout_ms=20000,
    )
    yield service
    service.stop()


def create_ios_driver(custom_opts: dict | None = None) -> webdriver.Remote:
    """Factory for iOS driver instances."""
    options = XCUITestOptions()
    options.platform_version = "17.0"
    options.device_name = "iPhone 15 Pro"
    options.app = "/path/to/app.ipa"
    options.automation_name = "XCUITest"
    
    if custom_opts:
        options.load_capabilities(custom_opts)
    
    return webdriver.Remote(
        f"http://{APPIUM_HOST}:{APPIUM_PORT}",
        options=options
    )


def create_android_driver(custom_opts: dict | None = None) -> webdriver.Remote:
    """Factory for Android driver instances."""
    options = UiAutomator2Options()
    options.platform_version = "14"
    options.device_name = "Pixel 8"
    options.app = "/path/to/app.apk"
    options.automation_name = "UiAutomator2"
    
    if custom_opts:
        options.load_capabilities(custom_opts)
    
    return webdriver.Remote(
        f"http://{APPIUM_HOST}:{APPIUM_PORT}",
        options=options
    )


@pytest.fixture
def ios_driver(appium_service: AppiumService) -> Generator[webdriver.Remote, None, None]:
    """iOS driver fixture with automatic cleanup."""
    driver = create_ios_driver()
    yield driver
    driver.quit()


@pytest.fixture
def android_driver(appium_service: AppiumService) -> Generator[webdriver.Remote, None, None]:
    """Android driver fixture with automatic cleanup."""
    driver = create_android_driver()
    yield driver
    driver.quit()
```

### W3C Actions for Touch Gestures

```python
# Modern touch actions (replaces deprecated TouchAction)
from selenium.webdriver import ActionChains
from selenium.webdriver.common.actions import interaction
from selenium.webdriver.common.actions.action_builder import ActionBuilder
from selenium.webdriver.common.actions.pointer_input import PointerInput


def swipe_up(driver: webdriver.Remote, start_x: int, start_y: int, end_y: int) -> None:
    """Perform swipe up gesture using W3C Actions."""
    actions = ActionChains(driver)
    actions.w3c_actions = ActionBuilder(
        driver, 
        mouse=PointerInput(interaction.POINTER_TOUCH, "touch")
    )
    actions.w3c_actions.pointer_action.move_to_location(start_x, start_y)
    actions.w3c_actions.pointer_action.pointer_down()
    actions.w3c_actions.pointer_action.pause(0.1)
    actions.w3c_actions.pointer_action.move_to_location(start_x, end_y)
    actions.w3c_actions.pointer_action.release()
    actions.perform()
```


## 5. Page Object Model Pattern

### Base Page Implementation

```python
# tests/mobile/pages/base_page.py

from typing import TypeVar, Generic
from appium import webdriver
from appium.webdriver.common.appiumby import AppiumBy
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.remote.webelement import WebElement

T = TypeVar("T", bound="BasePage")


class BasePage(Generic[T]):
    """Base class for all Page Objects."""
    
    DEFAULT_TIMEOUT = 10
    
    def __init__(self, driver: webdriver.Remote) -> None:
        self.driver = driver
        self.wait = WebDriverWait(driver, self.DEFAULT_TIMEOUT)
    
    def find_element(self, locator: tuple[str, str]) -> WebElement:
        """Find element with explicit wait."""
        return self.wait.until(EC.presence_of_element_located(locator))
    
    def find_elements(self, locator: tuple[str, str]) -> list[WebElement]:
        """Find multiple elements."""
        return self.wait.until(EC.presence_of_all_elements_located(locator))
    
    def click(self, locator: tuple[str, str]) -> T:
        """Click element and return self for chaining."""
        element = self.wait.until(EC.element_to_be_clickable(locator))
        element.click()
        return self  # type: ignore
    
    def type_text(self, locator: tuple[str, str], text: str) -> T:
        """Type text into element."""
        element = self.find_element(locator)
        element.clear()
        element.send_keys(text)
        return self  # type: ignore
    
    def is_displayed(self, locator: tuple[str, str], timeout: int = 5) -> bool:
        """Check if element is displayed."""
        try:
            WebDriverWait(self.driver, timeout).until(
                EC.visibility_of_element_located(locator)
            )
            return True
        except:
            return False
    
    def get_text(self, locator: tuple[str, str]) -> str:
        """Get element text."""
        return self.find_element(locator).text


# tests/mobile/pages/login_page.py

class LoginPage(BasePage["LoginPage"]):
    """Login page object."""
    
    # Locators
    EMAIL_INPUT = (AppiumBy.ACCESSIBILITY_ID, "email-input")
    PASSWORD_INPUT = (AppiumBy.ACCESSIBILITY_ID, "password-input")
    LOGIN_BUTTON = (AppiumBy.ACCESSIBILITY_ID, "login-button")
    ERROR_MESSAGE = (AppiumBy.ACCESSIBILITY_ID, "error-message")
    
    def enter_email(self, email: str) -> "LoginPage":
        return self.type_text(self.EMAIL_INPUT, email)
    
    def enter_password(self, password: str) -> "LoginPage":
        return self.type_text(self.PASSWORD_INPUT, password)
    
    def tap_login(self) -> "HomePage":
        self.click(self.LOGIN_BUTTON)
        return HomePage(self.driver)
    
    def login(self, email: str, password: str) -> "HomePage":
        """Fluent login flow."""
        return (
            self.enter_email(email)
                .enter_password(password)
                .tap_login()
        )
    
    def get_error_message(self) -> str:
        return self.get_text(self.ERROR_MESSAGE)
    
    def is_error_displayed(self) -> bool:
        return self.is_displayed(self.ERROR_MESSAGE)
```


## 6. pytest-bdd for BDD Testing

### Feature File Structure

```gherkin
# tests/bdd/features/booking.feature

@booking @api
Feature: Court Booking
    As a registered user
    I want to book tennis courts
    So that I can play at my preferred time

    Background:
        Given I am logged in as a verified user
        And there is an available court "Court A"

    @smoke @positive
    Scenario: Successfully book an available court
        Given the court "Court A" is available at "10:00"
        When I book the court for "10:00" to "11:00"
        Then the booking should be confirmed
        And I should receive a confirmation notification

    @negative
    Scenario: Cannot book an already booked court
        Given the court "Court A" is booked at "10:00"
        When I try to book the court for "10:00" to "11:00"
        Then I should see an error "Court is not available"

    @positive
    Scenario Outline: Book courts at different times
        Given the court "<court>" is available at "<time>"
        When I book the court for "<time>" to "<end_time>"
        Then the booking should be confirmed

        Examples:
        | court   | time  | end_time |
        | Court A | 09:00 | 10:00    |
        | Court B | 14:00 | 15:30    |
        | Court C | 18:00 | 19:00    |
```

### Step Definitions

```python
# tests/bdd/step_defs/test_booking_steps.py

import pytest
from pytest_bdd import scenarios, given, when, then, parsers

# Load all scenarios from feature file
scenarios("../features/booking.feature")


# ============================================================
# GIVEN STEPS
# ============================================================

@given("I am logged in as a verified user", target_fixture="logged_in_user")
def logged_in_user(api_client):
    """Authenticate and return user context."""
    return api_client.login("test@example.com", "password123")


@given(parsers.parse('there is an available court "{court_name}"'), target_fixture="court")
def available_court(api_client, court_name: str):
    """Ensure court exists and is available."""
    return api_client.get_or_create_court(court_name)


@given(parsers.parse('the court "{court_name}" is available at "{time}"'))
def court_available_at_time(api_client, court_name: str, time: str, court):
    """Verify court availability at specific time."""
    assert api_client.check_availability(court["id"], time)


@given(parsers.parse('the court "{court_name}" is booked at "{time}"'))
def court_booked_at_time(api_client, court_name: str, time: str, court, logged_in_user):
    """Create a blocking booking."""
    api_client.create_booking(court["id"], time, logged_in_user["id"])


# ============================================================
# WHEN STEPS
# ============================================================

@when(
    parsers.parse('I book the court for "{start_time}" to "{end_time}"'),
    target_fixture="booking_result"
)
def book_court(api_client, court, logged_in_user, start_time: str, end_time: str):
    """Attempt to create a booking."""
    return api_client.create_booking(
        court_id=court["id"],
        start_time=start_time,
        end_time=end_time,
        user_id=logged_in_user["id"]
    )


@when(
    parsers.parse('I try to book the court for "{start_time}" to "{end_time}"'),
    target_fixture="booking_result"
)
def try_book_court(api_client, court, logged_in_user, start_time: str, end_time: str):
    """Attempt booking that may fail."""
    try:
        return api_client.create_booking(
            court_id=court["id"],
            start_time=start_time,
            end_time=end_time,
            user_id=logged_in_user["id"]
        )
    except APIError as e:
        return {"error": str(e)}


# ============================================================
# THEN STEPS
# ============================================================

@then("the booking should be confirmed")
def booking_confirmed(booking_result):
    assert booking_result.get("status") == "CONFIRMED"
    assert "id" in booking_result


@then("I should receive a confirmation notification")
def notification_received(api_client, logged_in_user):
    notifications = api_client.get_notifications(logged_in_user["id"])
    assert any(n["type"] == "BOOKING_CONFIRMED" for n in notifications)


@then(parsers.parse('I should see an error "{error_message}"'))
def error_displayed(booking_result, error_message: str):
    assert "error" in booking_result
    assert error_message in booking_result["error"]
```


## 7. Stress Testing with Locust

### Locust Test Scenarios

```python
# tests/stress/locustfile.py

from locust import HttpUser, task, between, events
from locust.runners import MasterRunner
import random
import logging

logger = logging.getLogger(__name__)


class CourtBookingUser(HttpUser):
    """Simulates a typical user booking courts."""
    
    wait_time = between(1, 3)  # Wait 1-3 seconds between tasks
    
    def on_start(self):
        """Called when a simulated user starts."""
        self.login()
        self.courts = self.get_available_courts()
    
    def login(self):
        """Authenticate the user."""
        response = self.client.post("/auth/login", json={
            "email": f"loadtest_{random.randint(1, 1000)}@example.com",
            "password": "testpassword"
        })
        if response.status_code == 200:
            self.token = response.json()["token"]
            self.client.headers["Authorization"] = f"Bearer {self.token}"
        else:
            logger.error(f"Login failed: {response.status_code}")
    
    def get_available_courts(self) -> list:
        """Fetch available courts."""
        response = self.client.get("/api/v1/courts")
        return response.json() if response.status_code == 200 else []
    
    @task(10)  # Weight: 10x more likely than other tasks
    def view_court_availability(self):
        """Most common action: check availability."""
        if self.courts:
            court = random.choice(self.courts)
            self.client.get(
                f"/api/v1/courts/{court['id']}/availability",
                name="/api/v1/courts/[id]/availability"
            )
    
    @task(5)
    def search_courts(self):
        """Search for courts by location."""
        self.client.get("/api/v1/courts/search", params={
            "lat": 37.9838 + random.uniform(-0.1, 0.1),
            "lon": 23.7275 + random.uniform(-0.1, 0.1),
            "radius": 5000
        })
    
    @task(3)
    def create_booking(self):
        """Create a new booking."""
        if self.courts:
            court = random.choice(self.courts)
            self.client.post("/api/v1/bookings", json={
                "courtId": court["id"],
                "date": "2026-03-15",
                "startTime": f"{random.randint(9, 20):02d}:00",
                "duration": 60
            })
    
    @task(2)
    def view_my_bookings(self):
        """View user's bookings."""
        self.client.get("/api/v1/bookings/me")
    
    @task(1)
    def cancel_booking(self):
        """Cancel a random booking."""
        response = self.client.get("/api/v1/bookings/me")
        if response.status_code == 200:
            bookings = response.json()
            if bookings:
                booking = random.choice(bookings)
                self.client.delete(
                    f"/api/v1/bookings/{booking['id']}",
                    name="/api/v1/bookings/[id]"
                )


class AdminUser(HttpUser):
    """Simulates admin operations (lower frequency)."""
    
    wait_time = between(5, 10)
    weight = 1  # 1/10th of regular users
    
    def on_start(self):
        self.admin_login()
    
    def admin_login(self):
        response = self.client.post("/auth/admin/login", json={
            "email": "admin@example.com",
            "password": "adminpassword"
        })
        if response.status_code == 200:
            self.token = response.json()["token"]
            self.client.headers["Authorization"] = f"Bearer {self.token}"
    
    @task
    def view_dashboard(self):
        self.client.get("/api/v1/admin/dashboard")
    
    @task
    def view_reports(self):
        self.client.get("/api/v1/admin/reports/bookings")


# Event hooks for custom metrics
@events.request.add_listener
def on_request(request_type, name, response_time, response_length, exception, **kwargs):
    if exception:
        logger.error(f"Request failed: {name} - {exception}")


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    if isinstance(environment.runner, MasterRunner):
        logger.info("Load test starting on master node")
```


## 8. Test Data Management

### pytest-factoryboy Integration

```python
# tests/functional/factories/user_factory.py

import factory
from factory import fuzzy
from pytest_factoryboy import register
from datetime import datetime, timedelta


class UserFactory(factory.Factory):
    """Factory for creating test users."""
    
    class Meta:
        model = dict  # Or your User model/dataclass
    
    id = factory.Sequence(lambda n: n + 1)
    email = factory.LazyAttribute(lambda o: f"user_{o.id}@example.com")
    name = factory.Faker("name")
    phone = factory.Faker("phone_number")
    created_at = factory.LazyFunction(datetime.utcnow)
    is_verified = True
    
    class Params:
        unverified = factory.Trait(is_verified=False)
        admin = factory.Trait(role="ADMIN")


class BookingFactory(factory.Factory):
    """Factory for creating test bookings."""
    
    class Meta:
        model = dict
    
    id = factory.Sequence(lambda n: n + 1)
    court_id = factory.Sequence(lambda n: (n % 5) + 1)
    user_id = factory.SubFactory(UserFactory)
    date = factory.LazyFunction(lambda: datetime.now().date() + timedelta(days=1))
    start_time = fuzzy.FuzzyChoice(["09:00", "10:00", "11:00", "14:00", "15:00"])
    duration = fuzzy.FuzzyChoice([60, 90, 120])
    status = "CONFIRMED"
    
    class Params:
        cancelled = factory.Trait(status="CANCELLED")
        pending = factory.Trait(status="PENDING")


# Register factories as fixtures
register(UserFactory)
register(UserFactory, "admin_user", admin=True)
register(UserFactory, "unverified_user", unverified=True)
register(BookingFactory)
register(BookingFactory, "cancelled_booking", cancelled=True)
```

### Using Factory Fixtures in Tests

```python
# tests/functional/test_bookings.py

def test_create_booking(api_client, user, court):
    """user fixture auto-created by pytest-factoryboy."""
    response = api_client.post("/bookings", json={
        "courtId": court["id"],
        "userId": user["id"],
        "date": "2026-03-15",
        "startTime": "10:00"
    })
    assert response.status_code == 201


def test_admin_can_view_all_bookings(api_client, admin_user, booking_factory):
    """Create multiple bookings using factory."""
    bookings = [booking_factory() for _ in range(5)]
    
    api_client.login_as(admin_user)
    response = api_client.get("/admin/bookings")
    
    assert response.status_code == 200
    assert len(response.json()) >= 5


def test_cancelled_booking_not_in_active_list(api_client, user, cancelled_booking):
    """Use trait-based fixture."""
    response = api_client.get(f"/users/{user['id']}/bookings/active")
    
    booking_ids = [b["id"] for b in response.json()]
    assert cancelled_booking["id"] not in booking_ids
```


## 9. Assertion Best Practices

### Use pytest's Native Assertions

```python
# ✅ CORRECT - pytest rewrites assertions for better output
def test_booking_status():
    booking = create_booking()
    assert booking.status == "CONFIRMED"
    assert booking.court_id > 0
    assert "user_id" in booking.__dict__


# ❌ AVOID - unittest style assertions
def test_booking_status_bad():
    booking = create_booking()
    self.assertEqual(booking.status, "CONFIRMED")  # Less informative
```

### pytest.approx for Floating Point

```python
def test_distance_calculation():
    distance = calculate_distance(lat1=37.98, lon1=23.72, lat2=37.99, lon2=23.73)
    assert distance == pytest.approx(1.5, rel=0.1)  # 10% tolerance
    assert distance == pytest.approx(1.5, abs=0.2)  # Absolute tolerance


def test_coordinates():
    coords = {"lat": 37.9838, "lon": 23.7275}
    assert coords == pytest.approx({"lat": 37.98, "lon": 23.73}, rel=0.01)
```

### Exception Testing

```python
import pytest

def test_booking_in_past_raises_error():
    with pytest.raises(ValueError, match=r".*past.*"):
        create_booking(date="2020-01-01")


def test_exception_details():
    with pytest.raises(BookingConflictError) as exc_info:
        create_conflicting_booking()
    
    assert exc_info.value.court_id == 1
    assert "already booked" in str(exc_info.value)


def test_no_exception_raised():
    # Verify no exception is raised
    create_valid_booking()  # Should not raise
```

### Custom Assertion Helpers

```python
# tests/utils/assertions.py

from typing import Any
import pytest


def assert_valid_booking(booking: dict) -> None:
    """Custom assertion for booking validation."""
    assert "id" in booking, "Booking must have an ID"
    assert booking["status"] in ["PENDING", "CONFIRMED", "CANCELLED"]
    assert booking["duration"] > 0
    assert booking["court_id"] > 0


def assert_api_error(response, status_code: int, error_contains: str) -> None:
    """Assert API error response format."""
    assert response.status_code == status_code
    error_body = response.json()
    assert "error" in error_body or "message" in error_body
    error_msg = error_body.get("error") or error_body.get("message")
    assert error_contains.lower() in error_msg.lower()


# Usage in tests
def test_booking_validation(api_client):
    response = api_client.post("/bookings", json=valid_booking_data)
    booking = response.json()
    assert_valid_booking(booking)


def test_invalid_booking_error(api_client):
    response = api_client.post("/bookings", json={"courtId": -1})
    assert_api_error(response, 400, "invalid court")
```


## 10. Parametrization Patterns

### Basic Parametrization

```python
import pytest

@pytest.mark.parametrize("email,expected_valid", [
    ("user@example.com", True),
    ("user@domain.co.uk", True),
    ("invalid-email", False),
    ("@nodomain.com", False),
    ("", False),
])
def test_email_validation(email: str, expected_valid: bool):
    assert validate_email(email) == expected_valid


# With custom IDs for better test output
@pytest.mark.parametrize(
    "duration,expected_price",
    [
        pytest.param(60, 20.0, id="1-hour"),
        pytest.param(90, 28.0, id="1.5-hours"),
        pytest.param(120, 35.0, id="2-hours"),
    ]
)
def test_booking_pricing(duration: int, expected_price: float):
    price = calculate_price(duration)
    assert price == pytest.approx(expected_price)
```

### Stacked Parametrization (Cartesian Product)

```python
@pytest.mark.parametrize("court_type", ["indoor", "outdoor"])
@pytest.mark.parametrize("surface", ["clay", "hard", "grass"])
@pytest.mark.parametrize("lighting", [True, False])
def test_court_combinations(court_type: str, surface: str, lighting: bool):
    """Runs 2 × 3 × 2 = 12 test combinations."""
    court = create_court(type=court_type, surface=surface, has_lighting=lighting)
    assert court.is_valid()
```

### Parametrize with Marks

```python
@pytest.mark.parametrize("user_role,expected_status", [
    pytest.param("admin", 200, id="admin-allowed"),
    pytest.param("user", 403, id="user-forbidden"),
    pytest.param("guest", 401, id="guest-unauthorized", marks=pytest.mark.xfail),
])
def test_admin_endpoint_access(api_client, user_role: str, expected_status: int):
    api_client.login_as_role(user_role)
    response = api_client.get("/admin/dashboard")
    assert response.status_code == expected_status
```

### Indirect Parametrization (Fixture Values)

```python
@pytest.fixture
def court(request):
    """Fixture that accepts parameters."""
    court_type = request.param
    return create_court(type=court_type)


@pytest.mark.parametrize("court", ["indoor", "outdoor"], indirect=True)
def test_court_booking(court, api_client):
    """court fixture receives 'indoor' and 'outdoor' as request.param."""
    response = api_client.post("/bookings", json={"courtId": court["id"]})
    assert response.status_code == 201
```


## 11. Test Markers & Selection

### Defining Custom Markers

```python
# conftest.py

import pytest

def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line("markers", "smoke: Quick sanity tests")
    config.addinivalue_line("markers", "slow: Tests taking > 5 seconds")
    config.addinivalue_line("markers", "integration: Requires external services")
    config.addinivalue_line("markers", "mobile(platform): Mobile platform tests")
```

### Using Markers

```python
import pytest

@pytest.mark.smoke
def test_api_health():
    """Quick health check - runs in smoke suite."""
    response = requests.get(f"{BASE_URL}/health")
    assert response.status_code == 200


@pytest.mark.slow
@pytest.mark.integration
def test_full_booking_flow():
    """End-to-end test - excluded from quick runs."""
    # ... long running test


@pytest.mark.mobile("ios")
def test_ios_login(ios_driver):
    """iOS-specific test."""
    pass


@pytest.mark.mobile("android")
def test_android_login(android_driver):
    """Android-specific test."""
    pass


@pytest.mark.skipif(
    os.getenv("CI") == "true",
    reason="Skipped in CI - requires physical device"
)
def test_bluetooth_pairing():
    pass


@pytest.mark.xfail(reason="Known bug #123 - payment gateway timeout")
def test_payment_retry():
    pass
```

### Running Tests by Marker

```bash
# Run only smoke tests
pytest -m smoke

# Run everything except slow tests
pytest -m "not slow"

# Run mobile tests for iOS only
pytest -m "mobile and ios"

# Complex expressions
pytest -m "(smoke or integration) and not slow"
```


## 12. Async Testing

### pytest-asyncio Configuration

```python
# conftest.py
import pytest
import asyncio

# Auto mode: automatically detect async tests
pytest_plugins = ["pytest_asyncio"]


@pytest.fixture(scope="session")
def event_loop():
    """Create event loop for session-scoped async fixtures."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture
async def async_api_client():
    """Async HTTP client fixture."""
    import httpx
    async with httpx.AsyncClient(base_url=BASE_URL) as client:
        yield client
```

### Async Test Examples

```python
import pytest
import asyncio

@pytest.mark.asyncio
async def test_async_booking_creation(async_api_client):
    """Test async API call."""
    response = await async_api_client.post("/bookings", json=booking_data)
    assert response.status_code == 201


@pytest.mark.asyncio
async def test_concurrent_bookings(async_api_client):
    """Test concurrent operations."""
    tasks = [
        async_api_client.post("/bookings", json={"courtId": i})
        for i in range(1, 6)
    ]
    responses = await asyncio.gather(*tasks)
    
    success_count = sum(1 for r in responses if r.status_code == 201)
    assert success_count >= 3  # At least 3 should succeed


@pytest.mark.asyncio
async def test_websocket_notifications(async_api_client):
    """Test WebSocket connection."""
    import websockets
    
    async with websockets.connect(f"{WS_URL}/notifications") as ws:
        # Trigger a booking
        await async_api_client.post("/bookings", json=booking_data)
        
        # Wait for notification
        message = await asyncio.wait_for(ws.recv(), timeout=5.0)
        notification = json.loads(message)
        
        assert notification["type"] == "BOOKING_CREATED"
```


## 13. Mocking & Test Doubles

### pytest-mock Usage

```python
import pytest
from unittest.mock import MagicMock, AsyncMock


def test_payment_processing(mocker):
    """Use mocker fixture from pytest-mock."""
    # Mock external payment gateway
    mock_stripe = mocker.patch("app.payments.stripe_client")
    mock_stripe.create_charge.return_value = {"id": "ch_123", "status": "succeeded"}
    
    result = process_payment(amount=100, currency="EUR")
    
    assert result["status"] == "succeeded"
    mock_stripe.create_charge.assert_called_once_with(
        amount=10000,  # cents
        currency="eur"
    )


def test_notification_sent(mocker):
    """Verify side effects."""
    mock_notify = mocker.patch("app.notifications.send_push")
    
    create_booking(user_id=1, court_id=1)
    
    mock_notify.assert_called_once()
    call_args = mock_notify.call_args
    assert call_args.kwargs["user_id"] == 1
    assert "booking" in call_args.kwargs["message"].lower()


@pytest.mark.asyncio
async def test_async_external_call(mocker):
    """Mock async functions."""
    mock_weather = mocker.patch(
        "app.weather.get_forecast",
        new_callable=AsyncMock,
        return_value={"temp": 25, "condition": "sunny"}
    )
    
    result = await get_court_conditions(court_id=1)
    
    assert result["weather"]["temp"] == 25
    mock_weather.assert_awaited_once()
```

### Fixture-based Mocking

```python
@pytest.fixture
def mock_payment_gateway(mocker):
    """Reusable payment gateway mock."""
    mock = mocker.patch("app.payments.PaymentGateway")
    mock.return_value.charge.return_value = {
        "id": "pay_123",
        "status": "succeeded",
        "amount": 2000
    }
    mock.return_value.refund.return_value = {
        "id": "ref_123",
        "status": "succeeded"
    }
    return mock.return_value


def test_booking_payment(mock_payment_gateway, api_client):
    """Use mock fixture."""
    response = api_client.post("/bookings", json=booking_with_payment)
    
    assert response.status_code == 201
    mock_payment_gateway.charge.assert_called_once()


def test_booking_cancellation_refund(mock_payment_gateway, api_client, booking):
    """Verify refund on cancellation."""
    api_client.delete(f"/bookings/{booking['id']}")
    
    mock_payment_gateway.refund.assert_called_once()
```


## 14. Test Naming & Organization

### Naming Conventions

```python
# ✅ GOOD: Descriptive, follows pattern
def test_should_create_booking_when_court_is_available():
    pass

def test_should_reject_booking_when_court_is_already_booked():
    pass

def test_should_send_notification_after_booking_confirmed():
    pass


# ✅ GOOD: Given-When-Then style
def test_given_available_court_when_booking_then_status_is_confirmed():
    pass


# ❌ BAD: Vague names
def test_booking():
    pass

def test_it_works():
    pass

def test_1():
    pass
```

### Test Class Organization

```python
class TestBookingCreation:
    """Group related booking creation tests."""
    
    def test_should_create_booking_with_valid_data(self, api_client, court):
        pass
    
    def test_should_reject_booking_in_the_past(self, api_client, court):
        pass
    
    def test_should_reject_booking_without_authentication(self, api_client):
        pass


class TestBookingCancellation:
    """Group cancellation-related tests."""
    
    def test_should_cancel_pending_booking(self, api_client, pending_booking):
        pass
    
    def test_should_refund_when_cancelling_paid_booking(self, api_client, paid_booking):
        pass
    
    def test_should_not_cancel_past_booking(self, api_client, past_booking):
        pass


class TestBookingNotifications:
    """Group notification tests."""
    
    @pytest.fixture(autouse=True)
    def setup_notification_mock(self, mocker):
        """Auto-mock notifications for all tests in this class."""
        self.mock_notify = mocker.patch("app.notifications.send")
    
    def test_should_send_confirmation_email(self, api_client, booking):
        pass
    
    def test_should_send_reminder_24h_before(self, api_client, booking):
        pass
```


## 15. Recommended Plugins & Dependencies

### Core Dependencies

```toml
# pyproject.toml

[project]
dependencies = [
    "pytest>=8.0.0",
    "pytest-asyncio>=0.23.0",
    "pytest-cov>=4.1.0",
    "pytest-xdist>=3.5.0",        # Parallel execution
    "pytest-timeout>=2.2.0",
    "pytest-mock>=3.12.0",
    "pytest-factoryboy>=2.6.0",
    "pytest-bdd>=7.0.0",
    "pytest-html>=4.1.0",         # HTML reports
    "pytest-randomly>=3.15.0",    # Randomize test order
    "httpx>=0.26.0",              # Async HTTP client
    "Faker>=22.0.0",              # Test data generation
]

[project.optional-dependencies]
mobile = [
    "Appium-Python-Client>=4.0.0",
    "selenium>=4.16.0",
]
stress = [
    "locust>=2.20.0",
]
quality = [
    "ruff>=0.1.0",                # Linting
    "mypy>=1.8.0",                # Type checking
    "black>=24.0.0",              # Formatting
]
```

### Plugin Configuration

```toml
# pyproject.toml

[tool.pytest.ini_options]
# pytest-cov
addopts = "--cov=app --cov-report=html --cov-report=term-missing"

# pytest-xdist (parallel)
# Run with: pytest -n auto
# Or: pytest -n 4

# pytest-randomly
# Disable with: pytest -p no:randomly
# Set seed: pytest --randomly-seed=12345

# pytest-timeout
timeout = 300
timeout_method = "thread"

[tool.coverage.run]
branch = true
source = ["app"]
omit = ["tests/*", "*/__init__.py"]

[tool.coverage.report]
exclude_lines = [
    "pragma: no cover",
    "if TYPE_CHECKING:",
    "raise NotImplementedError",
]
fail_under = 80
```


## 16. CI/CD Integration Patterns

### GitHub Actions Workflow

```yaml
# .github/workflows/test.yml

name: Test Suite

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  PYTHON_VERSION: "3.12"

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}
          cache: 'pip'
      
      - name: Install dependencies
        run: |
          pip install -e ".[dev]"
      
      - name: Run unit tests
        run: |
          pytest tests/unit -v --cov=app --cov-report=xml --junitxml=junit.xml
      
      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          files: coverage.xml
          fail_ci_if_error: true
      
      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: test-results
          path: junit.xml

  integration-tests:
    runs-on: ubuntu-latest
    needs: unit-tests
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: testpass
          POSTGRES_DB: testdb
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
      
      redis:
        image: redis:7
        ports:
          - 6379:6379
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}
          cache: 'pip'
      
      - name: Install dependencies
        run: pip install -e ".[dev]"
      
      - name: Run integration tests
        env:
          DATABASE_URL: postgresql://postgres:testpass@localhost:5432/testdb
          REDIS_URL: redis://localhost:6379
        run: |
          pytest tests/integration -v -m integration --junitxml=integration-junit.xml

  mobile-tests:
    runs-on: macos-latest
    needs: unit-tests
    strategy:
      matrix:
        platform: [ios, android]
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}
      
      - name: Install Appium
        run: |
          npm install -g appium
          appium driver install uiautomator2
          appium driver install xcuitest
      
      - name: Start Appium server
        run: appium &
      
      - name: Set up iOS Simulator
        if: matrix.platform == 'ios'
        run: |
          xcrun simctl boot "iPhone 15 Pro"
      
      - name: Set up Android Emulator
        if: matrix.platform == 'android'
        uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: 34
          target: google_apis
          arch: x86_64
          script: pytest tests/mobile -v -m ${{ matrix.platform }}
      
      - name: Run iOS tests
        if: matrix.platform == 'ios'
        run: pytest tests/mobile -v -m ios

  stress-tests:
    runs-on: ubuntu-latest
    needs: integration-tests
    if: github.ref == 'refs/heads/main'
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ env.PYTHON_VERSION }}
      
      - name: Install dependencies
        run: pip install -e ".[stress]"
      
      - name: Run Locust headless
        run: |
          locust -f tests/stress/locustfile.py \
            --headless \
            --users 100 \
            --spawn-rate 10 \
            --run-time 5m \
            --host ${{ secrets.STAGING_API_URL }} \
            --html=locust-report.html \
            --csv=locust-results
      
      - name: Upload stress test report
        uses: actions/upload-artifact@v4
        with:
          name: stress-test-report
          path: |
            locust-report.html
            locust-results*.csv
```

### Parallel Test Execution

```bash
# Run tests in parallel using pytest-xdist
pytest -n auto                    # Auto-detect CPU cores
pytest -n 4                       # Use 4 workers
pytest -n auto --dist loadscope  # Group by module
pytest -n auto --dist loadfile   # Group by file

# Parallel with coverage (requires pytest-cov)
pytest -n auto --cov=app --cov-report=xml
```

### Test Splitting for CI

```python
# conftest.py - Split tests across CI nodes

def pytest_collection_modifyitems(config, items):
    """Split tests across CI nodes."""
    node_id = int(os.getenv("CI_NODE_INDEX", 0))
    total_nodes = int(os.getenv("CI_NODE_TOTAL", 1))
    
    if total_nodes > 1:
        items[:] = [
            item for i, item in enumerate(items)
            if i % total_nodes == node_id
        ]
```


## 17. Reporting & HTML Reports

### pytest-html Configuration

```python
# conftest.py

import pytest
from datetime import datetime


def pytest_html_report_title(report):
    """Customize HTML report title."""
    report.title = "Court Booking QA Test Report"


def pytest_configure(config):
    """Add metadata to HTML report."""
    config._metadata["Project"] = "Court Booking Platform"
    config._metadata["Environment"] = os.getenv("TEST_ENV", "local")
    config._metadata["Tester"] = os.getenv("USER", "CI")


@pytest.hookimpl(hookwrapper=True)
def pytest_runtest_makereport(item, call):
    """Add extra info to test report."""
    outcome = yield
    report = outcome.get_result()
    
    # Add test docstring as description
    report.description = str(item.function.__doc__ or "")
    
    # Capture screenshot on failure for mobile tests
    if report.when == "call" and report.failed:
        if hasattr(item, "funcargs"):
            driver = item.funcargs.get("ios_driver") or item.funcargs.get("android_driver")
            if driver:
                screenshot = driver.get_screenshot_as_base64()
                extra = getattr(report, "extra", [])
                extra.append(pytest_html.extras.image(screenshot, "Screenshot"))
                report.extra = extra
```

### Allure Reporting (Alternative)

```python
# conftest.py - Allure integration

import allure
import pytest


@pytest.hookimpl(hookwrapper=True)
def pytest_runtest_makereport(item, call):
    outcome = yield
    report = outcome.get_result()
    
    if report.when == "call" and report.failed:
        # Attach logs on failure
        if hasattr(item, "funcargs"):
            driver = item.funcargs.get("driver")
            if driver:
                allure.attach(
                    driver.get_screenshot_as_png(),
                    name="screenshot",
                    attachment_type=allure.attachment_type.PNG
                )
                allure.attach(
                    driver.page_source,
                    name="page_source",
                    attachment_type=allure.attachment_type.HTML
                )


# Usage in tests
@allure.feature("Booking")
@allure.story("Create Booking")
@allure.severity(allure.severity_level.CRITICAL)
def test_create_booking(api_client):
    with allure.step("Send booking request"):
        response = api_client.post("/bookings", json=data)
    
    with allure.step("Verify response"):
        assert response.status_code == 201
```

### Running with Reports

```bash
# HTML report
pytest --html=report.html --self-contained-html

# Allure report
pytest --alluredir=allure-results
allure serve allure-results

# JUnit XML (for CI)
pytest --junitxml=junit.xml

# Coverage HTML
pytest --cov=app --cov-report=html
```


## 18. Quick Reference / Decision Rules

| Scenario | Recommended Approach | Example |
|----------|---------------------|---------|
| **Test isolation needed** | `function` scope fixture | Database cleanup per test |
| **Expensive setup** | `session` scope fixture | Docker containers, DB connections |
| **Test data creation** | pytest-factoryboy | `UserFactory`, `BookingFactory` |
| **Multiple input combinations** | `@pytest.mark.parametrize` | Email validation tests |
| **Cross-platform mobile** | Parametrized fixtures | `@pytest.fixture(params=["ios", "android"])` |
| **BDD/Gherkin tests** | pytest-bdd | Feature files + step definitions |
| **Load testing** | Locust | `locustfile.py` with user scenarios |
| **Async API calls** | pytest-asyncio + httpx | `@pytest.mark.asyncio` |
| **External service mocking** | pytest-mock | `mocker.patch()` |
| **Parallel execution** | pytest-xdist | `pytest -n auto` |
| **Flaky test handling** | pytest-rerunfailures | `@pytest.mark.flaky(reruns=3)` |
| **Slow test exclusion** | Custom markers | `pytest -m "not slow"` |
| **Screenshot on failure** | pytest-html hooks | `pytest_runtest_makereport` |

### When to Use Each Test Type

| Test Type | Purpose | Frequency | Duration |
|-----------|---------|-----------|----------|
| **Unit** | Isolated function logic | Every commit | < 1 min |
| **Integration** | Service interactions | Every PR | 2-5 min |
| **API/Functional** | Endpoint contracts | Every PR | 5-10 min |
| **Mobile E2E** | User flows on devices | Nightly/Release | 15-30 min |
| **BDD** | Business requirements | Every PR | 5-10 min |
| **Stress/Load** | Performance limits | Weekly/Release | 10-60 min |

### Fixture Scope Decision Tree

```
Is the setup expensive (> 1 second)?
├── Yes → Is state shared safely between tests?
│         ├── Yes → Use `session` or `module` scope
│         └── No → Use `function` scope with caching
└── No → Use `function` scope (default)
```


## 19. Technology Stack Summary

### Core Testing Stack

| Category | Technology | Version | Purpose |
|----------|------------|---------|---------|
| **Test Framework** | pytest | 8.x | Core test runner |
| **Async Testing** | pytest-asyncio | 0.23.x | Async test support |
| **Coverage** | pytest-cov | 4.x | Code coverage |
| **Parallel** | pytest-xdist | 3.x | Parallel execution |
| **Mocking** | pytest-mock | 3.x | Mock/patch utilities |
| **Factories** | pytest-factoryboy | 2.x | Test data factories |
| **BDD** | pytest-bdd | 7.x | Gherkin scenarios |
| **Reports** | pytest-html | 4.x | HTML test reports |
| **Timeouts** | pytest-timeout | 2.x | Test timeouts |
| **Randomization** | pytest-randomly | 3.x | Random test order |

### Mobile Testing Stack

| Category | Technology | Version | Purpose |
|----------|------------|---------|---------|
| **Automation** | Appium | 2.x | Mobile automation server |
| **Python Client** | Appium-Python-Client | 4.x | Python bindings |
| **WebDriver** | Selenium | 4.x | WebDriver protocol |
| **iOS Driver** | XCUITest | Latest | iOS automation |
| **Android Driver** | UiAutomator2 | Latest | Android automation |

### Stress Testing Stack

| Category | Technology | Version | Purpose |
|----------|------------|---------|---------|
| **Load Testing** | Locust | 2.x | Load/stress testing |
| **HTTP Client** | httpx | 0.26.x | Async HTTP requests |

### Code Quality Stack

| Category | Technology | Version | Purpose |
|----------|------------|---------|---------|
| **Linting** | Ruff | 0.1.x | Fast Python linter |
| **Type Checking** | mypy | 1.x | Static type analysis |
| **Formatting** | Black | 24.x | Code formatting |
| **Data Generation** | Faker | 22.x | Fake test data |

### Minimum Python Version

- **Python 3.11+** recommended for best performance and type hint support
- **Python 3.12** for latest features (improved error messages, faster startup)


## 20. Common Pitfalls & Solutions

### Pitfall 1: Fixture Scope Mismatch

```python
# ❌ BAD: Function-scoped fixture depending on function-scoped fixture
# that modifies shared state
@pytest.fixture(scope="session")
def database():
    return Database()

@pytest.fixture(scope="function")
def user(database):  # Creates user in session-scoped DB
    return database.create_user()  # Leaks between tests!

# ✅ GOOD: Proper cleanup
@pytest.fixture(scope="function")
def user(database):
    user = database.create_user()
    yield user
    database.delete_user(user.id)
```

### Pitfall 2: Hardcoded Test Data

```python
# ❌ BAD: Hardcoded values cause conflicts
def test_create_user():
    user = create_user(email="test@example.com")  # Conflicts in parallel!

# ✅ GOOD: Use factories with unique values
def test_create_user(user_factory):
    user = user_factory()  # Generates unique email
```

### Pitfall 3: Missing Async Markers

```python
# ❌ BAD: Async test without marker (silently passes!)
async def test_async_operation():
    result = await some_async_call()
    assert result  # Never actually runs!

# ✅ GOOD: Proper async test
@pytest.mark.asyncio
async def test_async_operation():
    result = await some_async_call()
    assert result
```

### Pitfall 4: Flaky Mobile Tests

```python
# ❌ BAD: No waits, flaky on slow devices
def test_login(driver):
    driver.find_element(By.ID, "login-btn").click()
    assert driver.find_element(By.ID, "welcome").text == "Welcome"

# ✅ GOOD: Explicit waits
def test_login(driver):
    wait = WebDriverWait(driver, 10)
    login_btn = wait.until(EC.element_to_be_clickable((By.ID, "login-btn")))
    login_btn.click()
    welcome = wait.until(EC.visibility_of_element_located((By.ID, "welcome")))
    assert welcome.text == "Welcome"
```

---

> **Document Version**: 1.0.0  
> **Last Updated**: February 2026  
> **Sources**: pytest docs, Appium Python Client, pytest-bdd, Locust, pytest plugin ecosystem


## 21. Playwright for Admin Web Testing

### Playwright Setup with pytest-playwright

```python
# tests/ui/admin/conftest.py

import pytest
from playwright.sync_api import Page, Browser, BrowserContext
from typing import Generator


@pytest.fixture(scope="session")
def browser_context_args(browser_context_args: dict) -> dict:
    """Configure browser context for all tests."""
    return {
        **browser_context_args,
        "viewport": {"width": 1920, "height": 1080},
        "ignore_https_errors": True,
        "locale": "en-US",
        "timezone_id": "Europe/Athens",
    }


@pytest.fixture(scope="session")
def admin_credentials() -> dict:
    """Admin user credentials for testing."""
    return {
        "email": os.getenv("ADMIN_TEST_EMAIL", "admin@test.courtbooking.gr"),
        "password": os.getenv("ADMIN_TEST_PASSWORD", "testpassword123"),
    }


@pytest.fixture
def authenticated_page(
    page: Page, 
    admin_credentials: dict,
    base_url: str
) -> Generator[Page, None, None]:
    """Page with authenticated admin session."""
    # Navigate to login
    page.goto(f"{base_url}/login")
    
    # Fill login form
    page.fill('[data-testid="email-input"]', admin_credentials["email"])
    page.fill('[data-testid="password-input"]', admin_credentials["password"])
    page.click('[data-testid="login-button"]')
    
    # Wait for dashboard
    page.wait_for_url("**/dashboard")
    
    yield page
    
    # Logout after test
    page.click('[data-testid="user-menu"]')
    page.click('[data-testid="logout-button"]')
```


### Admin Page Objects

```python
# tests/ui/admin/pages/base_page.py

from playwright.sync_api import Page, Locator
from typing import TypeVar, Generic

T = TypeVar("T", bound="BasePage")


class BasePage(Generic[T]):
    """Base class for admin web page objects."""
    
    def __init__(self, page: Page) -> None:
        self.page = page
    
    def get_by_testid(self, testid: str) -> Locator:
        """Find element by data-testid attribute."""
        return self.page.locator(f'[data-testid="{testid}"]')
    
    def wait_for_loading_complete(self) -> None:
        """Wait for loading spinner to disappear."""
        self.page.wait_for_selector('[data-testid="loading-spinner"]', state="hidden")
    
    def get_toast_message(self) -> str:
        """Get toast notification text."""
        toast = self.page.locator('[data-testid="toast-message"]')
        toast.wait_for(state="visible")
        return toast.text_content() or ""


# tests/ui/admin/pages/courts_page.py

class CourtsPage(BasePage["CourtsPage"]):
    """Courts management page object."""
    
    URL_PATH = "/courts"
    
    # Locators
    ADD_COURT_BUTTON = '[data-testid="add-court-button"]'
    COURT_LIST = '[data-testid="court-list"]'
    COURT_ROW = '[data-testid="court-row"]'
    SEARCH_INPUT = '[data-testid="court-search"]'
    
    def navigate(self) -> "CourtsPage":
        self.page.goto(f"{self.page.url.split('/')[0]}//{self.page.url.split('/')[2]}{self.URL_PATH}")
        self.wait_for_loading_complete()
        return self
    
    def click_add_court(self) -> "CourtFormPage":
        self.page.click(self.ADD_COURT_BUTTON)
        return CourtFormPage(self.page)
    
    def search_courts(self, query: str) -> "CourtsPage":
        self.page.fill(self.SEARCH_INPUT, query)
        self.page.keyboard.press("Enter")
        self.wait_for_loading_complete()
        return self
    
    def get_court_count(self) -> int:
        return self.page.locator(self.COURT_ROW).count()
    
    def click_court_row(self, index: int) -> "CourtDetailPage":
        self.page.locator(self.COURT_ROW).nth(index).click()
        return CourtDetailPage(self.page)
```


### Playwright Test Examples

```python
# tests/ui/admin/test_court_management.py

import pytest
from playwright.sync_api import Page, expect
from pages.courts_page import CourtsPage


class TestCourtManagement:
    """Admin court management UI tests."""
    
    def test_should_display_court_list(self, authenticated_page: Page):
        courts_page = CourtsPage(authenticated_page).navigate()
        
        expect(authenticated_page.locator(CourtsPage.COURT_LIST)).to_be_visible()
        assert courts_page.get_court_count() > 0
    
    def test_should_create_new_court(self, authenticated_page: Page, court_factory):
        courts_page = CourtsPage(authenticated_page).navigate()
        initial_count = courts_page.get_court_count()
        
        court_data = court_factory.build()
        form_page = courts_page.click_add_court()
        form_page.fill_court_form(court_data)
        form_page.submit()
        
        # Verify success
        assert "Court created successfully" in courts_page.get_toast_message()
        assert courts_page.get_court_count() == initial_count + 1
    
    def test_should_search_courts_by_name(self, authenticated_page: Page):
        courts_page = CourtsPage(authenticated_page).navigate()
        
        courts_page.search_courts("Tennis Court A")
        
        # Verify filtered results
        assert courts_page.get_court_count() >= 1
        expect(authenticated_page.locator(CourtsPage.COURT_ROW).first).to_contain_text("Tennis Court A")


# Running Playwright tests
# pytest tests/ui/admin/ --browser chromium --headed
# pytest tests/ui/admin/ --browser firefox --browser webkit  # Cross-browser
```


## 22. Contract Testing with Pact

### Consumer-Side Contract Tests

```python
# tests/contract/test_platform_service_consumer.py

import pytest
import atexit
from pact import Consumer, Provider, Like, EachLike, Term


# Initialize Pact
pact = Consumer("MobileApp").has_pact_with(
    Provider("PlatformService"),
    pact_dir="./tests/contract/pacts",
    log_dir="./tests/contract/logs",
)
pact.start_service()
atexit.register(pact.stop_service)


class TestPlatformServiceContract:
    """Consumer contract tests for Platform Service API."""
    
    def test_get_court_by_id(self):
        """Verify court retrieval contract."""
        expected_court = {
            "id": Like(1),
            "name": Like("Tennis Court A"),
            "type": Term(r"TENNIS|PADEL|BASKETBALL", "TENNIS"),
            "location": {
                "lat": Like(37.9838),
                "lon": Like(23.7275),
                "address": Like("123 Sports Ave, Athens"),
            },
            "basePrice": Like(2000),  # cents
            "currency": Like("EUR"),
            "duration": Like(60),
            "capacity": Like(4),
            "amenities": EachLike("LIGHTING"),
        }
        
        (pact
            .given("a court with ID 1 exists")
            .upon_receiving("a request for court 1")
            .with_request("GET", "/api/courts/1")
            .will_respond_with(200, body=expected_court))
        
        with pact:
            # Make actual request to mock server
            response = requests.get(f"{pact.uri}/api/courts/1")
            assert response.status_code == 200
            court = response.json()
            assert court["type"] in ["TENNIS", "PADEL", "BASKETBALL"]
```


### Kafka Event Schema Validation

```python
# tests/contract/kafka/test_event_schemas.py

import pytest
import json
from jsonschema import validate, ValidationError
from pathlib import Path


# Load event schemas from contract file
SCHEMA_PATH = Path("docs/api/kafka-event-contracts.json")


@pytest.fixture(scope="module")
def event_schemas() -> dict:
    """Load Kafka event schemas."""
    with open(SCHEMA_PATH) as f:
        return json.load(f)


class TestBookingEventSchemas:
    """Validate booking event payloads against contracts."""
    
    @pytest.mark.parametrize("event_type", [
        "BOOKING_CREATED",
        "BOOKING_CONFIRMED", 
        "BOOKING_CANCELLED",
        "BOOKING_MODIFIED",
        "BOOKING_COMPLETED",
        "SLOT_HELD",
        "SLOT_RELEASED",
    ])
    def test_booking_event_schema(self, event_schemas: dict, event_type: str):
        """Verify booking events match schema."""
        schema = event_schemas["booking-events"][event_type]
        
        # Sample valid event
        valid_event = {
            "eventId": "550e8400-e29b-41d4-a716-446655440000",
            "eventType": event_type,
            "source": "transaction-service",
            "timestamp": "2026-02-09T10:30:00Z",
            "traceId": "abc123",
            "spanId": "def456",
            "payload": {
                "bookingId": 12345,
                "courtId": 1,
                "userId": 100,
                "date": "2026-02-15",
                "startTime": "10:00",
                "endTime": "11:00",
                "status": "CONFIRMED",
            }
        }
        
        # Should not raise
        validate(instance=valid_event, schema=schema)
    
    def test_invalid_event_fails_validation(self, event_schemas: dict):
        """Verify invalid events are rejected."""
        schema = event_schemas["booking-events"]["BOOKING_CREATED"]
        
        invalid_event = {
            "eventId": "not-a-uuid",  # Invalid UUID format
            "eventType": "BOOKING_CREATED",
            # Missing required fields
        }
        
        with pytest.raises(ValidationError):
            validate(instance=invalid_event, schema=schema)


class TestNotificationEventSchemas:
    """Validate notification event payloads."""
    
    @pytest.mark.parametrize("notification_type", [
        "BOOKING_CONFIRMED",
        "BOOKING_CANCELLED",
        "PAYMENT_RECEIVED",
        "MATCH_JOINED",
        "WAITLIST_SLOT_AVAILABLE",
    ])
    def test_notification_event_schema(self, event_schemas: dict, notification_type: str):
        schema = event_schemas["notification-events"]["NOTIFICATION_REQUESTED"]
        
        valid_event = {
            "eventId": "550e8400-e29b-41d4-a716-446655440001",
            "eventType": "NOTIFICATION_REQUESTED",
            "source": "transaction-service",
            "timestamp": "2026-02-09T10:30:00Z",
            "payload": {
                "userId": 100,
                "type": notification_type,
                "title": "Booking Confirmed",
                "body": "Your booking has been confirmed",
                "channels": ["PUSH", "IN_APP"],
                "data": {"bookingId": 12345},
            }
        }
        
        validate(instance=valid_event, schema=schema)
```


## 23. WebSocket Testing

### WebSocket Client Fixture

```python
# tests/functional/conftest.py

import pytest
import asyncio
import json
from websockets.client import connect as ws_connect
from typing import AsyncGenerator


@pytest.fixture
async def websocket_client(
    auth_token: str,
    transaction_service_ws_url: str
) -> AsyncGenerator:
    """Authenticated WebSocket client for real-time updates."""
    
    headers = {"Authorization": f"Bearer {auth_token}"}
    
    async with ws_connect(
        f"{transaction_service_ws_url}/ws/availability",
        extra_headers=headers,
        ping_interval=20,
        ping_timeout=10,
    ) as websocket:
        yield websocket


@pytest.fixture
def ws_message_collector():
    """Collect WebSocket messages for assertions."""
    messages = []
    
    async def collect(websocket, timeout: float = 5.0, count: int = 1):
        collected = []
        try:
            async with asyncio.timeout(timeout):
                while len(collected) < count:
                    msg = await websocket.recv()
                    collected.append(json.loads(msg))
        except asyncio.TimeoutError:
            pass
        messages.extend(collected)
        return collected
    
    return collect
```

### WebSocket Test Examples

```python
# tests/functional/test_realtime_availability.py

import pytest
import asyncio


@pytest.mark.asyncio
class TestRealtimeAvailability:
    """Test real-time availability updates via WebSocket."""
    
    async def test_should_receive_availability_update_on_booking(
        self,
        websocket_client,
        ws_message_collector,
        api_client,
        available_court,
    ):
        """Verify WebSocket broadcasts availability changes."""
        court_id = available_court["id"]
        
        # Subscribe to court availability
        await websocket_client.send(json.dumps({
            "action": "subscribe",
            "courtId": court_id,
            "date": "2026-02-15",
        }))
        
        # Create a booking via API
        booking_response = await api_client.post("/api/bookings", json={
            "courtId": court_id,
            "date": "2026-02-15",
            "startTime": "10:00",
            "duration": 60,
        })
        assert booking_response.status_code == 201
        
        # Collect WebSocket message
        messages = await ws_message_collector(websocket_client, timeout=3.0, count=1)
        
        # Verify availability update received
        assert len(messages) >= 1
        update = messages[0]
        assert update["type"] == "AVAILABILITY_UPDATE"
        assert update["courtId"] == court_id
        assert "10:00" in update["unavailableSlots"]
    
    async def test_should_receive_slot_released_on_cancellation(
        self,
        websocket_client,
        ws_message_collector,
        api_client,
        existing_booking,
    ):
        """Verify slot release broadcast on booking cancellation."""
        court_id = existing_booking["courtId"]
        booking_id = existing_booking["id"]
        
        # Subscribe to court
        await websocket_client.send(json.dumps({
            "action": "subscribe",
            "courtId": court_id,
            "date": existing_booking["date"],
        }))
        
        # Cancel the booking
        cancel_response = await api_client.delete(f"/api/bookings/{booking_id}")
        assert cancel_response.status_code == 200
        
        # Verify slot released message
        messages = await ws_message_collector(websocket_client, timeout=3.0, count=1)
        assert any(m["type"] == "SLOT_RELEASED" for m in messages)
```


## 24. External Service Mocking with Wiremock

### Wiremock Docker Setup

```yaml
# docker-compose.test.yml

services:
  wiremock:
    image: wiremock/wiremock:3.3.1
    ports:
      - "8089:8080"
    volumes:
      - ./tests/mocks/wiremock:/home/wiremock
    command: --verbose --global-response-templating
```

### Wiremock Mappings

```json
// tests/mocks/wiremock/mappings/weather-api.json
{
  "mappings": [
    {
      "name": "Get weather forecast",
      "request": {
        "method": "GET",
        "urlPathPattern": "/data/2.5/forecast",
        "queryParameters": {
          "lat": { "matches": "[0-9.-]+" },
          "lon": { "matches": "[0-9.-]+" },
          "appid": { "matches": ".+" }
        }
      },
      "response": {
        "status": 200,
        "headers": { "Content-Type": "application/json" },
        "jsonBody": {
          "cod": "200",
          "list": [
            {
              "dt": "{{now offset='0 hours' format='epoch'}}",
              "main": { "temp": 293.15, "humidity": 65 },
              "weather": [{ "main": "Clear", "description": "clear sky" }],
              "wind": { "speed": 3.5 }
            }
          ],
          "city": {
            "name": "Athens",
            "coord": { "lat": "{{request.query.lat}}", "lon": "{{request.query.lon}}" }
          }
        }
      }
    },
    {
      "name": "Weather API rate limit",
      "request": {
        "method": "GET",
        "urlPathPattern": "/data/2.5/forecast",
        "headers": { "X-Test-Scenario": { "equalTo": "rate-limited" } }
      },
      "response": {
        "status": 429,
        "headers": { "Retry-After": "60" },
        "jsonBody": { "cod": 429, "message": "Rate limit exceeded" }
      }
    }
  ]
}
```

```json
// tests/mocks/wiremock/mappings/fcm-api.json
{
  "mappings": [
    {
      "name": "Send FCM notification",
      "request": {
        "method": "POST",
        "urlPath": "/v1/projects/court-booking/messages:send",
        "headers": { "Authorization": { "matches": "Bearer .+" } }
      },
      "response": {
        "status": 200,
        "jsonBody": {
          "name": "projects/court-booking/messages/{{randomValue type='UUID'}}"
        }
      }
    }
  ]
}
```


### Wiremock Fixtures

```python
# tests/functional/conftest.py

import pytest
import requests
from typing import Generator


@pytest.fixture(scope="session")
def wiremock_url() -> str:
    """Wiremock server URL."""
    return os.getenv("WIREMOCK_URL", "http://localhost:8089")


@pytest.fixture
def wiremock_client(wiremock_url: str):
    """Client for programmatic Wiremock control."""
    
    class WiremockClient:
        def __init__(self, base_url: str):
            self.base_url = base_url
            self.admin_url = f"{base_url}/__admin"
        
        def reset(self) -> None:
            """Reset all mappings and requests."""
            requests.post(f"{self.admin_url}/reset")
        
        def stub(self, mapping: dict) -> None:
            """Add a stub mapping."""
            requests.post(f"{self.admin_url}/mappings", json=mapping)
        
        def verify(self, request_pattern: dict) -> dict:
            """Verify requests were made."""
            response = requests.post(
                f"{self.admin_url}/requests/count",
                json=request_pattern
            )
            return response.json()
        
        def get_requests(self) -> list:
            """Get all recorded requests."""
            response = requests.get(f"{self.admin_url}/requests")
            return response.json().get("requests", [])
        
        def set_scenario_state(self, scenario: str, state: str) -> None:
            """Set Wiremock scenario state."""
            requests.put(
                f"{self.admin_url}/scenarios/{scenario}/state",
                json={"state": state}
            )
    
    client = WiremockClient(wiremock_url)
    yield client
    client.reset()


# Usage in tests
def test_weather_api_fallback_on_rate_limit(api_client, wiremock_client):
    """Test graceful degradation when weather API is rate limited."""
    # Set up rate limit scenario
    wiremock_client.stub({
        "request": {
            "method": "GET",
            "urlPathPattern": "/data/2.5/forecast"
        },
        "response": {
            "status": 429,
            "headers": {"Retry-After": "60"}
        }
    })
    
    # Request court with weather
    response = api_client.get("/api/courts/1?includeWeather=true")
    
    # Should succeed with cached/default weather
    assert response.status_code == 200
    court = response.json()
    assert court["weather"] is None or court["weather"]["source"] == "CACHED"
```


## 25. Test Profiles (Mocked vs Integration)

### Profile Configuration

```python
# tests/config/test_profiles.py

from dataclasses import dataclass
from enum import Enum
import os


class TestProfile(Enum):
    MOCKED = "mocked"       # All external services mocked (Wiremock)
    INTEGRATION = "integration"  # Real services in test namespace


@dataclass
class ProfileConfig:
    """Configuration for test profile."""
    profile: TestProfile
    platform_service_url: str
    transaction_service_url: str
    transaction_service_ws_url: str
    use_wiremock: bool
    wiremock_url: str | None
    database_url: str
    redis_url: str
    stripe_mode: str  # "test" or "mock"


def get_profile_config() -> ProfileConfig:
    """Load configuration based on TEST_PROFILE env var."""
    profile_name = os.getenv("TEST_PROFILE", "mocked")
    profile = TestProfile(profile_name)
    
    if profile == TestProfile.MOCKED:
        return ProfileConfig(
            profile=profile,
            platform_service_url="http://localhost:8080",
            transaction_service_url="http://localhost:8081",
            transaction_service_ws_url="ws://localhost:8081",
            use_wiremock=True,
            wiremock_url="http://localhost:8089",
            database_url="postgresql://test:test@localhost:5432/courtbooking_test",
            redis_url="redis://localhost:6379/1",
            stripe_mode="mock",
        )
    else:  # INTEGRATION
        return ProfileConfig(
            profile=profile,
            platform_service_url=os.getenv("PLATFORM_SERVICE_URL", "https://test-api.courtbooking.gr"),
            transaction_service_url=os.getenv("TRANSACTION_SERVICE_URL", "https://test-api.courtbooking.gr"),
            transaction_service_ws_url=os.getenv("TRANSACTION_WS_URL", "wss://test-api.courtbooking.gr"),
            use_wiremock=False,
            wiremock_url=None,
            database_url=os.getenv("DATABASE_URL"),
            redis_url=os.getenv("REDIS_URL"),
            stripe_mode="test",  # Stripe test mode with real API
        )
```

### Profile-Aware Fixtures

```python
# tests/conftest.py

import pytest
from config.test_profiles import get_profile_config, TestProfile


@pytest.fixture(scope="session")
def profile_config():
    """Load test profile configuration."""
    return get_profile_config()


@pytest.fixture(scope="session")
def platform_service_url(profile_config) -> str:
    return profile_config.platform_service_url


@pytest.fixture(scope="session")
def transaction_service_url(profile_config) -> str:
    return profile_config.transaction_service_url


@pytest.fixture(scope="session")
def skip_if_mocked(profile_config):
    """Skip test if running in mocked profile."""
    if profile_config.profile == TestProfile.MOCKED:
        pytest.skip("Skipped in mocked profile - requires real services")


@pytest.fixture(scope="session")
def skip_if_integration(profile_config):
    """Skip test if running in integration profile."""
    if profile_config.profile == TestProfile.INTEGRATION:
        pytest.skip("Skipped in integration profile - uses mocked services")
```

### Running with Profiles

```bash
# Run with mocked profile (default)
TEST_PROFILE=mocked pytest tests/functional/

# Run with integration profile
TEST_PROFILE=integration pytest tests/functional/

# pytest.ini marker for profile-specific tests
# [tool.pytest.ini_options]
# markers = [
#     "mocked_only: Tests that only run in mocked profile",
#     "integration_only: Tests that only run in integration profile",
# ]
```


## 26. Court Booking Domain Fixtures

### API Client Setup

```python
# tests/functional/conftest.py

import pytest
import httpx
from typing import Generator


@pytest.fixture(scope="session")
def platform_api_client(
    platform_service_url: str,
    session_auth_token: str
) -> Generator[httpx.Client, None, None]:
    """Authenticated client for Platform Service."""
    with httpx.Client(
        base_url=platform_service_url,
        headers={
            "Authorization": f"Bearer {session_auth_token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        timeout=30.0,
    ) as client:
        yield client


@pytest.fixture(scope="session")
def transaction_api_client(
    transaction_service_url: str,
    session_auth_token: str
) -> Generator[httpx.Client, None, None]:
    """Authenticated client for Transaction Service."""
    with httpx.Client(
        base_url=transaction_service_url,
        headers={
            "Authorization": f"Bearer {session_auth_token}",
            "Content-Type": "application/json",
            "X-Idempotency-Key": "",  # Set per request
        },
        timeout=30.0,
    ) as client:
        yield client


@pytest.fixture(scope="session")
def session_auth_token(platform_service_url: str, test_user_credentials: dict) -> str:
    """Authenticate once per session and return JWT token."""
    response = httpx.post(
        f"{platform_service_url}/api/auth/login",
        json=test_user_credentials,
    )
    response.raise_for_status()
    return response.json()["accessToken"]


@pytest.fixture(scope="session")
def test_user_credentials() -> dict:
    """Test user credentials."""
    return {
        "email": os.getenv("TEST_USER_EMAIL", "testuser@courtbooking.gr"),
        "password": os.getenv("TEST_USER_PASSWORD", "testpassword123"),
    }


@pytest.fixture(scope="session")
def court_owner_auth_token(platform_service_url: str) -> str:
    """Auth token for court owner role."""
    response = httpx.post(
        f"{platform_service_url}/api/auth/login",
        json={
            "email": os.getenv("COURT_OWNER_EMAIL", "owner@courtbooking.gr"),
            "password": os.getenv("COURT_OWNER_PASSWORD", "ownerpass123"),
        },
    )
    return response.json()["accessToken"]


@pytest.fixture(scope="session")
def admin_auth_token(platform_service_url: str) -> str:
    """Auth token for platform admin role."""
    response = httpx.post(
        f"{platform_service_url}/api/auth/login",
        json={
            "email": os.getenv("ADMIN_EMAIL", "admin@courtbooking.gr"),
            "password": os.getenv("ADMIN_PASSWORD", "adminpass123"),
        },
    )
    return response.json()["accessToken"]
```


### Domain Factories

```python
# tests/functional/factories/court_factory.py

import factory
from factory import fuzzy
from pytest_factoryboy import register
from datetime import time


class CourtFactory(factory.Factory):
    """Factory for creating test courts."""
    
    class Meta:
        model = dict
    
    id = factory.Sequence(lambda n: n + 1)
    name = factory.LazyAttribute(lambda o: f"Test Court {o.id}")
    type = fuzzy.FuzzyChoice(["TENNIS", "PADEL", "BASKETBALL"])
    surface = fuzzy.FuzzyChoice(["CLAY", "HARD", "GRASS", "SYNTHETIC"])
    indoor = fuzzy.FuzzyChoice([True, False])
    
    location = factory.LazyFunction(lambda: {
        "lat": 37.9838 + factory.fuzzy.FuzzyFloat(-0.1, 0.1).fuzz(),
        "lon": 23.7275 + factory.fuzzy.FuzzyFloat(-0.1, 0.1).fuzz(),
        "address": "123 Test Street, Athens",
        "city": "Athens",
        "country": "GR",
    })
    
    basePriceCents = fuzzy.FuzzyInteger(1500, 5000)
    currency = "EUR"
    duration = fuzzy.FuzzyChoice([60, 90, 120])
    capacity = fuzzy.FuzzyInteger(2, 8)
    
    amenities = factory.LazyFunction(lambda: ["LIGHTING", "PARKING"])
    
    availabilityWindows = factory.LazyFunction(lambda: [
        {"dayOfWeek": "MONDAY", "startTime": "08:00", "endTime": "22:00"},
        {"dayOfWeek": "TUESDAY", "startTime": "08:00", "endTime": "22:00"},
        {"dayOfWeek": "WEDNESDAY", "startTime": "08:00", "endTime": "22:00"},
        {"dayOfWeek": "THURSDAY", "startTime": "08:00", "endTime": "22:00"},
        {"dayOfWeek": "FRIDAY", "startTime": "08:00", "endTime": "22:00"},
        {"dayOfWeek": "SATURDAY", "startTime": "09:00", "endTime": "20:00"},
        {"dayOfWeek": "SUNDAY", "startTime": "09:00", "endTime": "18:00"},
    ])
    
    class Params:
        premium = factory.Trait(
            basePriceCents=8000,
            amenities=["LIGHTING", "PARKING", "LOCKER_ROOM", "SHOWER", "PRO_SHOP"],
        )
        indoor_only = factory.Trait(indoor=True)


# tests/functional/factories/booking_factory.py

class BookingFactory(factory.Factory):
    """Factory for creating test bookings."""
    
    class Meta:
        model = dict
    
    id = factory.Sequence(lambda n: n + 1)
    courtId = factory.Sequence(lambda n: (n % 5) + 1)
    userId = factory.Sequence(lambda n: n + 100)
    
    date = factory.LazyFunction(
        lambda: (datetime.now() + timedelta(days=randint(1, 14))).strftime("%Y-%m-%d")
    )
    startTime = fuzzy.FuzzyChoice(["09:00", "10:00", "11:00", "14:00", "15:00", "16:00"])
    duration = fuzzy.FuzzyChoice([60, 90, 120])
    
    status = "PENDING_CONFIRMATION"
    paymentStatus = "PENDING"
    totalAmountCents = fuzzy.FuzzyInteger(2000, 6000)
    currency = "EUR"
    
    class Params:
        confirmed = factory.Trait(
            status="CONFIRMED",
            paymentStatus="CAPTURED",
        )
        cancelled = factory.Trait(
            status="CANCELLED",
            paymentStatus="REFUNDED",
        )
        pending_payment = factory.Trait(
            status="PENDING_CONFIRMATION",
            paymentStatus="AUTHORIZED",
        )


# Register factories
register(CourtFactory)
register(CourtFactory, "premium_court", premium=True)
register(BookingFactory)
register(BookingFactory, "confirmed_booking", confirmed=True)
register(BookingFactory, "cancelled_booking", cancelled=True)
```


### Domain Test Fixtures

```python
# tests/functional/conftest.py

@pytest.fixture
def available_court(platform_api_client, court_factory) -> dict:
    """Create a court that's available for booking."""
    court_data = court_factory()
    response = platform_api_client.post("/api/courts", json=court_data)
    response.raise_for_status()
    court = response.json()
    
    yield court
    
    # Cleanup
    platform_api_client.delete(f"/api/courts/{court['id']}")


@pytest.fixture
def existing_booking(
    transaction_api_client,
    available_court,
    booking_factory,
    idempotency_key,
) -> dict:
    """Create a booking for testing."""
    booking_data = booking_factory(courtId=available_court["id"])
    
    response = transaction_api_client.post(
        "/api/bookings",
        json=booking_data,
        headers={"X-Idempotency-Key": idempotency_key},
    )
    response.raise_for_status()
    booking = response.json()
    
    yield booking
    
    # Cleanup - cancel if not already cancelled
    if booking.get("status") != "CANCELLED":
        transaction_api_client.delete(f"/api/bookings/{booking['id']}")


@pytest.fixture
def idempotency_key() -> str:
    """Generate unique idempotency key for each test."""
    return str(uuid.uuid4())


@pytest.fixture
def stripe_test_card() -> dict:
    """Stripe test card details."""
    return {
        "number": "4242424242424242",
        "exp_month": 12,
        "exp_year": 2028,
        "cvc": "123",
    }


@pytest.fixture
def stripe_payment_method(stripe_test_card: dict, profile_config) -> str:
    """Create Stripe PaymentMethod for testing."""
    if profile_config.stripe_mode == "mock":
        return "pm_mock_visa"
    
    import stripe
    stripe.api_key = os.getenv("STRIPE_TEST_SECRET_KEY")
    
    pm = stripe.PaymentMethod.create(
        type="card",
        card=stripe_test_card,
    )
    return pm.id
```


## 27. Geospatial Testing

### PostGIS Query Testing

```python
# tests/functional/test_geospatial.py

import pytest
from math import radians, sin, cos, sqrt, atan2


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two points in meters (reference implementation)."""
    R = 6371000  # Earth's radius in meters
    
    lat1, lon1, lat2, lon2 = map(radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    
    a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlon/2)**2
    c = 2 * atan2(sqrt(a), sqrt(1-a))
    
    return R * c


class TestGeospatialSearch:
    """Test geospatial court search functionality."""
    
    # Athens city center coordinates
    ATHENS_CENTER = {"lat": 37.9838, "lon": 23.7275}
    
    @pytest.mark.parametrize("radius_meters,expected_min_results", [
        (1000, 1),    # 1km radius
        (5000, 3),    # 5km radius
        (10000, 5),   # 10km radius
    ])
    def test_search_courts_by_radius(
        self,
        platform_api_client,
        radius_meters: int,
        expected_min_results: int,
    ):
        """Verify radius-based court search."""
        response = platform_api_client.get("/api/courts/search", params={
            "lat": self.ATHENS_CENTER["lat"],
            "lon": self.ATHENS_CENTER["lon"],
            "radius": radius_meters,
        })
        
        assert response.status_code == 200
        courts = response.json()
        assert len(courts) >= expected_min_results
        
        # Verify all returned courts are within radius
        for court in courts:
            distance = haversine_distance(
                self.ATHENS_CENTER["lat"],
                self.ATHENS_CENTER["lon"],
                court["location"]["lat"],
                court["location"]["lon"],
            )
            assert distance <= radius_meters, f"Court {court['id']} is {distance}m away, exceeds {radius_meters}m"
    
    def test_search_returns_courts_sorted_by_distance(self, platform_api_client):
        """Verify courts are returned sorted by distance (nearest first)."""
        response = platform_api_client.get("/api/courts/search", params={
            "lat": self.ATHENS_CENTER["lat"],
            "lon": self.ATHENS_CENTER["lon"],
            "radius": 10000,
            "sort": "distance",
        })
        
        courts = response.json()
        distances = []
        
        for court in courts:
            distance = haversine_distance(
                self.ATHENS_CENTER["lat"],
                self.ATHENS_CENTER["lon"],
                court["location"]["lat"],
                court["location"]["lon"],
            )
            distances.append(distance)
        
        # Verify sorted ascending
        assert distances == sorted(distances), "Courts not sorted by distance"
    
    def test_bounding_box_search(self, platform_api_client):
        """Test bounding box search for map viewport."""
        # Athens bounding box (roughly 5km x 5km)
        response = platform_api_client.get("/api/courts/search", params={
            "minLat": 37.96,
            "maxLat": 38.01,
            "minLon": 23.70,
            "maxLon": 23.76,
        })
        
        assert response.status_code == 200
        courts = response.json()
        
        # Verify all courts within bounding box
        for court in courts:
            loc = court["location"]
            assert 37.96 <= loc["lat"] <= 38.01
            assert 23.70 <= loc["lon"] <= 23.76
    
    @pytest.mark.parametrize("invalid_coords", [
        {"lat": 91, "lon": 23.7275},    # Invalid latitude
        {"lat": 37.9838, "lon": 181},   # Invalid longitude
        {"lat": -91, "lon": 23.7275},   # Invalid negative latitude
    ])
    def test_invalid_coordinates_rejected(self, platform_api_client, invalid_coords: dict):
        """Verify invalid coordinates return 400."""
        response = platform_api_client.get("/api/courts/search", params={
            **invalid_coords,
            "radius": 5000,
        })
        
        assert response.status_code == 400
        assert "coordinate" in response.json().get("message", "").lower()
```


## 28. Stripe Payment Testing

### Stripe Test Mode Patterns

```python
# tests/functional/test_payments.py

import pytest
import stripe


class TestPaymentFlows:
    """Test payment flows using Stripe test mode."""
    
    # Stripe test card numbers
    CARD_SUCCESS = "4242424242424242"
    CARD_DECLINED = "4000000000000002"
    CARD_INSUFFICIENT_FUNDS = "4000000000009995"
    CARD_REQUIRES_AUTH = "4000002500003155"  # 3D Secure
    
    @pytest.fixture(autouse=True)
    def setup_stripe(self, profile_config):
        """Configure Stripe for test mode."""
        if profile_config.stripe_mode == "test":
            stripe.api_key = os.getenv("STRIPE_TEST_SECRET_KEY")
    
    def test_successful_payment_capture(
        self,
        transaction_api_client,
        available_court,
        stripe_payment_method,
        idempotency_key,
    ):
        """Test successful payment authorization and capture."""
        # Create booking with payment
        response = transaction_api_client.post(
            "/api/bookings",
            json={
                "courtId": available_court["id"],
                "date": "2026-02-20",
                "startTime": "10:00",
                "duration": 60,
                "paymentMethodId": stripe_payment_method,
            },
            headers={"X-Idempotency-Key": idempotency_key},
        )
        
        assert response.status_code == 201
        booking = response.json()
        assert booking["paymentStatus"] == "AUTHORIZED"
        
        # Confirm booking (triggers capture)
        confirm_response = transaction_api_client.post(
            f"/api/bookings/{booking['id']}/confirm"
        )
        
        assert confirm_response.status_code == 200
        confirmed = confirm_response.json()
        assert confirmed["paymentStatus"] == "CAPTURED"
    
    @pytest.mark.parametrize("card_number,expected_error", [
        ("4000000000000002", "card_declined"),
        ("4000000000009995", "insufficient_funds"),
        ("4000000000000069", "expired_card"),
    ])
    def test_payment_failure_scenarios(
        self,
        transaction_api_client,
        available_court,
        card_number: str,
        expected_error: str,
        profile_config,
    ):
        """Test various payment failure scenarios."""
        if profile_config.stripe_mode == "mock":
            pytest.skip("Requires real Stripe test mode")
        
        # Create payment method with failing card
        pm = stripe.PaymentMethod.create(
            type="card",
            card={
                "number": card_number,
                "exp_month": 12,
                "exp_year": 2028,
                "cvc": "123",
            },
        )
        
        response = transaction_api_client.post(
            "/api/bookings",
            json={
                "courtId": available_court["id"],
                "date": "2026-02-20",
                "startTime": "14:00",
                "duration": 60,
                "paymentMethodId": pm.id,
            },
            headers={"X-Idempotency-Key": str(uuid.uuid4())},
        )
        
        assert response.status_code == 402
        error = response.json()
        assert expected_error in error.get("code", "").lower()
    
    def test_refund_on_cancellation(
        self,
        transaction_api_client,
        confirmed_booking_with_payment,
    ):
        """Test refund processing on booking cancellation."""
        booking_id = confirmed_booking_with_payment["id"]
        
        # Cancel booking
        response = transaction_api_client.delete(f"/api/bookings/{booking_id}")
        
        assert response.status_code == 200
        cancelled = response.json()
        assert cancelled["status"] == "CANCELLED"
        assert cancelled["paymentStatus"] in ["REFUNDED", "PARTIALLY_REFUNDED"]
```


## 29. Database Reset & Test Data Seeding

### Database Fixtures

```python
# tests/conftest.py

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker


@pytest.fixture(scope="session")
def db_engine(profile_config):
    """Create database engine for test database."""
    return create_engine(profile_config.database_url)


@pytest.fixture(scope="session")
def db_session(db_engine):
    """Create database session."""
    Session = sessionmaker(bind=db_engine)
    session = Session()
    yield session
    session.close()


@pytest.fixture(scope="function")
def clean_database(db_session):
    """Reset database state before each test."""
    yield
    
    # Truncate test data tables (preserve seed data)
    db_session.execute(text("""
        TRUNCATE TABLE transaction.bookings CASCADE;
        TRUNCATE TABLE transaction.payments CASCADE;
        TRUNCATE TABLE transaction.notifications CASCADE;
        TRUNCATE TABLE transaction.waitlists CASCADE;
        TRUNCATE TABLE transaction.open_matches CASCADE;
    """))
    db_session.commit()


@pytest.fixture(scope="session", autouse=True)
def seed_test_data(db_session, profile_config):
    """Seed required test data once per session."""
    if profile_config.profile.value == "mocked":
        # Seed minimal data for mocked tests
        db_session.execute(text("""
            -- Seed test users
            INSERT INTO platform.users (id, email, name, role, status)
            VALUES 
                (1, 'testuser@courtbooking.gr', 'Test User', 'CUSTOMER', 'ACTIVE'),
                (2, 'owner@courtbooking.gr', 'Court Owner', 'COURT_OWNER', 'ACTIVE'),
                (3, 'admin@courtbooking.gr', 'Admin User', 'PLATFORM_ADMIN', 'ACTIVE')
            ON CONFLICT (id) DO NOTHING;
            
            -- Seed test courts
            INSERT INTO platform.courts (id, owner_id, name, type, location, base_price_cents)
            VALUES 
                (1, 2, 'Test Tennis Court', 'TENNIS', ST_SetSRID(ST_MakePoint(23.7275, 37.9838), 4326), 2500),
                (2, 2, 'Test Padel Court', 'PADEL', ST_SetSRID(ST_MakePoint(23.7300, 37.9850), 4326), 3000)
            ON CONFLICT (id) DO NOTHING;
        """))
        db_session.commit()
    
    yield
    
    # Cleanup is handled by clean_database fixture


@pytest.fixture
def reset_sequences(db_session):
    """Reset ID sequences for predictable test data."""
    db_session.execute(text("""
        ALTER SEQUENCE transaction.bookings_id_seq RESTART WITH 1000;
        ALTER SEQUENCE transaction.payments_id_seq RESTART WITH 1000;
    """))
    db_session.commit()
```

### Test Data Isolation

```python
# tests/functional/conftest.py

@pytest.fixture
def isolated_test_user(db_session, user_factory) -> dict:
    """Create isolated user for test - cleaned up after."""
    user_data = user_factory()
    
    db_session.execute(text("""
        INSERT INTO platform.users (email, name, role, status)
        VALUES (:email, :name, 'CUSTOMER', 'ACTIVE')
        RETURNING id
    """), user_data)
    result = db_session.fetchone()
    user_data["id"] = result[0]
    db_session.commit()
    
    yield user_data
    
    # Cleanup
    db_session.execute(text("DELETE FROM platform.users WHERE id = :id"), {"id": user_data["id"]})
    db_session.commit()
```


## 30. Court Booking Test Scenarios Reference

### Critical Test Scenarios Checklist

| Category | Scenario | Priority | Profile |
|----------|----------|----------|---------|
| **Auth** | OAuth login (Google, Facebook, Apple) | P0 | Integration |
| **Auth** | JWT token refresh | P0 | Both |
| **Auth** | Role-based access control | P0 | Both |
| **Courts** | Create court with availability windows | P0 | Both |
| **Courts** | Geospatial search by radius | P0 | Both |
| **Courts** | Bounding box search for map | P1 | Both |
| **Bookings** | Create booking with payment | P0 | Integration |
| **Bookings** | Booking conflict detection | P0 | Both |
| **Bookings** | Slot hold mechanism (5-min hold) | P0 | Both |
| **Bookings** | Idempotency key handling | P0 | Both |
| **Bookings** | Cancellation with refund | P0 | Integration |
| **Bookings** | Recurring booking creation | P1 | Both |
| **Payments** | Stripe payment authorization | P0 | Integration |
| **Payments** | Payment capture on confirmation | P0 | Integration |
| **Payments** | Split payment flow | P1 | Integration |
| **Payments** | Refund on cancellation | P0 | Integration |
| **Waitlist** | Join waitlist for booked slot | P1 | Both |
| **Waitlist** | Waitlist notification on cancellation | P1 | Both |
| **Matches** | Create open match | P1 | Both |
| **Matches** | Join open match | P1 | Both |
| **Notifications** | Push notification delivery | P1 | Integration |
| **Notifications** | WebSocket real-time updates | P0 | Both |
| **Weather** | Weather forecast for court | P2 | Integration |
| **Support** | Create support ticket | P2 | Both |

### API Endpoint Coverage Matrix

```
Platform Service Endpoints:
├── /api/auth/*           ✓ Auth flows
├── /api/users/*          ✓ User management
├── /api/courts/*         ✓ Court CRUD + search
├── /api/weather/*        ✓ Weather integration
├── /api/analytics/*      ○ Dashboard data
├── /api/promo-codes/*    ○ Promo management
├── /api/feature-flags/*  ○ Feature flags
├── /api/admin/*          ○ Admin operations
└── /api/support/*        ○ Support tickets

Transaction Service Endpoints:
├── /api/bookings/*       ✓ Booking flows
├── /api/payments/*       ✓ Payment processing
├── /api/notifications/*  ✓ Notification management
├── /api/waitlist/*       ○ Waitlist flows
├── /api/matches/*        ○ Open matches
└── /api/split-payments/* ○ Split payments

Legend: ✓ = Covered, ○ = To implement
```

---

> **Document Version**: 2.0.0  
> **Last Updated**: February 2026  
> **Application**: Court Booking Platform QA Suite  
> **Sources**: pytest docs, Appium Python Client, pytest-bdd, Locust, Playwright, Pact, Wiremock, Stripe Test Mode
