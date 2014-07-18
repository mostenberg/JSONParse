#!/opt/local/bin/perl

# jsonparse.pl - Proof of concept written by SOASTA for Yahoo.
# version 0.16 17Jul2014 bbrumfield@soasta.com
#	v.016 - added -run, -rps, -duration command line options for Yahoo.
# Best viewed with tab space set to 4 (in vi use the command :se ts=4 )

require 5.6.0;
use Getopt::Long;
use File::Basename;
use lib qw(..);
use JSON qw( decode_json );     			# from CPAN
use JSON::Parse 'parse_json';
use JSON::Parse 'assert_valid_json';
use HTML::TagParser;						# from CPAN
use URI::Fetch;								# from CPAN
use File::Basename;
use LWP::Simple;							# from CPAN
use URI;
use strict;
use warnings;

my $DEBUG = 0;								# Default DEBUG state


############################
###########
##
## SOASTA Setup
##
my $PREVIEWMODE_DEFAULT = "false";
my $LOCATION_DEFAULT = "AnyServer";
my $ALLOW_DEFAULTS = 1;
my $CLOUDTEST_SERVER = "ed.soasta.com";		# Your CT Instance
my $WORKING_DIR = "$ENV{'PWD'}/Working";
my $TEMPLATE_DIR = "$ENV{'PWD'}/CT_Templates";
my $templateSeeddata = "${TEMPLATE_DIR}/Seeddata_Template_52_02.xml";
my $templateComposition = "${TEMPLATE_DIR}/Composition_Template_52_02.xml";
my $templateClip = "${TEMPLATE_DIR}/Clip_Template_52_02.xml";
my $templateTarget = "${TEMPLATE_DIR}/Target_Template_52_02.xml";
my $sCommandURL = "/downloads/scommand/scommand.zip";		# http://experimental.soasta.com/concerto/downloads/scommand/scommand.zip
my $sCommandPath = "${WORKING_DIR}/scommand/bin/scommand";
my $buildnumberFilePath = "${WORKING_DIR}/currentbuild";
my $buildnumberFilePath2 = "${WORKING_DIR}/versiontemp";
my $buildnumberFile = "";
my $testDurationMS;
my $pacingMS;
my $vuserCount;
##
##
############
#############################


#############################################
#############################################
##
## Yahoo! Project Definitions
##
## These settings can be made for long-term use
##
my $default_filename = "./sample.json"; 	# Default JSON file
my $default_CloudTest_url = "http://${CLOUDTEST_SERVER}/concerto";
my $default_CloudTest_username = "yahoorobot";
my $default_CloudTest_password = "d0 y0u yah00?";
my $default_outputFile = "${WORKING_DIR}/test_data.csv";
my $TARGET_SEEDDATA = "${WORKING_DIR}/yahoo_seeddata.xml";
my $CT_seeddataPath = "/yahoo-json/seeddata/";
my $CT_seeddataFile = "yahoo-seeddata";
my $TARGET_COMPOSITION = "${WORKING_DIR}/yahoo_composition.xml";
my $CT_compositionPath = "/yahoo-json/compositions/";
my $CT_compositionFile = "yahoo-automated-test";
my $TARGET_TARGET = "${WORKING_DIR}/yahoo_target.xml";
my $CT_targetPath = "/yahoo-json/targets/";
my $CT_targetFile = "yahoo-host-target";
my $TARGET_CLIP = "${WORKING_DIR}/yahoo_clip.xml";
my $CT_clipPath = "/yahoo-json/clips/";
#my $CT_clipFile = "yahoo-automated-test-clip v1-clip";
my $CT_clipFile = "yahoo-clip v1-clip";
my $CT_dashboardPath = "/yahoo-json/dashboards/";
##
##
##############################################
############# End of Definitions #############


###
##
# Setup the working dir if it is not already created:
if ( ! -e $WORKING_DIR ) {
	system( "mkdir '$WORKING_DIR'" );

	if ($? == -1) {
		die "Could not create working directory ($WORKING_DIR)";
	}
}

