#!/bin/bash

set -e

if [ ! -f /.dockerenv ]
then
	echo "must run in docker!"
	exit 1
fi

apt-get install -y \
	python-sphinx-rtd-theme \
	texlive-latex-recommended \
	texlive-base \
	graphviz \
	imagemagick python3-virtualenv

#/usr/bin/virtualenv ~/sphinx_version
#. ~/sphinx_version/bin/activate
pip install -r Documentation/sphinx/requirements.txt
make pdfdocs

echo "All done!"
