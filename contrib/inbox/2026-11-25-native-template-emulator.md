# Skill draft: run a Mendix native app on an Android emulator, headless (10.24 and 11.x)

**From:** Field Service Management template upgrade lab (Maurits Visser)
**Date:** 2026-11-25
**Kind:** skill-draft
**Field evidence:** Field Service Management template, upgraded 10.24.28 to 11.12.7 and walked natively on an Android 35 arm64 emulator on 2026-11-11 (login, planned list, open appointment on both versions; build steps recorded per step).
**Proposed target:** `skills/native-app-on-emulator.md` (new), listed in README's "When to use which skill" table.

---

Gap: the toolkit has no route for proving a native profile on a device. Make It Native cannot open a Mendix 11 app
(Make It Native 10 shows a "version issue" screen, Make It Native 11 is Play Store only), so a native journey on 11.x
needs a debug APK built from `mendix/native-template`. Without Studio Pro or the Native Mobile Builder that build has
four traps that each cost an hour the first time: mxbuild's native bundling runs out of memory in a small VM, the
React Native CLI in `deployment/native` fails on RN 0.84, the app's own native dependencies are not in the template,
and the RN 0.84 Gradle plugin breaks on Gradle 9. The route below works around all four.

The same route is proposed for the Mendix upgrade toolkit as `upgrade-toolkit/playbooks/native-on-emulator.md`.

Use it to test a native profile before and after an upgrade, or to record a native walk, without Studio Pro and
without the Native Mobile Builder. Field-proven on FSM (rung 2, 10.24.28 to 11.12.7, 2026-11-11): Mac arm64,
login, planned list and an opened appointment on both versions.

## Which route

| App on | Route | Time |
|---|---|---|
| 10.x | Make It Native 10 APK (github `mendix/make-it-native`, Releases; FSM used 10.24.10) + Metro | about 15 min once the data is right |
| 11.x | Build the app yourself from `mendix/native-template` (debug APK, bundle embedded) | about 40 min first build, 2 min after |

- Make It Native 10 against an 11 runtime shows *"We've encountered a version issue. It seems you're trying to
  connect to a Mendix application that is not supported by this version of the app."* Do not spend time on it.
- Make It Native 11 is Play Store only, and the emulator image has no Play Store. So on 11.x, build the app.
  This is what a developer does for a native release anyway.
- The Native Mobile Builder is not needed. Its job (pick the template, add the app's native dependencies, bundle,
  set the runtime URL) is done by hand below. Docs followed:
  `docs.mendix.com/refguide/mobile/distributing-mobile-apps/building-native-apps/native-build-locally-manually/`.

## Versions that worked (FSM, 11.12.7)