###
##
# Command-line option holders:
our ($opt_debugger, $opt_jsonfile, $opt_run, $opt_rps, $opt_duration, $opt_url, $opt_username, $opt_password, $opt_outputfile, $opt_removeOldCTFiles, $opt_help);

###
##
# Parse the command line for required and optional arguments
CommandLineProcess();

############
##
## DEBUGGING SANDBOX
## 
## If Debug > 10 stop in this section. Special no-run debug section.
##

# put your test code here



if ( $DEBUG >= 10 ) {
	DEBUGPRINT("Exiting now.\n");
	exit ;
}

#
##
#############


#########################################################
#
# The active work of parsing the JSON file and running
# the test starts at this point.
#
#########################################################


#########################################################
#
# STEP 1. Load the JSON file into a buffer for parsing
#
DEBUGPRINT ("##########\nSTEP 1. Load the JSON file into a buffer for parsing\n");
DEBUGPRINT ("Reading file: $opt_jsonfile ...\n");
my $json_text = do {
   open(my $json_fh, "<:encoding(UTF-8)", $opt_jsonfile)
      or die("Can't open \$opt_jsonfile\": $!\n");
   local $/;
   <$json_fh>
};

# Validate the JSON file structure or exit with fatal error:
eval {
        assert_valid_json ($json_text);
    };
    if ($@) {
        die "The JSON file provided is invalid: $@\n";
    }

# Decode the JSON doc:
my $json = decode_json $json_text ;



#########################################################
#
# STEP 2. Initialize Test Header Information
#
# ** NOTE ** JSON File structure definition is assumed/hard-coded as per Yahoo! sample.json file
# 
my $DURATION = "";
my $TPS = "";
DEBUGPRINT ("##########\nSTEP 2. Initialize Test Header Information\n");
my $TARGET = $json->{'test'}{'server'};						# used when constructing the new target below
if ( defined ( $opt_duration ) ) {
	DEBUGPRINT("Overriding test duration with command-line value ($opt_duration)\n");
	$DURATION = $opt_duration;
} else {
	$DURATION = $json->{'test'}{'duration'};				# used when constructing the new composition below
}
if ( defined ( $opt_rps ) ) {
	DEBUGPRINT("Overriding test RPS with command-line value ($opt_rps)\n");
	$TPS = $opt_rps;
} else {
	$TPS = $json->{'test'}{'rps'};					# used when constructing the new composition below
}
my $COMMON_HEADERS = $json->{'test'}{'common-headers'};		# used when constructing the new composition below
my $commonheader_string = "\"";									# Must begin and end with an encapsulating double-quote
my $header_string = "\"";									# Must begin and end with an encapsulating double-quote
my $headercount = 0;


DEBUGPRINT ("Test Configuration Data:\n");
DEBUGPRINT ("SOASTA Target: $TARGET\n");
DEBUGPRINT ("Test Duration (min): $DURATION\n");
DEBUGPRINT ("RPS (TPS): $TPS\n");
if ( ref($COMMON_HEADERS) eq "HASH") {
	DEBUGPRINT("Common headers:\n");
	while (my($key, $value) = each ($COMMON_HEADERS)){	# Grab the Key/Value pairs from the hash element
		DEBUGPRINT ("\t$key:$value\n");
		$commonheader_string .= "$key:$value\\n";
		$headercount++;
	}
}
else {
	DEBUGPRINT ("Common Headers: $COMMON_HEADERS\n");
}
DEBUGPRINT ("\n\n");

###
## TEST RUN-TIME CALCULATIONS
#
$testDurationMS = ConvertMins2Millis( $DURATION );		# run-time of test
DEBUGPRINT ("Test Duration (Min / MS) = $DURATION / $testDurationMS\n"); 
$pacingMS = 1000;						# iteration pacing
$vuserCount = int(${TPS});					# number of virtual users needed (assuming 1:1 vuser:transaction ratio)


