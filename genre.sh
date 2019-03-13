#!/bin/bash

sleep 30

K1A=1df2a2659c50fdab
K1B=77b8d9f8459cf95a
KEY1=$K1A$K1B

#TT=$(cat movie.nfo | grep "<id>" | cut -d \< -f2 | cut -d \> -f2)

TT=$radarr_movie_imdbid
IDS=$(curl -s "http://api.themoviedb.org/3/find/$TT?api_key=$KEY1&language=en-US&external_source=imdb_id" | tac | tac | jq '.movie_results[0] .genre_ids')
#IDSC=$(echo $IDS | sed 's/[][]//g' | sed 's/,//g' | sed 's/12/<genre>Adventure<\/genre>\\n/g;s/14/<genre>Fantasy<\/genre>\\n/g;s/16/<genre>Animation<\/genre>\\n/g;s/18/<genre>Drama<\/genre>\\n/g;s/27/<genre>Horror<\/genre>\\n/g;s/28/<genre>Action<\/genre>\\n/g;s/35/<genre>Comedy<\/genre>\\n/g;s/36/<genre>History<\/genre>\\n/g;s/37/<genre>Western<\/genre>\\n/g;s/53/<genre>Thriller<\/genre>\\n/g;s/80/<genre>Crime<\/genre>\\n/g;s/99/<genre>Documentary<\/genre>\\n/g;s/878/<genre>Science Fiction<\/genre>\\n/g;s/9648/<genre>Mystery<\/genre>\\n/g;s/10402/<genre>Music<\/genre>\\n/g;s/10749/<genre>Romance<\/genre>\\n/g;s/10751/<genre>Family<\/genre>\\n/g;s/10752/<genre>War<\/genre>\\n/g;s/10770/<genre>TV Movie<\/genre>\\n/g;/^\s*$/d' |  tr -d ' ' | sed '/^$/d' | sort)
IDSC=$(echo $IDS | sed 's/[][]//g' | sed 's/,//g' | sed 's/12/<genre>Adventure<\/genre>\\n/g;s/14/<genre>Fantasy<\/genre>\\n/g;s/16/<genre>Animation<\/genre>\\n/g;s/18/<genre>Drama<\/genre>\\n/g;s/27/<genre>Horror<\/genre>\\n/g;s/28/<genre>Action<\/genre>\\n/g;s/35/<genre>Comedy<\/genre>\\n/g;s/36/<genre>History<\/genre>\\n/g;s/37/<genre>Western<\/genre>\\n/g;s/53/<genre>Thriller<\/genre>\\n/g;s/80/<genre>Crime<\/genre>\\n/g;s/99/<genre>Documentary<\/genre>\\n/g;s/878/<genre>Science Fiction<\/genre>\\n/g;s/9648/<genre>Mystery<\/genre>\\n/g;s/10402/<genre>Music<\/genre>\\n/g;s/10749/<genre>Romance<\/genre>\\n/g;s/10751/<genre>Family<\/genre>\\n/g;s/10752/<genre>War<\/genre>\\n/g;s/10770/<genre>TV Movie<\/genre>\\n/g;/^\s*$/d' |  tr -d ' ' | sed '/^$/d' | sed 's/ScienceFiction/Science Fiction/g' | sed 's/TVMovie/TV Movie/g' | sort)

sed  '/<\/title>/a '""$(echo $IDSC)""'/' $radarr_movie_path/movie.nfo > $radarr_movie_path/.movie.nfo
cp $radarr_movie_path/movie.nfo $radarr_movie_path/movie.bak
mv $radarr_movie_path/.movie.nfo $radarr_movie_path/movie.nfo

#    "id": 12,    "name": "Adventure"
#    "id": 14,    "name": "Fantasy"
#    "id": 16,    "name": "Animation"
#    "id": 18,    "name": "Drama"
#    "id": 27,    "name": "Horror"
#    "id": 28,    "name": "Action"
#    "id": 35,    "name": "Comedy"
#    "id": 36,    "name": "History"
#    "id": 37,    "name": "Western"
#    "id": 53,    "name": "Thriller"
#    "id": 80,    "name": "Crime"
#    "id": 99,    "name": "Documentary"
#    "id": 878,    "name": "Science Fiction"
#    "id": 9648,    "name": "Mystery"
#    "id": 10402,    "name": "Music"
#    "id": 10749,    "name": "Romance"
#    "id": 10751,    "name": "Family"
#    "id": 10752,    "name": "War"
#    "id": 10770,    "name": "TV Movie"
