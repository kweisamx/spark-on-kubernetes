#!/bin/bash
# Author: Sam Zheng
# Time: 2017/08/07
#
# It is a shellscript to build spark on kubernetes automatically

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

kubectl create -f namespace-spark-cluster.yaml
kubectl create -f spark-master-controller.yaml
kubectl create -f spark-master-service.yaml
kubectl create -f spark-ui-proxy-controller.yaml
kubectl create -f spark-ui-proxy-service.yaml
kubectl create -f spark-worker-controller.yaml
kubectl create -f zeppelin-controller.yaml
kubectl create -f zeppelin-service.yaml

echo "All service finish"
