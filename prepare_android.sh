#!/usr/bin/env bash
# يولّد مجلد android ويضبط الصلاحيات و minSdk. يُستدعى محلياً أو من GitHub Actions.
set -euo pipefail

flutter create --platforms=android --project-name attendance_qr --org com.attendance.qr .
rm -rf test

# mobile_scanner يحتاج minSdk 21 على الأقل؛ نستخدم 23
for f in android/app/build.gradle android/app/build.gradle.kts; do
  if [ -f "$f" ]; then
    sed -i 's/flutter\.minSdkVersion/23/' "$f"
  fi
done

M=android/app/src/main/AndroidManifest.xml
if ! grep -q 'android.permission.CAMERA' "$M"; then
  sed -i 's#<application#<uses-permission android:name="android.permission.CAMERA"/>\n    <application#' "$M"
fi
sed -i 's#android:label="[^"]*"#android:label="حضور الطلاب"#' "$M"
echo "Android project prepared."