#########################################################
#
# STEP 3. Parse the JSON data bundles; unpack the paths and their related headers
#			and write them into a CSV for import into CloudTest as such:
#			path,headers
#
# NOTE: This is done at this stage as a sort of "fail safe" for the rest of the automation. If something should go wrong
# with any of the other moving parts, which may result in the automated test not running - at the very least, the JSON
# file will be parsed out to a CSV file, which can be used in manual intervention.
#
DEBUGPRINT ("##########\nSTEP 3. Parse the JSON data bundles; unpack the paths and their related headers\n");

# Open CSV file for writing:
#
if ( ! open( CSV, ">$opt_outputfile") ) {
	die "Could not open the CSV file for writing ($opt_outputfile)!";
}

my $outputLine = "";											# buffer that will be used to swap out placeholder in template seeddata file

# Print the CSV file headers
$outputLine = "path,headers\n";									# header row for seeddata XML file
print CSV "$outputLine";										# output header row to CSV file


foreach my $path(@{$json->{test}->{paths}}){					# Loop through the paths hierarchy from the JSON file
	my %paths_hash = ();

	$paths_hash{path} = $path->{path};							# all entries have paths
	DEBUGPRINT( "path:$path->{path}\n");
	print CSV "\"$path->{path}\",";								# output the first column to CSV file
	$outputLine .= "\"$path->{path}\",";						# construct output string for seeddata XML swap

	if ( defined($path->{headers})) 	{						# some entries have no headers, some have one, and some have multiple
		$paths_hash{headers} = $path->{headers};
	}

	# print the header structure of the JSON document - the whole column is wrapped in double-quotes for importing into CloudTest
	while (my($key, $value) = each (%paths_hash)){
		if ( ref($value) eq "HASH") {							# if the contained header is a hash, break it apart
			$header_string = $commonheader_string;

			while ( my($hash_key, $hash_value) = each ($value)) {
				$headercount++;
				$header_string .= "$hash_key:$hash_value\\n";

				DEBUGPRINT ("$hash_key:$hash_value");
			}
		}
	}
	print CSV "${header_string}\"\n";												# carriage return to end the current line
	$outputLine .= "${header_string}\"\n";
 }
close( CSV );													# close CSV file
chomp ( $outputLine );											# $outputLine is used when constructing the new seeddata file below

DEBUGPRINT("\n\noutputline = $outputLine\n");


#########################################################
#
# STEP 4. Manage the CloudTest scommand utility
#
# - check versions
# - update if necessary / download new version based on CT version
#
DEBUGPRINT ("##########\nSTEP 4. Manage the CloudTest scommand utility\n");

my $checkVersions = 0;
my $updateScommand = 0;

if ( -e $buildnumberFilePath ) { 
	$buildnumberFile = $buildnumberFilePath2;			# There is an existing download, we need to compare to the version on the server
	$checkVersions++;
} else {
	$buildnumberFile = $buildnumberFilePath;			# This must be the first run
	$updateScommand++;
}

DEBUGPRINT("Opening $buildnumberFile\n");
if ( ! open( BFD, "+>", "$buildnumberFile") )
{
	die "Could not open the buildnumber file for writing ($buildnumberFile)!";
}

DEBUGPRINT ("Fetching build number from ${opt_url}...\n");
my $html = HTML::TagParser->new( $opt_url );
my @meta = $html->getElementsByTagName( "meta" );

my $ServerBuildNumber;
my $currentBuildNumber;

# Parse the CloudTest login page DOM, extracting the meta tag with the current server build number:
foreach my $elem ( @meta ) {
    my $tagname = $elem->tagName;
    my $attr = $elem->attributes;
    my $text = $elem->innerText;

    while (my($key, $value) = each ($attr)){
    	if ( $key eq "content" ) {
			$ServerBuildNumber = $value;
		} 
    }
}

