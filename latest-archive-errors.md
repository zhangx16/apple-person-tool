# Archive failed on `1389422`

Run: https://github.com/zhangx16/apple-person-tool/actions/runs/29660135785
Commit: `138942208b5d5520107c2abc42a2de0ac0cf5a70`

## Grep errors
```
/Users/runner/work/apple-person-tool/apple-person-tool/Pods/Pods.xcodeproj: error: Pods-PersonalToolbox does not support provisioning profiles. Pods-PersonalToolbox does not support provisioning profiles, but provisioning profile 00008150-001A088E148B401C6F01CD has been manually specified. Set the provisioning profile value to "Automatic" in the build settings editor. (in target 'Pods-PersonalToolbox' from project 'Pods')
```

## Tail
```
Command line invocation:
    /Applications/Xcode_15.4.app/Contents/Developer/usr/bin/xcodebuild -workspace PersonalToolbox.xcworkspace -scheme PersonalToolbox -configuration Release -destination generic/platform=iOS -archivePath /Users/runner/work/_temp/PersonalToolbox.xcarchive clean archive CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=CTSQLK944L "CODE_SIGN_IDENTITY=iPhone Distribution" PRODUCT_BUNDLE_IDENTIFIER=app.parsnip6345.lake8262 PROVISIONING_PROFILE_SPECIFIER=00008150-001A088E148B401C6F01CD

User defaults from command line:
    IDEArchivePathOverride = /Users/runner/work/_temp/PersonalToolbox.xcarchive
    IDEPackageSupportUseBuiltinSCM = YES

Build settings from command line:
    CODE_SIGN_IDENTITY = iPhone Distribution
    CODE_SIGN_STYLE = Manual
    DEVELOPMENT_TEAM = CTSQLK944L
    PRODUCT_BUNDLE_IDENTIFIER = app.parsnip6345.lake8262
    PROVISIONING_PROFILE_SPECIFIER = 00008150-001A088E148B401C6F01CD

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

Build description signature: 20195a1c61c96faeff68ba4af31652d9
Build description path: /Users/runner/Library/Developer/Xcode/DerivedData/PersonalToolbox-dgocjqdlafevhdeibipzandqxwbb/Build/Intermediates.noindex/ArchiveIntermediates/PersonalToolbox/IntermediateBuildFilesPath/XCBuildData/20195a1c61c96faeff68ba4af31652d9.xcbuilddata
/Users/runner/work/apple-person-tool/apple-person-tool/Pods/Pods.xcodeproj: error: Pods-PersonalToolbox does not support provisioning profiles. Pods-PersonalToolbox does not support provisioning profiles, but provisioning profile 00008150-001A088E148B401C6F01CD has been manually specified. Set the provisioning profile value to "Automatic" in the build settings editor. (in target 'Pods-PersonalToolbox' from project 'Pods')
** ARCHIVE FAILED **

```
