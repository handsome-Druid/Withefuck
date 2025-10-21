#!/bin/bash

rm -rf /usr/local/bin/wtf
rm -rf /usr/local/bin/wtf.script

rm -rf ~/.wtf.sh

sed -i '/source \/root\/\.wtf\.sh/d' ~/.bashrc



rm -rf /usr/local/bin/wtf.uninstall