if ( $checkVersions ) {
	DEBUGPRINT("Opening ${buildnumberFilePath}\n");
	if ( ! open( BFD2, "${buildnumberFilePath}" ) ) {
		die "Failed trying to open the build number comparision file ($buildnumberFilePath)";
	}
	while ( <BFD2> ) {
		chomp;
		$currentBuildNumber = $_;
	}

	DEBUGPRINT("CurrentBuild = ${currentBuildNumber}\tServer Build = ${ServerBuildNumber}\n");

	if ( $currentBuildNumber ne $ServerBuildNumber ) {
		DEBUGPRINT("Our build is out of date, downloading the latest version of scommand...\n");
		$updateScommand++;
		print BFD2 "$ServerBuildNumber\n";					# Update the "current" build number with the version on the server.
	}
	close( BFD2 );

}

print BFD "$ServerBuildNumber\n";							# Update the build number - if 1st time, the currentversion file, if not, the versiontemp file.
close( BFD );

if ( $updateScommand ) {
	DEBUGPRINT("Fetching latest scommand utility from the CloudTest server...\n");
	system( "curl  --get ${opt_url}${sCommandURL} --output '${WORKING_DIR}/scommand.zip'" );
	if ($? == -1) {
	    print "curl command failed to execute: $!\n";
	}
	elsif ($? & 127) {
	    printf "curl command died with signal %d, %s coredump\n",
	    ($? & 127),  ($? & 128) ? 'with' : 'without';
	}
	else {
	    printf "curl command exited with value %d\n", $? >> 8;
	}
}

# TODO for Future Proofing:
#
# Handle unzipping of the scommand.zip here.
#
# This is built for a Macintosh, it will need to be updated to support other platforms accordingly.
#
if ( ! -e "${WORKING_DIR}/scommand" ) {
	DEBUGPRINT("Unzipping scommand archive...\n");

	# Setup the decompression mechanism:
	my $unzipCommand = "";

	if ( $^O eq 'darwin' ) {								# Mac OS X UNIX aka "Darwin"
		$unzipCommand = "unzip -u";
	} else {
		die "Do not know how to unpack the downloaded zip file."
	}

	system( "cd '${WORKING_DIR}'; ${unzipCommand} 'scommand'");
	if ($? == -1) {
	    print "unpacking command failed to execute: $!\n";
	}
	elsif ($? & 127) {
	    printf "unpacking command died with signal %d, %s coredump\n",
	    ($? & 127),  ($? & 128) ? 'with' : 'without';
	}
	else {
	    printf "unpacking command exited with value %d\n", $? >> 8;
	}
}

#########################################################
#
# STEP 5. Manage seed data
# - check for existing & rename (last) + overwrite : will always have to check for last and remove before rename
# - import new CSV to seeddata
DEBUGPRINT ("##########\nSTEP 5. Manage seed data \n");

DEBUGPRINT("Parsing the template seeddata file for the current test...\n");

# open seeddata files:
if ( ! open ( SDF, "${templateSeeddata}") ) {
	die "Could not open the seeddate template file for reading ($templateSeeddata)!";
}
							# Template to read
if ( ! open ( TSD, ">${TARGET_SEEDDATA}") ) {							# Target to write
	die "Could not open the seeddate target file for writing ($TARGET_SEEDDATA)!";
}

# loop through the seeddata template file, looking for the values to replace
while ( <SDF> ) {
	if ( $_ =~ m/DATACHUNK/ ) {
		$_ =~ s/DATACHUNK/$outputLine/;
	}

	if ( $_ =~ m/SEEDDATAFILE/ ) {
		$_ =~ s/SEEDDATAFILE/${CT_seeddataFile}/g;
	}

	if ( $_ =~ m/SEEDDATAPATH/ ) {
		$_ =~ s/SEEDDATAPATH/${CT_seeddataPath}/g;
	}
	print ( TSD "$_");
}

#close the files
close( SDF );
close( TSD );

