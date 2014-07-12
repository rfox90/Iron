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

#DATA SOURCE NAME
my $dsn = "dbi:mysql:$database:$host:$port";

if(!-d $input_path) {
	die('Input path not valid');
}
if(!-d $output_path) {
	die('Output path not valid');
}
my $dbh;
if($use_database) {
	$dbh = DBI->connect($dsn, $user, $password) or die "No DB";
} else {
	$dbh = undef;
}

sub parseExisting {
	opendir(OUT_DIR, $output_path) or die $!;
	while (my $name = readdir(OUT_DIR)) {
		next if($name=~ m/\.+$/);
		push(@dir,$name);
	}
	closedir(OUT_DIR);
}

sub examineMods {

	opendir(IN_DIR, $input_path) or die $!;
	my $matched = 0;
	my $unmatched = 0;
	my $total = 0;

	while (my $file = readdir(IN_DIR)) {
		next if($file=~ m/\.+$/);
		my $search = lc($file);
		$search =~ s/\-universal//;
		print $file . "\n";
		
		#TODO: Regex not my forte
		my ($name,$version) = $search =~ m/([\D]*)((_|-| |v|rv|[\d]{1}).*)\.(jar|zip)/;
		print "$name|$version\n";
		if($name && $version) {
			$matched++;
			($name,$version) = cleanMod($name,$version);
			print "$name|$version\n";
		} else {
			#TODO: Regex not my forte
			my $mcversion;
			my $pork;
			($mcversion,$pork,$name,$version) = $search =~ m/(1\.6\.[\d]{1}( |_))([\D]*)((_|-| |v|rv|[\d]{1}).*)\.(jar|zip)/;
			if($name && $version) {
				($name,$version) = cleanMod($name,$version);	
				print "$mcversion\n$name\n $version\n $pork";
				$matched++;
			} else {
				print "$file\n";
				$total ++;
				next;
			}
		}
		my $mod;
		$mod->{name} = $name;
		$mod->{version} = $version;
		$mod->{file} = $file;
		push(@mods, $mod);
		$total ++;
	}
	print "parsed/total files\n";
	print "$matched/$total\n";
}

