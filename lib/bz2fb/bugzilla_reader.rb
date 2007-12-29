#!/usr/bin/ruby -w
require 'rexml/document'
require 'date'

# Reads Bugzilla bugs from an XML export
module BZ2FB
    class BugzillaReader
        def initialize(bug_xml_data_stream)
            @stream = bug_xml_data_stream
            @doc = REXML::Document.new(@stream)
        end

        #Yields a hash containing the bug details once for each bug in the stream
        def each_bug
            @doc.elements.each("/bugzilla/bug") do |bug_node|
                bug = bug_from_node(bug_node)
                yield bug
            end
        end

        # Converts a bugzilla <bug> XML node into a Ruby hash with the bug info
        def bug_from_node(node)
            bug = {}

            bug[:xml] = node.to_s
            node.elements.each("*") do |elem|
                case elem.name
                    when 'bug_id'
                    bug[:id] = elem.text.to_i

                    when 'creation_ts'
                    bug[:created] = parse_bz_ts(elem.text)

                    when 'short_desc'
                    bug[:title] = elem.text

                    when 'delta_ts'
                    bug[:changed] = parse_bz_ts(elem.text)

                    when 'reporter_accessible'
                    bug[:reporter_accessible] = elem.text.to_i ? true : false

                    when 'cclist_accessible'
                    bug[:cclist_accessible] = elem.text.to_i ? true : false

                    when 'classification_id'
                    bug[:class_id] = elem.text.to_i

                    when 'classification'
                    bug[:class] = elem.text

                    when 'product'
                    bug[:product] = elem.text

                    when 'component'
                    bug[:component] = elem.text

                    when 'version'
                    bug[:version] = elem.text

                    when 'rep_platform'
                    bug[:platform] = elem.text

                    when 'op_sys'
                    bug[:os] = elem.text

                    when 'bug_status'
                    bug[:status] = elem.text

                    when 'resolution'
                    bug[:resolution] = elem.text

                    when 'priority'
                    bug[:priority] = elem.text

                    when 'bug_severity'
                    bug[:severity] = elem.text

                    when 'target_milestone'
                    bug[:milestone] = elem.text

                    when 'blocked'
                    append_to_array(bug, :blocks_bug_id, elem.text.to_i)

                    when 'dependson'
                    append_to_array(bug, :blocks_bug_id, elem.text.to_i)

                    when 'everconfirmed'
                    bug[:ever_confirmed] = elem.text.to_i

                    when 'reporter'
                    bug[:reporter] = elem.text

                    when 'assigned_to'
                    bug[:assigned_to] = elem.text

                    when 'cc'
                    append_to_array(bug, :cc, elem.text)

                    when 'group'
                    bug[:group] = elem.text

                    when 'long_desc'
                    append_to_array(bug, 
                        :notes, 
                        { :who => get_element_text(elem, "who"),
                            :ts => parse_bz_ts(get_element_text(elem, "bug_when")),
                            :note => get_element_text(elem, "thetext")
                        })
                    if get_element_text(elem, "thetext") =~ /\*\*\* This bug has been marked as a duplicate of bug (\d+) \*\*\*/)
                        bug[:dupe_of] = $&.to_i
                    end

                    when 'attachment'
                    append_to_array(bug, 
                        :attachments, 
                        { :obsolete => get_attribute(elem, 'isobsolete', '0').to_i ? true : false,
                            :patch => get_attribute(elem, 'ispatch', '0').to_i ? true : false,
                            :private => get_attribute(elem, 'isprivate', '0').to_i ? true : false,
                            :attachment_id => get_element_text(elem, "attach_id", '0').to_i,
                            :date => parse_bz_ts(get_element_text(elem, "date")),
                            :description => get_element_text(elem, "desc"),
                            :filename => get_element_text(elem, "filename"),
                            :type => get_element_text(elem, "type")
                        })

                    else
                        raise "Unrecognized <bug> element #{elem.name}"
                end
            end

            bug
        end

        def parse_bz_ts(ts)
            return nil if ts == nil
            DateTime.strptime(ts, "%Y-%m-%d %H:%M")
        end

        def append_to_array(hash, key, value)
            if hash[key] == nil
                hash[key] = []
            end

            hash[key] << value
        end

        def get_element_text(parent, element_name, default_value = nil)
            elem = get_named_value(parent.elements, element_name, nil)
            if elem == nil
                default_value
            else
                elem.text
            end
        end

        def get_attribute(parent, attribute_name, default_value = nil)
            get_named_value(parent.attributes, attribute_name, default_value)
        end

        def get_named_value(collection, key, default_value = nil)
            if collection[key] == nil
                default_value
            else
                collection[key]
            end
        end
    end
end
