#!/bin/bash
export IFS=$'\n' &&
for i in $(ls */*.mkv */*.mp4 */*.avi */*.mpg */*.mpeg */*.webm */*.flv | grep -v movie-trailer); do

        # guess we should check for existing crc files so we don't waste time
        # none of this has been tested, so have fun if something breaks horribly
        # not even sure if these if tags are closed properly, seriously don't use this yet
        
        if [ ! -f $i.crc ]
        
                then
                
                        # if the crc file does not exist at all, we do these things
                
                        printf "CRC file does not exist for $i, creating one." >&2
                        crc=$(crc32 $i)
                        #write=$(echo $i | sed s/\.[^.]*$//).crc
                        write="$i".crc
                        echo $crc >> $write
                        # get the complete data sv from https://www.srrdb.com/open (requires login)
                        #cat -v archivedfiles.csv | grep $(echo $crc | LC_ALL=sv_SE tr '[:lower:]' '[:upper:]') >> $write
                        grep -f -i $crc archivedfiles.csv >> $write
                        
                else
                
                        # see if the file has two lines
                        if [[ $(wc -l "$i".crc) -eq 2 ]]
                        #wc -l "$i".crc | cut -d\  -f1

                                then
                                
                                        printf "CRC file exists for $i, attempting compare with release." >&2
                                        crc=$(head -n 1 $i.crc)
                                        #write=$(echo $i | sed s/\.[^.]*$//).crc
                                        write="$i".crc
                                        echo $crc > $write
                                        # get the complete data sv from https://www.srrdb.com/open (requires login)
                                        #cat -v archivedfiles.csv | grep $(echo $crc | LC_ALL=sv_SE tr '[:lower:]' '[:upper:]') >> $write
                                        grep -f -i $crc archivedfiles.csv >> $write && echo "CRC Match!" >> $write
                                # see if the file has one line
                                else 
                                if [[ $(wc -l "$i".crc) -eq 1 ]]
                        
                                        printf "CRC file exists for $i, attempting compare with release." >&2
                                        crc=$(head -n 1 $i.crc)
                                        #write=$(echo $i | sed s/\.[^.]*$//).crc
                                        write="$i".crc
                                        #echo $crc > $write
                                        # get the complete data sv from https://www.srrdb.com/open (requires login)
                                        #cat -v archivedfiles.csv | grep $(echo $crc | LC_ALL=sv_SE tr '[:lower:]' '[:upper:]') >> $write
                                        grep -f -i $crc archivedfiles.csv >> $write && echo "CRC Match!" >> $write
                        
                                # see if the file is already matched
                                else
                                if [[ $(wc -l "$i".crc) -eq 3 ]] && [[ $(cat "$1".crc | grep -q "CRC Match!"; echo $?) -eq 0 ]]
                          
                                        # we'll finish this mess later      
                                        printf "CRC file exists for $i, and is a confirmed match with release." >&2
                          
                                fi
                                
                        fi
                        
        fi
        
done
