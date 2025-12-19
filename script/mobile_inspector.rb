#!/usr/bin/env ruby

require 'capybara'
require 'capybara/dsl'
require 'selenium-webdriver'

# Configure Capybara
Capybara.default_driver = :selenium_headless
Capybara.app_host = 'http://localhost:3000'

class MobileInspector
  include Capybara::DSL

  def initialize
    # Configure Chrome for mobile viewport
    Capybara.register_driver :selenium_headless do |app|
      options = Selenium::WebDriver::Chrome::Options.new
      options.add_argument('--headless=new')
      options.add_argument('--no-sandbox')
      options.add_argument('--disable-dev-shm-usage')
      options.add_argument('--window-size=375,812') # iPhone X dimensions

      Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
    end

    Capybara.current_driver = :selenium_headless
  end

  def capture_page(url, filename)
    puts "Capturing #{url}..."
    visit(url)
    sleep(2) # Wait for page to load

    # Set mobile viewport
    page.driver.browser.manage.window.resize_to(375, 812)
    sleep(1)

    # Take screenshot
    screenshot_path = Rails.root.join('tmp', 'screenshots', filename)
    FileUtils.mkdir_p(File.dirname(screenshot_path))
    page.save_screenshot(screenshot_path)

    puts "Screenshot saved to #{screenshot_path}"
    screenshot_path
  end

  def inspect_pages
    pages = [
      ['/', 'mobile_home.png'],
      ['/scores', 'mobile_scores_index.png'],
      ['/scores?search=bach', 'mobile_search_results.png'],
    ]

    # Try to find a score to screenshot
    begin
      visit('/scores')
      if page.has_css?('a[href*="/scores/"]', wait: 2)
        score_link = page.first('a[href*="/scores/"]')[:href]
        pages << [score_link, 'mobile_score_detail.png']
      end
    rescue => e
      puts "Could not find score detail page: #{e.message}"
    end

    screenshots = []
    pages.each do |url, filename|
      begin
        screenshot_path = capture_page(url, filename)
        screenshots << screenshot_path
      rescue => e
        puts "Error capturing #{url}: #{e.message}"
      end
    end

    puts "\n✅ Captured #{screenshots.length} screenshots"
    screenshots
  end
end

# Run if called directly
if __FILE__ == $0
  require_relative '../config/environment'

  inspector = MobileInspector.new
  inspector.inspect_pages
end
