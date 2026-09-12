Pod::Spec.new do |s|
  s.name             = 'lisiere_native_tts'
  s.version          = '0.1.0'
  s.summary          = 'Offline French TTS with utterance-aware word boundaries.'
  s.description      = 'AVSpeechSynthesizer integration for the Lisiere EPUB reader.'
  s.homepage         = 'https://example.invalid/lisiere'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Lisiere' => 'maintainer@example.invalid' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '16.0'
  s.swift_version    = '5.0'
  s.static_framework = true
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
