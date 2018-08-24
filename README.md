# simplepush
Bash script for sending encrypted push notifications to Android devices. It uses [simplepush API](https://simplepush.io/), and is based on their [bash script](https://github.com/simplepush/send-encrypted). However this project adds encrypted configuration file which can securily store multiple keys.

## Usage
Setup config file:

`./simplepush.sh setup`

Send encrypted push notifications:

`./simplepush.sh [-e <event>] [-t <title>] -m <message>`
