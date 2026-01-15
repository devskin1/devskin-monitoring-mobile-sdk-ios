Pod::Spec.new do |s|
  s.name             = 'DevSkinMobileSDK'
  s.version          = '1.0.0'
  s.summary          = 'DevSkin Mobile Analytics SDK for iOS'
  s.description      = <<-DESC
    DevSkin Mobile SDK provides comprehensive mobile analytics including:
    - Real User Monitoring (RUM)
    - Session recording
    - Performance tracking
    - Network request monitoring
    - Touch heatmaps
    - Crash reporting
  DESC

  s.homepage         = 'https://devskin.com.br'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'DevSkin' => 'contato@devskin.com.br' }
  s.source           = { :git => 'https://github.com/devskin/mobile-sdk-ios.git', :tag => s.version.to_s }
  s.documentation_url = 'https://docs.devskin.com.br/ios'

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.0'

  s.source_files = '**/*.swift'

  s.frameworks = 'Foundation', 'UIKit', 'SystemConfiguration'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_OPTIMIZATION_LEVEL' => '-Onone'
  }
end
