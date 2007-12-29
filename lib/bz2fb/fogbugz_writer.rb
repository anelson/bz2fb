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
            "ixRelatedBugs"
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
        end

        def logout
            return if @token == nil

            # Copy the API URI and munge it to add stuff to the request
            logout_uri = URI.parse(@api_uri.to_s)
            logout_uri.query = "cmd=logoff"

            http_get(logout_uri)

            @token = nil
        end

        def save(bug)
            puts "BUG: "
            p bug
            puts
        end

        # Given a Bugzilla bug ID, searches for a FogBugz case generated from the bug
        # based on the 'BugzillaBugId: n' value inserted into the "Computer" field of the case
        def find_migrated_bug(id)
            uri = URI.parse(@api_uri.to_s)
            search = "computer:\"BugzillaBugId: #{id}\""
            uri.query = "cmd=search&q=#{URI.escape(search)}&cols=#{FB_FIELDS_TO_RETRIEVE.join(",")}"

            body = http_get_xml(uri)

            if body.elements["/response/error"] != nil
                raise "Error #{body.elements["/response/error"].attributes["code"]} searching #{@api_uri} as #{@user}: #{body.elements["/response/error"].text}"
            elsif body.elements["//case"] != nil
                case_node = body.elements["//case"]

                bug = {}
                case_node.elements.each do |elem|
                    bug[elem.name] = elem.text
                end

                $log.debug "Found FogBugz case #{bug["ixBug"]} for migrated BugZilla bug #{id}"
            elsif body.elements["//cases[@count=0]"] != nil
                # no matching cases foudn
                bug = nil
                $log.debug "No FogBugz case found for migrated BugZilla bug #{id}"
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

        # Does an HTTP GET of the specified URI and returns the response
        def http_get(uri)
            # Add the auth token to all requests
            add_token_to_query(uri)

            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true if uri.scheme == 'https'

            $log.debug "Using SSL for #{uri}" if http.use_ssl
            req = uri.path
            req += "?#{uri.query}" unless uri.query == nil

            $log.debug "Sending GET request to #{uri.host} for #{req}"

            response = http.get(req)
        end

        def http_get_xml(uri)
            response = http_get(uri)

            # Raise an error if this isn't a successful response
            response.value

            body = REXML::Document.new(response.body)

            body
        end

        def add_token_to_query(uri)
            return if @token == nil

            if uri.query != nil && uri.query != ""
                uri.query += "&"
            end

            uri.query += "token=#{URI.escape(@token)}"
        end
    end
end
