#!/bin/bash

config_file="$HOME/.simplepush.conf"

usage() { echo "Usage: $0 [-e <event>] [-t <title>] -m <message>" 1>&2; exit 0; }

while getopts ":e:t:m:" o; do
	case "${o}" in
		e)
			event=${OPTARG}
			;;
		t)
			title=${OPTARG}
			;;
		m)
			message=${OPTARG}
			;;
		*)
			usage
			;;
	esac
done
shift $((OPTIND-1))

if [ -z "${message}" ]; then
  usage
	return 1
fi

create_config() {
	echo "Config file not found. Creating a new one"
	echo -n "Enter key: "
	read key
	echo -n "Enter salt: "
	read salt
	echo ""
	echo -n "Enter password: "
	read -s passwd
	echo ""

	config="$key
$salt
$passwd"

	res="$(openssl aes-256-cbc -a -salt -out $config_file <<< "$config")"
}

decrypt_config() {
	params=()
	res=$(openssl aes-256-cbc -d -a -in $config_file)
	if [ "$?" -ne 0 ]; then
		exit
	fi

	while read -r line; do
		params+=("$line")
	done <<< "$res"

	key="${params[0]}"
	salt="${params[1]}"
	passwd="${params[2]}"
}

generate_key () {
    # First argument is password
	if [ -z "${salt}" ]; then
    	echo -n "${1}${default_salt}" | sha1sum | awk '{print toupper($1)}' | cut -c1-32
	else
    	echo -n "${1}${salt}" | sha1sum | awk '{print toupper($1)}' | cut -c1-32
	fi
}

encrypt () {
    # First argument is key
    # Second argument is IV
    # Third argument is data

    echo -n "${3}" | openssl aes-128-cbc -base64 -K "${1}" -iv "${2}" | awk '{print}' ORS='' | tr '+' '-' | tr '/' '_'
}

if [ -e $config_file ]; then
	decrypt_config
else
	create_config
fi

iv=`openssl enc -aes-128-cbc -k dummy -P -md sha1 | grep iv | cut -d "=" -f 2`

default_salt=1789F0B8C4A051E5

encryption_key=`generate_key "${passwd}"`

if [ -n "${title}" ]; then
    title_encrypted=`encrypt "${encryption_key}" "${iv}" "${title}"`
	  title="&title=${title_encrypted}"
else
	  title=""
fi

if [ -n "${event}" ]; then
	  event="&event=${event}"
else
	  event=""
fi

message=`encrypt "${encryption_key}" "${iv}" "${message}"`

#echo "key=${key}${title}&msg=${message}${event}&encrypted=true&iv=$iv" "https://api.simplepush.io/send"
curl --http1.1 --data "key=${key}${title}&msg=${message}${event}&encrypted=true&iv=$iv" "https://api.simplepush.io/send" > /dev/null 2>&1
