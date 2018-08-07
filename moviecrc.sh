#!/bin/bash
export IFS=$'\n' &&
for i in $(ls */*.mkv */*.mp4 */*.avi */*.mpg */*.mpeg */*.webm */*.flv | grep -v movie-trailer); do

        crc=$(crc32 $i)
        #write=$(echo $i | sed s/\.[^.]*$//).crc
        write=$(echo $i).crc
        echo $crc >> $write
        # get the complete data sv from https://www.srrdb.com/open (requires login)
        #cat -v archivedfiles.csv | grep $(echo $crc | LC_ALL=sv_SE tr '[:lower:]' '[:upper:]') >> $write
        grep -f -i $crc archivedfiles.csv >> $write
        
done
