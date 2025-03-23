Since your **WidgetAPI container only runs a basic Go binary** with no shell, utilities, or debugging tools, we need to deploy an **additional sidecar container or a temporary debug pod** in the **same namespace** that has the required debugging tools (`sh`, `bash`, `ls`, etc.).

### **🛠️ Solution 1: Using an `alpine` Debug Container**
#### 🧰 Installing and Using the Netshoot kubectl Plugin via Krew

The Netshoot plugin makes it easy to launch temporary troubleshooting pods in your Kubernetes cluster.

### 📦 Installation

1. **Add the Netshoot plugin index to Krew:**

   ```bash
   kubectl krew index add netshoot https://github.com/nilic/kubectl-netshoot.git
   ```

2. **Install the Netshoot plugin:**

   ```bash
   kubectl krew install netshoot/netshoot
   ```

---

### 🚀 Usage

3. **Start a temporary troubleshooting pod in a specific namespace:**

   ```bash
   NS=widgetapi-dev
   kubectl netshoot run tmp-shell -n $NS
   ```

4. **Use a custom image (optional):**

   ```bash
   kubectl netshoot run tmp-shell --image-name busybox --image-tag 1.36.0 -n $NS
   ```

---

### 📍 Managing Namespaces

- **Temporarily set the namespace for a single command:**

  ```bash
  kubectl netshoot run tmp-shell -n $NS
  ```

- **Permanently set the namespace for the current context:**

  ```bash
  kubectl config set-context --current --namespace=$NS
  ```

- **Verify the namespace is correctly set:**

  ```bash
  kubectl config view --minify | grep namespace:
  ```

---

## **🎯 Troubleshooting Steps**
1. **Deploy the updated Helm chart**:
   ```bash
   helm upgrade --install widgetapi ./chart -n widgetapi-dev --values chart/dev-values.yaml --wait --timeout 5m
   helm test widgetapi -n widgetapi-dev
   ```

---

## widgetapi Notes 
- From the golang app we find out what options we can pass to it
```bash
Usage of /usr/local/bin/app:
  -addr string
    	address to listen (default "127.0.0.1:8080")
  -config string
    	path to config file
  -document_root string
    	path to document root directory (default ".")
  -enable_auth
    	enable authentication
  -enable_cors
    	enable CORS header (default true)
  -file_naming_strategy string
    	File naming strategy (default "uuid")
  -max_upload_size int
    	max upload size in bytes (default 1048576)
  -read_only_tokens value
    	comma separated list of read only tokens
  -read_write_tokens value
    	comma separated list of read write tokens
  -shutdown_timeout int
    	graceful shutdown timeout in milliseconds (default 15000)
```


### how we can find out the fully qualified address for this service
- Take the 'deployment-name' and the 'namespace' from the below
```bash
 helm ls -A
NAME              	NAMESPACE    	REVISION	UPDATED                             	STATUS  	CHART                    	APP VERSION
cert-manager      	cert-manager 	3       	2025-03-23 12:12:10.983962 -0600 MDT	deployed	cert-manager-v1.17.1     	v1.17.1
cluster-autoscaler	kube-system  	3       	2025-03-23 12:12:06.124989 -0600 MDT	deployed	cluster-autoscaler-9.46.3	1.32.0
ingress-nginx     	ingress-nginx	3       	2025-03-23 12:12:28.872081 -0600 MDT	deployed	ingress-nginx-4.12.0     	1.12.0
widgetapi         	widgetapi-dev	8       	2025-03-23 13:15:20.82904 -0600 MDT 	deployed	widgetapi-0.3.0          	v2
```

- Now we can use our netshoot debug container in the same pod
```bash
# URL="http://{{ .Release.Name }}.{{ .Release.Namespace }}.svc.cluster.local:8080/"

NS=widgetapi-dev
HOST=widgetapi.$NS.svc.cluster.local

curl -v http://$HOST:8080/
curl -v http://$HOST:8080/health
curl -v http://$HOST:8080/healthz
curl -v http://$HOST:8080/ping
# widgetapi curl http://$HOST:8080/healthz
# {"ok":false,"error":"not found"}#
# widgetapi curl http://$HOST:8080/
# {"ok":false,"error":"not found"}#
```

---

### **🛠️ Solution 2: If you need a longer-lasting option you could modify your deploying using an `alpine` Debug Container**
We'll update your `deployment.yaml` to include an **Alpine-based debug sidecar container** that mounts the same persistent volume as your application. This allows us to inspect, list, and validate file operations.

---

## **✅ Updated `deployment.yaml`**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: widgetapi
  labels:
    app: widgetapi
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: widgetapi
  template:
    metadata:
      labels:
        app: widgetapi
    spec:
      securityContext:
        fsGroup: 1000  # 🔹 Ensures volume is writable by non-root users
      containers:
        - name: widgetapi
          image: "{{ .Values.image.repository }}@{{ .Values.image.tag }}"
          ports:
            - containerPort: 8080
          args: ["-addr", "0.0.0.0:8080"]  # ✅ Ensure app listens externally
          volumeMounts:
            - name: data
              mountPath: /widgetapi/data
              subPath: data  # 🔹 Ensures a subdirectory is used correctly
          env:
            - name: TOKEN
              value: {{ .Values.environment.TOKEN | quote }}
            - name: UPLOAD_LIMIT
              value: {{ .Values.environment.UPLOAD_LIMIT | quote }}
            - name: LISTEN_ADDR
              value: "0.0.0.0:8080"
            - name: DATA_PATH
              value: "/widgetapi/data"
          securityContext:
            runAsUser: 1000
            runAsGroup: 1000
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: false
            capabilities:
              drop: ["ALL"]

        # 🔍 **Debugging Sidecar Container**
        - name: debug-sidecar
          image: alpine:latest  # ✅ Lightweight image with sh, ls, cat, etc.
          command: ["/bin/sh", "-c", "sleep infinity"]
          volumeMounts:
            - name: data
              mountPath: /widgetapi/data
          securityContext:
            runAsUser: 1000
            runAsGroup: 1000
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: false
            capabilities:
              drop: ["ALL"]

      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: widgetapi-pvc
```

---

## **✅ Why This Works**
- **Sidecar (`debug-sidecar`) runs `alpine:latest`**, which provides:
  - `sh`, `ls`, `cat`, `mkdir`, `chmod`, and other utilities.
- **It mounts the same `/widgetapi/data` volume**, so we can verify file creation.
- **It runs indefinitely (`sleep infinity`)**, so we can debug at any time.

---

## **🚀 How to Use the Debug Sidecar**
Once the pod is running, **exec into the debug sidecar instead**:
```sh
helm upgrade --install widgetapi chart/ --namespace widgetapi-local --values chart/local-values.yaml
kubectl exec -it $(kubectl get pod -l app=widgetapi -n widgetapi-local -o jsonpath="{.items[0].metadata.name}") -n widgetapi-local -c debug-sidecar -- sh
```
### **🔍 Debugging File Storage**
#### **Check mounted storage**
```sh
ls -lah /widgetapi/data
```
#### **Manually create and test files**
```sh
echo "test file" > /widgetapi/data/testfile.txt
ls -lah /widgetapi/data
cat /widgetapi/data/testfile.txt
```
#### **Check ownership & permissions**
```sh
ls -lah /widgetapi/
ls -lah /widgetapi/data
```
If the `widgetapi` container cannot write files, try manually setting permissions:
```sh
chmod -R 777 /widgetapi/data
```
#### **Restart the Pod**
```sh
kubectl rollout restart deployment widgetapi -n widgetapi-local
```
