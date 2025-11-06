#!/bin/bash
# Run the iptable commands if and only if apt get exists and user traffic does not exist
# remove sudo

echo "Turning off the Firewall..."
sudo iptables -S USER_TRAFFIC >/dev/null 2>&1
iptable_exists=$?

which apt-get &> /dev/null

# Case 1: apt get exists
if  [ $? -eq 0 ]; then
    
    # Case 1a: apt get exists and iptable does not exist
    if [ "$iptable_exists" -ne 0 ]; then
        echo "iptable doesn't exist and apt get exist"
        echo "" > /etc/iptables/rules.v4
        echo "" > /etc/iptables/rules.v6
        iptables -F
        iptables -X
        iptables -t nat -F
        iptables -t nat -X
        iptables -t mangle -F
        iptables -t mangle -X
        iptables -P INPUT ACCEPT
        iptables -P OUTPUT ACCEPT
        iptables -P FORWARD ACCEPT
    fi

# Case 2: apt get does not exist
else
    echo "apt get does not exist"
    # service firewalld stop
    # chkconfig firewalld off
fi