sub cleanMod {
	my($name,$version) = @_;
	#Applied energistics and Biblocraft need to use semantic versioning, as does natura!
	if($name =~ m/(rv|v|mc)$/) {
		#see if our name ends in V or RV and add it to the version
		my ($versionAdditive)= $name =~ m/(rv|v|mc)$/;
		$name =~ s/(rv|v|mc)$//;
		$version = $versionAdditive.$version;
	}
	#TODO: Regex not my forte
	#These all need reviewing, cant even remember what they do.
	$name =~ s{(\-|\_)(?!.*(\-|\_))}{}is; # remove any slashes or underscores from the end of the name
	$name =~ s{(\[)(?!.*(\[))}{}is; # remove any brackets
	$name =~ s{ (?!.* )}{}is;#Strip last space
	$name =~ s{\-(?!.*\-)}{}is; #last slash again for some reason (TM)
	$name =~ s/('|")//g; #Get rid of fancy mods and their fancy names
	$name =~ s/ /-/g; #Any remaining space gets changed to a dash
	$version =~s{(\])(?!.*(\]))}{}; #Get rid of brackets
	$version =~ s/^ //; #get rid of spaces on the front
	$version =~ s/ //g; # get rid of spaces in the middle
	$version =~ s/('|"|\+)//g; #Get rid of fancy mods and their fancy names
	$name =~ s/^\-//;
	my @ret;
	push(@ret,$name);
	push(@ret,$version);
	return @ret;
}

sub compareMods {
	my($a,$b) = @_;
	return 0 if(!$a || !$b) ;
	return 1 if($a eq $b) ;
	return 1 if(distance($a,$b)<=2) ;
}

sub checkDBForMod {
	my($mod) = @_;
#	print "Checking DB for $mod\n";
	my $sql = "select name from mods where name=?";
	my $firstPass = $dbh->prepare($sql);

	$firstPass->execute($mod);
	if($firstPass && $firstPass->rows() > 0) {
		my($dbMod) = $firstPass->fetchrow_array();
		if(compareMods($dbMod,$mod)) {
			return $mod;
		}
	}
}

sub findClosestDBMatch {
	my($mod) = @_;
	print "Finding closest mod for $mod\n";
	my $sql = "select name from mods";
	my $secondPass = $dbh->prepare($sql);
	$secondPass->execute();
	while(my($dbMod) = $secondPass->fetchrow_array()) {
		if($dbMod eq $mod) {
			$secondPass->finish();
			return $mod;
		} elsif (distance($dbMod,$mod)<=2) {
			$secondPass->finish();
			return $dbMod;
		}
	}
	$secondPass->finish();
	return undef;
}

sub addModToDB {
	my($mod) = @_;
	print "Adding $mod to the database\n";
	my $sql = "insert into mods(name,pretty_name) values(?,?)";
	my $insertSth = $dbh->prepare($sql);
	$insertSth->execute($mod,$mod);
}

sub checkForExistingVersion {
	my($mod,$version) = @_;
	my $modid = getModID($mod);
	if($modid) {
		my $sql = "select * from modversions where mod_id=? and version=?";
		my $sth = $dbh->prepare($sql);
		$sth->execute($modid,$version);
		return 1 if($sth && $sth->rows()>0);
		return 0;
	} 
	return 0;
}

sub addVersion {
	my($mod,$version,$file) =@_;
	my $file_md5 = file_md5_hex($file);
	if(!checkForExistingVersion($mod,$version)) {
		print "Adding $mod version $version \n";
		my $id = getModID($mod);
		my $sql = "insert into modversions(mod_id,version,md5) values(?,?,?)";
		my $sth = $dbh->prepare($sql);
		$sth->execute($id,$version,$file_md5);
		if($sth) {
			return 1;
		} else {
			return 0;
		}
	} else {
		print "updating hash\n";
		my $id = getModID($mod);
		my $sql = "update modversions set md5=? where mod_id=? and version=?";
		my $sth= $dbh->prepare($sql);
		$sth->execute($file_md5,$id,$version);
		if($sth) {
			return 1;
		} else {
			return 0;
		}
	}
}


sub getModID {
	my($mod) = @_;
	my $sql = "select id from mods where name=?";
	my $sth = $dbh->prepare($sql);
	$sth->execute($mod);
	my($modid) = $sth->fetchrow_array();
	return $modid;
}

sub prepare {
	my $total = 0;
	my $matched = 0;
	MOD: foreach ( sort {$a->{name} cmp $b->{name}} @mods) {
		print "Checking $_->{name}\n";
	 	my $matchedFlag = 0;
	 	my $dirMatch = "";
	 	DIR: foreach my $dir (@dir) {
	 		if(compareMods($dir,$_->{name})) {
	 			$matchedFlag = 1;
	 			$matched++;
	 			$dirMatch = $dir;
	 			last DIR;
	 		} else {
	 			$dirMatch = $dir;
	 		}
	 	}
	 	$total++;

	 	my $foundMod;
	 	if(!$matchedFlag) {
	 		$foundMod = $_->{name};
	 	} else {
	 		$foundMod = $dirMatch;
	 	}
	 	if($use_database) {
		 	if(!checkDBForMod($foundMod)) {
		 		my $closest = findClosestDBMatch($foundMod);
		 		if(!$closest) {
		 			addModToDB($foundMod)
		 		} else {
		 			$foundMod = $closest;
		 		}
		 	}
		}
		if(!$foundMod) {
			print "NO FOUND MOD\n";
			next MOD;
		}
	 	my $fullPath = "$output_path$foundMod";
	 	print "Final Path Result is $fullPath\n";
	 	unless(-d "$fullPath") {
	 		mkdir "$fullPath";
	 	}
		unless(-d "$fullPath./$foundMod-$_->{version}") {
			mkdir($fullPath."/$foundMod-$_->{version}");
			unless(-d $fullPath."/$foundMod-$_->{version}/mods/") {
				mkdir($fullPath."/$foundMod-$_->{version}/mods/");
			}
		}
		print "$input_path$_->{file} $fullPath/$foundMod-$_->{version}/mods/$_->{file}\n";
		if(-e "$fullPath/$foundMod-$_->{version}.zip" && !$force_generate) {
			if($use_database || checkForExistingVersion($foundMod,$_->{version})) {
				print "$foundMod-$_->{version} is already cached and available in solder\n";
			} else {
				print "Found the files but adding $_->{version} as it was missing from the database\n";
				addVersion($foundMod,$_->{version},"$fullPath/$foundMod-$_->{version}.zip");
			}
		} else {
			print "No file no version a completely new file\n";
			if(copy("$input_path$_->{file}","$fullPath/$foundMod-$_->{version}/mods/$_->{file}")) {
				chdir("$fullPath/$foundMod-$_->{version}");
				system("zip -r $foundMod-$_->{version}.zip ./*");
				move("$foundMod-$_->{version}.zip","../");
				if($use_database) {
					addVersion($foundMod,$_->{version},"$fullPath/$foundMod-$_->{version}.zip");
				}
			} else {
				print "Could not copy to output folder\n";
			}
		}
	}
 	print "$matched/$total\n";
}
parseExisting();
examineMods();
prepare()


