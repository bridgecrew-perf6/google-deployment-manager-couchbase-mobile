#!/bin/sh

#mkdir tmp

cp ../simple/deployment.py tmp
cp ../simple/cluster.py tmp
cp ../simple/group.py tmp
cp ../simple/server.sh tmp
cp ../simple/syncGateway.sh tmp

cp -r resources tmp
#cp couchbase.py tmp

cp couchbase.jinja tmp
cp couchbase.jinja.display tmp
cp couchbase.jinja.schema tmp
cp c2d_deployment_configuration.json tmp
cp test_config.yaml tmp

zip -r -X archive.zip tmp
#rm -rf tmp
