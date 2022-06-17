#!/bin/bash
## This will will check record content and update cloudflare if necessary
## Script will take the following parameters
## -k : Cloudflare login token
## -z : Cloudflare zone name
## -n : Cloudflare FQDN
## -i : interface to be used (optional on type A/AAAA)
## -c : content to be updated (required except for A/AAAA records)
## -t : DNS record Type


## Default section
auth_key=xxxxxxxxxxxxxx
zone_name="example.com"
record_name="dns.example.com"
rec_type=AAAA
iface=eno1   #interface to obtain IP address
content=""

while getopts ":e:k:z:n:i:t:c:" opts
do
   case "$opts" in
      "k")
         auth_key=$OPTARG
         ;;
      "z")
         zone_name="$OPTARG"
         ;;
      "n")
         record_name="$OPTARG"
         ;;
      "t")
         rec_type=$OPTARG
         ;;
      "i")
         iface=$OPTARG
         ;;
      "c")
         content="$OPTARG"
         ;;
      "?")
         echo "Unknown option $OPTARG"
         exit 1
         ;;
      ":")
         echo "Missing argument for option $OPTARG"
         exit 1
         ;;
      esac
done

if [ "$content" == "" ]; then
   if [ "$rec_type" == "AAAA" ]; then
      content=`/bin/ip -6 addr show $iface|sed -n 's%.*inet6\s\(.*\)/64.*global.*%\1%p'`
   elif [ "$rec_type" == "A" ]; then
      content=`/bin/ip -4 addr show $iface|sed -n 's/.*inet\s\(.*\)\/24.*/\1/p'`
   elif [ "$content" == "" ]; then
      echo "Must specify content on record type other than A/AAAA!"
      exit 1
   fi
fi

echo $(date)
echo "Checking $rec_type for $record_name"
zone_str=`curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone_name" \
-H "Authorization: Bearer $auth_key" \
-H "content-Type: application/json"`

#echo "Zone : $zone_str "

zone_id=`echo $zone_str | sed -n 's/.*result":\[{"id":"\([[:alnum:]]*\)".*/\1/p'`

echo "Zone ID : $zone_id"

record_str=`curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=$rec_type&name=$record_name" \
-H "Authorization: Bearer $auth_key" \
-H "content-Type: application/json"`
record_id=`echo $record_str|sed -n 's/.*result":\[{"id":"\([[:alnum:]]*\)".*/\1/p'`
echo "Record ID: $record_id"

current_content=`echo $record_str| sed -n 's/.*content":"\(.*[^"]\)","proxiable.*/\1/p'`
echo "Current Content : $current_content"


if [[ $current_content == $content ]]; then
    echo "Content not changed.  Exiting."
    exit 0
else
    echo "Content Changed.  Update Cloudflare."
    echo "Zone ID: $zone_id"
    echo "Record ID: $record_id"
    echo "Current Content: $current_content"
    echo "New Content: $content"
fi

update=`curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
-H "Authorization: Bearer $auth_key" \
-H "content-Type: application/json" \
-d "{\"id\":\"$zone_id\",\"type\":\"$rec_type\",\"name\":\"$record_name\",\"content\":\"$content\"}"`

if [[ $update == *"\"success\":false"* ]]; then
    message="API UPDATE FAILED.  DUMPING RESULTS:\n$update"
    echo "$message"
    exit 1
else
    message="$rec_type changed to: $content"
    echo "$message"
fi
