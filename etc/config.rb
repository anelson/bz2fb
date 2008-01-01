# Config file for bz2fb migration utility

$config = { 
    # Pre-conversion translations of Bugzilla product names to FogBugz project names
    # By default, bz2fb will expect each Bugzilla product to correspond to a FogBugz project
    # of the same name.  That can be overridden for specific product names by mapping them here
    :product_names_to_project_names => {
        # Example: 
        # 'My Bugzilla Product Name' => 'My FogBugz Project Name'
    
    },
    
    # Translations of Bugzilla component names to FogBugz area names
    :component_names_to_area_names => {
        # Example: 
        # 'My Bugzilla ComponentName' => 'My FogBugz Area Name'
        'DSM Command-line' => 'DSM UI',
        'DSM DLL (Library)' => 'DSM Libraries',
        'MSI Installer' => 'Installer',
        'WINPE' => 'RRC',
        'Management Objects' => 'MMC Snap-in',
        'TEVO Services' => 'Replay Server',
        'TEVO Target' => 'Replay Server',
        'TEVO Source' => 'Replay Agent',
        'TEVO User-Mode Libraries' => 'Replay Server'
    },
    
    # Translations of Bugzilla target milestone names to FogBugz fix for names
    :milestone_names_to_fix_for_names => {
        # Example: 
        # 'My Bugzilla Milestone' => 'My FogBugz Fix-For Version'
        '---' => 'Undecided',
        'Iteration .2 Aug 23' => '1.5 Iteration 2',
        'Iteration .3 Aug 30' => '1.5 Iteration 3',
        'Iteration .4 Sep 06' => '1.5 Iteration 4',
        'Iteration .5 Sep 13' => '1.5 Iteration 5',
        'Iteration .6 Sep 20' => '1.5 Iteration 6',
        'Iteration .7 Beta 1' => '1.5 Iteration 7 - Beta 1',
        'Iteration .8' => '1.5 Iteration 8',
        'Iteration .9' => '1.5 Iteration 9',
        'Iteration 10' => '1.5 Iteration 10',
        'Iteration 11 - 1.5' => '1.5 Iteration 11 - Gold',
        'Release Candidate' => '1.5 Iteration 11 - Gold',
        'Version 1.6' => '1.6',
        'Version 1.7' => '1.7',
        'Version 1.8' => '1.8',
        'Version 2.1' => '2.1',
        'Post-2.1' => 'Future Version',
    },
    
    # Translations of Bugzilla priority names to FogBugz priority names
    :priority_names_to_priority_names => {
        # Example: 
        # 'My Bugzilla Priority' => 'My FogBugz Priority'
        'Immediate' => '1 - Must Fix',
        'Iteration Requires' => '2 - Must Fix',
        'Release Requires' => '3 - Must Fix',
        'Nice to Have' => '4 - Fix If Time',
        'Someday/Maybe' => '6 - Fix If Time'
    },
    
    # Translations of Bugzilla user email addresses to FogBugz user email addresses
    :user_names_to_user_names => {
        # Example: 
        # 'user@bugzilla.org' => 'user@fogbugz.com'
        'rnurgudin@ddglobal.kiev.ua' => 'mzelenov@appassure.com'
    },
    
    # Translations of Bugzilla statuses to FogBugz statuses
    # For resolved bug, BugZilla uses a combination of status (eg, 'RESOLVED') and resolution (eg, 'FIXED', 'WORKSFORME', etc).
    # Fogbugz by contrast has multiple 'Resolved' statuses, like 'Resolved (Fixed)' and 'Resolved (Not Reproducible)'.
    # In the translation below, the combination of bugzilla status and resolution are separated by a double-colon (::), so
    # a status of 'RESOLVED' and a resolution of 'FIXED' appears as 'RESOLVED::FIXED'.
    :status_names_to_status_names => {
        # Example: 
        # 'Active' => 'New'
        'NEW' => 'Active',
        'ACTIVE' => 'Active',
        'ASSIGNED' => 'Active',
        'REOPENED' => 'Active',
        'RESOLVED::FIXED' => 'Resolved (Fixed)',
        'RESOLVED::INVALID' => 'Resolved (Won\'t Fix)',
        'RESOLVED::WONTFIX' => 'Resolved (Won\'t Fix)',
        'RESOLVED::LATER' => 'Resolved (Postponed)',
        'RESOLVED::REMIND' => 'Resolved (Postponed)',
        'RESOLVED::WORKSFORME' => 'Resolved (Not Reproducible)',
        'RESOLVED::DUPLICATE' => 'Resolved (Duplicate)',
        'CLOSED' => 'FBClosed',  # Closed and Verified are special-cases, since FOgBugz has separate flags to record closing a case
        'VERIFIED' => 'FBVerified'
    }
}
