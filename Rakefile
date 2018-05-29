if File.exists?('.git') && !ENV['IPPON_VERSION']
  tags = `git log -n1 --decorate-refs=refs/tags/v* --format=%d`
  if tags =~ /tag: v(\d+\.\d+)/
    ENV['IPPON_VERSION'] = $1
  end
end

require 'bundler/gem_tasks'
require 'rake/testtask'
require 'yard'

task :default => [:test, :"test:docs"]

ENV["COVERAGE"] = "1"

Rake::TestTask.new do
end

YARD::Rake::YardocTask.new("test:docs") do |t|
  t.options << "--no-output"
end

YARD::Rake::YardocTask.new(:docs) do |t|
end

