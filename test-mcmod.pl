#! /usr/bin/perl -w
use strict;
use warnings;

use File::Copy;
use Text::LevenshteinXS qw(distance);
use DBI;
use DBD::mysql;
use Digest::MD5::File qw(file_md5_hex);
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use YAML::XS qw/LoadFile/;
use Cwd;
use File::Find::Rule;
use Data::Dumper;
use JSON;

use Archive::Probe;

my $config = LoadFile('config.yml');



#All your lovely zips go here
my $output_path = $config->{locations}->{output} || "/var/www/api/public/mods/";
#Dirty unparsed files from your server and or multimc instance
my $input_path = $config->{locations}->{input} || "/var/www/api/public/input/";



my $modpackVersion = 0.0.1;

my @dir;
my @mods;

my $database = $config->{database}->{database} || "solder";
my $user = $config->{database}->{user} || "solder";
my $password = $config->{database}->{password} || "";
my $port = $config->{database}->{port} || '3306';
my $host = $config->{database}->{hostname} || "localhost";

my $use_database = $config->{options}->{update_database};
my $force_generate = $config->{options}->{force_generate};
my $just_update = $config->{options}->{just_update} || 1;
my $mcmodout = $config->{mcmod} || 1;
#my $mcmodout = $config->{just_mcmod} || 1;

sub testFile {
	my($file) = @_;
	#7za doesn't report success properly so we will look for it next
	system("7za -y -oworking/ x $file mcmod.info");
	my @files = File::Find::Rule->file()
                                  ->name( "mcmod.info" )
                                  ->maxdepth( 2 )
                                  ->in(getcwd().'/working/');
    my $json;
	{
  		local $/; #Enable 'slurp' mode
  		open my $fh, "<", $files[0];
  		$json = <$fh>;
  		close $fh;
	}
	if(length($json)>0) {
		my $data;
		eval {
			$data = decode_json($json);
			
		};
		if($@) {
			print $@;
			return;
		} else {
			return $data;
		}
	} else {
		return;
	}
	system("rm working/mcmod.info");
}

my $res = testFile('./Railcraft_1.6.4-8.4.0.0.jar');
if($res) {
	#print Dumper($res);
	my $data = $res->[0];
	my $authors = join(',',@{$data->{'authors'}});
	print $authors."\n";
} else {
	print "fail";
}