import XCTest

/// Targeted screenshot tests for specific App Store screenshot scenarios
final class ScreenshotUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launch()
        sleep(3)
    }
    
    override func tearDown() {
        app.terminate()
        super.tearDown()
    }
    
    func capture(name: String) {
        sleep(2)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let tmpDir = FileManager.default.temporaryDirectory
        let url = tmpDir.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
    }
    
    // Screen 1: Hero Scan - Scan tab
    func testScreen01HeroScan() throws {
        sleep(2)
        capture(name: "01-hero-scan")
    }
    
    // Screen 2: Good Grade Result - tap on a good-grade item in History
    func testScreen02GradeResult() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        
        // Go to History tab
        let historyTab = tabBar.buttons["History"]
        if historyTab.exists { historyTab.tap() } else { tabBar.buttons.element(boundBy: 1).tap() }
        sleep(2)
        
        // Look for Greek Yogurt (A grade) or first item
        let cells = app.tables.cells
        if cells.count > 0 {
            // Tap first item (should be Greek Yogurt A-grade)
            cells.element(boundBy: 0).tap()
            sleep(3)
            capture(name: "02-grade-result")
        } else {
            capture(name: "02-grade-result-list")
        }
    }
    
    // Screen 3: Ingredient Breakdown - tap on a flagged item
    func testScreen03IngredientBreakdown() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        
        // Go to History tab
        let historyTab = tabBar.buttons["History"]
        if historyTab.exists { historyTab.tap() } else { tabBar.buttons.element(boundBy: 1).tap() }
        sleep(2)
        
        // Tap on Cheez-It (C grade, has flags) - it's the second item
        let cells = app.tables.cells
        if cells.count > 1 {
            cells.element(boundBy: 1).tap()
            sleep(3)
            
            // Scroll down to see ingredient flags
            app.swipeUp()
            sleep(1)
            capture(name: "03-ingredient-breakdown")
        } else {
            capture(name: "03-ingredient-breakdown-fallback")
        }
    }
    
    // Screen 4: Personalization - Profile/Goals
    func testScreen04Personalization() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        
        // Go to More tab
        let moreTab = tabBar.buttons["More"]
        if moreTab.exists {
            moreTab.tap()
            sleep(2)
            
            // Look for Profile or Goals option
            let goalsBtn = app.tables.cells.staticTexts["My Goals & Priorities"]
            if goalsBtn.exists {
                goalsBtn.tap()
                sleep(3)
                capture(name: "04-personalization-goals")
            } else {
                let profileBtn = app.tables.cells.staticTexts["Profile"]
                if profileBtn.exists {
                    profileBtn.tap()
                    sleep(2)
                }
                capture(name: "04-personalization")
            }
        }
    }
    
    // Screen 5: Allergen Alert - Allergen Profiles view
    func testScreen05AllergenAlert() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        
        // Go to More tab
        let moreTab = tabBar.buttons["More"]
        if moreTab.exists {
            moreTab.tap()
            sleep(2)
            
            // Look for Profile first
            let profileBtn = app.tables.cells.staticTexts["Profile"]
            if profileBtn.exists {
                profileBtn.tap()
                sleep(2)
                
                // Look for Allergen Profiles option
                let allergenBtn = app.buttons.matching(identifier: "Allergen Profiles").firstMatch
                if allergenBtn.exists {
                    allergenBtn.tap()
                    sleep(2)
                    capture(name: "05-allergen-profiles")
                } else {
                    // Try finding it in a list
                    let allergenCell = app.tables.cells.staticTexts["Allergen Profiles"]
                    if allergenCell.exists {
                        allergenCell.tap()
                        sleep(2)
                        capture(name: "05-allergen-profiles")
                    } else {
                        capture(name: "05-profile-with-allergen")
                    }
                }
            } else {
                capture(name: "05-allergen-fallback")
            }
        }
    }
    
    // Screen 6: Pantry Tracker
    func testScreen06PantryTracker() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        
        // Go to Pantry tab (index 3)
        let pantryTab = tabBar.buttons["Pantry"]
        if pantryTab.exists {
            pantryTab.tap()
        } else {
            tabBar.buttons.element(boundBy: 3).tap()
        }
        sleep(2)
        capture(name: "06-pantry-tracker")
    }
    
    // Combined: capture all custom screenshots in one run
    func testCaptureAppStoreScreenshots() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        
        // === Screen 1: Hero Scan ===
        capture(name: "appstore-01-hero-scan")
        
        // === Screen 2: Grade Result (Product Detail - A grade) ===
        let historyTab = tabBar.buttons["History"]
        if historyTab.exists { historyTab.tap() } else { tabBar.buttons.element(boundBy: 1).tap() }
        sleep(2)
        
        let cells = app.tables.cells
        if cells.count > 0 {
            cells.element(boundBy: 0).tap()  // Greek Yogurt - A grade
            sleep(3)
            capture(name: "appstore-02-grade-result")
            app.navigationBars.buttons.firstMatch.tap()  // Back
            sleep(1)
        }
        
        // === Screen 3: Ingredient Breakdown (Cheez-It - flagged) ===
        if cells.count > 1 {
            cells.element(boundBy: 1).tap()  // Cheez-It - C grade with flags
            sleep(3)
            // Scroll to see flags
            app.swipeUp()
            sleep(1)
            capture(name: "appstore-03-ingredient-breakdown")
            app.navigationBars.buttons.firstMatch.tap()  // Back
            sleep(1)
        }
        
        // === Screen 6: Pantry Tracker ===
        let pantryTab = tabBar.buttons["Pantry"]
        if pantryTab.exists { pantryTab.tap() } else { tabBar.buttons.element(boundBy: 3).tap() }
        sleep(2)
        capture(name: "appstore-06-pantry-tracker")
        
        // === Screens 4 & 5: Profile/Personalization ===
        let moreTab = tabBar.buttons["More"]
        if moreTab.exists {
            moreTab.tap()
            sleep(2)
            
            let profileBtn = app.tables.cells.staticTexts["Profile"]
            if profileBtn.exists {
                profileBtn.tap()
                sleep(2)
                capture(name: "appstore-04-personalization")
                
                // Try to access allergen profiles from profile
                let allergenCell = app.tables.cells.staticTexts["Allergen Profiles"]
                if allergenCell.exists {
                    allergenCell.tap()
                    sleep(2)
                    capture(name: "appstore-05-allergen-alert")
                } else {
                    // Back to More and look for allergen separately
                    app.navigationBars.buttons.firstMatch.tap()
                    sleep(1)
                    capture(name: "appstore-05-allergen-from-profile")
                }
            } else {
                capture(name: "appstore-04-more-tab")
                capture(name: "appstore-05-more-tab-2")
            }
        }
    }
}
