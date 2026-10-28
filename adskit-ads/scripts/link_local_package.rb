#!/usr/bin/env ruby
# Links a local Swift package (default: AdsKit) to an app target of an .xcodeproj, the same way
# Xcode's "Add Local…" does: XCLocalSwiftPackageReference on the project, product dependency on the
# target, and a build file in the target's Frameworks phase. Idempotent.
#
# usage: link_local_package.rb <App.xcodeproj> <package dir> [--target NAME] [--product AdsKit]

require 'pathname'

begin
  require 'xcodeproj'
rescue LoadError
  abort 'error: the xcodeproj gem is missing — install it with `gem install xcodeproj`'
end

args = ARGV.dup
opt = ->(flag) { (i = args.index(flag)) ? args.slice!(i, 2)[1] : nil }
target_name = opt.call('--target')
product = opt.call('--product') || 'AdsKit'
project_path, package_dir = args
abort 'usage: link_local_package.rb <App.xcodeproj> <package dir> [--target NAME] [--product NAME]' unless project_path && package_dir

project_path = File.expand_path(project_path)
package_dir = File.expand_path(package_dir)
abort "error: #{package_dir}/Package.swift not found" unless File.exist?(File.join(package_dir, 'Package.swift'))

project = Xcodeproj::Project.open(project_path)
apps = project.native_targets.select { |t| t.product_type == 'com.apple.product-type.application' }

target =
  if target_name
    project.native_targets.find { |t| t.name == target_name } or
      abort "error: no target named #{target_name}; targets: #{project.native_targets.map(&:name).join(', ')}"
  elsif apps.size == 1
    apps.first
  else
    abort "error: pass --target; app targets: #{apps.map(&:name).join(', ')}"
  end

relative = Pathname(package_dir).relative_path_from(Pathname(File.dirname(project_path))).to_s
root = project.root_object

ref = root.package_references.find do |r|
  r.is_a?(Xcodeproj::Project::Object::XCLocalSwiftPackageReference) &&
    File.expand_path(r.relative_path.to_s, File.dirname(project_path)) == package_dir
end
unless ref
  ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  ref.relative_path = relative
  root.package_references << ref
  puts "added package reference #{relative}"
end

dep = target.package_product_dependencies.find { |d| d.product_name == product }
unless dep
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.product_name = product
  target.package_product_dependencies << dep
  puts "added #{product} to target #{target.name}"
end

unless target.frameworks_build_phase.files.any? { |f| f.product_ref == dep }
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dep
  target.frameworks_build_phase.files << build_file
  puts "linked #{product} in #{target.name} Frameworks phase"
end

project.save
puts "done: #{File.basename(project_path)} → #{target.name} uses #{product} (#{relative})"
