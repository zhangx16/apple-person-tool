require 'xcodeproj'
require 'json'

metadata = JSON.parse(File.read(ENV.fetch('SIGNING_METADATA')))
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
runner = project.targets.find { |target| target.name == 'Runner' }
share = project.targets.find { |target| target.name == 'ShareExtension' }
# The existing distribution profile signs the application only. As in the
# previous native build, omit the optional share extension from the archive.
runner.dependencies.select { |dependency| dependency.target == share }.each(&:remove_from_project)
runner.copy_files_build_phases.select { |phase| phase.name.to_s.include?('Extensions') }.each(&:remove_from_project)
# Keep the unbuilt target so Xcode's synchronized folder exception records
# remain valid; only the host dependency, embed phase and Podfile entry go away.
podfile = File.read('ios/Podfile')
podfile.sub!(/  # share_handler addition start.*?  # share_handler addition end\n/m, '')
File.write('ios/Podfile', podfile)
runner.build_configurations.each do |config|
  settings = config.build_settings
  settings['CODE_SIGN_STYLE'] = 'Manual'
  settings['DEVELOPMENT_TEAM'] = metadata.fetch('team')
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = metadata.fetch('bundle')
  settings['CODE_SIGN_IDENTITY'] = 'iPhone Distribution'
  settings['CODE_SIGN_IDENTITY[sdk=iphoneos*]'] = 'iPhone Distribution'
  settings['PROVISIONING_PROFILE_SPECIFIER'] = metadata.fetch('uuid')
  settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Distribution.entitlements'
end
project.save
