#!/bin/bash

usage() {
    echo "Usage: $0 <ACTION>"
    echo "  -h  Display help"
    echo "  ACTION  Action to perform, see action options"
    echo "  ACTION: start  Start the test, and create infra"
    echo "  ACTION: stop  Stop the test, and delete infra"
    exit 1
}


BASEDIR=$(dirname "$0")

if [ $# -ne 1 ]; then
    usage
fi

ACTION=$1

if [ "$ACTION" == "start" ]; then
    echo "Test to create a simple VM and stress it's node cpu and test migration"
    OCP_USERNAME="$( oc whoami )" ||  (echo "Issue with running oc" && exit 1 )

  
    oc apply -f $BASEDIR/manifests/project.yaml
    sleep 5
    oc apply -f $BASEDIR/manifests/test-deployment.yaml
    oc apply -f $BASEDIR/manifests/vm.yaml
    vmim_count=0

    while :; do
        oc patch deployment test1-stress-vm -n drs-test1 --patch '{"spec": {"replicas": 0}}'
        check_count=5
        while [ $check_count -gt 0 ]; do
            oc get vmi drs-test1-vm -n drs-test1 | grep Running
            if [ $? -eq 0 ]; then
                break
            fi
            sleep 10
            check_count=$((check_count-1))
        done

        if [ $check_count -eq 0 ]; then
            echo "VM is not running"
            exit 1
        fi

        check_count=5
        while [ $check_count -gt 0 ]; do
            oc get vmi drs-test1-vm -n drs-test1 -o jsonpath='{.status.phase}' | grep Running
            vmi_node=$(oc get vmi drs-test1-vm -n drs-test1 -o jsonpath='{.status.nodeName}')
            if [ $? -eq 0 ]; then
                break
            fi
            sleep 10    
            check_count=$((check_count-1))
        done

        if [ $check_count -eq 0 ]; then
            echo "VM is not running"
            exit 1
        fi

        if [ -z "$vmi_node" ]; then
            echo "Error getting VM Node"
            exit 1
        fi
        echo "VM is running on node $vmi_node"
        echo "Stressing the node $vmi_node"
        
        echo "Patching the stress deployment with NodeSelector for current test VM node"
        oc patch deployment test1-stress-vm -n drs-test1 --patch '{"spec": {"template": {"spec": {"nodeSelector": {"kubernetes.io/hostname": "'$vmi_node'"}}}}}'
        oc patch deployment test1-stress-vm -n drs-test1 --patch '{"spec": {"replicas": 1}}'
        

        retry_counter=10
        check_vmim_count=${vmim_count}

        while [ $check_vmim_count -eq $vmim_count ]; do
            # check if vmim is created
            if [ $retry_counter -eq 0 ]; then
                echo "Error: VMIM was not created"
                exit 1
            fi

            echo "Waiting for VMIM to be created and migration to start"
            vmim_count=$(oc get vmim -n drs-test1 -l acm_vm_name=drs-test1-vm | wc -l)

            if [ $vmim_count -gt $check_vmim_count ]; then
                vmim=$(oc get vmim -n drs-test1 -l acm_vm_name=drs-test1-vm --sort-by=.metadata.creationTimestamp | tail -n 1)               
                vmim_name=$(echo $vmim | awk '{print $1}')
                if [ "Failed" == "$(echo $vmim | awk '{print $2}')" ]; then
                    echo "Error: VMIM creation failed for $vmim_name"
                    break
                else
                    echo "VMIM $vmim_name is created"
                    sleep 10
                    source_node=$(oc get vmim $vmim_name -n drs-test1 -o jsonpath='{.status.migrationState.sourceNode}')
                    target_node=$(oc get vmim $vmim_name -n drs-test1 -o jsonpath='{.status.migrationState.targetNode}')
                    echo "Migration started from $source_node to $target_node"
                    sleep 60
                    break
                fi
            fi

            retry_counter=$((retry_counter-1))
            sleep 20
        done
  
    done


elif [ "$ACTION" == "stop" ]; then
    echo "Deleting infra"
    
    oc delete -f $BASEDIR/manifests/vm.yaml
    oc delete -f $BASEDIR/manifests/test-deployment.yaml
    oc delete -f $BASEDIR/manifests/project.yaml

else
    usage
fi


