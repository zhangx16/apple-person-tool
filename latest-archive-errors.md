# Archive failed on `32ba74b`

Run: https://github.com/zhangx16/apple-person-tool/actions/runs/29836970458
Commit: `32ba74b86ab0d93852aef875069fd5ede3ea9ca1`

## Grep errors
```
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox.xcodeproj: error: Provisioning profile "00008150-001A088E148B401C6F01CD" doesn't match the entitlements file's value for the com.apple.security.application-groups entitlement. Profile qualification is using entitlement definitions that may be out of date. Connect to network to update. (in target 'PersonalToolbox' from project 'PersonalToolbox')
```

## Tail
```
Command line invocation:
    /Applications/Xcode_15.4.app/Contents/Developer/usr/bin/xcodebuild -workspace PersonalToolbox.xcworkspace -scheme PersonalToolbox -configuration Release -destination generic/platform=iOS -archivePath /Users/runner/work/_temp/PersonalToolbox.xcarchive clean archive CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=CTSQLK944L "CODE_SIGN_IDENTITY=iPhone Distribution"

User defaults from command line:
    IDEArchivePathOverride = /Users/runner/work/_temp/PersonalToolbox.xcarchive
    IDEPackageSupportUseBuiltinSCM = YES

Build settings from command line:
    CODE_SIGN_IDENTITY = iPhone Distribution
    CODE_SIGN_STYLE = Manual
    DEVELOPMENT_TEAM = CTSQLK944L

note: Using codesigning identity override: iPhone Distribution

** CLEAN SUCCEEDED **

Prepare packages

note: Using codesigning identity override: iPhone Distribution
ComputeTargetDependencyGraph
note: Building targets in dependency order
note: Target dependency graph (3 targets)
    Target 'PersonalToolbox' in project 'PersonalToolbox'
        ➜ Implicit dependency on target 'Pods-PersonalToolbox' in project 'Pods' via file 'Pods_PersonalToolbox.framework' in build phase 'Link Binary'
    Target 'Pods-PersonalToolbox' in project 'Pods'
        ➜ Explicit dependency on target 'MobileVLCKit' in project 'Pods'
    Target 'MobileVLCKit' in project 'Pods' (no dependencies)

GatherProvisioningInputs

CreateBuildDescription

ExecuteExternalTool /Applications/Xcode_15.4.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -v -E -dM -arch arm64 -isysroot /Applications/Xcode_15.4.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS17.5.sdk -x c -c /dev/null

ExecuteExternalTool /Applications/Xcode_15.4.app/Contents/Developer/usr/bin/actool --print-asset-tag-combinations --output-format xml1 /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox/Resources/Assets.xcassets

ExecuteExternalTool /Applications/Xcode_15.4.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -v -E -dM -isysroot /Applications/Xcode_15.4.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS17.5.sdk -x c -c /dev/null

ExecuteExternalTool /Applications/Xcode_15.4.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -v -E -dM -arch arm64 -isysroot /Applications/Xcode_15.4.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS17.5.sdk -x objective-c -c /dev/null

ExecuteExternalTool /Applications/Xcode_15.4.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/libtool -V

ExecuteExternalTool /Applications/Xcode_15.4.app/Contents/Developer/usr/bin/actool --version --output-format xml1

ExecuteExternalTool /Applications/Xcode_15.4.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc -v

ExecuteExternalTool /Applications/Xcode_15.4.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/ld -version_details

Build description signature: 1b2fff4b8b5c3c2d43cb858b682e888b
Build description path: /Users/runner/Library/Developer/Xcode/DerivedData/PersonalToolbox-dgocjqdlafevhdeibipzandqxwbb/Build/Intermediates.noindex/ArchiveIntermediates/PersonalToolbox/IntermediateBuildFilesPath/XCBuildData/1b2fff4b8b5c3c2d43cb858b682e888b.xcbuilddata
/Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox.xcodeproj: error: Provisioning profile "00008150-001A088E148B401C6F01CD" doesn't match the entitlements file's value for the com.apple.security.application-groups entitlement. Profile qualification is using entitlement definitions that may be out of date. Connect to network to update. (in target 'PersonalToolbox' from project 'PersonalToolbox')
** ARCHIVE FAILED **

```
