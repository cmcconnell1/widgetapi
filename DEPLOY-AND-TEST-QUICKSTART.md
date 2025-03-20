## **Testing and Validating Local and Dev Environments**
Quickstart to **test and validate** your **local Minikube/Kind setup** and **EKS dev cluster**.

---

### **🛠 Local Testing (Minikube/Kind)**
Ensure Minikube/Kind is running and deploy the application.

#### **1️⃣ Start Minikube (If not already running)**
```bash
minikube start
```
or for Kind:
```bash
kind create cluster --name widgetapi-local
```

#### **2️⃣ Deploy to Local Cluster**
```bash
bash scripts/deploy.sh local
```

#### **3️⃣ Validate Deployment**
```bash
kubectl get all -n widgetapi-local
kubectl logs -n widgetapi-local -l app=widgetapi
```

#### **4️⃣ Test Application Connectivity**
```bash
helm test widgetapi --namespace widgetapi-local
```

#### **5️⃣ Check Ingress & Network**
```bash
kubectl get ingress -n widgetapi-local
minikube service list
kubectl get svc -n widgetapi-local
```

#### **6️⃣ Port Forward (If needed)**
If using Minikube, you may need to forward ports manually:
```bash
kubectl port-forward -n widgetapi-local svc/widgetapi 8080:8080
curl -vk http://localhost:8080
```

---

### **🌐 Dev Testing (EKS)**
Ensure you’re authenticated with AWS and have the correct cluster set up.

#### **1️⃣ Authenticate with AWS**
```bash
aws configure
aws eks update-kubeconfig --region us-west-2 --name widgetapi-dev
```

#### **2️⃣ Deploy to Dev Cluster**
```bash
bash scripts/deploy.sh dev
```

#### **3️⃣ Validate Deployment**
```bash
kubectl get all -n widgetapi-dev
kubectl logs -n widgetapi-dev -l app=widgetapi
```

#### **4️⃣ Test Application Connectivity**
```bash
helm test widgetapi --namespace widgetapi-dev
```

#### **5️⃣ Check Ingress & Load Balancer**
```bash
kubectl get ingress -n widgetapi-dev
kubectl get svc -n widgetapi-dev
```

#### **6️⃣ Retrieve ALB DNS Name**
```bash
kubectl get ingress -n widgetapi-dev -o jsonpath="{.items[0].status.loadBalancer.ingress[0].hostname}"
```
Then test it:
```bash
curl -vk http://$(kubectl get ingress -n widgetapi-dev -o jsonpath="{.items[0].status.loadBalancer.ingress[0].hostname}")
```

---

### **✅ Summary of Key Commands**
| **Environment**  | **Deploy** | **Validate** | **Test Connectivity** | **Ingress Check** | **Service Check** |
|-----------------|------------|-------------|--------------------|-----------------|----------------|
| **Local**  | `bash scripts/deploy.sh local` | `kubectl get all -n widgetapi-local` | `helm test widgetapi --namespace widgetapi-local` | `kubectl get ingress -n widgetapi-local` | `kubectl get svc -n widgetapi-local` |
| **Dev (EKS)** | `bash scripts/deploy.sh dev` | `kubectl get all -n widgetapi-dev` | `helm test widgetapi --namespace widgetapi-dev` | `kubectl get ingress -n widgetapi-dev` | `kubectl get svc -n widgetapi-dev` |

---

### **🚀 Debugging**
#### **If Helm Tests Fail**
```bash
kubectl logs -n widgetapi-local -l app=widgetapi
kubectl logs -n widgetapi-dev -l app=widgetapi
```

#### **If Load Balancer Not Created**
```bash
kubectl describe ingress -n widgetapi-dev
kubectl get events -n widgetapi-dev
```

---

✅ **Follow these steps to ensure both environments are running correctly!**