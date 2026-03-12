import XCTest

final class RevelioUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launch()
        // Wait for app to fully load
        sleep(3)
    }
    
    override func tearDown() {
        app.terminate()
        super.tearDown()
    }
    
    // MARK: - Screenshot Helper
    
    func captureAndAttach(name: String) {
        sleep(2) // Let animations settle
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        
        // Also save to a known temp path for easier extraction
        let tmpDir = FileManager.default.temporaryDirectory
        let screenshotURL = tmpDir.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: screenshotURL)
    }
    
    // MARK: - Tests
    
    func testCaptureAllScreenshots() throws {
        // Screenshot 1: Scan tab (default on launch)
        captureAndAttach(name: "01-scan")
        
        // Navigate to History tab
        let tabBar = app.tabBars.firstMatch
        let historyTab = tabBar.buttons["History"]
        if historyTab.exists {
            historyTab.tap()
        } else {
            // Try by index
            tabBar.buttons.element(boundBy: 1).tap()
        }
        captureAndAttach(name: "02-history")
        
        // Navigate to Trends tab
        let trendsTab = tabBar.buttons["Trends"]
        if trendsTab.exists {
            trendsTab.tap()
        } else {
            tabBar.buttons.element(boundBy: 2).tap()
        }
        captureAndAttach(name: "03-trends")
        
        // Navigate to Pantry tab
        let pantryTab = tabBar.buttons["Pantry"]
        if pantryTab.exists {
            pantryTab.tap()
        } else {
            tabBar.buttons.element(boundBy: 3).tap()
        }
        captureAndAttach(name: "04-pantry")
        
        // Navigate to More / Explore / Profile
        let moreTab = tabBar.buttons["More"]
        if moreTab.exists {
            moreTab.tap()
            sleep(1)
            // Look for Profile or Settings in More menu
            let profileButton = app.tables.cells.staticTexts["Profile"]
            if profileButton.exists {
                profileButton.tap()
                captureAndAttach(name: "05-profile")
            } else {
                captureAndAttach(name: "05-more")
            }
        } else {
            // Try Explore tab directly
            let exploreTab = tabBar.buttons["Explore"]
            if exploreTab.exists {
                exploreTab.tap()
                captureAndAttach(name: "05-explore")
            } else {
                tabBar.buttons.element(boundBy: 4).tap()
                captureAndAttach(name: "05-more")
            }
        }
        
        // Navigate to Settings from More menu  
        let moreTab2 = tabBar.buttons["More"]
        if moreTab2.exists {
            moreTab2.tap()
            sleep(1)
            let settingsButton = app.tables.cells.staticTexts["Settings"]
            if settingsButton.exists {
                settingsButton.tap()
                captureAndAttach(name: "06-settings")
            }
        }
    }
    
    func testCaptureScanScreen() throws {
        sleep(2)
        captureAndAttach(name: "01-scan")
    }
    
    func testCaptureHistoryScreen() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        
        let historyTab = tabBar.buttons["History"]
        if historyTab.exists {
            historyTab.tap()
        } else {
            tabBar.buttons.element(boundBy: 1).tap()
        }
        sleep(2)
        captureAndAttach(name: "02-history")
    }
    
    func testCaptureTrendsScreen() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        
        let trendsTab = tabBar.buttons["Trends"]
        if trendsTab.exists {
            trendsTab.tap()
        } else {
            tabBar.buttons.element(boundBy: 2).tap()
        }
        sleep(2)
        captureAndAttach(name: "03-trends")
    }
    
    func testCapturePantryScreen() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        
        let pantryTab = tabBar.buttons["Pantry"]
        if pantryTab.exists {
            pantryTab.tap()
        } else {
            tabBar.buttons.element(boundBy: 3).tap()
        }
        sleep(2)
        captureAndAttach(name: "04-pantry")
    }
    
    func testCaptureMoreScreens() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        
        // Tab 5: Explore or More
        let moreTab = tabBar.buttons["More"]
        let exploreTab = tabBar.buttons["Explore"]
        
        if moreTab.exists {
            moreTab.tap()
            sleep(2)
            captureAndAttach(name: "05-more")
        } else if exploreTab.exists {
            exploreTab.tap()
            sleep(2)
            captureAndAttach(name: "05-explore")
        } else {
            tabBar.buttons.element(boundBy: 4).tap()
            sleep(2)
            captureAndAttach(name: "05-extra")
        }
        
        // Settings (via More menu or direct tab)
        if moreTab.exists {
            moreTab.tap()
            sleep(1)
            let settingsCell = app.tables.cells.staticTexts["Settings"]
            if settingsCell.exists {
                settingsCell.tap()
                sleep(2)
                captureAndAttach(name: "06-settings")
            }
        }
    }
}
