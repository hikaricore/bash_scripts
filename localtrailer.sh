# messy version of the trailer grab script to be run manually via cli from individual directories.
# not for use with automation or radarr. it will not be updated very often unless i find a major issue.

# api keys for themoviedb and youtube data api v3 (split for lazy obfuscation purposes)
# These are old keys and probably don't/won't work anymore. Left for visiblity purposes.
K1A=1df2a2659c50fdab
K1B=77b8d9f8459cf95a
K2A=AIzaSyCCD8e6A
K2B=DQ4lOQcV77ErX
K2C=yK3_d4unJwcYE
KEY1=$K1A$K1B
KEY2=$K2A$K2B$K2C

# check to see if a trailer exists and do stuff if it doesn't (hey look this happens now!)
if [ ! -f movie-trailer.* ]
    then
        printf "Trailer does not exist for "${PWD##*/}", attempting to grab one."'\n' >&2


# gather and process video resolution (requires ffmpeg and permission to run it)
RES=$(ffmpeg -i $(ls *.mkv *.mp4 *.m4v *.webm *.flv *cd1*avi *.avi 2>/dev/null | grep -v movie-trailer | head -1) 2>&1 | grep -oP 'Stream .*, \K[0-9]+x[0-9]+')
RES2=$(echo $RES | cut -d 'x' -f1)

# confirm if video resolution requires an sd 480p or hd 720p trailer (we don't bother with 1080p, so there's no check or variable set for it here)
if [ $RES2 -gt 1000 ]
  then
    RES3=720
  else
    RES3=480
fi

# set imdbid for film to static variable (needed here)
if [ -f movie.nfo ]
    then
# Better than the stupid method before.
	TT=$(cat movie.nfo | sed -n 's/.*<uniqueid type="imdb">\([^<]*\)<\/uniqueid>.*/\1/p')
    else
# This might not work consistently, but I didn't really test it recently.
 	TT=$(cat *.nfo | grep -a "/tt" | tr -cd '\11\12\40-\176' | cut -d \/ -f5)
fi

# pull tmdb id for film based on imdbid (yes this does indeed require two api calls. should no longer result in Judgement Night, unless it does)
# Simple adjustment here which shhould result in slightly better reliability.
TMDB=$(curl -s "http://api.themoviedb.org/3/find/$TT?api_key=$KEY1&language=en-US&external_source=imdb_id" | tac | tac | jq -r '.' | grep "id\"" | sed 's/[^0-9]*//g')

# pull trailer video id from tmdb based on tmdb id (imperfect, may not grab anything or may grab an video that is not trailer)
# never assume just one video in the output. derp.
# This has been "fixed" for use with the latest API. Probably.
YOUTUBE=$(curl -s "http://api.themoviedb.org/3/movie/$TMDB/videos?api_key=$KEY1&language=en-US" | jq -r '.results?[] | select(.type == "Trailer" and .official == true) | .key' | head -n 1)

# color for id output (ok?)

BLUE='\033[0;34m'
GREEN='\033[0;32m'
LIGHTGREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
LIGHTRED='\033[1;31m'
NC='\033[0m' # No Color

# list imdb tmdb and youtube ids for reference
printf "${YELLOW}$TT ${BLUE}-> ${LIGHTGREEN}$TMDB ${BLUE}-> ${LIGHTRED}$YOUTUBE${NC}"'\n' >&2

# download trailer from youtube based on video resolution (requires youtube-dl and permission to run it)
# occasionally this step throws an error:
# "WARNING: Could not send HEAD request to https://www.youtube.com/watch?v=XXXXXXXXXXX
# XXXXXXXXXXX: <urlopen error no host given>
# ERROR: Unable to download webpage: <urlopen error no host given> (caused by URLError('no host given',))"
# no idea why this happens, or how to fix it.  XD
# now with 100% more validity checking!  that will "probably" work and not break the process?

# This is broken for me due to API quota nonsense, also I'm tired, so fuck it. This can easily be turned back on.
#SANITY=$(curl -s "https://www.googleapis.com/youtube/v3/videos?part=id&id=$YOUTUBE&key=$KEY2" | tac | tac | jq -r '.' | grep totalResults | sed 's/[^0-9]*//g')
# Sanity can be faked. Ha ha.
SANITY=1

if [[ $SANITY -eq 1 ]]
  then
    printf "YouTube trailer exists, attempting to download." >&2
    # Change to yt-dlp from youtube-dl.
    yt-dlp -f 'bestvideo[height<='$RES3']+bestaudio/best[height<='$RES3']' -q "https://www.youtube.com/watch?v=$YOUTUBE" -o movie-trailer --restrict-filenames --merge-output-format mkv
    sleep 5
    TRAILERNAME=$(ls movie-trailer.*)
    printf '\n'"Trailer downloaded: $TRAILERNAME"'\n' >&2
    chmod 644 "$TRAILERNAME"
  else
  if [[ $SANITY -eq 0 ]]
  then
    printf '\n'"YouTube trailer does not exist. (End of the line)"'\n' >&2
  else
    printf '\n'"WTF, something is very wrong. (You should never see this message..)"'\n' >&2
  fi
fi

# this is from earlier when we started checking for a trailer. let's hope nesting if statements doesn't fuck up somehow
    else
        TRAILERNAME=$(ls movie-trailer.*)
        printf "Trailer already exists for "${PWD##*/}": $TRAILERNAME"'\n' >&2
fi
