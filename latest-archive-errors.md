# Archive failed on `7015d59`

Run: https://github.com/zhangx16/apple-person-tool/actions/runs/29840095026
Commit: `7015d594aef002fb2cded09ad4b0b50ad6c12e08`

## Grep errors
```
xcodebuild: error: Unable to read project 'PersonalToolbox.xcodeproj'.
```

## Tail
```
Command line invocation:
    /Applications/Xcode_15.4.app/Contents/Developer/usr/bin/xcodebuild -project PersonalToolbox.xcodeproj -scheme PersonalToolbox -configuration Release -destination generic/platform=iOS -archivePath /Users/runner/work/_temp/PersonalToolbox.xcarchive clean archive CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=CTSQLK944L "CODE_SIGN_IDENTITY=iPhone Distribution"

User defaults from command line:
    IDEArchivePathOverride = /Users/runner/work/_temp/PersonalToolbox.xcarchive
    IDEPackageSupportUseBuiltinSCM = YES

Build settings from command line:
    CODE_SIGN_IDENTITY = iPhone Distribution
    CODE_SIGN_STYLE = Manual
    DEVELOPMENT_TEAM = CTSQLK944L

2026-07-21 14:39:10.300 xcodebuild[2021:9504] Error Domain=NSCocoaErrorDomain Code=3840 "JSON text did not start with array or object and option to allow fragments not set. around line 1, column 0." UserInfo={NSDebugDescription=JSON text did not start with array or object and option to allow fragments not set. around line 1, column 0., NSJSONSerializationErrorIndex=0}
2026-07-21 14:39:10.302 xcodebuild[2021:9504] Writing error result bundle to /var/folders/g3/pffjr_y96bq06blnkf72x_hw0000gn/T/ResultBundle_2026-21-07_14-39-0010.xcresult
xcodebuild: error: Unable to read project 'PersonalToolbox.xcodeproj'.
	Reason: The project ‘PersonalToolbox’ is damaged and cannot be opened due to a parse error. Examine the project file for invalid edits or unresolved source control conflicts.

Path: /Users/runner/work/apple-person-tool/apple-person-tool/PersonalToolbox.xcodeproj


```
