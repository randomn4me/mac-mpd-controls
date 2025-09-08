import Foundation

// Test runner for Linux without XCTest
print("Starting MPD Controls Tests...")

BasicTests.run()
MPDProtocolTests.run()
MPDTypesTests.run()
MPDClientTests.run()
NetworkConnectionTests.run()
EndToEndTests.run()
IntegrationTests.runAll()

print("\n✅ All test suites completed successfully!")