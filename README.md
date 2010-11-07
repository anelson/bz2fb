# bz2fb Bugzilla to FogBugz migration script #

I wrote this script when my company decided to upgrade from BugZilla to FogBugz.  At the time, the FogBugz migration tools were not available for
hosted FogBugz (so-called "FogBugz On Demand"), and I was not willing to pay $2500 for Fog Creek to do a custom migration, so I wrote this script.

# Usage #

It operates on an XML dump from BugZilla.  I don't remember exactly how we generated that, but I recall it being straightforward.

Next you generate a config file mapping BugZilla fields to FogBugs fields.  Use `bin/gen_config.rb` for that purpose; it actually has
a decent command line help function due to the `optparse` library, so no further documentation should be required.

Once you have a config file (`etc/config.rb` by default), you'll want to edit it to possibly change the mappings for projects and milestones.

To actually run the migration, run `bin/bz2fb.rb`.  Again the command line help is pretty decent so it should be clear how to use it.

# Gotchas #

I wrote this script for my own purposes, so it's very likely it won't do what you want.

It writes output directly to the FogBugz API, which means if you interrupt it halfway through and start it again, you'll get duplicates.

There isn't a perfect mapping between fields in BugZilla and FogBugz, so some information is migrated as text in a case note.  This means you can't easily filter on those fields.
It's the price you pay for migrating.

I make no warranty that this script will do anything other than delete your data and burn down your house.  If you injure yourself while using it, well, 
you are probably doing it wrong.
