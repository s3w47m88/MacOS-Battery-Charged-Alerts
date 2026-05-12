#!/usr/bin/env ruby
require 'spaceship'

KEY_ID = "XG3FW9LT9Q"
ISSUER_ID = "178bab61-1c45-4f62-9525-55f8ed15a98d"
KEY_PATH = File.expand_path("~/.appstoreconnect/private_keys/AuthKey_XG3FW9LT9Q.p8")
BUNDLE_ID = "com.spencerhill.fullbatteryalert"
APP_NAME = "MacOS Fully Battery Alert"
SKU = "fullbatteryalert001"

token = Spaceship::ConnectAPI::Token.create(
  key_id: KEY_ID,
  issuer_id: ISSUER_ID,
  filepath: KEY_PATH
)
Spaceship::ConnectAPI.token = token

puts "Checking for existing bundle ID..."
existing_bid = Spaceship::ConnectAPI::BundleId.all(filter: { identifier: BUNDLE_ID }).first
if existing_bid
  puts "Bundle ID #{BUNDLE_ID} already registered (id=#{existing_bid.id})"
else
  puts "Registering bundle ID #{BUNDLE_ID}..."
  Spaceship::ConnectAPI::BundleId.create(
    name: "MacOS Fully Battery Alert",
    platform: Spaceship::ConnectAPI::BundleIdPlatform::MAC_OS,
    identifier: BUNDLE_ID
  )
  puts "Bundle ID registered."
end

puts "Checking for existing app..."
existing_app = Spaceship::ConnectAPI::App.find(BUNDLE_ID)
if existing_app
  puts "App already exists: #{existing_app.name} (id=#{existing_app.id})"
else
  puts "Creating ASC app record..."
  Spaceship::ConnectAPI::App.create(
    name: APP_NAME,
    version_string: "0.1.0",
    sku: SKU,
    primary_locale: "en-US",
    bundle_id: BUNDLE_ID,
    platforms: [Spaceship::ConnectAPI::Platform::MAC_OS],
    company_name: nil
  )
  puts "App created."
end
