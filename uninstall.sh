#!/bin/bash

rm -rf /usr/local/bin/wtf
rm -rf /usr/local/bin/wtf.script
rm -rf /usr/local/bin/wtf.json
rm -rf ~/.wtf.sh
rm -rf /usr/local/bin/withefuck
rm -rf ~/.wtf_profile.sh

rm -rf ~/.shell_logs

sed -i '/source \/root\/\.wtf\.sh/d' ~/.bashrc
sed -i '/source \/root\/\.wtf_profile\.sh/d' ~/.bashrc

rm -rf /usr/local/bin/wtf.uninstall


echo "Withefuck has been uninstalled successfully. Please restart your terminal session to apply the changes."