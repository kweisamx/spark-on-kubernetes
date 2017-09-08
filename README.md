# Spark on Kubernetes 

![](https://i.imgur.com/6zYTLL8.png)

如何在kubernetes上部署spark

Kubernetes 示例[github](https://github.com/kubernetes/examples/tree/master/staging/spark)上提供了一個詳細的spark部署方法，由於他的步驟設置有些覆雜, 這邊簡化一些部份讓大家安裝的時候不用去多設定一些東西。



## 部署條件

* 一個kubernetes群集,可參考[集群部署](https://feisky.gitbooks.io/kubernetes/deploy/cluster.html)
* kube-dns正常運作

## 創建一個命名空間

namespace-spark-cluster.yaml

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: "spark-cluster"
  labels:
    name: "spark-cluster"
```

```sh
$ kubectl create -f examples/staging/spark/namespace-spark-cluster.yaml
```

這邊原文提到需要將kubectl的執行環境轉到spark-cluster,這邊為了方便我們不這樣做,而是將之後的佈署命名空間都加入spark-cluster


## 部署Master Service

建立一個replication controller,來運行Spark Master服務

```yaml
kind: ReplicationController
apiVersion: v1
metadata:
  name: spark-master-controller
  namespace: spark-cluster
spec:
  replicas: 1
  selector:
    component: spark-master
  template:
    metadata:
      labels:
        component: spark-master
    spec:
      containers:
        - name: spark-master
          image: gcr.io/google_containers/spark:1.5.2_v1
          command: ["/start-master"]
          ports:
            - containerPort: 7077
            - containerPort: 8080
          resources:
            requests:
              cpu: 100m
```


```sh
$ kubectl create -f spark-master-controller.yaml
```

創建master服務


spark-master-service.yaml

```yaml
kind: Service
apiVersion: v1
metadata:
  name: spark-master
  namespace: spark-cluster
spec:
  ports:
    - port: 7077
      targetPort: 7077
      name: spark
    - port: 8080
      targetPort: 8080
      name: http
  selector:
    component: spark-master
```

```sh
$ kubectl create -f spark-master-service.yaml
```

檢查Master 是否正常運行

```sh
$ kubectl get pod -n spark-cluster 
spark-master-controller-qtwm8     1/1       Running   0          6d
```

```sh
$ kubectl logs spark-master-controller-qtwm8 -n spark-cluster 
17/08/07 02:34:54 INFO Master: Registered signal handlers for [TERM, HUP, INT]
17/08/07 02:34:54 INFO SecurityManager: Changing view acls to: root
17/08/07 02:34:54 INFO SecurityManager: Changing modify acls to: root
17/08/07 02:34:54 INFO SecurityManager: SecurityManager: authentication disabled; ui acls disabled; users with view permissions: Set(root); users with modify permissions: Set(root)
17/08/07 02:34:55 INFO Slf4jLogger: Slf4jLogger started
17/08/07 02:34:55 INFO Remoting: Starting remoting
17/08/07 02:34:55 INFO Remoting: Remoting started; listening on addresses :[akka.tcp://sparkMaster@spark-master:7077]
17/08/07 02:34:55 INFO Utils: Successfully started service 'sparkMaster' on port 7077.
17/08/07 02:34:55 INFO Master: Starting Spark master at spark://spark-master:7077
17/08/07 02:34:55 INFO Master: Running Spark version 1.5.2
17/08/07 02:34:56 INFO Utils: Successfully started service 'MasterUI' on port 8080.
17/08/07 02:34:56 INFO MasterWebUI: Started MasterWebUI at http://10.2.6.12:8080
17/08/07 02:34:56 INFO Utils: Successfully started service on port 6066.
17/08/07 02:34:56 INFO StandaloneRestServer: Started REST server for submitting applications on port 6066
17/08/07 02:34:56 INFO Master: I have been elected leader! New state: ALIVE
```


若master 已經被建立與運行,我們可以透過Spark開發的webUI來察看我們spark的群集狀況,我們將佈署[specialized proxy](https://github.com/aseigneurin/spark-ui-proxy)


spark-ui-proxy-controller.yaml

```yaml
kind: ReplicationController
apiVersion: v1
metadata:
  name: spark-ui-proxy-controller
  namespace: spark-cluster
spec:
  replicas: 1
  selector:
    component: spark-ui-proxy
  template:
    metadata:
      labels:
        component: spark-ui-proxy
    spec:
      containers:
        - name: spark-ui-proxy
          image: elsonrodriguez/spark-ui-proxy:1.0
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 100m
          args:
            - spark-master:8080
          livenessProbe:
              httpGet:
                path: /
                port: 80
              initialDelaySeconds: 120
              timeoutSeconds: 5
```

```sh
$ kubectl create -f spark-ui-proxy-controller.yaml
```

提供一個service做存取,這邊原文是使用LoadBalancer type,這邊我們改成NodePort,如果你的kubernetes運行環境是在cloud provider,也可以參考原文作法

spark-ui-proxy-service.yaml

```yaml
kind: Service
apiVersion: v1
metadata:
  name: spark-ui-proxy
  namespace: spark-cluster
spec:
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
  selector:
    component: spark-ui-proxy
  type: NodePort
```

```sh
$ kubectl create -f spark-ui-proxy-service.yaml
```

部署完後你可以利用[kubecrl proxy](https://kubernetes.io/docs/tasks/access-kubernetes-api/http-proxy-access-api/)來察看你的Spark群集狀態

```sh
$ kubectl proxy --port=8001
```

可以透過[http://localhost:8001/api/v1/proxy/namespaces/spark-cluster/services/spark-master:8080](http://localhost:8001/api/v1/proxy/namespaces/spark-cluster/services/spark-master:8080/)
察看,若kubectl中斷就無法這樣觀察了,但我們再先前有設定nodeport
所以也可以透過任意台node的端口30080去察看
例如：http://10.201.2.34:30080
10.201.2.34是群集的其中一台node,這邊可換成你自己的


## 部署 Spark workers

要先確定Matser是再運行的狀態

spark-worker-controller.yaml
```
kind: ReplicationController
apiVersion: v1
metadata:
  name: spark-worker-controller
  namespace: spark-cluster
spec:
  replicas: 2
  selector:
    component: spark-worker
  template:
    metadata:
      labels:
        component: spark-worker
    spec:
      containers:
        - name: spark-worker
          image: gcr.io/google_containers/spark:1.5.2_v1
          command: ["/start-worker"]
          ports:
            - containerPort: 8081
          resources:
            requests:
              cpu: 100m
```

```sh
$ kubectl create -f spark-worker-controller.yaml
replicationcontroller "spark-worker-controller" created
```

透過指令察看運行狀況

```sh
$ kubectl get pod -n spark-cluster 
spark-master-controller-qtwm8     1/1       Running   0          6d
spark-worker-controller-4rxrs     1/1       Running   0          6d
spark-worker-controller-z6f21     1/1       Running   0          6d
spark-ui-proxy-controller-d4br2   1/1       Running   4          6d
```

也可以透過上面建立的WebUI服務去察看

基本上到這邊Spark的群集已經建立完成了


## 創建 Zeppelin UI

我們可以利用Zeppelin UI經由web notebook直接去執行我們的任務,
詳情可以看[Zeppelin UI](http://zeppelin.apache.org/)與[ Spark architecture](https://spark.apache.org/docs/latest/cluster-overview.html)

zeppelin-controller.yaml

```yaml
kind: ReplicationController
apiVersion: v1
metadata:
  name: zeppelin-controller
  namespace: spark-cluster
spec:
  replicas: 1
  selector:
    component: zeppelin
  template:
    metadata:
      labels:
        component: zeppelin
    spec:
      containers:
        - name: zeppelin
          image: gcr.io/google_containers/zeppelin:v0.5.6_v1
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 100m
```


```sh
$ kubectl create -f zeppelin-controller.yaml
replicationcontroller "zeppelin-controller" created
```

然後一樣佈署Service

zeppelin-service.yaml

```sh
kind: Service
apiVersion: v1
metadata:
  name: zeppelin
  namespace: spark-cluster
spec:
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 30081
  selector:
    component: zeppelin
  type: NodePort
```

```sh
$ kubectl create -f zeppelin-service.yaml
```

可以看到我們把NodePort設再30081,一樣可以透過任意台node的30081 port 訪問 zeppelin UI。

通過命令行訪問pyspark（記得把pod名字換成你自己的）：

```
$ kubectl exec -it zeppelin-controller-8f14f -n spark-cluster pyspark
Python 2.7.9 (default, Mar  1 2015, 12:57:24) 
[GCC 4.9.2] on linux2
Type "help", "copyright", "credits" or "license" for more information.
17/08/14 01:59:22 WARN Utils: Service 'SparkUI' could not bind on port 4040. Attempting port 4041.
Welcome to
      ____              __
     / __/__  ___ _____/ /__
    _\ \/ _ \/ _ `/ __/  '_/
   /__ / .__/\_,_/_/ /_/\_\   version 1.5.2
      /_/

Using Python version 2.7.9 (default, Mar  1 2015 12:57:24)
SparkContext available as sc, HiveContext available as sqlContext.
>>> 
```

接著就能使用Spark的服務了,如有錯誤歡迎更正。

## zeppelin常見問題

* zeppelin的鏡像非常大,所以再pull時會花上一些時間,而size大小的問題現在也正在解決中,詳情可參考 issue #17231 
* 在GKE的平台上, `kubectl post-forward` 可能有些不穩定,如果你看現zeppelin 的狀態為`Disconnected`,`port-forward`可能已經失敗你需要去重新啟動它,詳情可參考 #12179

## 參考文檔

- [https://github.com/kweisamx/spark-on-kubernetes](https://github.com/kweisamx/spark-on-kubernetes)
- [Spark examples](https://github.com/kubernetes/examples/tree/master/staging/spark)
