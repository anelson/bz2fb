#!/usr/bin/ruby -w
require 'rexml/document'
require 'date'
require 'yaml'

module BZ2FB
    class BugzillaToFogBugzConverter
        def initialize(config, bz_reader, fb_writer)
            @config = config
            @bz_reader = bz_reader
            @fb_writer = fb_writer
        end

        # Verifies that all the product fields used in BugZilla have FogBugz equivalents
        def pre_conversion_sanity_check()
            # Do a dry run of the bug conversion checking the mappings between BugZilla and FogBugz fields
            # If the FB API allowed creation of things like projects and priorities, this wouldn't be necessary
            missing_fields = []

            @bz_reader.each_bug do |bz_bug|
                verify_field_mappings(bz_bug, missing_fields)
            end

            missing_fields
        end

        def convert_bugs()
            # The conversion is a two-stage process
            # First, all bugs are added to FogBugz as Active bugs
            # Next, we go back through a second time and set the resolution values
            # and close out the bugs.  This is required to support bugs marked as 'duplicate', 
            # since the duplicate bug could conceivably be migrated first

            @bz_reader.each_bug do |bz_bug|
                fb_bug = convert_bug(bz_bug)
            
                @fb_writer.add_bug fb_bug
            end

            @bz_reader.each_bug do |bz_bug|
                fb_bug = convert_bug(bz_bug)

                @fb_writer.finalize_bug fb_bug
            end
        end

        def verify_field_mappings(bz_bug, missing_fields)
            # If the config file contains any pre-conversion field translations, do that now before
            # mapping the bugzilla values to FogBugs
            apply_pre_conversion_translations(bz_bug)

            begin
                fb_reporter_id = bz_user_name_to_fb_user_id(bz_bug[:reporter])
            rescue ArgumentError
                add_missing_field(missing_fields, "User '#{bz_bug[:reporter]}'")
            end

            begin
                fb_asignee_id = bz_user_name_to_fb_user_id(bz_bug[:assigned_to])
            rescue ArgumentError
                add_missing_field(missing_fields, "User '#{bz_bug[:assigned_to]}'")
            end

            begin
                fb_product_id = bz_product_name_to_fb_project_id(bz_bug[:product])
            rescue ArgumentError
                add_missing_field(missing_fields, "Project '#{bz_bug[:product]}'")
                return
            end

            begin
                fb_area_id = bz_component_name_to_fb_area_id(bz_bug[:product], bz_bug[:component])
            rescue ArgumentError
                add_missing_field(missing_fields, "Project '#{bz_bug[:product]}' area '#{bz_bug[:component]}'")
            end

            begin
                fb_fix_for_id = bz_target_milestone_name_to_fb_fix_for_id(bz_bug[:product], bz_bug[:milestone])
            rescue ArgumentError
                add_missing_field(missing_fields, "Project '#{bz_bug[:product]}' Fix-For '#{bz_bug[:milestone]}'")
            end

            begin
                fb_priority_id = bz_priority_name_to_fb_priority_id(bz_bug[:priority])
            rescue ArgumentError
                add_missing_field(missing_fields, "Priority '#{bz_bug[:priority]}'")
            end

            begin
                if bz_bug[:status] == "CLOSED" || bz_bug[:status] == "VERIFIED"
                    #Special case; nothing to map
                    status = "Resolved (Fixed)"
                else 
                    status = bz_status_and_resolution_name_to_fb_status_name(bz_bug[:status_and_resolution])
                end
            rescue ArgumentError
                add_missing_field(missing_fields, "Status '#{bz_bug[:status_and_resolution]}'")
            end
            
        end

        def add_missing_field(missing_fields, missing_field)
            unless missing_fields.include?(missing_field)
                missing_fields << missing_field
            end
        end

        def convert_bug(bz_bug)
            # If the config file contains any pre-conversion field translations, do that now before
            # mapping the bugzilla values to FogBugs
            apply_pre_conversion_translations(bz_bug)

            fb_bug = {}
            
            fb_bug[:sTitle] = bz_bug[:title] + " (BZ BUG " + bz_bug[:id].to_s + ")"

            fb_bug[:ixProject] = bz_product_name_to_fb_project_id(bz_bug[:product])
            fb_bug[:ixArea] = bz_component_name_to_fb_area_id(bz_bug[:product], bz_bug[:component])
            fb_bug[:ixPersonAssignedTo] = bz_user_name_to_fb_user_id(bz_bug[:assigned_to])
            fb_bug[:ixPersonOpenedBy] = bz_user_name_to_fb_user_id(bz_bug[:reporter])

            #FogBugz doesn't have a status value for closed or verified, since those
            #are separate parts of the workflow.  In FB, when the original reporter of a bug
            #verifies the bug is fixed, the case goes to closed.  Thus, 'closed' implies 'verified'
            # When we see bugs like this, mark them as resolved (fixed), and set the open flag to false
            if bz_bug[:status] == "CLOSED" || bz_bug[:status] == "VERIFIED"
                fb_bug[:sStatus] = bz_status_and_resolution_name_to_fb_status_name("Resolved (Fixed)")
                fb_bug[:fOpen] = false
            else
                fb_bug[:sStatus] = bz_status_and_resolution_name_to_fb_status_name(bz_bug[:status_and_resolution])
                fb_bug[:fOpen] = true
            end

            if fb_bug[:sStatus] == "Resolved (Duplicate)"
                fb_bug[:dupe_of_bz_bug_id] = bz_bug[:dupe_of]
            end

            fb_bug[:ixPriority] = bz_priority_name_to_fb_priority_id(bz_bug[:priority])

            fb_bug[:ixFixFor] = bz_target_milestone_name_to_fb_fix_for_id(bz_bug[:product], bz_bug[:milestone])

            fb_bug[:sVersion] = bz_bug[:version]

            fb_bug[:bugzillaBugId] = bz_bug[:id]

            fb_bug[:dtOpened] = bz_bug[:created]
            fb_bug[:dtLastUpdated] = bz_bug[:changed]
            fb_bug[:notes] = []
            
            if bz_bug[:notes] != nil
                bz_bug[:notes].each do |note|
                    if note[:note].length > 0
                        fb_bug[:notes] << {
                            :sEmail => note[:who],
                            :ts => note[:ts],
                            :note => note[:note]
                        }
                    end
                end
            end

            fb_bug[:migration_message] = "Migrated from BugZilla [Bug #{bz_bug[:id]}] - #{bz_bug[:title]}\nOriginally opened by: #{bz_bug[:reporter]}\nOriginally opened on: #{bz_bug[:created]}"

            fb_bug
        end

        def apply_pre_conversion_translations(bz_bug) 
            #Check the translation hash first to see if this name should be aliased
            #to anothername
            bz_bug[:project] = @config[:product_names_to_project_names][bz_bug[:project]] if @config[:product_names_to_project_names].has_key?(bz_bug[:project])
            bz_bug[:component] = @config[:component_names_to_area_names][bz_bug[:component]] if @config[:component_names_to_area_names].has_key?(bz_bug[:component])
            bz_bug[:milestone] = @config[:milestone_names_to_fix_for_names][bz_bug[:milestone]] if @config[:milestone_names_to_fix_for_names].has_key?(bz_bug[:milestone])
            bz_bug[:priority] = @config[:priority_names_to_priority_names][bz_bug[:priority]] if @config[:priority_names_to_priority_names].has_key?(bz_bug[:priority])
            bz_bug[:assigned_to] = @config[:user_names_to_user_names][bz_bug[:assigned_to]] if @config[:user_names_to_user_names].has_key?(bz_bug[:assigned_to])
            bz_bug[:reporter] = @config[:user_names_to_user_names][bz_bug[:reporter]] if @config[:user_names_to_user_names].has_key?(bz_bug[:reporter])
            bz_bug[:status_and_resolution] = @config[:status_names_to_status_names][bz_bug[:status_and_resolution]] if @config[:status_names_to_status_names].has_key?(bz_bug[:status_and_resolution])
        end

        def bz_product_name_to_fb_project_id(bz_product_name)
            fb_id = @fb_writer.find_project_id_by_name(bz_product_name)
            raise ArgumentError, "Invalid product name '#{bz_product_name}'" unless fb_id != nil
            fb_id
        end

        def bz_component_name_to_fb_area_id(bz_product_name, bz_component_name)
            fb_id = @fb_writer.find_area_id_by_name(bz_product_name, bz_component_name)
            raise ArgumentError, "Invalid component name '#{bz_component_name}' for product '#{bz_product_name}'" unless fb_id != nil
            fb_id
        end

        def bz_target_milestone_name_to_fb_fix_for_id(bz_product_name, bz_milestone_name)
            fb_id = @fb_writer.find_fixfor_by_name(bz_product_name, bz_milestone_name)
            raise ArgumentError, "Invalid fix for name '#{bz_milestone_name}' for product name '#{bz_product_name}'" unless fb_id != nil
            fb_id
        end

        def bz_priority_name_to_fb_priority_id(bz_priority_name)
            fb_id = @fb_writer.find_priority_id_by_name(bz_priority_name)
            raise ArgumentError, "Invalid priority name '#{bz_product_name}'" unless fb_id != nil
            fb_id
        end

        def bz_user_name_to_fb_user_id(bz_user_name)
            fb_id = @fb_writer.find_user_id_by_name(bz_user_name)
            raise ArgumentError, "Invalid user name '#{bz_product_name}'" unless fb_id != nil
            fb_id
        end

        def bz_status_and_resolution_name_to_fb_status_name(bz_status_and_resolution)
            fb_id = @fb_writer.find_status_id_by_name(bz_status_and_resolution)
            raise ArgumentError, "Invalid status/resolution '#{bz_status_and_resolution}'" unless fb_id != nil

            # The FB API doesn't actually use IDs for statuses, and it's easier
            # to write readable conditional code using the status text.
            # The above code services to verify the status and resolution string
            # corresponds to a valid status
            bz_status_and_resolution
        end
    end
end
