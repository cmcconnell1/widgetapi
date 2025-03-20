Since your **WidgetAPI container only runs a basic Go binary** with no shell, utilities, or debugging tools, we need to deploy an **additional sidecar container or a temporary debug pod** in the **same namespace** that has the required debugging tools (`sh`, `bash`, `ls`, etc.).

### **🛠️ Solution: Add an `alpine` Debug Container**
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

---

## **🎯 Troubleshooting Steps**
1. **Deploy the updated Helm chart**:
   ```sh
   helm upgrade --install widgetapi chart/ --namespace widgetapi-local --values chart/local-values.yaml
   ```
2. **Exec into the debug sidecar**:
   ```sh
   kubectl exec -it $(kubectl get pod -l app=widgetapi -n widgetapi-local -o jsonpath="{.items[0].metadata.name}") -n widgetapi-local -c debug-sidecar -- sh
   ```
3. **Verify file storage is working correctly** before re-running Helm tests.

---

## **✅ Expected Outcome**
- You can **interactively debug storage issues** without modifying the `widgetapi` application.
- The **file storage issue (`500 internal error: cannot open file`) should be resolved** after verifying permissions and volume mounts.
- **Files persist correctly across restarts**.