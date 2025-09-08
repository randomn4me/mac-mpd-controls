import Foundation

// Test runner for Linux without XCTest
@main
struct TestRunner {
    static func main() {
        print("Starting MPD Controls Tests...")
        
        BasicTests.run()
        MPDProtocolTests.run()
        MPDTypesTests.run()
        MPDClientTests.run()
        NetworkConnectionTests.run()
        
        print("\n✅ All test suites completed successfully!")
    }
}