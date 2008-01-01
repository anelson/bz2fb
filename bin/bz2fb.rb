#!/usr/bin/ruby -w
#
# BugZilla to FogBugz migration script by Adam Nelson
require 'optparse'
require 'logger'

require File.dirname(__FILE__) + '/../lib/bz2fb.rb'


def parse_opts()
    opts = {
        :bz_file => nil,
        :fb_url => nil,
        :fb_username => nil,
        :fb_password => nil,
        :config_file => File.dirname(__FILE__) + '/../etc/config.rb'
    }
    
    opt_parser = OptionParser.new
    opt_parser.banner = "Usage: #{$0} [options] bugzilla_file"

    opt_parser.separator ""

    opt_parser.separator "Required Options"

    opt_parser.on("-a", "--fogbugz-address URL", "The URL of the api.xml file for the FogBugz installation") { |val|
        opts[:fb_url] = val
        $log.debug "Setting FogBugz API URL to #{val}"
    }
    opt_parser.on("-u", "--fogbugz-user EMAIL", "The email address of a FogBugz user account") { |val|
        opts[:fb_username] = val
        $log.debug "Setting FogBugz user to #{val}"
    }
    opt_parser.on("-p", "--fogbugz-password PASSWORD", "The password of the FogBugz user account") { |val|
        opts[:fb_password] = val
        $log.debug "Setting FogBugz password to #{val}"
    }

    opt_parser.separator ""
    opt_parser.separator "Additional Options:"

    opt_parser.on("-v", "--verbose",  "Turns on verbose logging") {|val| 
        $log.level  = Logger::DEBUG
        $log.debug "Setting log level to DEBUG"
    }

    opt_parser.on("-c", "--config-file FILE",  "Overrides the default config file location, #{opts[:config_file]}") {|val| 
        opts[:config_file] = val
    }
    
    remaining_args = opt_parser.parse(*ARGV)
    if remaining_args.length > 0
        opts[:bz_file] = remaining_args.pop
    end

    if remaining_args.length > 0
        remaining_args.each do |arg|
            $log.error "Unrecognized argument '#{arg}'"
        end

        puts opt_parser.to_s
        exit(-1)
    end

    
    if opts[:bz_file] == nil
        $log.error "A BugZilla bug file must be specified"
        puts opt_parser.to_s
        exit(-1)
    end
    if opts[:fb_url] == nil
        $log.error "A FogBugz URL must be specified"
        puts opt_parser.to_s
        exit(-1)
    end
    if opts[:fb_username] == nil
        $log.error "A FogBugz user must be specified"
        puts opt_parser.to_s
        exit(-1)
    end
    if opts[:fb_password] == nil
        $log.error "A FogBugz password must be specified"
        puts opt_parser.to_s
        exit(-1)
    end

    opts
end

def read_config(config_file)
    begin
        require config_file
    rescue
        $log.error "Error reading config file '#{config_file}': #{$!}"
    end
end

def login_to_fogbugz(url, user, password) 
    BZ2FB::FogBugzWriter.new(url, user, password)
end

def main()
    $log.debug "Starting"

    opts = parse_opts()
    read_config(opts[:config_file])

    fb_writer = login_to_fogbugz(opts[:fb_url], opts[:fb_username], opts[:fb_password])
    bz_reader = BZ2FB::BugzillaReader.new(File.open(opts[:bz_file]))

    converter = BZ2FB::BugzillaToFogBugzConverter.new($config, bz_reader, fb_writer)

    #Before the conversion check for valid field mappings
    #missing_fields = converter.pre_conversion_sanity_check
    missing_fields = []
    if missing_fields.length > 0
        missing_fields.sort!
        $log.error "One or more FogBugz field values are missing:"
        missing_fields.each do |field|
            $log.error "\t#{field}"
        end
        exit(-1)
    end

    #Do the actual conversion
    converter.convert_bugs

    #bug = fb.find_migrated_bug(12345)
    #if bug != nil
    #    puts "Migrated bug: "
    #    p bug
    #    puts 
    #end

    $log.info "Done"
end

$log = Logger.new(STDOUT)
$log.level = Logger::INFO

main



