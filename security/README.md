# Signing keys

The build signs with `onigiri_platform` (system apps) and `onigiri_ota` (update packages), each a
`.pk8` and `.x509.pem` here. They are not in git.

`scripts/prepare_signing_keys.sh` creates a new pair when one is missing. That is only right for
a first build of your own: a phone running Onigiri keeps its apps' data and installs updates only
from builds signed with the keys it was installed with. Copy the existing keys here before
building for such a phone. [docs/releasing.md](../docs/releasing.md) covers backing them up and
the CI secret.
