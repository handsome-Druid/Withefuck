#!/usr/bin/env bash

rm -rf /usr/local/bin/wtf.py
rm -rf /usr/local/bin/wtf_script.py
rm -rf /usr/local/bin/wtf.json
rm -rf /usr/local/bin/uninstall.sh
rm -rf ~/.wtf.sh
rm -rf /usr/local/bin/withefuck
rm -rf ~/.wtf_profile.sh

rm -rf ~/.shell_logs


for rcfile in ~/.bashrc ~/.zshrc ~/.ashrc; do
    if [ -f "$rcfile" ]; then
        sed -i "\|source $HOME/\.wtf\.sh|d" "$rcfile"
        sed -i "\|source $HOME/\.wtf_profile\.sh|d" "$rcfile"
        sed -i "\|\. $HOME/\.wtf\.sh|d" "$rcfile"
        sed -i "\|\. $HOME/\.wtf_profile\.sh|d" "$rcfile"
    fi
done

rm -rf /usr/local/bin/wtf.uninstall


echo "Withefuck has been uninstalled successfully. Please restart your terminal session to apply the changes."