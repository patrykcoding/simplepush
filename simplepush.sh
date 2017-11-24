#!/bin/bash

config_file="$HOME/.simplepush.conf"

usage() { 
	echo "Usage: $0 [-e <event>] [-t <title>] -m <message>" 1>&2
	echo "Usage: $0 setup" 1>&2
	exit 0
}


create_config() {
	echo "Config file not found. Creating a new one"
	echo -n "Enter key: "
	read key
	echo -n "Enter salt: "
	read -s salt
	echo ""
	echo -n "Enter password: "
	read -s passwd
	echo ""

	config="1
key=$key
salt=$salt
passwd=$passwd"

	res="$(openssl aes-256-cbc -a -salt -out $config_file <<< "$config")"
}

add_to_config() {
	if [ ! -e $config_file ]; then
		create_config
		return
	fi

	config=`openssl aes-256-cbc -d -a -in $config_file`
	if [ "$?" -ne 0 ]; then
		return "$?"
	fi

	echo -n "Enter key: "
	read key
	echo -n "Enter salt: "
	read -s salt
	echo ""
	echo -n "Enter password: "
	read -s passwd
	echo ""

	# get the first line
	while read -r line; do
		num=$line
		break
	done <<< "$config"

	((num++))
	config=`sed "1s/.*/$num/" <<< "$config"`
	config+="
key=$key
salt=$salt
passwd=$passwd"

	res=`openssl aes-256-cbc -a -salt -out $config_file <<< "$config"`
}

delete_from_config() {
	res=`openssl aes-256-cbc -d -a -in $config_file`
	if [ "$?" -ne 0 ]; then
		exit
	fi

	params=()
	while read -r line; do
		params+=("$line")
	done <<< "$res"

	num=${params[0]} # number of keys stored

	declare -A values
	key_line=1 # line on which the first key is stored
	i=1
	while [ $i -le $num ]; do
		echo -n "$i) "
		echo "${params[$key_line]}" | awk -F "key=" "{print $2}"
		values+=( [$i]=$key_line ) # store line of the key
		((key_line+=3))
		((i++))
	done

	echo -n "Pick a key to delete: "
	while true; do
		read picked_key
		if [ $picked_key -lt 1 ] || [ $picked_key -gt $num ]; then
			echo -n "Input a number between 1 and $num: "
		else
			break
		fi
	done

	config=""
	line_num="${values[$picked_key]}"
	i=0
	while read -r line; do
		if [[ $i -ge $line_num ]] && [[ $i -le $line_num+2 ]]; then
			((i++))
			continue
		fi
		if [ $i -eq 0 ]; then
			((line--))
		else
			config+="
"
		fi
		config+="$line"
		((i++))
	done <<< "$res"

	res=`openssl aes-256-cbc -a -salt -out $config_file <<< "$config"`
}

decrypt_config() {
	res=`openssl aes-256-cbc -d -a -in $config_file`
	if [ "$?" -ne 0 ]; then
		exit
	fi

	params=()
	while read -r line; do
		params+=("$line")
	done <<< "$res"

	num=${params[0]} # number of keys stored

	if [ $num -gt 1 ]; then
		declare -A values
		key_line=1 # line on which the first key is stored
		i=1
		while [ $i -le $num ]; do
			echo -n "$i) "
			echo "${params[$key_line]}" | awk -F "key=" "{print $2}"
			values+=( [$i]=$key_line ) # store line of the key
			((key_line+=3))
			((i++))
		done

		echo -n "Pick a key: "
		while true; do
			read picked_key
			if [ $picked_key -lt 1 ] || [ $picked_key -gt $num ]; then
				echo -n "Input a number between 1 and $num: "
			else
				break
			fi
		done

		line_num="${values[$picked_key]}"
	else
		line_num=1
	fi

	key=`echo "${params[$line_num]}" | awk -F 'key=' '{print $2}'`
	((line_num++))
	salt=`echo "${params[$line_num]}" | awk -F 'salt=' '{print $2}'`
	((line_num++))
	passwd=`echo "${params[$line_num]}" | awk -F 'passwd=' '{print $2}'`
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

if [ "$1" = "setup" ] && [ "$#" -gt 1 ]; then
	usage
	exit 1
fi

if [ "$1" = "setup" ]; then
	echo "a) Add new key"
	echo "d) Delete a key"
	while true; do
		read ans
		if [ "$ans" = "a" ]; then
			add_to_config
			exit 0
		elif [ "$ans" = "d" ]; then
		       delete_from_config
		       exit 0
	       fi
	done
fi

if [ -z "${message}" ]; then
	usage
	exit 1
fi

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

curl --http1.1 --data "key=${key}${title}&msg=${message}${event}&encrypted=true&iv=$iv" "https://api.simplepush.io/send" > /dev/null 2>&1