| Item | Version |
|---|---|
| native-template | v19.1.8 (RN 0.84.1, React 19.2.3, mendix-native 0.5.3) |
| Gradle / Kotlin | 9.0.0 (wrapper) / 2.1.20 |
| Android | compileSdk 36, build-tools 36.0.0, NDK 27.3.13750724, cmake 3.22.1, minSdk 29 |
| JDK | 21 Temurin |
| Node / npm | Node 26.13 / npm 11.20 (the template's `.nvmrc` says 24; 26 worked) |
| Metro | 0.83.7, from the mxbuild node_modules |
| Emulator | 37.2.13.0, system image `android-35;google_apis;arm64-v8a` |
| SDK | `brew install --cask android-commandlinetools`, `ANDROID_HOME=/opt/homebrew/share/android-commandlinetools` |

## Emulator setup

```sh
sdkmanager "emulator" "platform-tools" "system-images;android-35;google_apis;arm64-v8a"
```

Create an AVD on that image (FSM: `fsm35`; the emulator raised RAM to 2560 MB). The exact `avdmanager` and
`emulator` command lines were not recorded on FSM: record them on the next run.

`10.0.2.2` is the host as the emulator sees it.

## Route 10.x: Make It Native

1. Start the runtime with `com.mendix.nativeui.NativePackagerPort` set to your Metro port.
2. Unzip the native sources from the .mda and start Metro there with the RN CLI from the mxbuild node_modules:
   ```sh
   unzip -oq <app>.mda 'native/*' -d <deployment>
   cd <deployment>/native
   node <mxbuild>/modeler/tools/node/node_modules/react-native/cli.js start --port <metro port>
   ```
3. Make It Native hardcodes the packager at `10.0.2.2:8083`. If Metro runs elsewhere: dev menu
   (`adb shell input keyevent 82`), Change Bundle Location, `10.0.2.2:<metro port>`, Reload.
4. URL field `http://10.0.2.2:<app port>`, Launch app. The URL survives force-stop, not `pm clear`.

## Route 11.x: own app from native-template

### 1. Pick the template version

Read `mendix_version.json` in the template repo and take the newest tag in the range. For 11.12:

```json
">=11.11.0": { "max": "19.*.*", "min": "19.1.0" }
```

### 2. Clone (under 1 min, 244 MB)

```sh
git clone --depth 1 --branch v19.1.8 https://github.com/mendix/native-template <template>
```

### 3. Bundle on the host with Metro, not with mxbuild (11 s)

The documented route, `mxbuild --target=deploy --native-packager --loose-version-check <mpr>`, was killed with
exit 137 at "Bundling native app for iOS" in a 5.8 GB colima VM, leaving `deployment/native/bundle/iOS` empty.
Instead, unzip `native/*` from the .mda as in route 10.x and bundle with the community CLI from the mxbuild
node_modules. `react-native/cli.js` fails on RN 0.84 ("react-native depends on @react-native-community/cli")
because `deployment/native/package.json` is just `{}`.

```sh
cd <deployment>/native
node <mxbuild>/modeler/tools/node/node_modules/@react-native-community/cli/build/bin.js bundle \
  --platform android --dev false --minify true --entry-file index.js --config metro.config.js \
  --bundle-output out/android-bundle/assets/index.android.bundle --assets-dest out/android-bundle/res
cp -R out/android-bundle/assets/. <template>/android/app/src/main/assets/
cp -R out/android-bundle/res/. <template>/android/app/src/main/res/
```

To read a JS stack trace, rebuild with `--minify false`.

### 4. Point the app at the runtime

Write `http://10.0.2.2:<app port>` to `android/app/src/main/res/raw/runtime_url` (default `10.0.2.2:8080`).
The bundle is embedded, so the app needs no Metro and the 8083 workaround does not apply.

### 5. npm install in the template (3 min, 430 MB)

```sh
cd <template> && npm install
```

Warnings only; postinstall runs `patches/apply-patches.js` and `jetify`. `npm run configure`
(`native-mobile-toolkit`, needs a `config.json`) is not needed for a debug APK.

### 6. Add the app's own native dependencies (easy to miss)

The template does not carry the app's native dependencies; the Native Builder normally adds them. Both lists:

- `deployment/model/nativeDependencies.json` (FSM: netinfo 11.5.2, async-storage 2.2.0, permissions 5.5.1, image-picker 7.2.3)
- `deployment/native/widgets/dependencies.json` (FSM: react-native-dialog 9.3.0, react-native-view-shot 5.1.0)

Install each one the template does not have yet (they autolink). FSM:

```sh
npm install --save-exact @react-native-community/netinfo@11.5.2 react-native-view-shot@5.1.0 react-native-dialog@9.3.0
```

Missed, the app shows *"Error: An error occurred, please contact your system administrator."* after login, and
`adb logcat | grep ReactNativeJS` shows `TypeError: Cannot read property '$$style' of undefined at findPage`.
The real cause is earlier in the same log: `@react-native-community/netinfo: NativeModule.RNCNetInfo is null`.

### 7. SDK packages (48 s, about 2.6 GB)

```sh
sdkmanager "platforms;android-36" "build-tools;36.0.0" "ndk;27.3.13750724" "cmake;3.22.1"
```

### 8. Gradle build

```sh
export JAVA_HOME=$(/usr/libexec/java_home -v 21)
cd <template>/android && ./gradlew assembleAppstoreDebug
```

RN 0.84.1 on Gradle 9 fails in 35 s with `Class org.gradle.jvm.toolchain.JvmVendorSpec does not have member field
... IBM_SEMERU`: `node_modules/@react-native/gradle-plugin/settings.gradle.kts` pins `foojay-resolver-convention`
0.5.0. Bump it (in the template root), then run the same build again. Redo it after every fresh `npm install`.

```sh
sed -i '' 's/foojay-resolver-convention").version("0.5.0")/foojay-resolver-convention").version("1.0.0")/' node_modules/@react-native/gradle-plugin/settings.gradle.kts
```

First build 10 min 54 s (all ABIs), incremental 1 min 40 s. Output
`android/app/build/outputs/apk/appstore/debug/app-appstore-debug.apk`, 270-290 MB, package `com.mendix.nativetemplate`.

### 9. Install and start

```sh
adb install -r -g android/app/build/outputs/apk/appstore/debug/app-appstore-debug.apk
adb shell pm clear com.mendix.nativetemplate
adb shell am start -n com.mendix.nativetemplate/.MainActivity
```

Login screen after 11 s; the first launch took about 45 s on a loaded machine.

After a model change, repeat steps 3, 8 and 9 (`./gradlew assembleAppstoreDebug -q`).

## Driving the emulator

- Emulator plus runtime plus Metro loads the Mac. Expect "isn't responding" dialogs: check
  `adb shell dumpsys window | grep mCurrentFocus` for "Not Responding" before every tap and tap **Wait**.
- Type a whole field with one `adb shell input text`; character by character drops characters under load.
  Clear a field first with keyevent 123 and 25x keyevent 67.
- `adb shell screenrecord` stops at 180 s: record in parts and pull each part.
- `adb logcat -d | grep ReactNativeJS` shows nanoflows and the offline SQL.

## Test data, not the build

On FSM every empty "No appointments found" list was data, never the build:
- the demo user must be linked to every account-like entity the native home page reads (FSM: NativeTechnician
  and Technician);
- date filters run on the device: shift every date column the offline list filters on (FSM: DisplayTravelStart,
  not only DisplayStart). The filter is in the offline SQL in logcat.

Do this in scratch database clones, never the run database.

## What the native walk found on FSM 11.12

- 11.12 enforces create access on helper objects the native client creates (`SecurityRuntimeException ...
  NativeMobile.TimeSlotHelper`, then OfflineHelper on sync). Model access was the same on 10.24, so this is a runtime
  behaviour change. Fix: grant create on TimeSlotHelper, OfflineHelper and TimeRegistrationHelper to
  NativeMobile.EditMy. Hypothesis until the same path is run on 10.24.
- The planned list header draws a stray date text over the heading on 11.12, not on 10.24. Open review item.

## Disk and time

Template 244 MB, node_modules 430 MB, SDK about 2.6 GB, build folder 8.7 GB, APK 270-290 MB. Ask before the
downloads.