# Remove old file from CloudTest:
if ( defined($opt_removeOldCTFiles) ) {
	DEBUGPRINT("Removing old seeddata file (${CT_seeddataPath}${CT_seeddataFile})...");
	system( "sh '${sCommandPath}' url='${opt_url}' username='${opt_username}' password='${opt_password}' cmd=delete type=seeddata name='${CT_seeddataPath}${CT_seeddataFile}'");
	if ($? == -1) {
		die "Could not delete the existing seeddata file (${CT_seeddataPath}${CT_seeddataFile}).";
	}
}

# Import the new file to CloudTest:
DEBUGPRINT("Importing new seeddata file (${TARGET_SEEDDATA})...\n");
system ( "sh '${sCommandPath}' url='${opt_url}' username='${opt_username}' password='${opt_password}' cmd=import mode=overwrite file='${TARGET_SEEDDATA}'" );
if ($? == -1) {
	die "Could not import the latest seeddata file (${TARGET_SEEDDATA}).";
}


#########################################################
#
# STEP 6. Manage the target for the test
# - parse template target
# - replace run-time information
# - delete existing target
# - import new target
#
DEBUGPRINT ("##########\nSTEP 6. Manage the target for the test\n");

# open target files:
if ( ! open ( TTF, "${templateTarget}") ) {							# Template to read
	die "Could not open the target template file for reading ($templateTarget)!";
}
if ( ! open ( TCF, ">${TARGET_TARGET}") ) {							# Target to write
	die "Could not open the target's target file for writing ($TARGET_TARGET)!";
}

# loop through the seeddata template file, looking for the values to replace
while ( <TTF> ) {
	if ( $_ =~ m/TARGETNAME/ ) {
		$_ =~ s/TARGETNAME/${TARGET}/;
	}

	if ( $_ =~ m/TARGETPATH/ ) {
		$_ =~ s/TARGETPATH/${CT_targetPath}/;
	}

	if ( $_ =~ m/TARGETNAMESPACE/ ) {
		$_ =~ s/TARGETNAMESPACE/${TARGET}/;						# host name from Yahoo JSON file
	}

	if ( $_ =~ m/SEEDDATANAME/ ) {
		$_ =~ s/SEEDDATANAME/${CT_seeddataFile}/;				# the path to the seeddata files stored in CT
	}

	if ( $_ =~ m/SEEDDATAPATH/ ) {
		$_ =~ s/SEEDDATAPATH/${CT_seeddataPath}/;				# the path to the seeddata files stored in CT
	}

	print ( TCF "$_");
}

#close the files
close( TTF );
close( TCF );

if ( defined($opt_removeOldCTFiles) ) {
	DEBUGPRINT("Deleting existing target (${CT_targetPath}${TARGET})...\n");
	system( "sh '${sCommandPath}' url='${opt_url}' username='${opt_username}' password='${opt_password}' cmd=delete type=target name='${CT_targetPath}${TARGET}'");
	if ($? == -1) {
		die "Could not delete the existing target file (${CT_targetPath}${TARGET})";
	}
}

# Import the new target to CloudTest:
DEBUGPRINT("Importing new target (${TARGET_TARGET})...\n");
system ( "sh '${sCommandPath}' url='${opt_url}' username='${opt_username}' password='${opt_password}' cmd=import mode=overwrite file='${TARGET_TARGET}'" );
if ($? == -1) {
	die "Could not import the latest target file (${TARGET_TARGET}).";
}

#########################################################
#
# STEP 7. Manage the clip for the test
# - parse template clip
# - replace run-time information
# - delete existing clip
# - import new clip
#
DEBUGPRINT ("##########\nSTEP 7. Manage the clip for the test\n");

# Elements in the clip tempalte that need to be swapped out:
# CLIPNAME
# CLIPPATH
# TARGETLOCATION == TARGETNAME (TARGETNAME) 
# TARGETNAME
# TARGETPATH
# URL for the request
DEBUGPRINT("Parsing the template clip file for the current test...\n");
# open clip files:
if ( ! open ( TTF, "${templateClip}") ) {							# Template to read
	die "Could not open the clip template file for reading ($templateClip)!";
}
if ( ! open ( TCF, ">${TARGET_CLIP}") ) {							# Target to write
	die "Could not open the clip target file for writing ($TARGET_CLIP)!";
}

