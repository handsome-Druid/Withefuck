#!/usr/bin/env bash

set -e

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"


pwd=$(cd "$(dirname "$0")" && pwd)
echo "install_dir : $pwd"
echo "Home : $HOME"



ln -sf $pwd/wtf_profile.sh $HOME/.wtf_profile.sh
chmod +x $HOME/.wtf_profile.sh
ln -sf $pwd/wtf.sh $HOME/.wtf.sh


chmod +x $pwd/wtf.py
chmod +x $pwd/wtf_script.py
chmod +x $pwd/uninstall.sh

if ! grep -q "wtf.sh" ~/.bashrc; then
    echo "source $HOME/.wtf.sh" >> ~/.bashrc
fi

if ! grep -q "wtf_profile.sh" ~/.bashrc; then
    echo "source $HOME/.wtf_profile.sh" >> ~/.bashrc
fi

source $HOME/.wtf.sh
source $HOME/.wtf_profile.sh

$pwd/wtf.py --config

$HOME/.wtf_profile.sh


echo "Withefuck has been installed successfully."