#!/bin/bash

project=antinex
test_exists=$(oc project | grep ${project} | wc -l)
first_time_deploy="0"
if [[ "${test_exists}" == "0" ]]; then
    oc new-project ${project}
    first_time_deploy="1"
fi
echo ""
echo "Creating ${project} project"
oc project ${project}

echo ""
echo "Getting Status"
oc status

echo "Deploying Redis"
oc new-app \
    --name=redis \
    ALLOW_EMPTY_PASSWORD=yes \
    --docker-image=bitnami/redis
echo ""

echo "Deploying Crunchy Postgres Single Primary Database"
source ./primary-db.sh
pushd /opt/antinex/api/openshift/crunchy-containers/examples/kube/primary
./run.sh
popd
echo ""

echo "Creating Redis - persistent volume"
oc apply -f redis/persistent-volume.json
echo ""

echo "Waiting for volumes to register"
sleep 5

# map to template - objects[1].spec.volmes[0].persistentVolumeClaim.claimName
redis_pvc_name="redis"
# what path is this volume mounting into the container
redis_pvc_mount_path="/bitnami"

echo "Creating Redis persistent volume claim"
oc volume \
    dc/redis \
    --add \
    --claim-size 10G \
    --claim-name redis-antinex \
    --name ${redis_pvc_name} \
    --mount-path ${redis_pvc_mount_path}
echo ""

echo "Exposing Redis service"
oc expose svc/redis

echo "Exposing Crunchy Postgres Database service"
oc expose svc/primary

echo "Deploying AntiNex - Django Rest Framework REST API workers"
oc apply -f worker/deployment.yaml
echo ""

echo "Deploying AntiNex - AI Core"
oc apply -f core/deployment.yaml
echo ""

echo "Deploying AntiNex - Django Rest Framework REST API server"
oc apply -f api/service.yaml -f api/deployment.yaml 
echo ""

echo "Deploying AntiNex - Network Pipeline consumer"
oc apply -f pipeline/deployment.yaml
echo ""

echo "Deploying Jupyter integrated with AntiNex"
oc apply -f jupyter/service.yaml -f jupyter/deployment.yaml
echo ""

echo "Checking OpenShift cluster status"
oc status
echo ""

echo "Exposing API and Jupyter services"
oc expose svc/api
oc expose svc/jupyter

echo "Waiting for services to start"
sleep 5

echo ""
oc status
echo ""

# If you're using Postgres before 9.6 then you might need to create the database:
#
# echo "------------------------"
# echo "For first time deployment make sure to create the database:"
# ./show-create-db.sh
# echo "------------------------"
# echo ""

echo "------------------------"
echo "If you need to run a database migration you can use:"
echo "./show-migrate-cmds.sh"
echo ""
echo "which should show the commands to perform the migration:"
./show-migrate-cmds.sh
echo "------------------------"
echo ""

exit 0
