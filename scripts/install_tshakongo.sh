#!/usr/bin/env bash
set -e
sudo apt-get update
sudo apt-get install -y python3-pip python3-dev libatlas-base-dev scons
pip3 install --upgrade pip
pip3 install -r requirements.txt
echo "Install OK"
