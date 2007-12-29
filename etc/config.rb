# Config file for bz2fb migration utility

config = {
    #The URL of the api.xml file which describes the fogbugz API
    :fogbugz_api_url => "https://appassure.fogbugz.com/api.xml"
    ,

    #The email address to log into fogbugz with
    :fogbugz_username => "anelson@appassure.com"
    ,

    #The password to log into fogbugz with
    :fogbugz_password => "An3Ls@n"
}

# What follows is filled in by gen_config.rb automatically.  You can edit it to change how field values in BugZilla are mapped
# to similar fields in FogBugz

# Translation of BugZilla priorities into the FogBugz 1 (highest) through 7 (lowest) scheme
# TODO: You MUST adjust the priority levels assigned below
config[:priorities] = {
  "Release Requires" => 3,
  "Someday/Maybe" => 3,
  "Nice to Have" => 3,
  "Immediate" => 3,
  "Iteration Requires" => 3,
  :default => 3
}

# Translation of BugZilla status and resolution into the FogBugz Status scheme
config[:statuses] = {
  "NEW" => "NEW",
  "VERIFIED" => "VERIFIED",
  "CLOSED" => "CLOSED",
  "DUPLICATE" => "DUPLICATE",
  "LATER" => "LATER",
  "WORKSFORME" => "WORKSFORME",
  "" => "",
  "INVALID" => "INVALID",
  "WONTFIX" => "WONTFIX",
  "FIXED" => "FIXED",
  "ASSIGNED" => "ASSIGNED",
  :default => "Open"
}

