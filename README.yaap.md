# YAAP for Motorola Fogos

Use the YAAP `seventeen` source tree. Copy `manifests/yaap-fogos.xml` into your checkout's `.repo/local_manifests` directory before syncing. This manifest selects the Pencil Association `YAAP` branches, the tested 6.1 kernel and vendor snapshots, and the source revisions needed by the patches.

From the source root, run the build as follows.

```bash
repo sync
source build/envsetup.sh
lunch yaap_fogos-cp2a-userdebug
m bacon
```

Set `TARGET_BUILD_GAPPS=true` before sourcing the environment to include Google apps. Setup applies the checked-in patches through `vendorsetup.sh`. It checks all selected projects before applying patches, and repeated setup recognizes already-applied patches. If setup reports a conflict, check the named project's revision and local edits before retrying.

For BuildBuddy remote builds, start your configured `rbe_auto` helper before lunch. Setup selects the two BuildBuddy source patches when the helper has installed its client and enabled RBE.
