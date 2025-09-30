

# # require 'json'

# # package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

# # Pod::Spec.new do |s|
# #   s.name           = 'ExpoIperf'
# #   s.version        = package['version']
# #   s.summary        = package['description']
# #   s.description    = package['description']
# #   s.license        = package['license']
# #   s.author         = package['author']
# #   s.homepage       = package['homepage']
# #   s.platforms      = {
# #     :ios => '15.1',
# #     :tvos => '15.1'
# #   }
# #   s.swift_version  = '5.9'
# #   s.source         = { git: 'https://github.com/ChrisCosentino/expo-iperf' }
# #   s.static_framework = true

# #   s.dependency 'ExpoModulesCore'

# #   # Swift/Objective-C compatibility
# #   s.pod_target_xcconfig = {
# #     'DEFINES_MODULE' => 'YES',
# #   }

# #   s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
# # end
# require 'json'

# package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

# Pod::Spec.new do |s|
#   s.name           = 'ExpoIperf'
#   s.version        = package['version']
#   s.summary        = package['description']
#   s.description    = package['description']
#   s.license        = package['license']
#   s.author         = package['author']
#   s.homepage       = package['homepage']
#   s.platforms      = {
#     :ios => '15.1',
#     :tvos => '15.1'
#   }
#   s.swift_version  = '5.9'
#   s.source         = { git: 'https://github.com/ChrisCosentino/expo-iperf' }
#   s.static_framework = true

#   s.dependency 'ExpoModulesCore'

#   s.public_header_files = 'IperfRunner.h'

# #  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
#   s.source_files = [
#     "**/*.{h,m,mm,swift,hpp,cpp}",
#     "ios/iperf3/src/**/*.{c,h}"
#   ]

#   # Compile your Obj-C/Swift + iperf sources
#   # s.source_files = [
#   #   'ios/**/*.{swift,h,m,mm,c}',
#   #   'ios/iperf3/src/**/*.{c,h}'
#   # ]

#   # Do NOT build the iperf CLI (contains main())
#   s.exclude_files = [
#     'ios/iperf3/src/iperf3.c',
#     'ios/iperf3/src/main.c'
#   ]

#   # Let Swift see your Obj-C class, and find iperf headers
#   s.public_header_files = 'ios/IperfRunner.h'

#   s.pod_target_xcconfig = {
#     'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/iperf3/src"',
#     'CLANG_ENABLE_MODULES' => 'YES',
#     # Easiest way to make Swift see Obj-C inside a pod target:
#     'SWIFT_OBJC_BRIDGING_HEADER' => '$(PODS_TARGET_SRCROOT)/ExpoIperf-Bridging-Header.h'
#   }
# end

require 'json'

package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

Pod::Spec.new do |s|
  s.name             = 'ExpoIperf'
  s.version          = package['version']
  s.summary          = package['description']
  s.description      = package['description']
  s.license          = package['license']
  s.author           = package['author']
  s.homepage         = package['homepage']

  # iOS only (add tvOS later if you need it)
  s.platforms        = { :ios => '15.1' }
  s.swift_version    = '5.9'

  # IMPORTANT: use local path for a development pod (files in this ios/ folder)
  s.source           = { :path => '.' }

  # Expo runtime
  s.dependency 'ExpoModulesCore'

  # Build as a static framework (typical for Expo modules)
  s.static_framework = true

  # Compile Swift/Obj-C in this ios/ folder + iperf C sources
  # Note: podspec lives in ios/, so these globs are relative to ios/
  s.source_files = [
    '**/*.{swift,h,m,mm,c,cpp,hpp}',
    'iperf3/src/**/*.{c,h}'
  ]

  # Do NOT compile the iperf CLI (it has main())
  s.exclude_files = [
    'iperf3/src/iperf3.c',
    'iperf3/src/main.c'
  ]

  # Expose Obj-C API to Swift inside this pod (no bridging header needed)
  s.public_header_files = 'IperfRunner.h'

  # Make iperf headers resolvable; allow modular includes
  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/iperf3/src"',
    'CLANG_ENABLE_MODULES' => 'YES',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES'
  }
end
