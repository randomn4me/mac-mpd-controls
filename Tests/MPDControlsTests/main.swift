import Foundation

// Test runner for Linux without XCTest
print("Starting MPD Controls Tests...")

BasicTests.run()
MPDProtocolTests.run()
MPDTypesTests.run()

print("\n✅ All test suites completed successfully!")