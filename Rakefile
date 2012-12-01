#!/usr/bin/env rake
require "bundler/gem_tasks"
require 'yard'
YARD::Rake::YardocTask.new

task :test do
  puts %x[node test/testClientJSONRPC.js]
  puts $?.exitstatus
end
