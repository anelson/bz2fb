#!/usr/bin/ruby -w
#
# BugZilla to FogBugz migration script by Adam Nelson
# Generates a config file for bz2fb with field mappings based on actual
# bugzilla bug data
require 'optparse'
require 'logger'
require 'set'

require File.dirname(__FILE__) + '/../lib/bz2fb.rb'

def parse_opts()
    opts = {
        :bz_file => nil,
        :config_in => File.dirname(__FILE__) + '/../etc/config.rb.in',
        :config_out => File.dirname(__FILE__) + '/../etc/config.rb',
        :fb_url => nil,
        :fb_username => nil,
        :fb_password => nil
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

    opt_parser.on("-i", "--config-in", "The path to the config file template to use (default: #{opts[:config_in]})") { |val|
        opts[:config_in] = val
        $log.debug "Setting config file template path to #{val}"
    }
    opt_parser.on("-o", "--config-out", "The path to the config file to generate (default: #{opts[:config_out]})") { |val|
        opts[:config_out] = val
        $log.debug "Setting config file path to #{val}"
    }
    opt_parser.on("-v", "--verbose",  "Turns on verbose logging") {|val| 
        $log.level  = Logger::DEBUG
        $log.debug "Setting log level to DEBUG"
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

def extract_bug_fields(bz_file)
    fields = {}
    fields[:products] = {} # Each product has child hashes listing components, versions, and milestones
    fields[:statuses] = Set.new
    fields[:resolutions] = Set.new
    fields[:priorities] = Set.new
    fields[:user_email_addresses] = Set.new

    $log.info "Reading BugZilla bug file #{bz_file} (may take several minutes)"

    rdr = BZ2FB::BugzillaReader.new(File.open(bz_file))

    rdr.each_bug do |bug|
        $log.debug "Processing bug #{bug[:id]} - #{bug[:title]}"

        if bug[:product] != nil
            if fields[:products][bug[:product]] == nil
                fields[:products][bug[:product]] = { :components => Set.new, :versions => Set.new, :milestones => Set.new }
            end

            prod = fields[:products][bug[:product]]

            prod[:components].add(bug[:component])
            prod[:versions].add(bug[:version])
            prod[:milestones].add(bug[:milestone])
        end

        fields[:statuses].add(bug[:status])
        fields[:resolutions].add(bug[:resolution])
        fields[:priorities].add(bug[:priority])
        fields[:user_email_addresses].add(bug[:reporter])
        fields[:user_email_addresses].add(bug[:assigned_to])
        if bug[:cc] != nil
            bug[:cc].each do |cc|
                fields[:user_email_addresses].add(cc)
            end
        end
    end

    $log.debug "Found statuses: #{fields[:statuses].to_a.join(',')}"
    $log.debug "Found resolutions: #{fields[:resolutions].to_a.join(',')}"
    $log.debug "Found priorities: #{fields[:priorities].to_a.join(',')}"
    $log.debug "Found user email addresses: #{fields[:user_email_addresses].to_a.join(',')}"
    $log.debug "Found products: #{fields[:products].keys.to_a.join(',')}"
    fields[:products].each do |key, value|
        $log.debug "Found product '#{key}' versions: #{value[:versions].to_a.join(',')}"
        $log.debug "Found product '#{key}' milestones: #{value[:milestones].to_a.join(',')}"
        $log.debug "Found product '#{key}' components: #{value[:components].to_a.join(',')}"
    end

    fields
end

def write_bug_fields(config_in_path, config_out_path, url, user, password, bug_fields)
    $log.debug "Generating config file #{config_out_path} from template #{config_in_path}"
    config_in = File.open(config_in_path, "r")
    config_out = File.open(config_out_path, "w")
    
    # Copy config_in to config_out
    config_in.each do |line|
        line.sub!("{{url}}", url)
        line.sub!("{{user}}", user)
        line.sub!("{{password}}", password)
        config_out.puts line
    end
    
    config_in.close

    config_out.puts "# Translation of BugZilla priorities into the FogBugz 1 (highest) through 7 (lowest) scheme"
    config_out.puts "# TODO: You MUST adjust the priority levels assigned below"
    config_out.puts "config[:priorities] = {"
    bug_fields[:priorities].each do |priority|
        config_out.puts "  \"#{priority}\" => 3,"
    end
    config_out.puts "  :default => 3"
    config_out.puts "}"
    config_out.puts

    config_out.puts "# Translation of BugZilla status and resolution into the FogBugz Status scheme"
    config_out.puts "config[:statuses] = {"
    bug_fields[:statuses].each do |status|
        fb_equiv = "Active"

        case status
            when "CLOSED"
            fb_equiv = "Closed"
            when "VERIFIED"
            fb_equiv = "Verified"
        end

        if status == "RESOLVED"
            #Display resolutions instead of this status, since FogBugz doesn't
            #make the distinction between statuses and resolutions
            bug_fields[:resolutions].each do |resolution|
                fb_equiv = "Responded"

                case resolution
                    when "DUPLICATE"

                end
                config_out.puts "  \"#{resolution}\" => \"#{resolution}\","
            end
        else
            config_out.puts "  \"#{status}\" => \"#{fb_equiv}\","
        end
    end
    config_out.puts "  :default => \"Open\""
    config_out.puts "}"
    config_out.puts

end

def login_to_fogbugz(url, user, password) 
    BZ2FB::FogBugzWriter.new(url, user, password)
end

def main()
    $log.debug "Starting"

    opts = parse_opts()

    fb = login_to_fogbugz(opts[:fb_url], opts[:fb_username], opts[:fb_password])
    fb.logout
    
    #Build the list of bug fields which will be used to generate a mapping between BZ and FB
    bug_fields = extract_bug_fields(opts[:bz_file])
    
    write_bug_fields(opts[:config_in], opts[:config_out], opts[:fb_url], opts[:fb_username], opts[:fb_password], bug_fields)
    
    
    $log.info "Done"
end

$log = Logger.new(STDOUT)
$log.level = Logger::INFO

main

