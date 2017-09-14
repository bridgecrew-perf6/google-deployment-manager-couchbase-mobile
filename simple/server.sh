echo "Running server.sh"

#######################################################
############ Turn Off Transparent Hugepages ###########
#######################################################

echo "Turning off transparent hugepages..."

# Please look at http://bit.ly/1ZAcLjD as for how to PERMANENTLY alter this setting.

echo "#!/bin/bash
### BEGIN INIT INFO
# Provides:          disable-thp
# Required-Start:    $local_fs
# Required-Stop:
# X-Start-Before:    couchbase-server
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Disable THP
# Description:       disables Transparent Huge Pages (THP) on boot
### END INIT INFO

echo 'never' > /sys/kernel/mm/transparent_hugepage/enabled
echo 'never' > /sys/kernel/mm/transparent_hugepage/defrag
" > /etc/init.d/disable-thp
chmod 755 /etc/init.d/disable-thp
service disable-thp start
update-rc.d disable-thp defaults

#######################################################
################# Set Swappiness to 0 #################
#######################################################

echo "Setting swappiness to 0..."

# Please look at http://bit.ly/1k2CtNn as for how to PERMANENTLY alter this setting.

sysctl vm.swappiness=0
echo "
# Required for Couchbase
vm.swappiness = 0" >> /etc/sysctl.conf

#######################################################
############### Install Couchbase Server ##############
#######################################################

echo "Installing Couchbase Server..."
wget http://packages.couchbase.com/releases/4.6.3/couchbase-server-enterprise_4.6.3-ubuntu14.04_amd64.deb
dpkg -i couchbase-server-enterprise_4.6.3-ubuntu14.04_amd64.deb
apt-get update
apt-get -y install couchbase-server

#######################################################
############## Configure Couchbase Server #############
#######################################################

echo "Configuring Couchbase Server"

echo "Using the settings:"
echo couchbaseUsername ${couchbaseUsername}
echo couchbasePassword ${couchbasePassword}
echo services ${services}
echo DEPLOYMENT ${DEPLOYMENT}
echo CLUSTER ${CLUSTER}

#######################################################
################### Pick Rally Point ##################
#######################################################

apt-get -y install jq

ACCESS_TOKEN=$(curl -s -H "Metadata-Flavor:Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token | awk -F\" '{ print $4 }')
PROJECT_ID=$(curl -s -H "Metadata-Flavor:Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
CONFIG=${DEPLOYMENT}-${CLUSTER}-runtimeconfig

nodePrivateDNS=`curl -s http://metadata/computeMetadata/v1beta1/instance/hostname`
echo nodePrivateDNS: ${nodePrivateDNS}

echo "Creating new runtimeconfig variable for this host..."
hostname=`hostname`
curl -s -k -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "X-GFE-SSL: yes" \
  -d "{name: \"projects/${PROJECT_ID}/configs/$CONFIG/variables/nodeList/${hostname}\", text: \"${nodePrivateDNS}\" }" \
  https://runtimeconfig.googleapis.com/v1beta1/projects/${PROJECT_ID}/configs/${CONFIG}/variables

# Get nodeCount from runtimeconfig
nodeCount=$(curl -s -H "Authorization":"Bearer ${ACCESS_TOKEN}" \
  https://runtimeconfig.googleapis.com/v1beta1/projects/${PROJECT_ID}/configs/${CONFIG}/variables/nodeCount \
  | jq ".text" \
  | sed 's/"//g')
echo nodeCount: ${nodeCount}

liveNodeCount=0
while [[ $liveNodeCount -lt $nodeCount ]]
do
  # Get number of nodes currently in runtime config
  liveNodeCount=$(curl -s -H "Authorization":"Bearer ${ACCESS_TOKEN}" \
    https://runtimeconfig.googleapis.com/v1beta1/projects/${PROJECT_ID}/configs/${CONFIG}/variables/?filter=projects%2F${PROJECT_ID}%2Fconfigs%2F${CONFIG}%2Fvariables%2FnodeList \
    | jq ".variables | length")
  echo liveNodeCount: ${liveNodeCount}
  sleep 10
done

rallyPrivateDNS=$(curl -s -H "Authorization":"Bearer ${ACCESS_TOKEN}" \
  https://runtimeconfig.googleapis.com/v1beta1/projects/${PROJECT_ID}/configs/${CONFIG}/variables/?filter=projects%2F${PROJECT_ID}%2Fconfigs%2F${CONFIG}%2Fvariables%2FnodeList\&returnValues=True \
  | jq ".variables | sort_by(.text)" \
  | jq ".[0].text" \
  | sed 's/"//g')
echo rallyPrivateDNS: ${rallyPrivateDNS}

#######################################################
############# Configure with Couchbase CLI ############
#######################################################

cd /opt/couchbase/bin/

echo "Running couchbase-cli node-init"
./couchbase-cli node-init \
  --cluster=$nodePrivateDNS \
  --node-init-hostname=$nodePrivateDNS \
  --user=$couchbaseUsername \
  --pass=$couchbasePassword

if [[ $rallyPrivateDNS == $nodePrivateDNS ]]
then
  totalRAM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  dataRAM=$((50 * $totalRAM / 100000))
  indexRAM=$((15 * $totalRAM / 100000))

  echo "Running couchbase-cli cluster-init"
  ./couchbase-cli cluster-init \
    --cluster=$nodePrivateDNS \
    --cluster-ramsize=$dataRAM \
    --cluster-index-ramsize=$indexRAM \
    --cluster-username=$couchbaseUsername \
    --cluster-password=$couchbasePassword \
    --services=${services}

    echo "Running couchbase-cli bucket-create"
  ./couchbase-cli bucket-create \
    --cluster=$nodePrivateDNS \
    --user=$couchbaseUsername \
    --pass=$couchbasePassword \
    --bucket=sync_gateway \
    --bucket-type=couchbase \
    --bucket-ramsize=$dataRAM
else
  echo "Running couchbase-cli server-add"
  output=""
  while [[ $output != "Server $nodePrivateDNS:8091 added" && ! $output =~ "Node is already part of cluster." ]]
  do
    output=`./couchbase-cli server-add \
      --cluster=$rallyPrivateDNS \
      --user=$couchbaseUsername \
      --pass=$couchbasePassword \
      --server-add=$nodePrivateDNS \
      --server-add-username=$couchbaseUsername \
      --server-add-password=$couchbasePassword \
      --services=${services}`
    echo server-add output \'$output\'
    sleep 10
  done

  echo "Running couchbase-cli rebalance"
  output=""
  while [[ ! $output =~ "SUCCESS" ]]
  do
    output=`./couchbase-cli rebalance \
      --cluster=$rallyPrivateDNS \
      --user=$couchbaseUsername \
      --pass=$couchbasePassword`
    echo rebalance output \'$output\'
    sleep 10
  done

fi