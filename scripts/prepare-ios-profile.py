import json
import os
import pathlib
import plistlib
import shutil

temporary = pathlib.Path(os.environ['RUNNER_TEMP'])
with (temporary / 'profile.plist').open('rb') as source:
    profile = plistlib.load(source)
team = profile['TeamIdentifier'][0]
bundle = profile['Entitlements']['application-identifier'].removeprefix(team + '.')
metadata = {'team': team, 'bundle': bundle, 'uuid': profile['UUID']}
(temporary / 'signing.json').write_text(json.dumps(metadata))
for directory in ['Library/MobileDevice/Provisioning Profiles',
                  'Library/Developer/Xcode/UserData/Provisioning Profiles']:
    destination = pathlib.Path.home() / directory
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copy(temporary / 'profile.mobileprovision', destination / (profile['UUID'] + '.mobileprovision'))
options = {
    'method': 'ad-hoc', 'teamID': team, 'signingStyle': 'manual',
    'signingCertificate': 'iPhone Distribution',
    'provisioningProfiles': {bundle: profile['UUID']},
    'stripSwiftSymbols': True, 'compileBitcode': False,
}
with (temporary / 'ExportOptions.plist').open('wb') as output:
    plistlib.dump(options, output)
with pathlib.Path('ios/Runner/Distribution.entitlements').open('wb') as output:
    plistlib.dump({}, output)
print('Configured signing for', bundle, '; registered devices:', len(profile.get('ProvisionedDevices', [])))
