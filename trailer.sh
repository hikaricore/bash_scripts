#!/bin/bash

# script requires ffmpeg and youtube-dl + permission to run them
# script is imperfect and quite assumptive that everything is where it should be
# script expects you are using radarr to move your videos to the final path and that this process has completed
# script don't give a damn if there is no trailer on tmdb, it will run all the way through like a wrecking ball of failure, hell sometimes it downloads the trailer for 1993's Judgment Night just for kicks (not kidding, it really does this)
# script will try to write to movie-trailer.mkv unless youtube-dl wants to do something else...

# api keys for themoviedb and youtube data api v3 (split for lazy obfuscation purposes)
KEY1A=1a7373301961d03f
KEY1B=97f853a876dd1212
KEY2A=AIzaSyAY4Xh64
KEY2B=Ffci_plHFzeqb
KEY2C=aYNASLqKN0-hE
KEY1=$KEY1A$KEY1B
KEY2=$KEY2A$KEY2B$KEY2C

echo $KEY1
echo $KEY2

# wait a bit to be safe (who knows if radarr is done or not)
sleep 60

# gather and process video resolution (requires ffmpeg and permission to run it)
RES=$(ffmpeg -i $radarr_moviefile_path 2>&1 | grep -oP 'Stream .*, \K[0-9]+x[0-9]+')
RES2=$(echo $RES | cut -d 'x' -f1)

# confirm if video resolution requires an sd 480p or hd 720p trailer (we don't bother with 1080p, so there's no check or variable set for it here)
if [ $RES2 -gt 1000 ]
  then
    RES3=720
  else
    RES3=480
fi

# set imdbid for film to static variable (because why the hell not)
TT=$radarr_movie_imdbid

# pull tmdb id for film based on imdbid (yes this does indeed require two api calls. should no longer result in Judgement Night, unless it does)
TMDB=$(curl -s "http://api.themoviedb.org/3/find/$TT?api_key=1a7373301961d03f97f853a876dd1212&language=en-US&external_source=imdb_id" | tac | tac | jq -r '.' | grep "id\"" | sed 's/[^0-9]*//g')

# pull trailer video id from tmdb based on tmdb id (imperfect, may not grab anything or may grab an video that is not trailer)

YOUTUBE=$(curl -s "http://api.themoviedb.org/3/movie/$TMDB/videos?api_key=1a7373301961d03f97f853a876dd1212" | tac | tac | jq -r '.' | grep key | cut -d \" -f4)

# download trailer from youtube based on video resolution (requires youtube-dl and permission to run it)
# occasionally this step throws an error:
# "WARNING: Could not send HEAD request to https://www.youtube.com/watch?v=XXXXXXXXXXX
# XXXXXXXXXXX: <urlopen error no host given>
# ERROR: Unable to download webpage: <urlopen error no host given> (caused by URLError('no host given',))"
# no idea why this happens, or how to fix it.  XD
# now with 100% more validity checking!  that will "probably" work and not break the process?

SANITY=$(curl -s "https://www.googleapis.com/youtube/v3/videos?part=id&id=$YOUTUBE&key=$KEY2" | tac | tac | jq -r '.' | grep totalResults | sed 's/[^0-9]*//g')

if [[ $SANITY -eq 1 ]]
  then
    #echo "Video exists."
    youtube-dl -f 'bestvideo[height<='$RES3']+bestaudio/best[height<='$RES3']' -q "https://www.youtube.com/watch?v=$YOUTUBE" -o $radarr_movie_path/movie-trailer --restrict-filenames --merge-output-format mkv
  else
  if [[ $SANITY -eq 0 ]]
  then
    echo "Video does not exist."
  else
    echo "WTF. Something is very wrong."
  fi
fi

#youtube-dl -f 'bestvideo[height<='$RES3']+bestaudio/best[height<='$RES3']' -q "https://www.youtube.com/watch?v=$YOUTUBE" -o $radarr_movie_path/movie-trailer --restrict-filenames --merge-output-format mkv

# as a final note the script doesn't bother to check for existing trailers. ¯\_(ツ)_/¯
# as a final final note you probably shouldn't leave the "shruggie" in the previous line, it could break something
