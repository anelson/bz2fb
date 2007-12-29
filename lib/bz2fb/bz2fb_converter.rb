#!/usr/bin/ruby -w
require 'rexml/document'
require 'date'

module BZ2FB
    class BugzillaToFogBugzConverter
        def initialize()
            @bz_reader = nil
            @fb_writer = nil
            @product_conversion_callbacks = { 
                :default => make_default_project_converter
            }
            @class_conversion_callback = &default_converter
            @platform_conversion_callback = &default_converter
            @os_conversion_callback = &default_converter
            @status_and_resolution_conversion_callback = &default_status_and_resolution_converter
            @priority_conversion_callback = &default_converter
            @severity_conversion_callback = &default_converter
            @user_conversion_callback = &default_converter
            @is_bug_open_callback = &default_is_bug_open
        end

        def on_product(product, &block)
            @product_conversion_callbacks[product] = make_default_project_converter unless @product_conversion_callbacks[product] != nil
            @product_conversion_callbacks[product][:product] = &block
        end

        def on_product_milestone(product, &block)
            @product_conversion_callbacks[product] = make_default_project_converter unless @product_conversion_callbacks[product] != nil
            @product_conversion_callbacks[product][:milestones] = &block
        end

        def on_product_version(product, &block)
            @product_conversion_callbacks[product] = make_default_project_converter unless @product_conversion_callbacks[product] != nil
            @product_conversion_callbacks[product][:versions] = &block
        end

        def on_product_component(product, &block)
            @product_conversion_callbacks[product] = make_default_project_converter unless @product_conversion_callbacks[product] != nil
            @product_conversion_callbacks[product][:components] = &block
        end

        def on_class(&block)
            @class_conversion_callback = &block
        end

        def on_platform(&block)
            @platform_conversion_callback = &block
        end

        def on_os(&block)
            @os_conversion_callback = &block
        end

        def on_status_and_resolution(&block)
            @status_and_resolution_conversion_callback = &block
        end

        def on_priority(&block)
            @priority_conversion_callback = &block
        end

        def on_severity(&block)
            @class_conversion_callback = &block
        end

        def on_user(&block)
            @user_conversion_callback = &block
        end

        def on_is_bug_open(&block)
            @is_bug_open_callback = &block
        end

        def convert_bugs(bz_reader, fb_writer)
            bz_reader.each_bug do |bz_bug|
                fb_bug = convert_bug(bz_bug, fb_writer)

                fb_writer.save_bug fb_bug
            end
        end

        def convert_bug(bz_bug, fb_writer)
            fb_bug = {}

            fb_bug[:sTitle] = bz_bug[:title]
            fb_bug[:sProject] = convert_project(bz_bug[:project])
            fb_bug[:sArea] = convert_project_component(bz_bug[:project], bz_bug[:component])
            fb_bug[:sEmailAssignedTo] = convert_user(bz_bug[:assigned_to])
            fb_bug[:sEmailOpenedBy] = convert_user(bz_bug[:reporter])
            fb_bug[:sStatus] = convert_status(bz_bug[:status], bz_bug[:resolution])
            fb_bug[:sPriority] = convert_priority(bz_bug[:priority])
            fb_bug[:sFixFor] = convert_project_milestone(bz_bug[:project], bz_bug[:milestone])
            fb_bug[:sVersion] = convert_project_version(bz_bug[:project], bz_bug[:version])
            fb_bug[:sComputer] = convert_platform(bz_bug[:platform]) + " " + convert_os(bz_bug[:os])
            fb_bug[:sCategory] = "Bug"
            fb_bug[:dtOpened] = bz_bug[:created]
            fb_bug[:dtLastUpdated] = bz_bug[:changed]
            fb_bug[:notes] = []

            if bz_bug[:notes] != nil
                bz_bug[:notes].each do |note|
                    fb_bug[:notes] << {
                        :sEmail => note[:who],
                        :dt => note[:dt],
                        :note => note[:note]
                    }
                end
            end

            fb_bug[:notes] << {
                :sEmail => fb_writer.user,
                :dt => DateTime.now,
                :note => "Migrated from BugZilla [Bug #{bz_bug[:id]}] - #{bz_bug[:title]}\n\nRaw XML of original bug: #{bz_bug[:xml]}"
            }

            fb_bug[:fOpen] = @is_bug_open_callback(bz_bug, fb_bug)
        end

        def convert_project(project)
            # Find the callback to handle this
            if @product_conversion_callbacks[project] != nil
                @product_conversion_callbacks[project][:project](project)
            else 
                @product_conversion_callbacks[:default][:project](project)
            end
        end

        def default_converter(bz_value)
            # Convert bugzilla values to FogBugz values literally
            bz_value
        end

        def default_status_and_resolution_converter(status, resolution)
            if status == "RESOLVED"
                resolution
            else
                status
            end
        end

        # Given the bugzilla and fogbugz versions of a bug, determines if the bug should be 'open' in fogbugz
        def default_is_bug_open(bz_bug, fb_bug)
            return bz_bug[:status] != "CLOSED"
        end

        # Creates a hash containing the converter callbacks for a project, all set to 
        # the default one-to-one converter
        def make_default_project_converter 
            {
                :product => &default_converter,
                :milestones => &default_converter,
                :versions => &default_converter,
                :components => &default_converter
            }
        end
    end
end
