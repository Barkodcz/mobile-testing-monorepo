#!/usr/bin/env ruby
# Adds the native XCUITest "RunnerUITests" target that Patrol's iOS runner
# requires -- `flutter create` only generates a unit test target
# ("RunnerTests"), never a UI test target, so Patrol's own xctestrun patcher
# has nothing real to attach to and the run fails with "Missing test product
# at (null)". Safe to run many times: no-op if the target already exists.
# Usage (from apps/flutter): ruby tool/patrol_setup_ios.rb

require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'ios', 'Runner.xcodeproj')
TARGET_NAME = 'RunnerUITests'
BUNDLE_ID = 'io.bitrise.sample.counterFlutter.RunnerUITests'

unless File.exist?(PROJECT_PATH)
  warn "#{PROJECT_PATH} not found. Run `flutter create . --platforms=android,ios` first."
  exit 1
end

project = Xcodeproj::Project.open(PROJECT_PATH)

if project.targets.any? { |t| t.name == TARGET_NAME }
  puts "#{TARGET_NAME} target already exists, nothing to do."
  exit 0
end

runner_target = project.targets.find { |t| t.name == 'Runner' }
abort "Runner target not found in #{PROJECT_PATH}" unless runner_target

# Flutter sets IPHONEOS_DEPLOYMENT_TARGET via an included xcconfig file
# (Flutter/Release.xcconfig), not inline in the pbxproj build settings the
# xcodeproj gem reads directly -- that read comes back nil, and an unset
# deployment target makes Xcode default a new target to the newest
# installed SDK version, which then refuses to run on any older simulator
# runtime ("iPhone 17 Pro cannot run RunnerUITests ... lower than
# RunnerUITests's minimum deployment target of 27.2", confirmed locally).
# Resolve the real, xcconfig-inherited value via `xcodebuild -showBuildSettings`.
runner_settings = runner_target.build_configurations.first.build_settings
resolved = `xcodebuild -showBuildSettings -workspace #{File.join(ROOT, 'ios', 'Runner.xcworkspace')} -scheme Runner -sdk iphonesimulator 2>/dev/null`
deployment_target = resolved[/IPHONEOS_DEPLOYMENT_TARGET = (\S+)/, 1] || '13.0'

ui_test_target = project.new_target(:ui_test_bundle, TARGET_NAME, :ios, nil, nil, :objc)
ui_test_target.add_dependency(runner_target)

# This is Patrol's own required native glue (verbatim from its example app,
# github.com/leancodepl/patrol packages/patrol/example/ios/RunnerUITests) --
# the macro expands into the actual XCTestCase that starts Patrol's
# AutomatorServer and bridges to the Dart-defined tests. `patrol` here is
# the Swift package patrol_cli itself injects into the build at build time
# (seen in its own build log as "Xcode is fetching Swift Package Manager
# dependencies... patrol"), not something this project needs to declare.
src_dir = File.join(ROOT, 'ios', TARGET_NAME)
Dir.mkdir(src_dir) unless Dir.exist?(src_dir)
src_file = File.join(src_dir, "#{TARGET_NAME}.m")
File.write(src_file, <<~OBJC) unless File.exist?(src_file)
  @import XCTest;
  @import patrol;
  @import ObjectiveC.runtime;

  PATROL_INTEGRATION_TEST_IOS_RUNNER(RunnerUITests)
OBJC

group = project.main_group.find_subpath(TARGET_NAME, true)
group.set_source_tree('<group>')
file_ref = group.new_reference(src_file)
ui_test_target.add_file_references([file_ref])

# `@import patrol;` above resolves through FlutterGeneratedPluginSwiftPackage
# -- the local SPM package `flutter pub get` already generated (it
# aggregates every plugin's native code, including the `patrol` plugin's).
# Flutter's own build tooling keeps Runner's link to it in sync automatically,
# but has no awareness of this extra RunnerUITests target, so it never
# links there -- without this, `@import patrol` fails to compile with
# "Module 'patrol' not found" (confirmed live). Patrol's own example app
# wires this exact same way: two independent product-dependency objects
# with the same productName, one per target (verified against
# github.com/leancodepl/patrol packages/patrol/example/ios/Runner.xcodeproj).
plugin_package_name = runner_target.package_product_dependencies
                                    .map(&:product_name)
                                    .find { |n| n == 'FlutterGeneratedPluginSwiftPackage' }
if plugin_package_name
  product_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product_dep.product_name = plugin_package_name
  ui_test_target.package_product_dependencies << product_dep

  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = product_dep
  ui_test_target.frameworks_build_phase.files << build_file
else
  warn "Runner has no FlutterGeneratedPluginSwiftPackage dependency yet (run " \
       "`flutter pub get` first) -- RunnerUITests won't be able to `@import patrol`."
end

ui_test_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  config.build_settings['TEST_TARGET_NAME'] = 'Runner'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = deployment_target
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['CLANG_ENABLE_MODULES'] = 'YES' # required for @import in Objective-C
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
end

# This is the attribute Xcode itself writes when you add a UI Testing Bundle
# target via File > New > Target and pick "Runner" under "Target to be
# Tested" -- it's what makes xcodebuild treat RunnerUITests as a real UI
# test host of Runner (embeds it, populates TestBundlePath/TestHostPath in
# the .xctestrun), not just the TEST_TARGET_NAME build setting alone.
project.root_object.attributes['TargetAttributes'] ||= {}
project.root_object.attributes['TargetAttributes'][ui_test_target.uuid] = {
  'TestTargetID' => runner_target.uuid,
}

project.save

scheme_path = File.join(ROOT, 'ios', 'Runner.xcodeproj', 'xcshareddata', 'xcschemes', 'Runner.xcscheme')
scheme = Xcodeproj::XCScheme.new(scheme_path)
test_action = scheme.test_action
already_present = test_action.testables.any? do |t|
  t.buildable_references.first && t.buildable_references.first.target_name == TARGET_NAME
end
unless already_present
  testable = Xcodeproj::XCScheme::TestAction::TestableReference.new(ui_test_target)
  test_action.add_testable(testable)
  scheme.save!
end

puts "Added #{TARGET_NAME} target to #{PROJECT_PATH} and wired it into the Runner scheme's Test action."
