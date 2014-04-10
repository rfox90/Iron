Iron
====

An Iron to Solder with. Technic Pack Solder file manager written in perl. 

Turns a large collection of .jars and .zips into solder compatible mod listings whilst also optionally keeping the solder database up to date.

A Work in progress!

Tested with a modpack that has over 50 mods.

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
1. Install Dependancies
2. Copy config.yml.sample to config.yml
3. plop your mod files from your non-technic minecraft test instance into the input path
4. Run

Issues
====
I suck at ReGex. Whole thing will break if a mod author names a file weirdly :)
Some mods require additional files to be in mods/ if these are not picked up by the above its likely the pack will break.

