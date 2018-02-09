#!/bin/bash
if [ "$1" == "" ]; then
  echo "Please enter a message to push!"
  exit 1
fi

#echo \'"$1"\'
 git add --all
 git commit -am \'"$1"\'
 git checkout master && git merge dev && git checkout dev && git push origin --all
