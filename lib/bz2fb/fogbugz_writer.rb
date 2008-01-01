#!/usr/bin/ruby -w
require 'rexml/document'
require 'date'
require 'net/http'
require 'net/https'
require 'uri'

module BZ2FB
    class FogBugzWriter
        FB_FIELDS_TO_RETRIEVE = [
            "ixBug",
            "fOpen",
            "sTitle",
            "sLatestTextSummary",
            "ixBugEventLatestText",
            "ixProject",
            "sProject",
            "ixArea",
            "sArea",
            "ixGroup",
            "ixPersonAssignedTo",
            "sPersonAssignedTo",
            "sEmailAssignedTo",
            "ixPersonOpenedBy",
            "ixPersonResolvedBy",
            "ixPersonClosedBy",
            "ixPersonLastEditedBy",
            "ixStatus",
            "sStatus",
            "ixPriority",
            "sPriority",
            "ixFixFor",
            "sFixFor",
            "dtFixFor",
            "sVersion",
            "sComputer",
            "c",
            "sCustomerEmail",
            "ixMailbox",
            "ixCategory",
            "sCategory",
            "ixBugEventLatest",
            "fReplied",
            "fForwarded",
            "ixRelatedBugs",
            "events"
        ]

        def initialize(url, user, password)
            @url = url
            @user = user
            @password = password
            @token = nil

            login
        end

        def user
            @user
        end

        def login
            logout

            #Retrieve the api.xml file from the given URL, which will provide us with the necessary info
            @api_uri = get_actual_api_url

            # Copy the API URI and munge it to add stuff to the request
            login_uri = URI.parse(@api_uri.to_s)
            login_uri.query = "cmd=logon&email=#{URI.escape(@user)}&password=#{URI.escape(@password)}"

            $log.debug "Sending login request to #{login_uri}"
            body = http_get_xml(login_uri)

            if body.elements["/response/error"] != nil
                raise "Error #{body.elements["/response/error"].attributes["code"]} logging in to #{@api_uri} as #{@user}: #{body.elements["/response/error"].text}"
            elsif body.elements["/response/token"] != nil
                @token = body.elements["/response/token"].text
                $log.debug "Successfully logged in to #{@api_uri} as #{@user}; token = #{@token}"
            else
                raise "Unexpected response: #{response.body}"
            end

            prefetch_fields
        end

        def logout
            return if @token == nil

            # Copy the API URI and munge it to add stuff to the request
            logout_uri = URI.parse(@api_uri.to_s)
            logout_uri.query = "cmd=logoff"

            http_get(logout_uri)

            @token = nil
        end

        def add_bug(bug)
            existing_bug = find_migrated_bug(bug[:bugzillaBugId])

            if existing_bug 
                $log.debug "Updating existing case # #{existing_bug[:ixBug]}"
                update_existing_bug(existing_bug[:ixBug], bug, existing_bug)
            else
                $log.debug "Creating new case for Bug ID #{bug[:bugzillaBugId]}"

                bug_id = create_new_bug(bug, bug[:migration_message])

                #For each note in the bug, add a note
                bug[:notes].each do |note|
                    add_bugzilla_bug_note(bug_id, note)
                end

            end
        end

        def finalize_bug(bug)
            existing_bug = find_migrated_bug(bug[:bugzillaBugId])

            if !existing_bug 
                raise ApplicationError, "Unable to find case for BugZilla bug # #{bug[:bugzillaBugId]}"
            end

            $log.debug "Finalizing case #{existing_bug[:ixBug]} for BugZilla Bug ID #{bug[:bugzillaBugId]}"

            if bug[:sStatus] == "Active"
                # The bug is still active, so there's nothing to do
                $log.debug "Bug # #{bug[:bugzillaBugId]} is still active, so nothing to finalize"
                return
            end


            if existing_bug[:ixStatus] == find_status_id_by_name(bug[:sStatus])
                $log.debug "Case #{existing_bug[:ixBug]} already has the correct final status, #{existing_bug[:sStatus]}"
            elsif bug[:sStatus] == "Resolved (Duplicate)"
                #This is a duplicate of another case.  Need to find that case
                if !bug.has_key?(:dupe_of_bz_bug_id)
                    raise RuntimeError, "Bug# #{bug[:bugzillaBugId]} is a duplicate, but the :dupe_of_bz_bug_id value is nil"
                end

                existing_duplicate_bug = find_migrated_bug(bug[:dupe_of_bz_bug_id])

                if !existing_duplicate_bug
                    raise RuntimeError, "Unable to find case for migrated bug #{bug[:dupe_of_bz_bug_id]}, of which bug #{bug[:bugzillaBugId]} is a duplicate"
                end

                resolve_case_as_dupe(existing_bug[:ixBug], bug[:dtLastUpdated], existing_duplicate_bug[:ixBug])
            else
                resolve_case(existing_bug[:ixBug], bug[:dtLastUpdated], bug[:sStatus])
            end

            #Resolution may have changed the assigned-to value, so reload
            existing_bug = get_bug_by_id(existing_bug[:ixBug])

            if existing_bug[:ixPersonAssignedTo] != bug[:ixPersonOpenedBy] &&
                existing_bug[:ixPersonAssignedTo] != 1 # 1 is the built-in 'closed' user, which is assigned all closed bugs
                #Normally, resolving a case would automatically assign it back to the reporter.
                #However, since the reporter for all of these cases will be the account used to perform
                #the migration, this won't happen for migrated cases.  Thus, explicitly reassign the resolved
                #case to the account of the original reporter
                #before closing
                $log.debug "Case #{existing_bug[:ixBug]} is currently assigned to #{existing_bug[:ixPersonAssignedTo]}, but should be #{bug[:ixPersonOpenedBy]}"
                reassign_case(existing_bug[:ixBug], bug[:ixPersonOpenedBy], "Assigning resolved migrated case to original reporter of bug")
            end

            #Finally, close case
            if existing_bug[:fOpen] != "false"
                close_case(existing_bug[:ixBug])
            end
        end

        def find_project_id_by_name(project_name)
            if @projects.has_key?(project_name)
                @projects[project_name][:id]
            else
                nil
            end
        end

        def find_area_id_by_name(project_name, area_name)
            if @projects.has_key?(project_name) && @projects[project_name][:areas].has_key?(area_name)
                @projects[project_name][:areas][area_name][:id]
            else
                nil
            end
        end

        def find_fixfor_by_name(project_name, fixfor_name)
            # Look first in the project-specific fixfor list, then try the global fixfor list
            # before giving up
            if @projects.has_key?(project_name) && @projects[project_name][:fixfors].has_key?(fixfor_name)
                @projects[project_name][:fixfors][fixfor_name][:id]
            elsif @fixfors.has_key?(fixfor_name)
                @fixfors[fixfor_name][:id]
            else
                nil
            end
        end

        def find_priority_id_by_name(priority_name)
            if @priorities.has_key?(priority_name)
                @priorities[priority_name][:id]
            else
                nil
            end
        end

        def find_user_id_by_name(user_name)
            if @users.has_key?(user_name)
                @users[user_name][:id]
            else
                nil
            end
        end

        def find_status_id_by_name(status)
            if @statuses.has_key?(status)
                @statuses[status][:id]
            else
                nil
            end
        end

        # Given a Bugzilla bug ID, searches for a FogBugz case generated from the bug
        # based on the 'BugzillaBugId: n' value inserted into the "Computer" field of the case
        def find_migrated_bug(id)
            uri = URI.parse(@api_uri.to_s)
            search = "computer:\"BugzillaBugId: #{id}\""
            uri.query = "cmd=search&q=#{URI.escape(search)}&cols=ixBug"

            body = http_get_xml_with_error_reporting(uri, "searching #{@api_uri}")

            if body.elements["//case"] != nil
                case_node = body.elements["//case"]
                bug_id = case_node.elements["ixBug"].text.to_i

                $log.debug "Found FogBugz case #{bug_id} for migrated BugZilla bug #{id}"

                bug = get_bug_by_id(bug_id)
            elsif body.elements["//cases[@count=0]"] != nil
                # no matching cases foudn
                bug = nil
                $log.debug "No FogBugz case found for migrated BugZilla bug #{id}"
            else
                raise "Unexpected response: #{response.body}"
            end

            bug
        end

        # Merges the existing contents of a bug with the migrated bug data, including events
        def update_existing_bug(bug_id, new_bug, existing_bug)
            if new_bug[:sTitle] != existing_bug[:sTitle] ||
                new_bug[:ixProject] != existing_bug[:ixProject] ||
                new_bug[:ixArea] != existing_bug[:ixArea] ||
                new_bug[:ixFixFor] != existing_bug[:ixFixFor] ||
                new_bug[:ixPersonAssignedTo] != existing_bug[:ixPersonAssignedTo] ||
                new_bug[:ixPriority] != existing_bug[:ixPriority] ||
                new_bug[:sVersion] != existing_bug[:sVersion]
                # Basic bug info doesn't match
                set_existing_bug(bug_id, new_bug, "Updating migrated bug with latest migration results")
            end

            # Make sure all the notes in the new bug also appear in the existing bug as events
            new_bug[:notes].each do |note|
                note_found = false

                existing_bug[:events].each do |event|
                    #puts "Event text: #{event[:text]}"
                    if event[:text] != nil && event[:text].include?(note[:note])
                        note_found = true
                    end
                end

                if !note_found
                    add_bugzilla_bug_note(bug_id, note)
                end
            end

            true
        end

        def create_new_bug(bug, comment)
            uri = URI.parse(@api_uri.to_s)

            query = build_query_for_bug(bug, comment)
            query["cmd"] = "new"
            query["cols"] = "ixBug"

            body = http_post_xml_with_error_reporting(uri, query, "creating new case for BugZilla bug ID #{bug[:bugzillaBugId]}")

            if body.elements["//case"] != nil
                case_node = body.elements["//case"]

                bug_id = case_node.elements["ixBug"].text.to_i

                $log.debug "Created FogBugz case #{bug_id} for migrated BugZilla bug #{bug[:bugzillaBugId]}"
            else
                raise "Unexpected response: #{response.body}"
            end

            bug_id
        end

        def set_existing_bug(bug_id, bug, comment)
            uri = URI.parse(@api_uri.to_s)

            query = build_query_for_bug(bug, comment)
            query["cmd"] = "edit"
            query["ixBug"] = bug_id
            query["cols"] = "ixBug"

            body = http_post_xml_with_error_reporting(uri, query, "Updating case # #{bug_id} for BugZilla bug ID #{bug[:bugzillaBugId]}")

            if body.elements["//case"] != nil
                case_node = body.elements["//case"]

                bug_id = case_node.elements["ixBug"].text.to_i

                $log.debug "Updated FogBugz case #{bug_id} for migrated BugZilla bug #{bug[:bugzillaBugId]}"
            else
                raise "Unexpected response: #{response.body}"
            end

            bug_id
        end

        def resolve_case_as_dupe(bug_id, original_resolved_date, duplicate_of_bug_id)
            resolve_case_internal(bug_id, original_resolved_date, "Resolved (Duplicate)", duplicate_of_bug_id)
        end

        def resolve_case(bug_id, original_resolved_date, status)
            resolve_case_internal(bug_id, original_resolved_date, status, nil)
        end

        def resolve_case_internal(bug_id, original_resolved_date, status, duplicate_of_bug_id)
            $log.debug "Resolving case #{bug_id} to status '#{status}'"

            uri = URI.parse(@api_uri.to_s)
            query = {
                "cmd" => "resolve",
                "ixBug" => bug_id,
                "ixStatus" => find_status_id_by_name(status),
                "sEvent" => "Originally resolved in BugZilla as of #{original_resolved_date}",
                "cols" => "ixBug"
            }

            if duplicate_of_bug_id != nil
                query["sEvent"] += "; duplicate of FogBugz Bug #{duplicate_of_bug_id}"
            end

            body = http_post_xml_with_error_reporting(uri, query, "Updating status of case # #{bug_id} to '#{status}'")

            if body.elements["//case"] != nil
                case_node = body.elements["//case"]

                bug_id = case_node.elements["ixBug"].text.to_i

                $log.debug "Resolved FogBugz case #{bug_id} as '#{status}'"
            else
                raise "Unexpected response: #{response.body}"
            end
        end

        def reassign_case(bug_id, ixUser, comment)
            uri = URI.parse(@api_uri.to_s)
            query = {
                "cmd" => "assign",
                "ixBug" => bug_id,
                "ixPersonAssignedTo" => ixUser,
                "sEvent" => comment,
                "cols" => "ixBug"
            }
            http_post_xml_with_error_reporting(uri, query, "Reassigning #{bug_id}")
        end

        def close_case(bug_id)
            uri = URI.parse(@api_uri.to_s)
            query = {
                "cmd" => "close",
                "ixBug" => bug_id,
                "cols" => "ixBug"
            }
            http_post_xml_with_error_reporting(uri, query, "Closing #{bug_id}")
        end

        def build_query_for_bug(bug, comment) 
            query = {
                "sTitle" => bug[:sTitle],
                "ixProject" => bug[:ixProject],
                "ixArea" => bug[:ixArea],
                "ixFixFor" => bug[:ixFixFor],
                "sCategory" => "Bug",
                "ixPersonAssignedTo" => bug[:ixPersonAssignedTo],
                "ixPersonOpenedBy" => bug[:ixPersonOpenedBy],
                "dtOpened" => bug[:dtOpened].to_s,
                "ixPriority" => bug[:ixPriority],
                "sVersion" => bug[:sVersion],
                "sComputer" => 'BugzillaBugId: ' + bug[:bugzillaBugId].to_s,
                "sEvent" => comment
            }

            query
        end

        def add_bugzilla_bug_note(bug_id, note)
            add_bug_event(bug_id,
                "***Note Migrated From BugZilla***\nTimestamp from BugZilla: #{note[:ts]}\nUser from BugZilla: #{note[:sEmail]}\nNote from BugZilla: #{note[:note]}")
        end

        def add_bug_event(bug_id, comment)
            uri = URI.parse(@api_uri.to_s)

            query = {
                "cmd" => "edit",
                "ixBug" => bug_id,
                "sEvent" => comment,
                "cols" => "ixBug"
            }

            body = http_post_xml_with_error_reporting(uri, query, "Adding event to case #{bug_id}")

            if body.elements["//case"] != nil
                case_node = body.elements["//case"]

                bug_id = case_node.elements["ixBug"].text.to_i

                $log.debug "Added event to FogBugz case #{bug_id}"
            else
                raise "Unexpected response: #{response.body}"
            end
        end

        def get_bug_by_id(bug_id)
            # Gets all info in FogBugz for the given bug ID
            uri = URI.parse(@api_uri.to_s)
            search = bug_id.to_s
            uri.query = "cmd=search&q=#{URI.escape(search)}&cols=#{FB_FIELDS_TO_RETRIEVE.join(",")}"

            body = http_get_xml_with_error_reporting(uri, "loading case #{bug_id}")

            #puts "Bug #{bug_id}:\n\n#{body.to_s}\n\n"

            if body.elements["//case"] != nil
                case_node = body.elements["//case"]

                # Load all the elements for the case into a hash
                bug = {}
                case_node.elements.each do |elem|
                    # Parse the IDs as ints; everything else is a string
                    if elem.name.index("ix") == 0
                        bug[elem.name.to_sym] = elem.text.to_i
                    else
                        bug[elem.name.to_sym] = elem.text
                    end
                end

                # Also load all of the events
                bug[:events] = []
                case_node.elements["events"].each do |event_node|
                    event = {}
                    event[:id] = event_node.elements["ixBugEvent"].text.to_i
                    event[:type] = event_node.elements["evt"].text.to_i
                    event[:ixPerson] = event_node.elements["ixPerson"].text.to_i
                    event[:text] = event_node.elements["s"].text

                    bug[:events] << event
                end

                $log.debug "Loaded FogBugz case #{bug[:ixBug]}"
            elsif body.elements["//cases[@count=0]"] != nil
                # no matching cases foudn
                bug = nil
                $log.debug "No FogBugz case # #{bug_id} found"
            else
                raise "Unexpected response: #{response.body}"
            end

            bug
        end

        def get_actual_api_url
            # Request the api.xml file specified in @url, verify its contents, and use it to determine the
            # actual URL of the FogBugz HTTP interface
            uri = URI.parse(@url)
            if !['http', 'https'].include?(uri.scheme)
                raise "API.XML URL #{@url} scheme '#{uri.scheme}' is not supported"
            end

            body = http_get_xml(uri)

            version = body.elements["/response/version"].text.to_i
            min_version = body.elements["/response/minversion"].text.to_i
            api_url = body.elements["/response/url"].text

            $log.debug "From #{@url}, version=#{version}, minversion=#{min_version}, API URL=#{api_url}"

            if min_version > 3
                raise "The FogBugz API URL reports a minimum version of #{min_version}, but this code uses API version 3"
            end

            # the api_url is a relative value, specified relative to the @url location
            # Make it absolute
            path, query = api_url.split("?")

            uri.path = "/" + path
            uri.query = query

            uri
        end

        # Fetch the static field lists (users, projects, priorities, etc)
        # so they can be queried during the migration without incurring HTTP
        # overhead each time
        def prefetch_fields()
            prefetch_projects()
            prefetch_areas()
            prefetch_fixfors()
            prefetch_priorities()
            prefetch_users()
            prefetch_statuses()
        end

        def prefetch_projects
            @projects = {}

            $log.debug "Prefetching FogBugz projects"

            uri = URI.parse(@api_uri.to_s)
            uri.query = "cmd=listProjects&fWrite=1"

            body = http_get_xml_with_error_reporting(uri, "listing writable projects")

            if body.elements["//project"] != nil
                body.elements["//projects"].each do |project_node|
                    #puts project_node.to_s
                    project = {}

                    project[:id] = project_node.elements["ixProject"].text.to_i
                    project[:name] = project_node.elements["sProject"].text
                    project[:areas] = {}
                    project[:fixfors] = {} 
    
                    $log.debug "Found FogBugz project ID #{project[:id]}, '#{project[:name]}"
    
                    @projects[project[:name]] = project
                end
            else
                raise "Unexpected response: #{response.body}"
            end
        end

        def prefetch_areas

            $log.debug "Prefetching FogBugz areas"


            uri = URI.parse(@api_uri.to_s)
            uri.query = "cmd=listAreas&fWrite=1"

            body = http_get_xml_with_error_reporting(uri, "listing writable areas")

            if body.elements["//area"] != nil
                body.elements["//areas"].each do |area_node|
                    area_project_name = area_node.elements["sProject"].text
                    project = @projects[area_project_name]

                    area = {}
                    area[:id] = area_node.elements["ixArea"].text.to_i
                    area[:name] = area_node.elements["sArea"].text
                    project[:areas][area[:name]] = area
    
                    $log.debug "Found FogBugz area ID #{area[:id]}, '#{area[:name]}', for project '#{area_project_name}'"
                end
            else
                raise "Unexpected response: #{response.body}"
            end
        end

        def prefetch_fixfors

            $log.debug "Prefetching FogBugz fixfors"


            @fixfors = {}
            uri = URI.parse(@api_uri.to_s)
            uri.query = "cmd=listFixFors"

            body = http_get_xml_with_error_reporting(uri, "listing fixfors")

            if body.elements["//fixfor"] != nil
                body.elements["//fixfors"].each do |fixfor_node|
                    fixfor_project_name = fixfor_node.elements["sProject"].text
                    # If the project name for this fixfor is an empty string, it's a global fixfor, otherwise it belongs to a specific project
                    if fixfor_project_name == nil
                        fixfors = @fixfors
                    else
                        fixfors = @projects[fixfor_project_name][:fixfors]
                    end

                    fixfor = {}
                    fixfor[:id] = fixfor_node.elements["ixFixFor"].text.to_i
                    fixfor[:name] = fixfor_node.elements["sFixFor"].text
                    fixfors[fixfor[:name]] = fixfor
    
                    $log.debug "Found FogBugz fixfor ID #{fixfor[:id]}, '#{fixfor[:name]}', for project '#{fixfor_project_name}'"
                end
            else
                raise "Unexpected response: #{response.body}"
            end
        end

        def prefetch_priorities
            @priorities = {}

            $log.debug "Prefetching FogBugz priorities"


            uri = URI.parse(@api_uri.to_s)
            uri.query = "cmd=listPriorities"

            body = http_get_xml_with_error_reporting(uri, "listing priorities")

            if body.elements["//priority"] != nil
                body.elements["//priorities"].each do |priority_node|
                    priority = {}

                    # In the FogBugz UI, priorities are displayed as ID - Name, presumably
                    # because the default configuration has three 'Must Fix' priorities with different IDs.
                    # Preserve that convention here, since we must be able to assume the priority name
                    # is a unique identifier
                    priority[:id] = priority_node.elements["ixPriority"].text.to_i
                    priority[:name] = priority[:id].to_s + " - " + priority_node.elements["sPriority"].text
                    @priorities[priority[:name]] = priority
    
                    $log.debug "Found FogBugz priority ID #{priority[:id]}, '#{priority[:name]}'"
                end
            else
                raise "Unexpected response: #{response.body}"
            end
        end

        def prefetch_users
            @users = {}

            $log.debug "Prefetching FogBugz users"


            uri = URI.parse(@api_uri.to_s)
            uri.query = "cmd=listPeople"

            body = http_get_xml_with_error_reporting(uri, "listing users")

            if body.elements["//person"] != nil
                body.elements["//people"].each do |person_node|
                    user = {}
                    user[:id] = person_node.elements["ixPerson"].text.to_i
                    user[:name] = person_node.elements["sFullName"].text
                    user[:email] = person_node.elements["sEmail"].text
                    @users[user[:email]] = user
    
                    $log.debug "Found FogBugz user ID #{user[:id]}, '#{user[:email]}'"
                end
            else
                raise "Unexpected response: #{response.body}"
            end
        end

        def prefetch_statuses
            @statuses = {}

            $log.debug "Prefetching FogBugz statuses"


            uri = URI.parse(@api_uri.to_s)
            uri.query = "cmd=listStatuses"

            body = http_get_xml_with_error_reporting(uri, "listing statuses")

            if body.elements["//status"] != nil
                body.elements["//statuses"].each do |status_node|
                    status = {}
                    status[:id] = status_node.elements["ixStatus"].text.to_i
                    status[:name] = status_node.elements["sStatus"].text
                    @statuses[status[:name]] = status
    
                    $log.debug "Found FogBugz status ID #{status[:id]}, '#{status[:name]}'"
                end
            else
                raise "Unexpected response: #{response.body}"
            end
        end

        # Does an HTTP GET of the specified URI and returns the response
        def http_get(uri)
            # Add the auth token to all requests
            add_token_to_query_string(uri)

            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true if uri.scheme == 'https'

            $log.debug "Using SSL for #{uri}" if http.use_ssl
            req = uri.path
            req += "?#{uri.query}" unless uri.query == nil

            $log.debug "Sending GET request to #{uri.host} for #{req}"

            tries = 0
            begin
                response = http.get(req)
            rescue Errno::EBADF
                #Get these bad file descriptor errors sometimes
                #Retry clears them up usuall
                tries += 1

                if tries < 3
                    $log.error "Request failed due to bad file descriptor; retrying"
                    retry
                else
                    raise
                end
            end
        end

        def http_get_xml(uri)
            response = http_get(uri)

            # Raise an error if this isn't a successful response
            response.value

            #$log.debug "Got response [[[\n#{response.body}\n]]]"

            body = REXML::Document.new(response.body)

            body
        end

        def http_get_xml_with_error_reporting(uri, action_name)
            body = http_get_xml(uri)

            if body.elements["/response/error"] != nil
                raise "Error #{body.elements["/response/error"].attributes["code"]} #{action_name} as #{@user}: #{body.elements["/response/error"].text}"
            else
                body
            end
        end

        def http_post(uri, query)
            # Add the auth token to all requests
            add_token_to_query(query)

            http_session = Net::HTTP.new(uri.host, uri.port)
            http_session.use_ssl = true if uri.scheme == 'https'

            post_req = Net::HTTP::Post.new(uri.path)
            post_req.set_form_data(query)

            $log.debug "Using SSL for #{uri}" if http_session.use_ssl
            $log.debug "Sending POST request to #{uri.host} for #{uri.path}"

            tries = 0
            begin
                response = http_session.request(post_req)
            rescue Errno::EBADF
                #Get these bad file descriptor errors sometimes
                #Retry clears them up usuall
                tries += 1

                if tries < 3
                    $log.error "Request failed due to bad file descriptor; retrying"
                    retry
                else
                    raise
                end
            end
        end
    
        def http_post_xml(uri, query)
            response = http_post(uri, query)

            # Raise an error if this isn't a successful response
            response.value

            #$log.debug "Got response [[[\n#{response.body}\n]]]"

            body = REXML::Document.new(response.body)

            body
        end
    
        def http_post_xml_with_error_reporting(uri, query, action_name)
            body = http_post_xml(uri, query)
            if body.elements["/response/error"] != nil
                raise "Error #{body.elements["/response/error"].attributes["code"]} #{action_name} as #{@user}: #{body.elements["/response/error"].text}"
            else
                body
            end
        end

        def add_token_to_query_string(uri)
            return if @token == nil

            if uri.query != nil && uri.query != ""
                uri.query += "&"
            end

            uri.query += "token=#{URI.escape(@token)}"
        end

        def add_token_to_query(query)
            return if @token == nil

            query["token"] = @token
        end
    end
end