# loop through the seeddata template file, looking for the values to replace
while ( <TTF> ) {
	if ( $_ =~ m/CLIPNAME/ ) {
		$_ =~ s/CLIPNAME/${CT_clipFile}/g;
	}

	if ( $_ =~ m/CLIPPATH/ ) {
		$_ =~ s/CLIPPATH/${CT_clipPath}/;
	}

	if ( $_ =~ m/TARGETNAME/ ) {
		$_ =~ s/TARGETNAME/${TARGET}/g;
	}

	if ( $_ =~ m/TARGETPATH/ ) {
		$_ =~ s/TARGETPATH/${CT_targetPath}/g;
	}

	if ( $_ =~ m/TARGETLOCATION/ ) {
		$_ =~ s/TARGETLOCATION/${TARGET}/g;
	}

	if ( $_ =~ m/TARGETNAMESPACE/ ) {
		$_ =~ s/TARGETNAMESPACE/${TARGET}/g;						# host name from Yahoo JSON file
	}

	if ( $_ =~ m/SEEDDATANAME/ ) {
		$_ =~ s/SEEDDATANAME/${CT_seeddataFile}/g;				# the path to the seeddata files stored in CT
	}

	if ( $_ =~ m/SEEDDATAPATH/ ) {
		$_ =~ s/SEEDDATAPATH/${CT_seeddataPath}/g;				# the path to the seeddata files stored in CT
	}

	print ( TCF "$_");
}

#close the files
close( TTF );
close( TCF );

if ( defined($opt_removeOldCTFiles) ) {
	DEBUGPRINT("Deleting existing target (${CT_clipPath}${CT_clipFile})...\n");
	system( "sh '${sCommandPath}' url='${opt_url}' username='${opt_username}' password='${opt_password}' cmd=delete type=clip name='${CT_clipPath}${CT_clipFile}'");
	if ($? == -1) {
		die "Could not delete the existing clip file (${CT_clipPath}${CT_clipFile})";
	}
}

# Import the new target to CloudTest:
DEBUGPRINT("Importing new clip (${TARGET_CLIP})...\n");
system ( "sh '${sCommandPath}' url='${opt_url}' username='${opt_username}' password='${opt_password}' cmd=import mode=overwrite file='${TARGET_CLIP}'" );
if ($? == -1) {
	die "Could not import the latest target file (${TARGET_CLIP}).";
}



#########################################################
#
# STEP 8. Manage the test composition
# - parse template composition
# - replace run-time information
# - check for existing & rename (last) + overwrite : will always have to check for last and remove before rename
# - import new composition
#
# A. Check the compositions for ours
# - remove if there
#
DEBUGPRINT ("##########\nSTEP 8. Manage the test composition\n");

# open target files:
if ( ! open ( TTF, "${templateComposition}") ) {							# Template to read
	die "Could not open the composition template file for reading ($templateComposition)!";
}
if ( ! open ( TCF, ">${TARGET_COMPOSITION}") ) {							# Target to write
	die "Could not open the composition target file for writing ($TARGET_COMPOSITION)!";
}

