# Default admission rules for OAR 2
# $Id$

DROP TABLE IF EXISTS admission_rules;
CREATE TABLE IF NOT EXISTS admission_rules (
id INT UNSIGNED NOT NULL AUTO_INCREMENT,
rule TEXT NOT NULL,
PRIMARY KEY (id)
);

# Default admission rules

# Specify the default value for queue parameter
INSERT IGNORE INTO admission_rules (rule) VALUES ('# Set default queue is no queue is set
if (not defined($queue_name)) {$queue_name="default";}
');

# Prevent root and oar to submit jobs.
INSERT IGNORE INTO admission_rules (rule) VALUES ('# Prevent users oar and root to submit jobs
# Note: do not change this unless you want to break oar !
die ("[ADMISSION RULE] root and oar users are not allowed to submit jobs.\\n") if ( $user eq "root" or $user eq "oar" );
');

# Avoid users except admin to go in the admin queue
INSERT IGNORE INTO admission_rules (rule) VALUES ('# Restrict the admin queue to members of the admin group
my $admin_group = "admin";
if ($queue_name eq "admin") {
    my $members; 
    (undef,undef,undef, $members) = getgrnam($admin_group);
    my %h = map { $_ => 1 } split(/\\s+/,$members);
    if ( $h{$user} ne 1 ) {
        {die("[ADMISSION RULE] Only member of the group ".$admin_group." can submit jobs in the admin queue\\n");}
    }
}
');

# Prevent the use of system properties
INSERT IGNORE INTO admission_rules (rule) VALUES ('# Prevent users from using internal resource properties for oarsub requests 
my @bad_resources = ("type","state","next_state","finaud_decision","next_finaud_decision","state_num","suspended_jobs","scheduler_priority","cpuset","besteffort","deploy","expiry_date","desktop_computing","last_job_date","available_upto","last_available_upto");
foreach my $mold (@{$ref_resource_list}){
    foreach my $r (@{$mold->[0]}){
        my $i = 0;
        while (($i <= $#{$r->{resources}})){
            if (grep(/^$r->{resources}->[$i]->{resource}$/i, @bad_resources)){
                die("[ADMISSION RULE] \'$r->{resources}->[$i]->{resource}\' resource is not allowed\\n");
            }
            $i++;
        }
    }
}
');

# Force besteffort jobs to run in the besteffort queue
# Force job of the besteffort queue to be of the besteffort type
# Force besteffort jobs to run on nodes with the besteffort property
INSERT IGNORE INTO admission_rules (rule) VALUES ('# Tie the besteffort queue, job type and resource property together
if (grep(/^besteffort$/, @{$type_list}) and not $queue_name eq "besteffort"){
    $queue_name = "besteffort";
    print("[ADMISSION RULE] Automatically redirect in the besteffort queue\\n");
}
if ($queue_name eq "besteffort" and not grep(/^besteffort$/, @{$type_list})) {
    push(@{$type_list},"besteffort");
    print("[ADMISSION RULE] Automatically add the besteffort type\\n");
}
if (grep(/^besteffort$/, @{$type_list})){
    if ($jobproperties ne ""){
        $jobproperties = "($jobproperties) AND besteffort = \\\'YES\\\'";
    }else{
        $jobproperties = "besteffort = \\\'YES\\\'";
    }
    print("[ADMISSION RULE] Automatically add the besteffort constraint on the resources\\n");
}
');

# Verify if besteffort jobs are not reservations
INSERT IGNORE INTO admission_rules (rule) VALUES ('# Prevent besteffort advance-reservation
if ((grep(/^besteffort$/, @{$type_list})) and ($reservationField ne "None")){
    die("[ADMISSION RULE] Error: a job cannot both be of type besteffort and be a reservation.\\n");
}
');

# Force deploy jobs to go on resources with the deploy property
INSERT IGNORE INTO admission_rules (rule) VALUES ('# Tie the deploy job type and resource property together
if (grep(/^deploy$/, @{$type_list})){
    if ($jobproperties ne ""){
        $jobproperties = "($jobproperties) AND deploy = \\\'YES\\\'";
    }else{
        $jobproperties = "deploy = \\\'YES\\\'";
    }
}
');

# Restrict allowed properties for deploy jobs to force requesting entire nodes
INSERT IGNORE INTO admission_rules (rule) VALUES ('# Restrict allowed properties for deploy jobs to force requesting entire nodes
my @bad_resources = ("cpu","core","thread","resource_id",);
if (grep(/^deploy$/, @{$type_list})){
    foreach my $mold (@{$ref_resource_list}){
        foreach my $r (@{$mold->[0]}){
            my $i = 0;
            while (($i <= $#{$r->{resources}})){
                if (grep(/^$r->{resources}->[$i]->{resource}$/i, @bad_resources)){
                    die("[ADMISSION RULE] the \'$r->{resources}->[$i]->{resource}\' resource property cannot be used with jobs of type deploy\\n");
                }
                $i++;
            }
        }
    }
}
');

# Force desktop_computing jobs to go on nodes with the desktop_computing property
INSERT IGNORE INTO admission_rules (rule) VALUES ('# Tie desktop computing job type and resource property together
if (grep(/^desktop_computing$/, @{$type_list})){
    print("[ADMISSION RULE] Added automatically desktop_computing resource constraints\\n");
    if ($jobproperties ne ""){
        $jobproperties = "($jobproperties) AND desktop_computing = \\\'YES\\\'";
    }else{
        $jobproperties = "desktop_computing = \\\'YES\\\'";
    }
}else{
    if ($jobproperties ne ""){
        $jobproperties = "($jobproperties) AND desktop_computing = \\\'NO\\\'";
    }else{
        $jobproperties = "desktop_computing = \\\'NO\\\'";
    }
}
');

# Limit the number of reservations that a user can do.
# (overrided on user basis using the file: ~oar/unlimited_reservation.users)
INSERT IGNORE INTO admission_rules (rule) VALUES ('# Limit the number of advance reservations per user
if ($reservationField eq "toSchedule") {
    my $unlimited=0;
    if (open(FILE, "< $ENV{HOME}/unlimited_reservation.users")) {
        while (<FILE>){
            if (m/^\\s*$user\\s*$/m){
                $unlimited=1;
            }
        }
        close(FILE);
    }
    if ($unlimited > 0) {
        print("[ADMISSION RULE] Unlimited advance reservation privilege granted\\n");
    } else {
        my $max_nb_resa = 2;
        my $nb_resa = $dbh->do("    SELECT job_id
                                    FROM jobs
                                    WHERE
                                        job_user = \\\'$user\\\' AND
                                        (reservation = \\\'toSchedule\\\' OR
                                        reservation = \\\'Scheduled\\\') AND
                                        (state = \\\'Waiting\\\' OR state = \\\'Hold\\\')
                               ");
        if ($nb_resa >= $max_nb_resa){
            die("[ADMISSION RULE] Error: you cannot have more than $max_nb_resa waiting advance reservations.\\n");
        }
    }
}
');

## How to perform actions if the user name is in a file
#INSERT IGNORE INTO admission_rules (rule) VALUES ('
#open(FILE, "/tmp/users.txt");
#while (($queue_name ne "admin") and ($_ = <FILE>)){
#    if ($_ =~ m/^\\s*$user\\s*$/m){
#        print("[ADMISSION RULE] Change assigned queue into admin\\n");
#        $queue_name = "admin";
#    }
#}
#close(FILE);
#');

# Limit walltime for interactive jobs
INSERT IGNORE INTO admission_rules (rule) VALUES ('# Limit the walltime for interactive jobs
my $max_walltime = OAR::IO::sql_to_duration("12:00:00");
if (($jobType eq "INTERACTIVE") and ($reservationField eq "None")){ 
    foreach my $mold (@{$ref_resource_list}){
        if ((defined($mold->[1])) and ($max_walltime < $mold->[1])){
            print("[ADMISSION RULE] Walltime to big for an INTERACTIVE job so it is set to $max_walltime.\\n");
            $mold->[1] = $max_walltime;
        }
    }
}
');

# specify the default walltime if it is not specified
INSERT IGNORE INTO admission_rules (rule) VALUES ('# Set the default walltime is not specified
my $default_wall = OAR::IO::sql_to_duration("2:00:00");
foreach my $mold (@{$ref_resource_list}){
    if (!defined($mold->[1])){
        print("[ADMISSION RULE] Set default walltime to $default_wall.\\n");
        $mold->[1] = $default_wall;
    }
}
');

# Check if types given by the user are right
INSERT IGNORE INTO admission_rules (rule) VALUES ('# Check if job types are valid
my @types = ("container","inner","deploy","desktop_computing","besteffort","cosystem","idempotent","timesharing","token\\:xxx=yy");
foreach my $t (@{$type_list}){
    my $i = 0;
    while (($types[$i] ne $t) and ($i <= $#types)){
        $i++;
    }
    if (($i > $#types) and ($t !~ /^(timesharing|inner|token\\:\\w+\\=\\d+)/)){
        die("[ADMISSION RULE] The job type $t is not handled by OAR; Right values are : @types\\n");
    }
}
');

# If resource types are not specified, then we force them to default
INSERT IGNORE INTO admission_rules (rule) VALUES ('# Set resource type to default if not specified
foreach my $mold (@{$ref_resource_list}){
    foreach my $r (@{$mold->[0]}){
        my $prop = $r->{property};
        if (($prop !~ /[\\s\\(]type[\\s=]/) and ($prop !~ /^type[\\s=]/)){
            if (!defined($prop)){
                $r->{property} = "type = \\\'default\\\'";
            }else{
                $r->{property} = "($r->{property}) AND type = \\\'default\\\'";
            }
        }
    }
}
print("[ADMISSION RULE] Modify resource description with type constraints\\n");
');
