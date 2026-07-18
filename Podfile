# CocoaPods — FLV-capable player (same role as SimpleLive's media_kit / mpv).
platform :ios, '17.0'
use_frameworks!
inhibit_all_warnings!

target 'PersonalToolbox' do
  # LibVLC-based player; plays HTTP-FLV / HLS that AVPlayer cannot.
  pod 'MobileVLCKit'
end

# Share Extension must not link VLC (size + no need).
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      # Silence bitcode leftovers on older pod binaries if any.
      config.build_settings['ENABLE_BITCODE'] = 'NO'
      config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
    end
  end
end
