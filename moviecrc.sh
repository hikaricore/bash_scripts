#!/bin/bash
export IFS=$'\n' &&
for i in $(ls */*.mkv */*.avi */*.mp4 */*.webm */*.flv | grep -v movie-trailer); do

        crc="crc32 $i"
        crc32 $i >> $(echo $i | sed s/\.[^.]*$//).crc
        cat -v archivedfiles.csv | grep $(crc32 $i|LC_ALL=sv_SE tr '[:lower:]' '[:upper:]') >>

done
