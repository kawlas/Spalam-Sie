# Spalam Sie - Testing Strategy

## Overview

Spalam Sie employs a comprehensive testing strategy to ensure reliability, correctness, and maintainability. The approach combines unit testing, integration testing, and manual verification to cover all aspects of the application.

## Testing Levels

### 1. Unit Testing
- **Purpose**: Validate individual components in isolation
- **Scope**: Each class, struct, and function with complex logic
- **Framework**: XCTest (built into Swift)
- **Frequency**: Run on every build (continuous integration)
- **Coverage Goal**: 80%+ for critical modules (Audio, Metadata, Parsing)

#### Unit Test Characteristics:
- Fast execution (should complete in seconds)
- No external dependencies (mock services, file system, etc.)
- Deterministic output given identical input
- Focus on business logic and edge cases

#### Example Units to Test:
- AudioConverter.format detection and routing
- MetadataExtractor JSON parsing and field extraction
- CUEParser grammar handling and edge cases
- String utilities and file path manipulations
- Data model validation and serialization

### 2. Integration Testing
- **Purpose**: Verify that modules work together correctly
- **Scope**: Workflows spanning multiple modules
- **Framework**: XCTest with test doubles/mocks where appropriate
- **Frequency**: Run on every build, more comprehensive than unit tests
- **Coverage Goal**: Critical user workflows

#### Integration Test Characteristics:
- May involve actual file system operations
- May use real command-line tools in test environment
- Tests complete workflows from input to output
- Validates data flow between modules

#### Example Integrations to Test:
- Full audio conversion pipeline (input file → WAV output)
- Metadata extraction integrated with audio conversion
- CUE parsing combined with track listing generation
- Temporary file creation, usage, and cleanup
- Error propagation between modules

### 3. Manual Testing
- **Purpose**: Validate user experience and edge cases not easily automated
- **Scope**: UI interactions, hardware integration, complex workflows
- **Frequency**: Before each release, during feature development
- **Responsibility**: QA and developer verification

#### Manual Test Areas:
- User interface responsiveness and accessibility
- Drag-and-drop functionality
- Device detection and burning with actual hardware
- Error recovery and user feedback mechanisms
- Performance under various system loads
- Compatibility with different macOS versions

#### Manual Test Environments:
- Multiple macOS versions (minimum supported to latest)
- Various hardware configurations (different Mac models)
- Different optical drive models (USB and internal)
- Various file system formats (APFS, HFS+, exFAT, etc.)
- Different audio file qualities and metadata formats

### 4. Performance Testing
- **Purpose**: Ensure application meets performance requirements
- **Scope**: Startup time, memory usage, conversion speed, burning throughput
- **Frequency**: Weekly or before major releases
- **Tools**: Instruments, custom benchmarking scripts

#### Performance Metrics:
- Application launch time (< 2 seconds)
- Memory usage (< 100MB typical, < 200MB maximum)
- Audio conversion speed (real-time or better)
- UI response time (< 16ms for 60fps)
- Resource cleanup efficiency

### 5. Regression Testing
- **Purpose**: Prevent reintroduction of fixed bugs
- **Scope**: Previously identified and fixed issues
- **Frequency**: Every build
- **Implementation**: Specific test cases for each bug fixed

## Test Organization

### Unit Tests
- Located in `Tests/` directory mirroring source structure
- Naming convention: `[Class]Tests.swift]Tests.swift`
- Each test class contains multiple test methods
- Test methods follow `test[Feature][Condition][ExpectedResult]` naming

### Test Targets
- Main application target: `Spalam Sie`
- Unit test target: `Spalam SieTests`
- Potential future UI test target: `Spalam SieUITests`

## Mocking and Test Doubles

### When to Use Mocks
- External services (network, hardware)
- Slow operations (file I/O on network drives)
- Non-deterministic components (timers, random number generators)
- Complex setup scenarios

