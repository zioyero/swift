fastlane documentation
================
# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```
xcode-select --install
```

Install _fastlane_ using
```
[sudo] gem install fastlane -NV
```
or alternatively using `brew cask install fastlane`

# Available Actions
### test
```
fastlane test
```
Executes SDK Unit Tests
### code_coverage
```
fastlane code_coverage
```
Generates Code Coverage Files
### codacy_code_coverage
```
fastlane codacy_code_coverage
```

### release_verification
```
fastlane release_verification
```
Executes Linting for Framework releasing
### lint_cocoapods
```
fastlane lint_cocoapods
```
Lints a release using Cocoapods
### lint_swift_package_manager
```
fastlane lint_swift_package_manager
```
Lints a release using Swift Package Manager
### code_coverage_local
```
fastlane code_coverage_local
```
Generates Code Coverage Files
### build_example
```
fastlane build_example
```
Builds the SDK Example app

----

This README.md is auto-generated and will be re-generated every time [fastlane](https://fastlane.tools) is run.
More information about fastlane can be found on [fastlane.tools](https://fastlane.tools).
The documentation of fastlane can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
