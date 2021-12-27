k8s弹性伸缩

1、什么是K8s的弹性伸缩？
Hpa（全称叫做Horizontal Pod Autoscaler），Horizontal Pod Autoscaler的操作对象是Replication Controller、ReplicaSet或者Deployment对应的Pod（k8s中可以控制Pod的是rc、rs、deployment），根据观察到的CPU使用量与用户的阈值进行比对，做出是否需要增加或者减少实例数量的决策。controller目前使用heapSter来检测CPU使用量，检测周期默认是30秒。

2、K8s的弹性伸缩的工作原理？
Horizontal Pod Autoscaler的工作原理，主要是监控一个Pod，监控这个Pod的资源CPU使用率，一旦达到了设置的阈值，就做策略来决定它是否需要增加，做策略的时候还需要一个周期，比如，持续五分钟都发现CPU使用率高，就抓紧增加Pod的数量来减轻它的压力。当然也有一个策略，就是持续五分钟之后，压力一直都很低，那么会减少Pod的数量。这就是k8s的弹性伸缩的工作原理，主要是监控CPU的使用率，然后来决定是否增加或者减少Pod的数量。
HPA（Horizontal Pod Autoscaler）Pod自动弹性伸缩，K8S通过对Pod中运行的容器各项指标（CPU占用、内存占用、网络请求量）的检测，实现对Pod实例个数的动态新增和减少。
早期的kubernetes版本，只支持CPU指标的检测，因为它是通过kubernetes自带的监控系统heapster实现的。
到了kubernetes 1.8版本后，heapster已经弃用，资源指标主要通过metrics api获取，这时能支持检测的指标就变多了（CPU、内存等核心指标和qps等自定义指标）

3、HPA设置
HPA是一种资源对象，通过yaml进行配置：
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: podinfo
spec:
  scaleTargetRef:
    apiVersion: extensions/v1beta1
    kind: Deployment
    name: podinfo
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      targetAverageUtilization: 80
  - type: Resource
    resource:
      name: memory
      targetAverageValue: 200Mi
  - type: Pods
    pods:
      metric:
        name: packets-per-second
      target:
        type: AverageValue
        averageValue: 1k
  - type: Object
    object:
      metric:
        name: requests-per-second
      describedObject:
        apiVersion: networking.k8s.io/v1beta1
        kind: Ingress
        name: main-route
      target:
        type: Value
        value: 10k
minReplicas： 最小pod实例数
maxReplicas： 最大pod实例数
metrics： 用于计算所需的Pod副本数量的指标列表
resource： 核心指标，包含cpu和内存两种（被弹性伸缩的pod对象中容器的requests和limits中定义的指标。）
object： k8s内置对象的特定指标（需自己实现适配器）
pods： 应用被弹性伸缩的pod对象的特定指标（例如，每个pod每秒处理的事务数）（需自己实现适配器）
external： 非k8s内置对象的自定义指标（需自己实现适配器）

4、HPA获取自定义指标（Custom Metrics）的底层实现（基于Prometheus）
Kubernetes是借助Agrregator APIServer扩展机制来实现Custom Metrics。Custom Metrics APIServer是一个提供查询Metrics指标的API服务（Prometheus的一个适配器），这个服务启动后，kubernetes会暴露一个叫custom.metrics.k8s.io的API，当请求这个URL时，请求通过Custom Metics APIServer去Prometheus里面去查询对应的指标，然后将查询结果按照特定格式返回。

HPA样例配置：
kind: HorizontalPodAutoscaler
apiVersion: autoscaling/v2beta1
metadata:
  name: sample-metrics-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: sample-metrics-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Object
    object:
      target:
        kind: Service
        name: sample-metrics-app
      metricName: http_requests
      targetValue: 100

当配置好HPA后，HPA会向Custom Metrics APIServer发送https请求：
https://<apiserver_ip>/apis/custom-metrics.metrics.k8s.io/v1beta1/namespaces/default/services/sample-metrics-app/http_requests

可以从上面的https请求URL路径中得知，这是向 default 这个 namespaces 下的名为 sample-metrics-app 的 service 发送获取 http_requests 这个指标的请求。

Custom Metrics APIServer收到 http_requests 查询请求后，向Prometheus发送查询请求查询 http_requests_total 的值（总请求次数），Custom Metics APIServer再将结果计算成 http_requests （单位时间请求率）返回，实现HPA对性能指标的获取，从而进行弹性伸缩操作。

指标获取流程如下图所示：

如何自定义Adapter的指标：https://github.com/DirectXMan12/k8s-prometheus-adapter
Helm的方式自定义Adapter的指标：
https://github.com/helm/charts/blob/master/stable/prometheus-adapter/README.md


#创建hpa的yaml
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: uhomecp-lease
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: uhomecp-lease
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Object
    object:
      target:
        kind: Service
        name: uhomecp-lease
      metricName: http_requests
      targetValue: 100
  - type: Resource
    resource:
      name: cpu
      targetAverageUtilization: 80
  - type: Resource
    resource:
      name: memory
      targetAverageValue: 1024Mi


#查看hpa
kubectl get hpa
#删除hpa
kubectl delete hpa +hpa_name
或 kubectl delete -f hpa_yaml文件






