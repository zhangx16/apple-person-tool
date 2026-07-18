#!/usr/bin/env bash
# Usage: GH_TOKEN=ghp_xxx ./scripts/set-github-secrets.sh /path/to/secrets.env
set -euo pipefail
ENV_FILE=${1:-}
if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "Set GH_TOKEN to a classic PAT with repo scope (or fine-grained: Actions secrets write)"
  exit 1
fi
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Usage: GH_TOKEN=... $0 secrets.env"
  exit 1
fi
REPO=zhangx16/apple-person-tool
export GH_TOKEN
# shellcheck disable=SC1090
set -a
# shellcheck disable=SC1090
source <(grep -E '^(BUILD_|P12_|KEYCHAIN_)' "$ENV_FILE")
set +a
python3 - "$REPO" <<'PY'
import os,sys,json,base64,urllib.request
repo=sys.argv[1]
token=os.environ['GH_TOKEN']
names=[
  'BUILD_CERTIFICATE_BASE64','P12_PASSWORD',
  'BUILD_PROVISION_PROFILE_BASE64','KEYCHAIN_PASSWORD'
]
req=urllib.request.Request(
  f'https://api.github.com/repos/{repo}/actions/secrets/public-key',
  headers={'Authorization':f'Bearer {token}','Accept':'application/vnd.github+json','User-Agent':'set-secrets'})
pk=json.load(urllib.request.urlopen(req))
key_id,key_b64=pk['key_id'],pk['key']
try:
  from nacl import public
except ImportError:
  import subprocess
  subprocess.check_call([sys.executable,'-m','pip','install','pynacl','-q'])
  from nacl import public
pub=public.PublicKey(base64.b64decode(key_b64))
box=public.SealedBox(pub)
for name in names:
  value=os.environ[name]
  encrypted=base64.b64encode(box.encrypt(value.encode())).decode()
  body=json.dumps({'encrypted_value':encrypted,'key_id':key_id}).encode()
  req2=urllib.request.Request(
    f'https://api.github.com/repos/{repo}/actions/secrets/{name}',
    data=body, method='PUT',
    headers={'Authorization':f'Bearer {token}','Accept':'application/vnd.github+json','User-Agent':'set-secrets','Content-Type':'application/json'})
  urllib.request.urlopen(req2)
  print('set', name)
print('OK — open Actions and run Build Ad Hoc IPA')
PY
