#!/bin/bash

if [ $# -ne 2 ]
then
	echo "Error:any of the arguments were not specified."
	exit 1
fi

writefile=$1
writestr=$2

mkdir -p "$(dirname "$writefile")"

echo "$writestr" > "$writefile"

if [ $? -ne 0 ]
then 
	echo "Error:the files cannot be created."
	exit 1
fi
