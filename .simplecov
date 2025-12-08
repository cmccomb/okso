require 'simplecov'
require 'simplecov_json_formatter'
require 'simplecov-cobertura'

SimpleCov.coverage_dir ENV.fetch('COVERAGE_DIR', 'coverage')
SimpleCov.enable_coverage :branch

SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new(
  [
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::JSONFormatter,
    SimpleCov::Formatter::CoberturaFormatter
  ]
)

SimpleCov.start do
  root ENV.fetch('SIMPLECOV_ROOT', Dir.pwd)
  add_filter %r{^/tmp/}
  add_filter %r{^/usr/}
  add_filter %r{^/var/}
  track_files 'src/**/*.sh'
end
