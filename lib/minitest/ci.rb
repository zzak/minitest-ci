gem 'minitest', '2.6.0'
require "minitest/unit"
abort 'minitest version 2.6.0 required' unless MiniTest::Unit::VERSION == '2.6.0'

require 'fileutils'
require 'cgi'

module MiniTest
  module Ci
    VERSION = '1.0.2'

    @test_dir = nil #'test/reports'
    @error = nil
    @munit = nil
    @suites = Hash.new {|h,k| h[k] = []}

    class << self
      attr_accessor :test_dir
    end

    def add_error e
      @error = e
    end

    def push suite, method, time, num
      a = [method, time, num]
      if @error
        a << @error
        @error = nil
      end
      @suites[suite] << a
    end

    def finish
      @munit.puts
      @munit.puts 'generating ci files'

      clean

      Dir.chdir @test_dir do
        @suites.each do |name, suite|
          generate_suite name, suite
        end
      end
    end

    def munit= m
      @munit = m
    end

    private

    def clean
      FileUtils.rm_rf @test_dir
      FileUtils.mkdir_p @test_dir
    end

    def generate_suite name, suite
      total_time, assertions, errors, failures, skips = 0, 0, 0, 0, 0
      suite.each do |_, t, a, e|
        total_time += t
        assertions += a
        case e
        when MiniTest::Skip
          skips += 1
        when MiniTest::Assertion
          failures += 1
        else
          errors += 1
        end
      end

      File.open "TEST-#{name}.xml", "w" do |f|
        f.puts '<?xml version="1.0" encoding="UTF-8"?>'
        f.puts "<testsuite time='#{"%6f" % total_time}' skipped='#{skips}' failures='#{failures}' errors='#{errors}' name='#{name}' assertions='#{assertions}' tests='#{suite.count}'>"

        suite.each do |method, time, asserts, error|
          f.puts "  <testcase time='#{"%6f" % time}' name='#{method}' assertions='#{asserts}'>"
          if error
            bt = MiniTest::filter_backtrace(error.backtrace).join "\n"
            f.write "    <#{type error} type='#{error.class}' message='#{CGI.escapeHTML(error.message)}'>"
            f.puts CGI.escapeHTML(bt)
            f.puts "    </#{type error}>"
          end
          f.puts "  </testcase>"
        end

        f.puts "</testsuite>"
      end
    end

    def type e
      case e
      when MiniTest::Skip
        'skipped'
      else
        'failure'
      end
    end

    extend self
  end

  class CiUnit < Unit

    # copied out of MiniTest::Unit
    def _run_suite suite, type
      # added this line
      MiniTest::Ci.munit = self

      header = "#{type}_suite_header"
      puts send(header, suite) if respond_to? header

      filter = options[:filter] || '/./'
      filter = Regexp.new $1 if filter =~ /\/(.*)\//

      assertions = suite.send("#{type}_methods").grep(filter).map { |method|
        inst = suite.new method
        inst._assertions = 0

        print "#{suite}##{method} = " if @verbose

        @start_time = Time.now
        result = inst.run self
        time = Time.now - @start_time

        print "%.2f s = " % time if @verbose
        print result
        puts if @verbose

        # added this line
        MiniTest::Ci.push suite, method, time, inst._assertions

        inst._assertions
      }

      return assertions.size, assertions.inject(0) { |sum, n| sum + n }
    end

    def puke klass, meth, e
      MiniTest::Ci.add_error e
      super
    end

    def status io = self.output
      super
      MiniTest::Ci.finish
    end

  end
end

# set defaults
MiniTest::Ci.test_dir = 'test/reports'
MiniTest::Unit.runner = MiniTest::CiUnit.new