#!/bin/bash -x

echo "Test to create a simple VM and stress it's node cpu and test migration"
OCP_USERNAME="$( oc whoami )" ||  (echo "Issue with running oc" && exit 1 )

BASEDIR=$(dirname "$0")


oc apply -k $BASEDIR/manifests

check_count=5
while [ $check_count -gt 0 ]; do
    oc get vmi drs-test1-vm -n drs-test1 | grep Running
    if [ $? -eq 0 ]; then
        break
    fi
    sleep 10
    check_count=$((check_count-1))
done