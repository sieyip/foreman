ENV["RAILS_ENV"] = "test"
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'
require 'mocha/mini_test'
require 'capybara/rails'
require 'factory_girl_rails'
require 'capybara/poltergeist'
require 'show_me_the_cookies'
require 'database_cleaner'
require 'active_support_test_case_helper'
require 'minitest-optional_retry'

DatabaseCleaner.strategy = :transaction

Capybara.register_driver :poltergeist do |app|
  opts = {
    # To enable debugging uncomment `:inspector => true` and
    # add `page.driver.debug` in code to open webkit inspector
    # :inspector => true
    :js_errors => true,
    :timeout => 60,
    :extensions => ["#{Rails.root}/test/integration/support/poltergeist_onload_extensions.js"],
    :phantomjs => File.join(Rails.root, 'node_modules', '.bin', 'phantomjs')
  }
  Capybara::Poltergeist::Driver.new(app, opts)
end

Capybara.default_max_wait_time = 30
Capybara.javascript_driver = :poltergeist

class ActionDispatch::IntegrationTest
  # Make the Capybara DSL available in all integration tests
  include Capybara::DSL
  include ShowMeTheCookies

  # Stop ActiveRecord from wrapping tests in transactions
  self.use_transactional_fixtures = false

  def assert_index_page(index_path,title_text,new_link_text = nil,has_search = true,has_pagination = true)
    visit index_path
    assert page.has_selector?('h1', :text => title_text), "#{title_text} was expected in the <h1> tag, but was not found"
    (assert find_link(new_link_text).visible?, "#{new_link_text} is not visible") if new_link_text
    (assert find_button('Search').visible?, "Search button is not visible") if has_search
    (assert has_content?("Displaying"), "Pagination 'Display ...' does not appear") if has_pagination
  end

  def assert_new_button(index_path,new_link_text,new_path)
    visit index_path
    click_link new_link_text
    assert_current_path new_path
  end

  def assert_submit_button(redirect_path,button_text = "Submit")
    click_button button_text
    assert_current_path redirect_path
  end

  def assert_delete_row(index_path, link_text, delete_text = "Delete", dropdown = false)
    visit index_path
    within(:xpath, "//tr[contains(.,'#{link_text}')]") do
      find("i.caret").click if dropdown
      click_link(delete_text)
    end
    popup = page.driver.browser.switch_to.alert
    popup.accept
    assert page.has_no_link?(link_text), "link '#{link_text}' was expected NOT to be on the page, but it was found."
    assert page.has_content?('Successfully destroyed'), "flash message 'Successfully destroyed' was expected but it was not found on the page"
  end

  def assert_cannot_delete_row(index_path, link_text, delete_text = "Delete", dropdown = false, flash_message = true)
    visit index_path
    within(:xpath, "//tr[contains(.,'#{link_text}')]") do
      find("i.caret").click if dropdown
      click_link(delete_text)
    end
    popup = page.driver.browser.switch_to.alert
    popup.accept
    assert page.has_link?(link_text), "link '#{link_text}' was expected but it was not found on the page."
    assert page.has_content?("is used by"), "flash message 'is used by' was expected but it was not found on the page."
  end

  def fix_mismatches
    Location.all_import_missing_ids
    Organization.all_import_missing_ids
  end

  def select2(value, attrs)
    find("#s2id_#{attrs[:from]}").click
    find(".select2-input").set(value)
    within ".select2-results" do
      find("span", text: value).click
    end
  end

  def wait_for_ajax
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop until page.evaluate_script('jQuery.active').zero?
    end
  end

  setup :login_admin

  teardown do
    DatabaseCleaner.clean       # Truncate the database
    Capybara.reset_sessions!    # Forget the (simulated) browser state
    Capybara.use_default_driver # Revert Capybara.current_driver to Capybara.default_driver
    SSO.deregister_method(TestSSO)
  end

  private

  def login_admin
    SSO.register_method(TestSSO)
    set_request_user(:admin)
  end

  def logout_admin
    delete_cookie('test_user')
  end

  def set_request_user(user)
    user = users(user) unless user.is_a?(User)
    create_cookie('test_user', user.login)
  end
end

class IntegrationTestWithJavascript < ActionDispatch::IntegrationTest
  def login_admin
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.start
    Capybara.current_driver = Capybara.javascript_driver
    super
  end
end

class TestSSO < SSO::Base
  def available?
    Rails.env.test? && request.cookies['test_user'].present?
  end

  def authenticated?
    self.user = request.cookies['test_user']
  end
end
