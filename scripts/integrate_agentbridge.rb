#!/usr/bin/env ruby
# Wires the local Packages/AgentBridge SPM package into AllNotch.xcodeproj.
# Idempotent: re-running will not create duplicate references.
require "xcodeproj"

PROJECT = File.expand_path("../AllNotch.xcodeproj", __dir__)
TARGET_NAME = "DynamicIsland"

project = Xcodeproj::Project.open(PROJECT)
target = project.targets.find { |t| t.name == TARGET_NAME }
raise "target #{TARGET_NAME} not found" unless target

# 1. Local package reference -------------------------------------------------
pkg_ref = project.root_object.package_references.find do |r|
  r.is_a?(Xcodeproj::Project::Object::XCLocalSwiftPackageReference) &&
    r.relative_path == "Packages/AgentBridge"
end
unless pkg_ref
  pkg_ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  pkg_ref.relative_path = "Packages/AgentBridge"
  project.root_object.package_references << pkg_ref
  puts "+ added local package reference Packages/AgentBridge"
end

def product_dep(project, target, pkg_ref, name)
  dep = target.package_product_dependencies.find { |d| d.product_name == name }
  return dep if dep

  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.package = pkg_ref
  dep.product_name = name
  target.package_product_dependencies << dep
  puts "+ added product dependency #{name}"
  dep
end

# 2. Link the OpenIslandCore library -----------------------------------------
core_dep = product_dep(project, target, pkg_ref, "OpenIslandCore")
unless target.frameworks_build_phase.files.any? { |f| f.product_ref == core_dep }
  bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  bf.product_ref = core_dep
  target.frameworks_build_phase.files << bf
  puts "+ linked OpenIslandCore in Frameworks phase"
end

# 3. Embed the AgentHooks helper as a SELF-CONTAINED binary ------------------
#
# Xcode always builds package products as dynamic frameworks (@rpath), so an
# Xcode-built AgentHooks crashes once copied out of the bundle into
# ~/Library/Application Support/AllNotch/bin (dyld can't find OpenIslandCore.framework).
# SwiftPM, by contrast, statically links the OpenIslandCore *target* into the
# executable. So we build the CLI with `swift build` and copy that relocatable
# binary into Contents/Helpers via a script phase.

# Remove the old product-embed copy phase + product dependency if present.
old_phase = target.build_phases.find do |p|
  p.respond_to?(:name) && p.name == "Embed Agent Hooks"
end
if old_phase
  old_phase.files.dup.each { |f| f.remove_from_project }
  target.build_phases.delete(old_phase)
  old_phase.remove_from_project
  puts "- removed legacy 'Embed Agent Hooks' copy phase"
end
if (dep = target.package_product_dependencies.find { |d| d.product_name == "AgentHooks" })
  target.package_product_dependencies.delete(dep)
  dep.remove_from_project
  puts "- removed AgentHooks product dependency (built via SwiftPM instead)"
end

SCRIPT_NAME = "Build & Embed Agent Helpers"
unless target.shell_script_build_phases.any? { |p| p.name == SCRIPT_NAME }
  phase = project.new(Xcodeproj::Project::Object::PBXShellScriptBuildPhase)
  phase.name = SCRIPT_NAME
  phase.shell_path = "/bin/sh"
  phase.always_out_of_date = "1"
  phase.shell_script = <<~SH
    set -e
    PKG_DIR="$SRCROOT/Packages/AgentBridge"
    HELPERS="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Helpers"
    mkdir -p "$HELPERS"

    ARCH_FLAGS=""
    for a in $ARCHS; do ARCH_FLAGS="$ARCH_FLAGS --arch $a"; done

    # Self-contained CLI (SwiftPM statically links OpenIslandCore into it).
    swift build --package-path "$PKG_DIR" -c release $ARCH_FLAGS --product AgentHooks
    BIN_DIR="$(swift build --package-path "$PKG_DIR" -c release $ARCH_FLAGS --show-bin-path)"
    cp -f "$BIN_DIR/AgentHooks" "$HELPERS/AgentHooks"
    chmod 0755 "$HELPERS/AgentHooks"

    if [ "$CODE_SIGNING_ALLOWED" = "YES" ] && [ -n "$EXPANDED_CODE_SIGN_IDENTITY" ]; then
      codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none --options runtime "$HELPERS/AgentHooks"
    fi
  SH
  target.build_phases << phase
  puts "+ added '#{SCRIPT_NAME}' script phase"
end

project.save
puts "saved #{PROJECT}"

# NOTE: Xcodeproj strips the synchronized-group `attributesByRelativePath`
# block it doesn't understand. Re-add the CodeSignOnCopy for the existing
# Helpers/NowPlayingTestClient helper so we don't break its signing.
pbx = File.join(PROJECT, "project.pbxproj")
text = File.read(pbx)
unless text.include?("attributesByRelativePath")
  text.sub!(
    /(isa = PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet;\n)(\t+)(buildPhase =)/,
    "\\1\\2attributesByRelativePath = {\n\\2\tHelpers/NowPlayingTestClient = (CodeSignOnCopy, );\n\\2};\n\\2\\3"
  )
  File.write(pbx, text)
  puts "+ restored attributesByRelativePath for NowPlayingTestClient"
end
