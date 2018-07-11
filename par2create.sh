#!/bin/bash

# This script creates an MD5 hash and PAR2 sets for individual files within a rom set.
# It is intended to be operated from individual directories containing rom sets in the 7zip format. I recommend placing it on the directory nested below this .. and runing it from there.
# Though I guess there's nothing stopping you from shoving all your sets into one massive unorganized directory like fucking savage.
#
# If an MD5 file exists for the archive, the md5sum is run on the applicable rom archive to check for a match.
#   If the MD5 hash matches the set is indicated as accurate onscreen, and we move on to the next rom archive.
#   If the MD5 hash does not match 7zip is used to check the rom archive for errors.
#   If errors are found by 7zip the set is indicated as inaccurate onscree, and we move on to the next rom archive.
#   If no errors are found a new PAR2 set and MD5 hash are created in that order. This accomidates valid updates to a rom archive.
# If an MD5 file does not exist for the archive 7zip is used to check the rom archive for errors.
#   If errors are found by 7zip the set is indicated as inaccurate onscreen, and we move on to the next rom archive.
#   If no errors are found a PAR2 set and MD5 hash are created in that order. This ensures there is never an MD5 hash present without a PAR2 set being created.
# If something goes wrong a purple notification will appear onscreen.  There shouldn't be any reason for this to happen.
#
# At the end of any erroneous run, the script will attempt to open pico (nano) to display a file (romdataerrors.txt) contanting information on the errors so you don't have to watch or scroll the output.
# If you don't have an alias for nano called pico, you'll probably just want to edit any references outside of comments from pico to nano.
#
# The script outputs information during the process in the below format:
# 02:06:59 2018-07-11 • Rom Set Name.7z • Set does not need scanned or updated. • (1/9388)
#
# The notification to the right of the set name will appear in one of the following colors:
# Green = Things are good!
# Light Blue = Something is being checked. 
# Red = Things are bad!
# Purple = Something is wrong, but not for certain bad?  This color happens when the script breaks somehow, if it even keeps running at that point.  IDK.
#
# One known issue with this script is that the % symbol in a filename messes up the status output for a line and a half.
# This is due to the current setup of "printf" commands.  It has zero impact on the processing and creation of MD5/PAR2 so I didn't fix it.
# I mean, I tried to fix it, but I was fairly tired of tinkering with the damn mess and gave up/reverted at the first sign of trouble.
# 
# I'm probably not going to fix this script if something doesn't work for you, it's just here to be here incase anyone wants it.  I also didn't spell check any of this prefacing commentary.  It's like 2am and the baby woke me up at 6am yesterday.  D:
#
# As a word of caution, you should always have a backup of your rom sets incase something goes horribly wrong (like a typo in a script for example), this script is just a preventative measure.

export IFS=$'\n' && 

currentdir="${PWD##*/}"
parbasedir="/media/rom/zPAR2/"
count="0"
total=$(ls -1 *.7z | wc -l)

WHITE='\033[1;37m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
LIGHTBLUE='\033[1;34m'
PURPLE='\033[1;34m'
ORANGE='\033[0;33m'
DARKGREY='\033[1;30m'
LIGHTRED='\033[1;31m'

NC='\033[0m' # No Color

mkdir -p "$parbasedir$currentdir"

for i in $(ls *.7z); do

	((count++))

	if md5sum -c "$parbasedir$currentdir"/"$i".md5 --quiet --status >/dev/null 2>&1 ; then

		printf "${DARKGREY}$(date +%T\ %F) ${BLUE}• ${WHITE}$i ${BLUE}• ${GREEN}Set does not need scanned or updated. ${BLUE}• ${ORANGE}($count/$total)${NC}\n"

	else

		printf "${DARKGREY}$(date +%T\ %F) ${BLUE}• ${WHITE}$i ${BLUE}• ${LIGHTBLUE}Set is being scanned for errors or needed updates. ${BLUE}• ${ORANGE}($count/$total)${NC}\n"

	        7z t "$i" | grep -q Error
	        greprc=$?
	                if [[ $greprc -eq 0 ]] ; then
        	                #echo $(ls -la "$i")    
	                        printf "${RED}$(date +%T\ %F) ${WHITE}• ${LIGHTRED}$i ${WHITE}• ${RED}Set contains a Data Error and requires manual review. ${WHITE}• ${LIGHTRED}($count/$total)${NC}\n"
                	        printf "__________ \n\n"
				echo "$currentdir/$i" >> romdataerrors.txt 
        	        else
	                if [[ $greprc -eq 1 ]] ; then # no errors
        	                par2create -q -q -r5 -l "$i" "$i" >/dev/null 2>&1 # write par set first
                	        md5sum "$i" > "$parbasedir$currentdir"/"$i.md5" # write CRC last to prevent false security after a cancelled process
				mv "$i"*.par2 "$parbasedir$currentdir" >/dev/null 2>&1 # because apparently some versions of par2 can't do create a par set outside of the basepath..
				printf "${DARKGREY}$(date +%T\ %F) ${BLUE}• ${WHITE}$i ${BLUE}• ${GREEN}PAR2 & MD5 files have been generated for this set. ${BLUE}• ${ORANGE}($count/$total)${NC}\n" #echo (printf) about it or whatever.
				printf "__________ \n\n"
	                else
                	        printf "${DARKGREY}$(date +%T\ %F) ${BLUE}• ${WHITE}$i ${BLUE}• ${PURPLE}grep has somehow failed. what the fuck? ${BLUE}• ${ORANGE}($count/$total)${NC}\n" # grep error
				printf "__________ \n\n"
        	        fi
	        fi


	fi

done

if [[ -f romdataerrors.txt ]]; then

	pico romdataerrors.txt

fi
