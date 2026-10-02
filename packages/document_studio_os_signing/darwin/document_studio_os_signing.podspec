Pod::Spec.new do |s|
  s.name             = 'document_studio_os_signing'
  s.version          = '0.1.0'
  s.summary          = 'Keychain identity signing for Document Studio'
  s.homepage         = 'https://github.com/tejashvi-kumawat/DocumentStudio'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Document Studio' => 'dev@local' }
  s.source           = { :path => '.' }
  s.source_files     = 'Sources/document_studio_os_signing/**/*.swift'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.swift_version    = '5.0'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
