#!/bin/bash

if ! which nasm 
then
	sudo yum install -y nasm
fi

set -x
nasm -f bin boot.nasm -o boot
ls -alh boot boot.nasm