# loop through the composition template file, looking for the values to replace
while ( <TTF> ) {

	# Do all the scenario template swap-outs here

	if ( $_ =~ m/LOCATION/ ) {
		$_ =~ s/LOCATION/${LOCATION_DEFAULT}/g;
	}

	if ( $_ =~ m/PREVIEWMODE/ ) {
		$_ =~ s/PREVIEWMODE/${PREVIEWMODE_DEFAULT}/g;
	}

	if ( $_ =~ m/COMPOSITIONNAME/ ) {
		$_ =~ s/COMPOSITIONNAME/${CT_compositionFile}/g;
	}

	if ( $_ =~ m/COMPOSITIONPATH/ ) {
		$_ =~ s/COMPOSITIONPATH/${CT_compositionPath}/g;
	}

	if ( $_ =~ m/DASHBOARDPATH/ ) {
		$_ =~ s/DASHBOARDPATH/${CT_dashboardPath}/g;
	}

	if ( $_ =~ m/CLIPPATH/ ) {
		$_ =~ s/CLIPPATH/${CT_clipPath}/g;
	}
	
	if ( $_ =~ m/CLIPNAME/ ) {
		$_ =~ s/CLIPNAME/${CT_clipFile}/g;
	}

	if ( $_ =~ m/AUTOSTOPTIME/ ) {
		$_ =~ s/AUTOSTOPTIME/${testDurationMS}/g;
	}

	if ( $_ =~ m/VUSERCOUNT/ ) {
		$_ =~ s/VUSERCOUNT/${vuserCount}/g;
	}

	if ( $_ =~ m/PACINGMS/ ) {
		$_ =~ s/PACINGMS/${pacingMS}/g;
	}

	print ( TCF "$_");
}

#close the files
close( TTF );
close( TCF );

if ( defined($opt_removeOldCTFiles) ) {

	DEBUGPRINT("Deleting old composition file (${CT_compositionPath}${CT_compositionFile})...");
	system( "sh '${sCommandPath}' url='${opt_url}' username='${opt_username}' password='${opt_password}' cmd=delete type=composition name='${CT_compositionPath}${CT_compositionFile}'");
	if ($? == -1) {
		die "Could not delete the existing composition file (${CT_compositionPath}${CT_compositionFile})";
	}
}

# Import the new composition to CloudTest:
DEBUGPRINT("Importing new composition file (${TARGET_COMPOSITION})...\n");
system ( "sh '${sCommandPath}' url='${opt_url}' username='${opt_username}' password='${opt_password}' cmd=import mode=overwrite file='${TARGET_COMPOSITION}'" );
if ($? == -1) {
	die "Could not import the latest composition (${TARGET_COMPOSITION}).";
}



#########################################################
#
# STEP 9. Launch composition
#
if ( defined( $opt_run ) ) {
	DEBUGPRINT ("##########\nSTEP 9. Launch composition\n");
	
	DEBUGPRINT("Launching the test composition (${CT_compositionFile})...\n");
	system ( "sh '${sCommandPath}' url='${opt_url}' username='${opt_username}' password='${opt_password}' cmd=play name=${CT_compositionPath}${CT_compositionFile} wait=yes" );
	if ($? == -1) {
		die "Could not run the composition (${TARGET_COMPOSITION}).";
	}
}


#########################################################
#
# STEP 10. Capture result & report
# - Use BuildNotifier? Can it be used in a non-Jenkins setting?
# - 
# DEBUGPRINT ("##########\nSTEP 10. Capture result & report\n");


exit 0;

################################################
#
# UTILITY FUNTIONCTIONS
#

