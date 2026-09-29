# ci_scripts
<!-- trigger Xcode Cloud scheme rescan -->
`ci_post_clone.sh` stamps `CURRENT_PROJECT_VERSION` in
`Alignment Charts/Alignment Charts.xcodeproj/project.pbxproj` with Xcode Cloud's
`CI_BUILD_NUMBER` right after checkout, before Xcode reads the project. This
keeps every cloud archive's build number unique and traceable. It is needed as
a file edit (rather than a build phase) because the generated Info.plist means
the version comes from the build setting, not from a plist a build phase could
edit.

When `CI_BUILD_NUMBER` is unset (e.g. a local build on Zach's Mac) the script
does nothing and always exits 0, so it can never fail the build.

## REQUIRED before the first TestFlight distribution

This script alone does not make a build TestFlight-eligible: Xcode Cloud
manages the distributed build number itself and its counter starts at 1.
Build 1.0 (24) already shipped to TestFlight, so in App Store Connect go to
the app > Xcode Cloud > Settings > Build Number and set **Next Build Number
to 25** before enabling distribution — otherwise the upload is rejected
because its build number is lower than the shipped 24.
