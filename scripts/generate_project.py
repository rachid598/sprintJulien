#!/usr/bin/env python3
"""Generate the committed portable Xcode project using only Python's standard library.

Run after adding/removing Swift sources or resource directories. Xcode users need
only open the checked-in .xcodeproj; Python is not a build dependency.
"""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent.parent


def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def quote(value):
    return json.dumps(str(value), ensure_ascii=False)


def make_project():
    entries = []

    def add(key, body, comment=""):
        entries.append(f"\t\t{ident(key)} /* {comment or key} */ = {{ {body} }};")

    source_paths = sorted((ROOT / "SprintTimer").rglob("*.swift"))
    test_paths = sorted((ROOT / "SprintTimerTests").rglob("*.swift"))
    ui_test_paths = sorted((ROOT / "SprintTimerUITests").rglob("*.swift"))
    resource_paths = sorted((ROOT / "SprintTimer").rglob("*.xcassets"))
    resource_paths += sorted((ROOT / "SprintTimer").rglob("*.xcprivacy"))
    resource_paths += sorted((ROOT / "SprintTimer").rglob("*.strings"))
    resource_paths += sorted((ROOT / "SprintTimer").rglob("*.stringsdict"))

    for path in source_paths + test_paths + ui_test_paths + resource_paths:
        rel = path.relative_to(ROOT).as_posix()
        filetype = {
            ".swift": "sourcecode.swift", ".xcassets": "folder.assetcatalog",
            ".xcprivacy": "text.xml", ".strings": "text.plist.strings",
            ".stringsdict": "text.plist.xml",
        }[path.suffix]
        add("ref:" + rel, f"isa = PBXFileReference; lastKnownFileType = {quote(filetype)}; path = {quote(rel)}; sourceTree = SOURCE_ROOT;", path.name)
        add("build:" + rel, f"isa = PBXBuildFile; fileRef = {ident('ref:' + rel)};", path.name)

    add("app-product", 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SprintTimer.app; sourceTree = BUILT_PRODUCTS_DIR;', "SprintTimer.app")
    add("test-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = SprintTimerTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;', "SprintTimerTests.xctest")
    add("uitest-product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = SprintTimerUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;', "SprintTimerUITests.xctest")
    add("info", 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = SprintTimer/Resources/Info.plist; sourceTree = SOURCE_ROOT;', "Info.plist")

    def ids(paths, prefix):
        return ", ".join(ident(prefix + p.relative_to(ROOT).as_posix()) for p in paths)

    add("source-group", f"isa = PBXGroup; children = ({ids(source_paths + resource_paths, 'ref:')}, {ident('info')}); name = SprintTimer; sourceTree = \"<group>\";")
    add("test-group", f"isa = PBXGroup; children = ({ids(test_paths, 'ref:')}); name = SprintTimerTests; sourceTree = \"<group>\";")
    add("uitest-group", f"isa = PBXGroup; children = ({ids(ui_test_paths, 'ref:')}); name = SprintTimerUITests; sourceTree = \"<group>\";")
    add("products", f"isa = PBXGroup; children = ({ident('app-product')}, {ident('test-product')}, {ident('uitest-product')}); name = Products; sourceTree = \"<group>\";")
    add("main-group", f"isa = PBXGroup; children = ({ident('source-group')}, {ident('test-group')}, {ident('uitest-group')}, {ident('products')}); sourceTree = \"<group>\";")

    for target, paths in [("app", source_paths), ("tests", test_paths), ("uitests", ui_test_paths)]:
        add(target + "-sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({ids(paths, 'build:')}); runOnlyForDeploymentPostprocessing = 0;")
        resources = resource_paths if target == "app" else []
        add(target + "-resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({ids(resources, 'build:')}); runOnlyForDeploymentPostprocessing = 0;")
        framework_files = ""
        if target != "uitests":
            add(target + "-package", f"isa = XCSwiftPackageProductDependency; package = {ident('local-package')}; productName = SprintTimerCore;")
            add(target + "-package-build", f"isa = PBXBuildFile; productRef = {ident(target + '-package')};", "SprintTimerCore in Frameworks")
            framework_files = ident(target + '-package-build')
        add(target + "-frameworks", f"isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({framework_files}); runOnlyForDeploymentPostprocessing = 0;")

    add("local-package", 'isa = XCLocalSwiftPackageReference; relativePath = Packages/SprintTimerCore;', "SprintTimerCore")
    common = {
        "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "6.0", "SWIFT_STRICT_CONCURRENCY": "complete",
        "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
    }
    app = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "PRODUCT_NAME": "SprintTimer", "PRODUCT_BUNDLE_IDENTIFIER": "org.sprintjulien.SprintTimer",
        "INFOPLIST_FILE": "SprintTimer/Resources/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
        "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": "",
        "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
        "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0.0",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
    }
    tests = {
        "PRODUCT_NAME": "SprintTimerTests", "PRODUCT_BUNDLE_IDENTIFIER": "org.sprintjulien.SprintTimerTests",
        "GENERATE_INFOPLIST_FILE": "YES", "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": "",
        "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks",
        "SKIP_INSTALL": "YES",
        "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/SprintTimer.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SprintTimer",
        "BUNDLE_LOADER": "$(TEST_HOST)",
    }
    uitests = {
        "PRODUCT_NAME": "SprintTimerUITests", "PRODUCT_BUNDLE_IDENTIFIER": "org.sprintjulien.SprintTimerUITests",
        "GENERATE_INFOPLIST_FILE": "YES", "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": "",
        "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "TEST_TARGET_NAME": "SprintTimer", "SKIP_INSTALL": "YES",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks",
    }
    for scope, settings in [("project", common), ("app", app), ("tests", tests), ("uitests", uitests)]:
        config_ids = []
        for config in ["Debug", "Release"]:
            build = dict(settings)
            if scope == "project":
                build.update({
                    "DEBUG_INFORMATION_FORMAT": "dwarf" if config == "Debug" else "dwarf-with-dsym",
                    "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if config == "Debug" else "-O",
                    "SWIFT_COMPILATION_MODE": "singlefile" if config == "Debug" else "wholemodule",
                    "ENABLE_TESTABILITY": "YES" if config == "Debug" else "NO",
                    "GCC_PREPROCESSOR_DEFINITIONS": "DEBUG=1 $(inherited)" if config == "Debug" else "$(inherited)",
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)" if config == "Debug" else "$(inherited)",
                    "ONLY_ACTIVE_ARCH": "YES" if config == "Debug" else "NO",
                })
            body = " ".join(f"{k} = {quote(v)};" for k, v in sorted(build.items()))
            key = scope + "-config-" + config
            config_ids.append(ident(key))
            add(key, f"isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {config};", config)
        add(scope + "-configs", f"isa = XCConfigurationList; buildConfigurations = ({', '.join(config_ids)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")

    for target, name, product, product_type in [
        ("app", "SprintTimer", "app-product", "com.apple.product-type.application"),
        ("tests", "SprintTimerTests", "test-product", "com.apple.product-type.bundle.unit-test"),
        ("uitests", "SprintTimerUITests", "uitest-product", "com.apple.product-type.bundle.ui-testing"),
    ]:
        phases = ", ".join(ident(target + "-" + s) for s in ["sources", "frameworks", "resources"])
        dependencies = ""
        if target != "app":
            add(target + "-app-proxy", f"isa = PBXContainerItemProxy; containerPortal = {ident('project')}; proxyType = 1; remoteGlobalIDString = {ident('app-target')}; remoteInfo = SprintTimer;")
            add(target + "-app-dependency", f"isa = PBXTargetDependency; target = {ident('app-target')}; targetProxy = {ident(target + '-app-proxy')};")
            dependencies = ident(target + "-app-dependency")
        package_products = ident(target + '-package') if target != "uitests" else ""
        add(target + "-target", f"isa = PBXNativeTarget; buildConfigurationList = {ident(target + '-configs')}; buildPhases = ({phases}); buildRules = (); dependencies = ({dependencies}); name = {name}; packageProductDependencies = ({package_products}); productName = {name}; productReference = {ident(product)}; productType = {quote(product_type)};", name)

    add("project", f"isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {ident('app-target')} = {{ CreatedOnToolsVersion = 16.0; }}; {ident('tests-target')} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {ident('app-target')}; }}; {ident('uitests-target')} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {ident('app-target')}; }}; }}; }}; buildConfigurationList = {ident('project-configs')}; compatibilityVersion = \"Xcode 14.0\"; developmentRegion = fr; hasScannedForEncodings = 0; knownRegions = (fr, en, Base); mainGroup = {ident('main-group')}; packageReferences = ({ident('local-package')}); productRefGroup = {ident('products')}; projectDirPath = \"\"; projectRoot = \"\"; targets = ({ident('app-target')}, {ident('tests-target')}, {ident('uitests-target')});")

    project = ROOT / "SprintTimer.xcodeproj"
    project.mkdir(exist_ok=True)
    (project / "project.pbxproj").write_text("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n" + "\n".join(entries) + f"\n\t}};\n\trootObject = {ident('project')};\n}}\n")
    schemes = project / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)

    def ref(target, name, product):
        return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident(target + "-target")}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:SprintTimer.xcodeproj"/>'

    app_ref = ref("app", "SprintTimer", "SprintTimer.app")
    test_ref = ref("tests", "SprintTimerTests", "SprintTimerTests.xctest")
    uitest_ref = ref("uitests", "SprintTimerUITests", "SprintTimerUITests.xctest")
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
      <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{test_ref}</BuildActionEntry>
      <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{uitest_ref}</BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables><TestableReference skipped="NO" parallelizable="NO">{test_ref}</TestableReference><TestableReference skipped="NO" parallelizable="NO">{uitest_ref}</TestableReference></Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    (schemes / "SprintTimer.xcscheme").write_text(scheme)
    print(f"Generated SprintTimer.xcodeproj: {len(source_paths)} app Swift files, {len(test_paths)} unit-test files, {len(ui_test_paths)} UI-test files, {len(resource_paths)} resource bundles/files")


if __name__ == "__main__":
    make_project()
