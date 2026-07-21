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
      config.build_settings['ENABLE_BITCODE'] = 'NO'
      config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
      # Pods must not receive the app's manual provisioning profile.
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
      config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
      config.build_settings['EXPANDED_CODE_SIGN_IDENTITY'] = ''
      config.build_settings['CODE_SIGN_IDENTITY'] = ''
      config.build_settings['PROVISIONING_PROFILE_SPECIFIER'] = ''
      config.build_settings['PROVISIONING_PROFILE'] = ''
    end
  end
end
