Iron
====

An Iron to Solder with. Technic Pack Solder file manager written in perl.

A Work in progress!

Dependancies
====
* DBI - For Database access
* DBD::mysql - Solder uses mysql
* Text::LevenshteinXS - Fuzzy String matching(guesswork)
* Digest::MD5::File - Solder requires every zip to have a hash
* Archive::Zip - Makes zips
* YAML::XS - Reads config

Usage
====
Install Dependancies
Copy config.yml.sample to config.yml
plop your mod files from your non-technic minecraft test instance into the input path
Run

Issues
====
I suck at ReGex. Whole thing will break if a mod author names a file weirdly :)
Some mods require additional files to be in mods/ if these are not picked up by the above its likely the pack will break.

