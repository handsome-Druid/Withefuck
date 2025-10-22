#!/usr/bin/env bash

set -e

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Set and display installation and home directory
pwd=$(cd "$(dirname "$0")" && pwd)
echo "install_dir : $pwd"
echo "Home : $HOME"


# Create profile links and set permissions
ln -sf $pwd/wtf_profile.sh $HOME/.wtf_profile.sh
chmod +x $HOME/.wtf_profile.sh
ln -sf $pwd/wtf.sh $HOME/.wtf.sh

# Set execute permissions for main scripts
chmod +x $pwd/wtf.py
chmod +x $pwd/wtf_script.py
chmod +x $pwd/uninstall.sh


#Create symlinks in /usr/local/bin for ash
ln -sf $pwd/wtf.py /usr/local/bin/wtf.py
ln -sf $pwd/wtf_script.py /usr/local/bin/wtf_script.py
ln -sf $pwd/uninstall.sh /usr/local/bin/uninstall.sh

# Add sourcing to .bashrc
if ! grep -q "wtf.sh" ~/.bashrc; then
    echo "source $HOME/.wtf.sh" >> ~/.bashrc
fi

if ! grep -q "wtf_profile.sh" ~/.bashrc; then
    echo "source $HOME/.wtf_profile.sh" >> ~/.bashrc
fi


# Source the scripts
source $HOME/.wtf.sh
source $HOME/.wtf_profile.sh

# Run initial configuration
$pwd/wtf.py --config



# Force script logging
$HOME/.wtf_profile.sh


echo "Withefuck has been installed successfully."