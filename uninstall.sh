#!/usr/bin/env bash

rm -rf /usr/local/bin/wtf.py
rm -rf /usr/local/bin/wtf_script.py
rm -rf /usr/local/bin/wtf.json
rm -rf /usr/local/bin/uninstall.sh
rm -rf ~/.wtf.sh
rm -rf /usr/local/bin/withefuck
rm -rf ~/.wtf_profile.sh

rm -rf ~/.shell_logs

sed -i '/source \/root\/\.wtf\.sh/d' ~/.bashrc
sed -i '/source \/root\/\.wtf_profile\.sh/d' ~/.bashrc

rm -rf /usr/local/bin/wtf.uninstall


echo "Withefuck has been uninstalled successfully. Please restart your terminal session to apply the changes."