### Mocking Approach
- Protocol-based dependency injection
- Manual mock objects (Swift doesn't have built-in mocking framework)
- Test-specific implementations of protocols

### Example: Testing MetadataExtractor
```swift
// Instead of relying on actual files and ffprobe in tests,
// we could inject a FileReader protocol and provide a mock
// that returns predefined JSON responses
```

## Test Data Management

### Fixtures
- Small, representative files stored in `Tests/Fixtures/`
- Includes various audio formats with known metadata
- Edge case files (empty files, malformed headers, etc.)
- Version controlled but kept small to minimize repo size

### Generated Data
- Most test data created programmatically in setUp()
- Ensures tests are self-contained and deterministic
- Reduces dependency on external files

### Temporary Files
- All tests use `FileManager.default.temporaryDirectory`
- Unique file names to prevent collisions
- Proper cleanup in tearDown() or using defer statements
- Validation that no test files remain after test completion

## Continuous Integration

### Local Development
- `swift test` runs before each commit
- Developers run full test suite before pushing
- Xcode test navigator used for debugging failing tests

### Automated CI (Future)
- GitHub Actions or similar service
- Build and test on push/pull request
- Test results reported in PR checks
- Code coverage reports generated
- Performance benchmarks tracked over time

## Coverage Analysis

### Tools
- Xcode's built-in code coverage (enabled via scheme settings)
- `slather` or `xcov` for detailed reports
- Coverage reports generated on CI

### Metrics to Track
- Line coverage percentage
- Branch coverage percentage
- Function coverage percentage
- Changes in coverage over time

### Thresholds
- Block merge if coverage drops below threshold for new code
- Require justification for excluded lines
- Focus on complex logic rather than trivial getters/setters

## Test Maintenance

### Test Reviews
- Tests reviewed alongside code in pull requests
- Same quality standards applied to test code as production code
- Tests should be readable, maintainable, and valuable

### Test Refactoring
- Tests refactored when they become brittle or hard to understand
- Duplicate test code extracted to helper methods
- Test data factories created for complex object creation
- Obsolete or redundant tests removed

### Flaky Tests
- Immediately investigated when detected
- Common causes: timing issues, external resource dependencies
- Fixed or replaced with more reliable alternatives
- Quarantined if cannot be fixed immediately

## Specific Test Plans by Module

### Audio Module Tests
- Format detection accuracy
- Conversion quality (bit rate, sample rate, channels)
- Error handling (missing files, unsupported formats, corrupt data)
- Performance benchmarks
- Temporary file cleanup verification

### Metadata Module Tests
- Metadata extraction accuracy for various formats
- Handling of missing or malformed metadata
- Character encoding support (UTF-8, ISO-8859-1, etc.)
- Performance with large files
- Memory usage patterns

### Parsing Module Tests
- Complete CUE specification compliance
- Error recovery for malformed cue sheets
- Support for various audio file types in FILE statements
- Proper handling of indices, pregaps, postgaps
- CD-TEXT keyword extraction

### Burning Module Tests (Mocked)
- Device detection logic
- Parameter validation and sanitization
- Progress reporting accuracy
- Error handling and recovery scenarios
- Resource cleanup verification

### UI Tests (Future)
- User interaction workflows
- State persistence and restoration
- Accessibility compliance
- Responsive behavior to window resizing
- Dark/light mode adaptability

## Release Criteria

### Blocking Issues
- Any failing unit or integration test in core modules
- Security vulnerabilities identified
- Critical usability issues blocking core workflows
- Performance regressions beyond acceptable thresholds

### Non-Blocking Issues
- UI polish and enhancement suggestions
- Non-critical edge case failures
- Documentation improvements
- Build time increases (unless severe)

## Tools and Resources

### Testing Frameworks
- XCTest (primary)
- Quick/Nimble (optional, for more expressive assertions if needed)
- Custom test helpers as needed

### Analysis Tools
- Xcode Instruments (for performance and memory profiling)
- Clang Static Analyzer
- SwiftLint (for code style enforcement)
- Tailor (for style checking, if adopted)

### External Services
- None required for core testing (avoiding external dependencies increases reliability)
- Network-dependent features would use mocked services in tests

This testing strategy ensures that Spalam Sie maintains high quality, reliability, and correctness throughout its development lifecycle, giving users confidence in the application's ability to safely and correctly burn their audio CDs.