sub CommandLineProcess
{
	my $fatal = 0;

	our ($opt_debugger, $opt_run, $opt_rps, $opt_duration, $opt_url, $opt_jsonfile, $opt_username, $opt_password, $opt_outputfile, $opt_removeOldCTFiles);

	GetOptions( "help",  "run=i", "rps=i", "duration", "jsonfile=s", "debugger=i", "composition=s", "username=s", "password=s", "url=s", "outputfile=s", "removeOldCTFiles") || ScriptHelp();

	if ( defined($opt_help) ) {
		ScriptHelp();
	}

	if ( ! defined($opt_url) ) {
		warn "The option -url http://hostname/concerto is a mandatory argument.";
		if ( ! defined( $default_CloudTest_url ) ) {
			$fatal++;
		} else {
			if ( $ALLOW_DEFAULTS ) {
				warn "overriding url with the default value ($default_CloudTest_url).";
				$opt_url = $default_CloudTest_url;
			} else {
				$fatal++;
			}
		}
	}

	# check for a well formed URL:
	if ( defined($opt_url) ) {
		if ( $opt_url !~ m/http:\/\/.*\/[C,c]oncerto/ ) {
			warn "the specified url is not a valid CloudTest URL.";
			$fatal++;
		}
	}

	if ( ! defined($opt_username) ) {
		warn "The option -username is a mandatory argument.";
		if ( ! defined( $default_CloudTest_username) ) {
			$fatal++;
		} else {
			if ( $ALLOW_DEFAULTS ) {
				warn "overriding username the default value ($default_CloudTest_username).";
				$opt_username = $default_CloudTest_username;
			} else {
				$fatal++;
			}
 		}
	}

	if ( ! defined($opt_password) ) {
		warn "The option -password is a mandatory argument.";
		if ( ! defined( $default_CloudTest_password) ) {
			$fatal++;
		} else {
			if ( $ALLOW_DEFAULTS ) {
				warn "overriding password the default value.";
				$opt_password = $default_CloudTest_password;
			} else {
				$fatal++;
			}
		}
	}

	# Handle the input file setup:
	if ( defined($opt_jsonfile) ) {
		if (! -e $opt_jsonfile ) {
			warn "File ($opt_jsonfile) does not exist";
			$fatal++;
		}
	} else {
		if ( $ALLOW_DEFAULTS ) {
			$opt_jsonfile = $default_filename;
		} else {
			$fatal++;
		}
	}

	# Handle the output file setup:
	if ( defined($opt_outputfile) ) {
		if ( $opt_outputfile =~ m/(.*)\.csv/ ) {
			if ( -e $opt_outputfile ) {
				DEBUGPRINT ("$opt_outputfile exists with csv suffix. Renaming existing file to ${1}_csv.old\n");
			}
			else {
				DEBUGPRINT ("File does not exist with .csv suffix, will create new file: $opt_outputfile\n");
			}
		} else {
			if ( -e $opt_outputfile ) {
				if ( $opt_outputfile =~ m/\(.*\)\.\(...\)/ ) {

				}
				DEBUGPRINT ("Will append .csv to filename and create new file: ${opt_outputfile}.csv\n");
			}
		}
	} else {
		warn "The option -outputfile is a required argument, so that we can generate the CSV file.";
		if ( defined( $default_outputFile ) ) {
			if ( $ALLOW_DEFAULTS ) {
				warn "overriding outputfile with the default value ($default_outputFile).";
				$opt_outputfile = $default_outputFile;
			} else {
				$fatal++;
			}
		} else {
			$fatal++;
		}
	}

	if ( defined($opt_debugger) ) {
		$DEBUG = $opt_debugger;
	}

	if ( $fatal ) {
		die;
	}
}

# for verbose logging of information when in debug mode only (specify -d 1 on the command-line, to enable)
sub DEBUGPRINT
{
	my ($toPrint) = (@_);

	if ( $DEBUG ) {
		print "$toPrint";
	}
}

sub ScriptHelp
{
	print "\n";
	print "jsonparse: Usage\n";
	print "\t-jsonfile [path+filename]\tThe JSON file to parse ($default_filename).\n";
	print "\t-run\tRun the test composition\n";
	print "\t-rps [#]\tThe target requests per second\n";
	print "\t-duration [#]\tThe test duration in minutes.\n";
	print "\t-url [CLOUDTEST SERVER URL]\tA valid URL - http://hostname/concerto ($default_CloudTest_url)\n";
	print "\t-username [CLOUDTEST USER NAME]\tCloudtest user name ($default_CloudTest_username)\n";
	print "\t-password [CLOUDTEST PASSWORD]\tCloudtest users password ($default_CloudTest_password()\n";
	print "\t-outputfile [path+filename]\tA backup CSV file ($default_outputFile)\n";
	print "\t-debugger #\t(optional)\tOutput debugging information.\n";

	exit( -1 );
}

sub ConvertMins2Millis
{
	my ($min) = @_;
	my ($millis) = int (( $min * 60 ) * 1000);

	return $millis;
}
