echo "===== per-app rotation toggle ====="
(
  set -e
  cd packages/apps/Settings
  git checkout -- .    # drop leftovers from a previous run
  curl -fsSL -o /tmp/per_app_rotation_toggle.patch \
    https://raw.githubusercontent.com/FaqatZubair1/scripts/main/per_app_rotation_toggle.patch
  git apply --check /tmp/per_app_rotation_toggle.patch
  git apply /tmp/per_app_rotation_toggle.patch
  echo "per-app rotation patch applied"
) || { echo "!!! per-app rotation patch FAILED - stopping"; exit 1; }

  

echo "three finger screenshot fix"

curl -fsSL https://raw.githubusercontent.com/FaqatZubair1/scripts/main/fix_screenshot_display.sh | bash


sed -i '36s/vendor.camera.aux.packagelist=org.codeaurora/vendor.camera.aux.packagelist=org.lineageos.aperture,org.codeaurora/' vendor/motorola/camera/camera.mk
sed -n 36p vendor/motorola/camera/camera.mk

python3 - <<'EOF'
p='vendor/voltage/build/soong/Android.bp'
s=open(p).read()
old='"if [ -n \\"$(TARGET_KERNEL_PLATFORM_TARGET)\\" ]; then " +'
new=('"if [ -n \\"$(TARGET_PREBUILT_KERNEL_HEADERS)\\" ]; then " +\n'
     '         "    mkdir -p $(genDir) && gzip -d < $(TARGET_PREBUILT_KERNEL_HEADERS) | tar -x -C $(genDir); " +\n'
     '         "elif [ -n \\"$(TARGET_KERNEL_PLATFORM_TARGET)\\" ]; then " +')
assert s.count(old)==1, s.count(old)
open(p,'w').write(s.replace(old,new))
print("patched")
EOF

